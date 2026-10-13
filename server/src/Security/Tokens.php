<?php
declare(strict_types=1);

namespace BuildLayer\Security;

use BuildLayer\Core\ApiException;
use BuildLayer\Core\Config;
use BuildLayer\Core\Database;

/**
 * Opaque bearer tokens.
 *
 * Deliberately not JWTs: a JWT would put the device id in a payload anyone can
 * read, needs careful algorithm pinning to avoid the "alg: none" class of bug,
 * and cannot be revoked without server state anyway. A random opaque string
 * checked against a table is simpler and revocable by deleting a row.
 */
final class Tokens
{
    /** Plaintext is returned once, at issue time, and never stored. */
    public static function issue(int $deviceId, string $kind): array
    {
        $plain = bin2hex(random_bytes(32));
        $ttlDays = $kind === 'refresh'
            ? (int) Config::get('tokens.refresh_ttl_days', 400)
            : (int) Config::get('tokens.access_ttl_days', 90);
        $expires = gmdate('Y-m-d H:i:s', time() + ($ttlDays * 86400));

        Database::run(
            'INSERT INTO device_tokens (device_id, token_hash, kind, created_at, expires_at)
             VALUES (?, ?, ?, ?, ?)',
            [$deviceId, self::hash($plain), $kind, Database::utcNow(), $expires]
        );

        return ['token' => $plain, 'expires_at' => $expires];
    }

    /**
     * Resolves a bearer token to its device, or throws.
     *
     * @return array<string,mixed> the devices row
     */
    public static function authenticate(string $plain): array
    {
        if ($plain === '' || strlen($plain) !== 64 || !ctype_xdigit($plain)) {
            throw new ApiException('Authentication required.', 401, 'unauthorized');
        }

        $row = Database::first(
            'SELECT t.id AS token_id, t.expires_at, t.revoked_at, t.last_used_at,
                    d.*
               FROM device_tokens t
               JOIN devices d ON d.id = t.device_id
              WHERE t.token_hash = ? AND t.kind = ?
              LIMIT 1',
            [self::hash($plain), 'access']
        );

        if ($row === null) {
            throw new ApiException('Authentication required.', 401, 'unauthorized');
        }
        if ($row['revoked_at'] !== null) {
            throw new ApiException('This token has been revoked.', 401, 'token_revoked');
        }
        if (strtotime((string) $row['expires_at']) < time()) {
            throw new ApiException('This token has expired.', 401, 'token_expired');
        }
        if ($row['blocked_at'] !== null) {
            throw new ApiException('This device has been blocked.', 403, 'device_blocked');
        }

        self::touch((int) $row['token_id'], $row['last_used_at']);
        return $row;
    }

    public static function revokeAllFor(int $deviceId): void
    {
        Database::run(
            'UPDATE device_tokens SET revoked_at = ? WHERE device_id = ? AND revoked_at IS NULL',
            [Database::utcNow(), $deviceId]
        );
    }

    /** Rotates the access token, used by the refresh endpoint. */
    public static function refresh(string $refreshPlain): array
    {
        if (strlen($refreshPlain) !== 64 || !ctype_xdigit($refreshPlain)) {
            throw new ApiException('Invalid refresh token.', 401, 'unauthorized');
        }
        $row = Database::first(
            'SELECT t.device_id, t.expires_at, t.revoked_at, d.blocked_at
               FROM device_tokens t
               JOIN devices d ON d.id = t.device_id
              WHERE t.token_hash = ? AND t.kind = ?
              LIMIT 1',
            [self::hash($refreshPlain), 'refresh']
        );
        if ($row === null || $row['revoked_at'] !== null) {
            throw new ApiException('Invalid refresh token.', 401, 'unauthorized');
        }
        if (strtotime((string) $row['expires_at']) < time()) {
            throw new ApiException('Refresh token has expired.', 401, 'token_expired');
        }
        if ($row['blocked_at'] !== null) {
            throw new ApiException('This device has been blocked.', 403, 'device_blocked');
        }

        $deviceId = (int) $row['device_id'];
        // Retire the old access tokens so a stolen one stops working as soon as
        // the legitimate client refreshes.
        Database::run(
            'UPDATE device_tokens SET revoked_at = ?
              WHERE device_id = ? AND kind = ? AND revoked_at IS NULL',
            [Database::utcNow(), $deviceId, 'access']
        );

        return self::issue($deviceId, 'access');
    }

    public static function hash(string $plain): string
    {
        // A fast hash is correct here, unlike for passwords: the token is 256
        // bits of entropy, so there is nothing to brute-force and no reason to
        // pay a KDF cost on every single request.
        return hash('sha256', $plain);
    }

    /** Writes last_used_at at most once an hour to avoid a write per request. */
    private static function touch(int $tokenId, ?string $lastUsed): void
    {
        if ($lastUsed !== null && strtotime($lastUsed) > time() - 3600) {
            return;
        }
        Database::run('UPDATE device_tokens SET last_used_at = ? WHERE id = ?', [Database::utcNow(), $tokenId]);
    }

    /** Opportunistic sweep, since shared hosting gives us no cron. */
    public static function pruneExpired(): void
    {
        if (random_int(1, 200) !== 1) {
            return;
        }
        Database::run('DELETE FROM device_tokens WHERE expires_at < ?', [gmdate('Y-m-d H:i:s', time() - 86400)]);
        Database::run('DELETE FROM transfer_codes WHERE expires_at < ?', [gmdate('Y-m-d H:i:s', time() - 86400)]);
        Database::run('DELETE FROM rate_limits WHERE window_start < ?', [time() - 86400]);
    }
}
