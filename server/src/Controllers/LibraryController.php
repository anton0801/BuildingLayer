<?php
declare(strict_types=1);

namespace BuildLayer\Controllers;

use BuildLayer\Core\Database;
use BuildLayer\Core\Request;
use BuildLayer\Core\Response;

/**
 * Server-managed reference data: the material catalogue and the build-up
 * templates.
 *
 * These shipped hard-coded in 1.0, which meant a wrong lambda value could only
 * be corrected by an App Store release. Serving them lets the catalogue be
 * fixed the same day. The app keeps its built-in copy as a fallback, so a
 * server outage degrades to "slightly stale library", never to a broken screen.
 */
final class LibraryController
{
    /** Cheap poll: one row, so the app can skip the download when nothing moved. */
    public function version(Request $request, array $device): void
    {
        $row = Database::first('SELECT version, updated_at FROM library_meta WHERE id = 1');
        Response::ok([
            'version'    => (int) ($row['version'] ?? 1),
            'updated_at' => (string) ($row['updated_at'] ?? ''),
        ]);
    }

    public function fetch(Request $request, array $device): void
    {
        $meta = Database::first('SELECT version FROM library_meta WHERE id = 1');

        $materials = array_map(
            static fn (array $r): array => [
                'slug'             => (string) $r['slug'],
                'name'             => (string) $r['name'],
                'lambda'           => (float) $r['lambda'],
                'density'          => (float) $r['density'],
                'vapor_resistance' => (float) $r['vapor_resistance'],
                'is_insulation'    => (bool) $r['is_insulation'],
            ],
            Database::all('SELECT * FROM library_materials WHERE is_active = 1 ORDER BY sort_order ASC, name ASC')
        );

        $templates = [];
        foreach (Database::all('SELECT * FROM library_templates WHERE is_active = 1 ORDER BY sort_order ASC, name ASC') as $row) {
            $layers = json_decode((string) $row['layers_json'], true);
            if (!is_array($layers)) {
                continue;   // a malformed row is skipped, never served broken
            }
            $templates[] = [
                'slug'         => (string) $row['slug'],
                'name'         => (string) $row['name'],
                'detail'       => (string) $row['detail'],
                'element_type' => (string) $row['element_type'],
                'layers'       => $layers,
            ];
        }

        Response::ok([
            'version'   => (int) ($meta['version'] ?? 1),
            'materials' => $materials,
            'templates' => $templates,
        ]);
    }
}
