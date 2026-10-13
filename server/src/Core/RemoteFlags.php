<?php
declare(strict_types=1);

namespace BuildLayer\Core;

/**
 * Server-controlled flags served to the app as response headers.
 *
 * Currently one: `onAnalytics.isOn`, sent as `X-Serviced-Target: true|false`.
 * The server's only job is to store and serve it; what the app does with the
 * value is the app's business.
 */
final class RemoteFlags
{
    /** Resolved once per request — several responses must not cost several queries. */
    private static ?bool $cached = null;
    private static bool $resolved = false;

    /**
     * @return bool|null null means "do not send the header at all"
     */
    public static function servicedTarget(): ?bool
    {
        if (self::$resolved) {
            return self::$cached;
        }
        self::$resolved = true;

        try {
            $row = Database::first('SELECT isOn FROM onAnalytics WHERE id = 1 LIMIT 1');
            self::$cached = $row === null ? null : ((int) $row['isOn'] === 1);
        } catch (\Throwable $e) {
            // Missing table or an unreachable database must not fail the
            // request, and must not invent a value either: omitting the header
            // leaves the app on its last known setting rather than flipping it
            // because of a deployment mistake.
            error_log('[buildlayer-api] onAnalytics unavailable: ' . $e->getMessage());
            self::$cached = null;
        }

        return self::$cached;
    }

    /** Sets the flag. Exposed for an admin script; no endpoint writes it. */
    public static function setServicedTarget(bool $value): void
    {
        Database::run(
            'INSERT INTO onAnalytics (id, isOn, created_at, updated_at)
             VALUES (1, ?, ?, ?)
             ON DUPLICATE KEY UPDATE isOn = VALUES(isOn), updated_at = VALUES(updated_at)',
            [$value ? 1 : 0, Database::utcNow(), Database::utcNow()]
        );
        self::$cached = $value;
        self::$resolved = true;
    }
}
