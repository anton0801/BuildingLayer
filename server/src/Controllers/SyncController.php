<?php
declare(strict_types=1);

namespace BuildLayer\Controllers;

use BuildLayer\Core\ApiException;
use BuildLayer\Core\Config;
use BuildLayer\Core\Database;
use BuildLayer\Core\Request;
use BuildLayer\Core\Response;
use BuildLayer\Core\Validator;

/**
 * Delta sync.
 *
 * Every row a device owns carries a `rev` drawn from that device's own counter.
 * The client remembers the highest rev it has seen and asks for everything
 * above it, so a routine sync moves a handful of rows rather than the whole
 * project.
 *
 * Conflicts resolve last-write-wins on the client's own edit timestamp. For a
 * single-device anonymous account real conflicts are rare — they happen after a
 * transfer, when two installs briefly hold the same account — and for that case
 * "the most recent edit wins" is both predictable and explainable to a user.
 * It is deliberately not a merge: silently merging two versions of a build-up
 * would produce a stack nobody designed.
 */
final class SyncController
{
    private const STATUSES = ['Pass', 'In Progress', 'Attention', 'Fail'];
    private const TYPES    = ['Wall', 'Roof', 'Floor'];
    private const SIDES    = ['Outside', 'Core', 'Inside'];
    private const PAGE     = 200;

    /** @param array<string,mixed> $device */
    public function pull(Request $request, array $device): void
    {
        $deviceId = (int) $device['id'];
        $since = isset($request->query['since']) && ctype_digit($request->query['since'])
            ? (int) $request->query['since']
            : 0;

        $elements  = $this->pullElements($deviceId, $since);
        $materials = $this->pullSimple('materials', $deviceId, $since, [$this, 'mapMaterial']);
        $reminders = $this->pullSimple('reminders', $deviceId, $since, [$this, 'mapReminder']);
        $history   = $this->pullSimple('history_entries', $deviceId, $since, [$this, 'mapHistory']);
        $photos    = $this->pullSimple('photos', $deviceId, $since, [$this, 'mapPhotoMeta']);

        // More pages remain if any bucket came back full.
        $hasMore = count($elements) >= self::PAGE
            || count($materials) >= self::PAGE
            || count($reminders) >= self::PAGE
            || count($history) >= self::PAGE
            || count($photos) >= self::PAGE;

        // With paging in play the client must only advance as far as the data
        // it actually received, or it would skip the rows it has not seen.
        $highest = $since;
        foreach ([$elements, $materials, $reminders, $history, $photos] as $bucket) {
            foreach ($bucket as $item) {
                $highest = max($highest, (int) $item['rev']);
            }
        }
        $serverRev = (int) $device['sync_rev'];

        Response::ok([
            'rev'       => $hasMore ? $highest : $serverRev,
            'server_rev'=> $serverRev,
            'has_more'  => $hasMore,
            'elements'  => $elements,
            'materials' => $materials,
            'reminders' => $reminders,
            'history'   => $history,
            'photos'    => $photos,
        ]);
    }

    /** @param array<string,mixed> $device */
    public function push(Request $request, array $device): void
    {
        $deviceId = (int) $device['id'];
        $maxItems = (int) Config::get('limits.max_batch_items', 400);

        $elements  = Validator::objectList($request->json, 'elements', $maxItems);
        $materials = Validator::objectList($request->json, 'materials', $maxItems);
        $reminders = Validator::objectList($request->json, 'reminders', $maxItems);
        $history   = Validator::objectList($request->json, 'history', $maxItems);

        if ($elements === [] && $materials === [] && $reminders === [] && $history === []) {
            Response::ok(['rev' => (int) $device['sync_rev'], 'applied' => 0, 'skipped' => 0]);
            return;
        }

        $applied = 0;
        $skipped = 0;

        Database::transaction(function () use (
            $deviceId, $elements, $materials, $reminders, $history, &$applied, &$skipped
        ): void {
            // One rev for the whole batch: everything pushed together becomes
            // visible together, so a puller can never catch half a batch.
            $rev = $this->nextRev($deviceId);

            foreach ($elements as $item) {
                $this->upsertElement($deviceId, $rev, $item) ? $applied++ : $skipped++;
            }
            foreach ($materials as $item) {
                $this->upsertMaterial($deviceId, $rev, $item) ? $applied++ : $skipped++;
            }
            foreach ($reminders as $item) {
                $this->upsertReminder($deviceId, $rev, $item) ? $applied++ : $skipped++;
            }
            foreach ($history as $item) {
                $this->upsertHistory($deviceId, $rev, $item) ? $applied++ : $skipped++;
            }
        });

        $fresh = Database::first('SELECT sync_rev FROM devices WHERE id = ?', [$deviceId]);
        Response::ok([
            'rev'     => (int) ($fresh['sync_rev'] ?? 0),
            'applied' => $applied,
            'skipped' => $skipped,
        ]);
    }

