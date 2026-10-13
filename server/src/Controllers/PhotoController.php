<?php
declare(strict_types=1);

namespace BuildLayer\Controllers;

use BuildLayer\Core\ApiException;
use BuildLayer\Core\Config;
use BuildLayer\Core\Database;
use BuildLayer\Core\Request;
use BuildLayer\Core\Response;
use BuildLayer\Core\Validator;
use BuildLayer\Security\RateLimiter;

/**
 * Element photos.
 *
 * Bytes live on disk outside the webroot and are served back through this
 * controller, so reading one requires a valid token. Putting them in a public
 * directory would make every photo readable by anyone who guessed a filename —
 * and these are photographs of people's buildings.
 *
 * They are also kept out of the sync payloads: a few hundred KB of base64 per
 * element would bloat every delta, so the sync carries only a photo_uuid and
 * the client fetches bytes separately when it actually needs them.
 */
final class PhotoController
{
    /** @param array<string,mixed> $device */
    public function upload(Request $request, array $device): void
    {
        $deviceId = (int) $device['id'];
        RateLimiter::hit('photo', (string) $deviceId);

        $uuid = Validator::uuid($request->json, 'uuid');
        $base64 = Validator::str($request->json, 'data', 8 * 1024 * 1024);
        if ($base64 === '') {
            throw new ApiException('No image data supplied.', 422, 'missing_data');
        }

        $bytes = base64_decode($base64, true);
        if ($bytes === false) {
            throw new ApiException('Image data is not valid base64.', 422, 'invalid_data');
        }

        $maxBytes = (int) Config::get('limits.max_photo_bytes', 3145728);
        if (strlen($bytes) > $maxBytes) {
            throw new ApiException('Image is too large.', 413, 'photo_too_large');
        }

        // Trust the bytes, not the client's word: getimagesizefromstring reads
        // the actual header, so a renamed script cannot be stored as a "photo".
        $info = @getimagesizefromstring($bytes);
        if ($info === false || !in_array($info[2] ?? 0, [IMAGETYPE_JPEG, IMAGETYPE_PNG], true)) {
            throw new ApiException('Only JPEG and PNG images are accepted.', 422, 'unsupported_image');
        }

        $dir = rtrim((string) Config::get('storage_path', __DIR__ . '/../../storage'), '/') . '/photos';
        if (!is_dir($dir) && !@mkdir($dir, 0750, true) && !is_dir($dir)) {
            throw new ApiException('Storage is unavailable.', 500, 'storage_error');
        }

        // Filename is server-generated. A client-supplied name is a path
        // traversal waiting to happen.
        $storageName = bin2hex(random_bytes(16)) . '.bin';
        if (@file_put_contents($dir . '/' . $storageName, $bytes, LOCK_EX) === false) {
            throw new ApiException('Could not store the image.', 500, 'storage_error');
        }

        $now = Database::utcNow();
        $sha = hash('sha256', $bytes);
        $size = strlen($bytes);

        Database::transaction(function () use ($deviceId, $uuid, $storageName, $size, $sha, $now, $dir): void {
            Database::run('UPDATE devices SET sync_rev = sync_rev + 1 WHERE id = ?', [$deviceId]);
            $revRow = Database::first('SELECT sync_rev FROM devices WHERE id = ?', [$deviceId]);
            $rev = (int) ($revRow['sync_rev'] ?? 1);

            $existing = Database::first(
                'SELECT id, storage_name FROM photos WHERE device_id = ? AND uuid = ? LIMIT 1',
                [$deviceId, $uuid]
            );
            if ($existing !== null) {
                Database::run(
                    'UPDATE photos SET storage_name = ?, byte_size = ?, sha256 = ?, rev = ?, created_at = ?, deleted_at = NULL
                      WHERE id = ?',
                    [$storageName, $size, $sha, $rev, $now, $existing['id']]
                );
                $old = $dir . '/' . basename((string) $existing['storage_name']);
                if (is_file($old)) {
                    @unlink($old);
                }
            } else {
                Database::run(
                    'INSERT INTO photos (device_id, uuid, rev, storage_name, byte_size, sha256, created_at)
                     VALUES (?,?,?,?,?,?,?)',
                    [$deviceId, $uuid, $rev, $storageName, $size, $sha, $now]
                );
            }
        });

        Response::ok(['uuid' => $uuid, 'byte_size' => $size, 'sha256' => $sha], 201);
    }

    /** @param array<string,mixed> $device */
    public function download(Request $request, array $device): void
    {
        $deviceId = (int) $device['id'];
        $uuid = Validator::uuid($request->query, 'uuid');

        // Scoped by device_id in the WHERE clause, so one device can never read
        // another's photo by guessing a uuid.
        $row = Database::first(
            'SELECT storage_name, byte_size FROM photos WHERE device_id = ? AND uuid = ? AND deleted_at IS NULL LIMIT 1',
            [$deviceId, $uuid]
        );
        if ($row === null) {
            throw new ApiException('Photo not found.', 404, 'not_found');
        }

        $dir = rtrim((string) Config::get('storage_path', __DIR__ . '/../../storage'), '/') . '/photos';
        $path = $dir . '/' . basename((string) $row['storage_name']);
        if (!is_file($path)) {
            throw new ApiException('Photo is no longer stored.', 410, 'gone');
        }

        // Returned as base64 JSON rather than raw bytes so the client has one
        // response shape to handle and the same signature checks apply.
        $bytes = file_get_contents($path);
        if ($bytes === false) {
            throw new ApiException('Could not read the image.', 500, 'storage_error');
        }
        Response::ok(['uuid' => $uuid, 'data' => base64_encode($bytes)]);
    }

    /** @param array<string,mixed> $device */
    public function delete(Request $request, array $device): void
    {
        $deviceId = (int) $device['id'];
        $uuid = Validator::uuid($request->json, 'uuid');

        $row = Database::first(
            'SELECT id, storage_name FROM photos WHERE device_id = ? AND uuid = ? LIMIT 1',
            [$deviceId, $uuid]
        );
        if ($row === null) {
            Response::ok(['deleted' => false]);
            return;
        }

        Database::transaction(function () use ($deviceId, $row): void {
            Database::run('UPDATE devices SET sync_rev = sync_rev + 1 WHERE id = ?', [$deviceId]);
            $revRow = Database::first('SELECT sync_rev FROM devices WHERE id = ?', [$deviceId]);
            Database::run(
                'UPDATE photos SET deleted_at = ?, rev = ? WHERE id = ?',
                [Database::utcNow(), (int) ($revRow['sync_rev'] ?? 1), $row['id']]
            );
        });

        $dir = rtrim((string) Config::get('storage_path', __DIR__ . '/../../storage'), '/') . '/photos';
        $path = $dir . '/' . basename((string) $row['storage_name']);
        if (is_file($path)) {
            @unlink($path);
        }

        Response::ok(['deleted' => true]);
    }
}