    // -----------------------------------------------------------------------
    // Revision allocation
    // -----------------------------------------------------------------------

    /**
     * Bumps and returns the device's counter.
     *
     * The UPDATE-then-SELECT runs inside the caller's transaction and touches a
     * single row keyed by primary key, so concurrent pushes from the same
     * device serialise on that row rather than racing to the same rev.
     */
    private function nextRev(int $deviceId): int
    {
        Database::run('UPDATE devices SET sync_rev = sync_rev + 1, last_seen_at = ? WHERE id = ?', [Database::utcNow(), $deviceId]);
        $row = Database::first('SELECT sync_rev FROM devices WHERE id = ?', [$deviceId]);
        return (int) ($row['sync_rev'] ?? 1);
    }

    // -----------------------------------------------------------------------
    // Writers. Each returns false when the incoming row is older than what is
    // already stored, which is a skip rather than an error.
    // -----------------------------------------------------------------------

    /** @param array<string,mixed> $item */
    private function upsertElement(int $deviceId, int $rev, array $item): bool
    {
        $uuid = Validator::uuid($item, 'uuid');
        $updatedMs = Validator::epochMs($item, 'updated_ms');
        $deleted = Validator::bool($item, 'deleted');

        $existing = Database::first(
            'SELECT id, client_updated_ms FROM elements WHERE device_id = ? AND uuid = ? LIMIT 1',
            [$deviceId, $uuid]
        );
        if ($existing !== null && (int) $existing['client_updated_ms'] > $updatedMs) {
            return false;   // stored copy is newer
        }

        $now = Database::utcNow();

        if ($deleted) {
            if ($existing === null) {
                return false;
            }
            Database::run(
                'UPDATE elements SET deleted_at = ?, rev = ?, client_updated_ms = ?, updated_at = ? WHERE id = ?',
                [$now, $rev, $updatedMs, $now, $existing['id']]
            );
            Database::run('DELETE FROM element_layers WHERE element_id = ?', [$existing['id']]);
            return true;
        }

        $fields = [
            'name'              => Validator::str($item, 'name', 120),
            'type'              => Validator::enum($item, 'type', self::TYPES, 'Wall'),
            'area'              => Validator::num($item, 'area', 0, 100000),
            'target_u'          => Validator::num($item, 'target_u', 0, 10),
            'tolerance'         => Validator::num($item, 'tolerance', 0, 1),
            'inside_temp'       => Validator::num($item, 'inside_temp', -80, 80, 20),
            'outside_temp'      => Validator::num($item, 'outside_temp', -80, 80, -5),
            'indoor_rh'         => Validator::num($item, 'indoor_rh', 1, 100, 55),
            'outdoor_rh'        => Validator::num($item, 'outdoor_rh', 1, 100, 85),
            'status'            => Validator::enum($item, 'status', self::STATUSES, 'In Progress'),
            'manual_status'     => Validator::optionalEnum($item, 'manual_status', self::STATUSES),
            'insulation_name'   => Validator::str($item, 'insulation_name', 120),
            'notes'             => Validator::str($item, 'notes', 8000),
            'has_vapor_control' => Validator::bool($item, 'has_vapor_control') ? 1 : 0,
            'existing_u'        => Validator::num($item, 'existing_u', 0, 10),
            'cost_insulation'   => Validator::num($item, 'cost_insulation', 0, 100000000),
            'cost_membrane'     => Validator::num($item, 'cost_membrane', 0, 100000000),
            'cost_finish'       => Validator::num($item, 'cost_finish', 0, 100000000),
            'cost_reserve_pct'  => Validator::num($item, 'cost_reserve_pct', 0, 100, 10),
            'signoff_by'        => Validator::str($item, 'signoff_by', 120),
            'signature_json'    => $this->encodeSignature($item['signature'] ?? null),
            'photo_uuid'        => Validator::optionalUuid($item, 'photo_uuid'),
        ];

        $signoffMs = isset($item['signoff_ms']) ? Validator::epochMs($item, 'signoff_ms') : null;
        $signoffAt = $signoffMs === null ? null : Validator::msToSql($signoffMs);
        $createdAt = Validator::msToSql(Validator::epochMs($item, 'date_created_ms', $updatedMs));

        if ($existing === null) {
            Database::run(
                'INSERT INTO elements
                   (device_id, uuid, rev, name, type, area, target_u, tolerance, inside_temp, outside_temp,
                    indoor_rh, outdoor_rh, status, manual_status, insulation_name, notes, has_vapor_control,
                    existing_u, cost_insulation, cost_membrane, cost_finish, cost_reserve_pct,
                    signoff_by, signoff_date, signature_json, photo_uuid,
                    client_updated_ms, date_created, updated_at, deleted_at)
                 VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,NULL)',
                array_merge([$deviceId, $uuid, $rev], [
                    $fields['name'], $fields['type'], $fields['area'], $fields['target_u'], $fields['tolerance'],
                    $fields['inside_temp'], $fields['outside_temp'], $fields['indoor_rh'], $fields['outdoor_rh'],
                    $fields['status'], $fields['manual_status'], $fields['insulation_name'], $fields['notes'],
                    $fields['has_vapor_control'], $fields['existing_u'], $fields['cost_insulation'],
                    $fields['cost_membrane'], $fields['cost_finish'], $fields['cost_reserve_pct'],
                    $fields['signoff_by'], $signoffAt, $fields['signature_json'], $fields['photo_uuid'],
                    $updatedMs, $createdAt, $now,
                ])
            );
            $row = Database::first('SELECT id FROM elements WHERE device_id = ? AND uuid = ?', [$deviceId, $uuid]);
            $elementId = (int) ($row['id'] ?? 0);
        } else {
            $elementId = (int) $existing['id'];
            Database::run(
                'UPDATE elements SET rev = ?, name = ?, type = ?, area = ?, target_u = ?, tolerance = ?,
                        inside_temp = ?, outside_temp = ?, indoor_rh = ?, outdoor_rh = ?, status = ?,
                        manual_status = ?, insulation_name = ?, notes = ?, has_vapor_control = ?, existing_u = ?,
                        cost_insulation = ?, cost_membrane = ?, cost_finish = ?, cost_reserve_pct = ?,
                        signoff_by = ?, signoff_date = ?, signature_json = ?, photo_uuid = ?,
                        client_updated_ms = ?, updated_at = ?, deleted_at = NULL
                  WHERE id = ?',
                [
                    $rev, $fields['name'], $fields['type'], $fields['area'], $fields['target_u'], $fields['tolerance'],
                    $fields['inside_temp'], $fields['outside_temp'], $fields['indoor_rh'], $fields['outdoor_rh'],
                    $fields['status'], $fields['manual_status'], $fields['insulation_name'], $fields['notes'],
                    $fields['has_vapor_control'], $fields['existing_u'], $fields['cost_insulation'],
                    $fields['cost_membrane'], $fields['cost_finish'], $fields['cost_reserve_pct'],
                    $fields['signoff_by'], $signoffAt, $fields['signature_json'], $fields['photo_uuid'],
                    $updatedMs, $now, $elementId,
                ]
            );
        }

        if ($elementId > 0) {
            $this->replaceLayers($elementId, $item);
        }
        return true;
    }

    /**
     * Layers are replaced wholesale. They are an ordered stack that only ever
     * changes as a unit, so diffing them per row would buy nothing and would
     * introduce ordering conflicts.
     *
     * @param array<string,mixed> $item
     */
    private function replaceLayers(int $elementId, array $item): void
    {
        Database::run('DELETE FROM element_layers WHERE element_id = ?', [$elementId]);
        $layers = Validator::objectList($item, 'layers', 100);
        $position = 0;
        foreach ($layers as $layer) {
            $uuid = isset($layer['uuid']) ? Validator::optionalUuid($layer, 'uuid') : null;
            Database::run(
                'INSERT INTO element_layers
                   (element_id, uuid, position, material_name, lambda, vapor_resistance, thickness_mm, is_insulation, side)
                 VALUES (?,?,?,?,?,?,?,?,?)',
                [
                    $elementId,
                    $uuid ?? DeviceController::uuid4(),
                    $position++,
                    Validator::str($layer, 'material_name', 120),
                    Validator::num($layer, 'lambda', 0.001, 10, 0.04),
                    Validator::num($layer, 'vapor_resistance', 1, 100000, 1),
                    Validator::num($layer, 'thickness_mm', 0, 2000),
                    Validator::bool($layer, 'is_insulation') ? 1 : 0,
                    Validator::enum($layer, 'side', self::SIDES, 'Core'),
                ]
            );
        }
    }

    /** @param array<string,mixed> $item */
    private function upsertMaterial(int $deviceId, int $rev, array $item): bool
    {
        $uuid = Validator::uuid($item, 'uuid');
        $updatedMs = Validator::epochMs($item, 'updated_ms');
        $deleted = Validator::bool($item, 'deleted');
        $now = Database::utcNow();

        $existing = Database::first(
            'SELECT id, client_updated_ms FROM materials WHERE device_id = ? AND uuid = ? LIMIT 1',
            [$deviceId, $uuid]
        );
        if ($existing !== null && (int) $existing['client_updated_ms'] > $updatedMs) {
            return false;
        }
        if ($deleted) {
            if ($existing === null) {
                return false;
            }
            Database::run(
                'UPDATE materials SET deleted_at = ?, rev = ?, client_updated_ms = ?, updated_at = ? WHERE id = ?',
                [$now, $rev, $updatedMs, $now, $existing['id']]
            );
            return true;
        }

        $args = [
            Validator::str($item, 'name', 120),
            Validator::num($item, 'lambda', 0.001, 10, 0.04),
            Validator::num($item, 'density', 0, 5000),
            Validator::num($item, 'vapor_resistance', 1, 100000, 1),
            Validator::bool($item, 'is_insulation') ? 1 : 0,
            Validator::bool($item, 'is_custom', true) ? 1 : 0,
        ];

        if ($existing === null) {
            Database::run(
                'INSERT INTO materials
                   (device_id, uuid, rev, name, lambda, density, vapor_resistance, is_insulation, is_custom,
                    client_updated_ms, updated_at)
                 VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                array_merge([$deviceId, $uuid, $rev], $args, [$updatedMs, $now])
            );
        } else {
            Database::run(
                'UPDATE materials SET rev = ?, name = ?, lambda = ?, density = ?, vapor_resistance = ?,
                        is_insulation = ?, is_custom = ?, client_updated_ms = ?, updated_at = ?, deleted_at = NULL
                  WHERE id = ?',
                array_merge([$rev], $args, [$updatedMs, $now, $existing['id']])
            );
        }
        return true;
    }

    /** @param array<string,mixed> $item */
    private function upsertReminder(int $deviceId, int $rev, array $item): bool
    {
        $uuid = Validator::uuid($item, 'uuid');
        $updatedMs = Validator::epochMs($item, 'updated_ms');
        $deleted = Validator::bool($item, 'deleted');
        $now = Database::utcNow();

        $existing = Database::first(
            'SELECT id, client_updated_ms FROM reminders WHERE device_id = ? AND uuid = ? LIMIT 1',
            [$deviceId, $uuid]
        );
        if ($existing !== null && (int) $existing['client_updated_ms'] > $updatedMs) {
            return false;
        }
        if ($deleted) {
            if ($existing === null) {
                return false;
            }
            Database::run(
                'UPDATE reminders SET deleted_at = ?, rev = ?, client_updated_ms = ?, updated_at = ? WHERE id = ?',
                [$now, $rev, $updatedMs, $now, $existing['id']]
            );
            return true;
        }

        $args = [
            Validator::str($item, 'kind', 48),
            Validator::msToSql(Validator::epochMs($item, 'fire_at_ms')),
            Validator::bool($item, 'is_on', true) ? 1 : 0,
            Validator::optionalUuid($item, 'element_uuid'),
            Validator::str($item, 'element_name', 120),
        ];

        if ($existing === null) {
            Database::run(
                'INSERT INTO reminders
                   (device_id, uuid, rev, kind, fire_at, is_on, element_uuid, element_name, client_updated_ms, updated_at)
                 VALUES (?,?,?,?,?,?,?,?,?,?)',
                array_merge([$deviceId, $uuid, $rev], $args, [$updatedMs, $now])
            );
        } else {
            Database::run(
                'UPDATE reminders SET rev = ?, kind = ?, fire_at = ?, is_on = ?, element_uuid = ?, element_name = ?,
                        client_updated_ms = ?, updated_at = ?, deleted_at = NULL
                  WHERE id = ?',
                array_merge([$rev], $args, [$updatedMs, $now, $existing['id']])
            );
        }
        return true;
    }

    /**
     * History is append-only: an entry describes something that already
     * happened, so it is never updated, only created or pruned.
     *
     * @param array<string,mixed> $item
     */
    private function upsertHistory(int $deviceId, int $rev, array $item): bool
    {
        $uuid = Validator::uuid($item, 'uuid');
        $now = Database::utcNow();
        $deleted = Validator::bool($item, 'deleted');

        $existing = Database::first(
            'SELECT id FROM history_entries WHERE device_id = ? AND uuid = ? LIMIT 1',
            [$deviceId, $uuid]
        );

        if ($deleted) {
            if ($existing === null) {
                return false;
            }
            Database::run(
                'UPDATE history_entries SET deleted_at = ?, rev = ?, updated_at = ? WHERE id = ?',
                [$now, $rev, $now, $existing['id']]
            );
            return true;
        }
        if ($existing !== null) {
            return false;
        }

        Database::run(
            'INSERT INTO history_entries (device_id, uuid, rev, title, detail, icon, happened_at, updated_at)
             VALUES (?,?,?,?,?,?,?,?)',
            [
                $deviceId, $uuid, $rev,
                Validator::str($item, 'title', 120),
                Validator::str($item, 'detail', 255),
                Validator::str($item, 'icon', 64),
                Validator::msToSql(Validator::epochMs($item, 'happened_at_ms')),
                $now,
            ]
        );
        return true;
    }

    // -----------------------------------------------------------------------
    // Readers
    // -----------------------------------------------------------------------

    /** @return array<int,array<string,mixed>> */
    private function pullElements(int $deviceId, int $since): array
    {
        $rows = Database::all(
            'SELECT * FROM elements WHERE device_id = ? AND rev > ? ORDER BY rev ASC, id ASC LIMIT ' . self::PAGE,
            [$deviceId, $since]
        );
        if ($rows === []) {
            return [];
        }

        $ids = array_map(static fn ($r) => (int) $r['id'], $rows);
        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $layerRows = Database::all(
            'SELECT * FROM element_layers WHERE element_id IN (' . $placeholders . ') ORDER BY element_id, position',
            $ids
        );

        $layersByElement = [];
        foreach ($layerRows as $layer) {
            $layersByElement[(int) $layer['element_id']][] = [
                'uuid'             => (string) $layer['uuid'],
                'material_name'    => (string) $layer['material_name'],
                'lambda'           => (float) $layer['lambda'],
                'vapor_resistance' => (float) $layer['vapor_resistance'],
                'thickness_mm'     => (float) $layer['thickness_mm'],
                'is_insulation'    => (bool) $layer['is_insulation'],
                'side'             => (string) $layer['side'],
            ];
        }

        $out = [];
        foreach ($rows as $row) {
            $id = (int) $row['id'];
            $out[] = [
                'uuid'              => (string) $row['uuid'],
                'rev'               => (int) $row['rev'],
                'deleted'           => $row['deleted_at'] !== null,
                'name'              => (string) $row['name'],
                'type'              => (string) $row['type'],
                'area'              => (float) $row['area'],
                'target_u'          => (float) $row['target_u'],
                'tolerance'         => (float) $row['tolerance'],
                'inside_temp'       => (float) $row['inside_temp'],
                'outside_temp'      => (float) $row['outside_temp'],
                'indoor_rh'         => (float) $row['indoor_rh'],
                'outdoor_rh'        => (float) $row['outdoor_rh'],
                'status'            => (string) $row['status'],
                'manual_status'     => $row['manual_status'] !== null ? (string) $row['manual_status'] : null,
                'insulation_name'   => (string) $row['insulation_name'],
                'notes'             => (string) ($row['notes'] ?? ''),
                'has_vapor_control' => (bool) $row['has_vapor_control'],
                'existing_u'        => (float) $row['existing_u'],
                'cost_insulation'   => (float) $row['cost_insulation'],
                'cost_membrane'     => (float) $row['cost_membrane'],
                'cost_finish'       => (float) $row['cost_finish'],
                'cost_reserve_pct'  => (float) $row['cost_reserve_pct'],
                'signoff_by'        => (string) $row['signoff_by'],
                'signoff_ms'        => Validator::sqlToMs($row['signoff_date'] !== null ? (string) $row['signoff_date'] : null),
                'signature'         => $this->decodeSignature($row['signature_json'] !== null ? (string) $row['signature_json'] : null),
                'photo_uuid'        => $row['photo_uuid'] !== null ? (string) $row['photo_uuid'] : null,
                'date_created_ms'   => Validator::sqlToMs((string) $row['date_created']),
                'updated_ms'        => (int) $row['client_updated_ms'],
                'layers'            => $layersByElement[$id] ?? [],
            ];
        }
        return $out;
    }

    /** @return array<int,array<string,mixed>> */
    private function pullSimple(string $table, int $deviceId, int $since, callable $mapper): array
    {
        // $table is a constant from this class, never user input — there is no
        // way for a caller to influence it.
        $rows = Database::all(
            'SELECT * FROM ' . $table . ' WHERE device_id = ? AND rev > ? ORDER BY rev ASC, id ASC LIMIT ' . self::PAGE,
            [$deviceId, $since]
        );
        return array_map($mapper, $rows);
    }

    /** @param array<string,mixed> $row @return array<string,mixed> */
    private function mapMaterial(array $row): array
    {
        return [
            'uuid'             => (string) $row['uuid'],
            'rev'              => (int) $row['rev'],
            'deleted'          => $row['deleted_at'] !== null,
            'name'             => (string) $row['name'],
            'lambda'           => (float) $row['lambda'],
            'density'          => (float) $row['density'],
            'vapor_resistance' => (float) $row['vapor_resistance'],
            'is_insulation'    => (bool) $row['is_insulation'],
            'is_custom'        => (bool) $row['is_custom'],
            'updated_ms'       => (int) $row['client_updated_ms'],
        ];
    }

    /** @param array<string,mixed> $row @return array<string,mixed> */
    private function mapReminder(array $row): array
    {
        return [
            'uuid'         => (string) $row['uuid'],
            'rev'          => (int) $row['rev'],
            'deleted'      => $row['deleted_at'] !== null,
            'kind'         => (string) $row['kind'],
            'fire_at_ms'   => Validator::sqlToMs((string) $row['fire_at']),
            'is_on'        => (bool) $row['is_on'],
            'element_uuid' => $row['element_uuid'] !== null ? (string) $row['element_uuid'] : null,
            'element_name' => (string) $row['element_name'],
            'updated_ms'   => (int) $row['client_updated_ms'],
        ];
    }

    /** @param array<string,mixed> $row @return array<string,mixed> */
    private function mapHistory(array $row): array
    {
        return [
            'uuid'           => (string) $row['uuid'],
            'rev'            => (int) $row['rev'],
            'deleted'        => $row['deleted_at'] !== null,
            'title'          => (string) $row['title'],
            'detail'         => (string) $row['detail'],
            'icon'           => (string) $row['icon'],
            'happened_at_ms' => Validator::sqlToMs((string) $row['happened_at']),
        ];
    }

    /** @param array<string,mixed> $row @return array<string,mixed> */
    private function mapPhotoMeta(array $row): array
    {
        return [
            'uuid'       => (string) $row['uuid'],
            'rev'        => (int) $row['rev'],
            'deleted'    => $row['deleted_at'] !== null,
            'byte_size'  => (int) $row['byte_size'],
            'sha256'     => (string) $row['sha256'],
        ];
    }

    // -----------------------------------------------------------------------

    /**
     * Signature strokes are stored as an opaque JSON document because nothing
     * server-side ever queries inside them. Size is capped so a client cannot
     * park megabytes of points in a row.
     */
    private function encodeSignature($value): ?string
    {
        if (!is_array($value) || $value === []) {
            return null;
        }
        $strokes = [];
        foreach (array_slice($value, 0, 60) as $stroke) {
            if (!is_array($stroke)) {
                continue;
            }
            $points = [];
            foreach (array_slice($stroke, 0, 400) as $point) {
                if (!is_array($point)) {
                    continue;
                }
                $points[] = [
                    'x' => round(Validator::num($point, 'x', -10000, 10000), 2),
                    'y' => round(Validator::num($point, 'y', -10000, 10000), 2),
                ];
            }
            if ($points !== []) {
                $strokes[] = $points;
            }
        }
        if ($strokes === []) {
            return null;
        }
        $json = json_encode($strokes, JSON_UNESCAPED_SLASHES);
        return $json === false ? null : $json;
    }

    /** @return array<int,array<int,array{x:float,y:float}>> */
    private function decodeSignature(?string $json): array
    {
        if ($json === null || $json === '') {
            return [];
        }
        $decoded = json_decode($json, true);
        return is_array($decoded) ? $decoded : [];
    }
}
