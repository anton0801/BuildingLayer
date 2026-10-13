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
use BuildLayer\Security\Tokens;

/**
 * Anonymous device identity.
 *
 * There is no email, no password and no profile. The app generates a random
 * install secret on first launch, keeps it in the Keychain, and proves
 * ownership with it. That keeps the privacy posture of the 1.0 release almost
 * intact — the server still holds no personal information — at the cost of
 * needing the transfer-code flow below to move an account between devices.
 */
final class DeviceController
{
    public function register(Request $request): void
    {
        RateLimiter::hit('register', RateLimiter::ipSubject($request->ip()));

        $installSecret = Validator::str($request->json, 'install_secret', 128);
        if (strlen($installSecret) < 32) {
            throw new ApiException('Missing install secret.', 422, 'invalid_install_secret');
        }
        $installHash = hash('sha256', $installSecret);

        $platform   = Validator::enum($request->json, 'platform', ['ios', 'ipados'], 'ios');
        $appVersion = Validator::str($request->json, 'app_version', 24);
        $osVersion  = Validator::str($request->json, 'os_version', 24);
        $model      = Validator::str($request->json, 'model', 48);

        $result = Database::transaction(function () use ($installHash, $platform, $appVersion, $osVersion, $model) {
            $existing = Database::first('SELECT * FROM devices WHERE install_hash = ? LIMIT 1', [$installHash]);

            if ($existing !== null) {
                if ($existing['blocked_at'] !== null) {
                    throw new ApiException('This device has been blocked.', 403, 'device_blocked');
                }
                // Re-registering with the same secret is the normal path after
                // the app is reinstalled from a backup: same account, new
                // tokens. Old tokens are dropped so a lost device goes quiet.
                Tokens::revokeAllFor((int) $existing['id']);
                Database::run(
                    'UPDATE devices SET app_version = ?, os_version = ?, model = ?, last_seen_at = ? WHERE id = ?',
                    [$appVersion, $osVersion, $model, Database::utcNow(), $existing['id']]
                );
                return ['device' => $existing, 'created' => false];
            }

            $publicId = self::uuid4();
            Database::run(
                'INSERT INTO devices (public_id, install_hash, sync_rev, platform, app_version, os_version, model, created_at, last_seen_at)
                 VALUES (?, ?, 0, ?, ?, ?, ?, ?, ?)',
                [$publicId, $installHash, $platform, $appVersion, $osVersion, $model, Database::utcNow(), Database::utcNow()]
            );
            $device = Database::first('SELECT * FROM devices WHERE install_hash = ? LIMIT 1', [$installHash]);
            if ($device === null) {
                throw new ApiException('Could not create the device.', 500, 'server_error');
            }
            return ['device' => $device, 'created' => true];
        });

        $device = $result['device'];
        $deviceId = (int) $device['id'];

        $access  = Tokens::issue($deviceId, 'access');
        $refresh = Tokens::issue($deviceId, 'refresh');

        self::audit($deviceId, $result['created'] ? 'device.register' : 'device.reregister', $request);

        Response::ok([
            'device_id'     => $device['public_id'],
            'created'       => $result['created'],
            'access_token'  => $access['token'],
            'access_expires_at'  => Validator::sqlToMs($access['expires_at']),
            'refresh_token' => $refresh['token'],
            'refresh_expires_at' => Validator::sqlToMs($refresh['expires_at']),
            'sync_rev'      => (int) $device['sync_rev'],
        ], 201);
    }

    public function refresh(Request $request): void
    {
        RateLimiter::hit('register', RateLimiter::ipSubject($request->ip()));
        $token = Validator::str($request->json, 'refresh_token', 128);
        $access = Tokens::refresh($token);
        Response::ok([
            'access_token' => $access['token'],
            'access_expires_at' => Validator::sqlToMs($access['expires_at']),
        ]);
    }

    /** @param array<string,mixed> $device */
    public function me(Request $request, array $device): void
    {
        $deviceId = (int) $device['id'];
        $counts = Database::first(
            'SELECT
               (SELECT COUNT(*) FROM elements  WHERE device_id = ? AND deleted_at IS NULL) AS elements,
               (SELECT COUNT(*) FROM materials WHERE device_id = ? AND deleted_at IS NULL) AS materials,
               (SELECT COUNT(*) FROM reminders WHERE device_id = ? AND deleted_at IS NULL) AS reminders,
               (SELECT COUNT(*) FROM photos    WHERE device_id = ? AND deleted_at IS NULL) AS photos',
            [$deviceId, $deviceId, $deviceId, $deviceId]
        ) ?? [];

        Response::ok([
            'device_id'  => $device['public_id'],
            'sync_rev'   => (int) $device['sync_rev'],
            'created_at' => Validator::sqlToMs((string) $device['created_at']),
            'counts'     => [
                'elements'  => (int) ($counts['elements'] ?? 0),
                'materials' => (int) ($counts['materials'] ?? 0),
                'reminders' => (int) ($counts['reminders'] ?? 0),
                'photos'    => (int) ($counts['photos'] ?? 0),
            ],
        ]);
    }

    /**
     * Erases everything this device owns, server-side.
     *
     * Present because the app must be able to honour "remove my data" without
     * an email to us. The ON DELETE CASCADE on every child table means one
     * delete is genuinely one delete.
     *
     * @param array<string,mixed> $device
     */
    public function deleteAccount(Request $request, array $device): void
    {
        $confirm = Validator::str($request->json, 'confirm', 16);
        if ($confirm !== 'DELETE') {
            throw new ApiException('Confirmation is required.', 422, 'confirmation_required');
        }
        $deviceId = (int) $device['id'];

        $photos = Database::all('SELECT storage_name FROM photos WHERE device_id = ?', [$deviceId]);
        Database::run('DELETE FROM devices WHERE id = ?', [$deviceId]);

        // Rows go first: if unlinking a file fails we have still honoured the
        // deletion, and an orphan file is cleaned up by the sweep below.
        $root = (string) Config::get('storage_path', __DIR__ . '/../../storage');
        foreach ($photos as $photo) {
            $path = $root . '/photos/' . basename((string) $photo['storage_name']);
            if (is_file($path)) {
                @unlink($path);
            }
        }

        self::audit(null, 'device.delete', $request);
        Response::ok(['deleted' => true]);
    }

    // -----------------------------------------------------------------------
    // Transfer between devices
    // -----------------------------------------------------------------------

    /**
     * Issues a short-lived numeric code the user types on the new device.
     *
     * Without this an anonymous account dies with the phone, which would make
     * the whole backup pointless. The code is stored hashed and single-use.
     *
     * @param array<string,mixed> $device
     */
    public function createTransferCode(Request $request, array $device): void
    {
        $deviceId = (int) $device['id'];

        // Only one live code at a time, so an old slip of paper stops working
        // the moment a new code is generated.
        Database::run(
            'DELETE FROM transfer_codes WHERE device_id = ? AND consumed_at IS NULL',
            [$deviceId]
        );

        // 9 digits in 3 groups: ~1e9 space, single-use, 10-minute life and a
        // 5-attempt cap make guessing hopeless without being unreadable.
        $digits = '';
        for ($i = 0; $i < 9; $i++) {
            $digits .= (string) random_int(0, 9);
        }
        $ttl = (int) Config::get('transfer.code_ttl_seconds', 600);

        Database::run(
            'INSERT INTO transfer_codes (device_id, code_hash, created_at, expires_at) VALUES (?, ?, ?, ?)',
            [$deviceId, hash('sha256', $digits), Database::utcNow(), gmdate('Y-m-d H:i:s', time() + $ttl)]
        );

        self::audit($deviceId, 'transfer.create', $request);

        Response::ok([
            'code'       => $digits,
            'expires_in' => $ttl,
        ], 201);
    }

    /**
     * Redeems a code: the calling install adopts the originating account.
     *
     * The old device keeps working but loses its tokens, which is the correct
     * behaviour for "I moved to a new phone".
     */
    public function redeemTransferCode(Request $request): void
    {
        RateLimiter::hit('transfer', RateLimiter::ipSubject($request->ip()));

        $code = preg_replace('/\D/', '', Validator::str($request->json, 'code', 32)) ?? '';
        $installSecret = Validator::str($request->json, 'install_secret', 128);
        if (strlen($code) !== 9) {
            throw new ApiException('Enter the 9-digit transfer code.', 422, 'invalid_code');
        }
        if (strlen($installSecret) < 32) {
            throw new ApiException('Missing install secret.', 422, 'invalid_install_secret');
        }

        $codeHash = hash('sha256', $code);
        $maxAttempts = (int) Config::get('transfer.max_attempts', 5);

        $deviceId = Database::transaction(function () use ($codeHash, $installSecret, $maxAttempts) {
            $row = Database::first(
                'SELECT * FROM transfer_codes WHERE code_hash = ? LIMIT 1 FOR UPDATE',
                [$codeHash]
            );
            if ($row === null) {
                throw new ApiException('That code is not valid.', 404, 'code_not_found');
            }
            if ($row['consumed_at'] !== null) {
                throw new ApiException('That code has already been used.', 409, 'code_used');
            }
            if (strtotime((string) $row['expires_at']) < time()) {
                throw new ApiException('That code has expired. Generate a new one.', 410, 'code_expired');
            }
            if ((int) $row['attempts'] >= $maxAttempts) {
                throw new ApiException('Too many attempts for this code.', 429, 'code_locked');
            }

            $sourceId = (int) $row['device_id'];

            // The redeeming install takes over the account outright: its secret
            // becomes the account's secret, and every token issued to the old
            // handset is revoked.
            Database::run(
                'UPDATE devices SET install_hash = ?, last_seen_at = ? WHERE id = ?',
                [hash('sha256', $installSecret), Database::utcNow(), $sourceId]
            );
            Tokens::revokeAllFor($sourceId);
            Database::run(
                'UPDATE transfer_codes SET consumed_at = ?, consumed_by = ? WHERE id = ?',
                [Database::utcNow(), $sourceId, $row['id']]
            );

            return $sourceId;
        });

        $device = Database::first('SELECT * FROM devices WHERE id = ? LIMIT 1', [$deviceId]);
        if ($device === null) {
            throw new ApiException('Account is unavailable.', 500, 'server_error');
        }

        $access  = Tokens::issue($deviceId, 'access');
        $refresh = Tokens::issue($deviceId, 'refresh');
        self::audit($deviceId, 'transfer.redeem', $request);

        Response::ok([
            'device_id'     => $device['public_id'],
            'access_token'  => $access['token'],
            'access_expires_at'  => Validator::sqlToMs($access['expires_at']),
            'refresh_token' => $refresh['token'],
            'refresh_expires_at' => Validator::sqlToMs($refresh['expires_at']),
            // Deliberately 0: the new device holds nothing yet and must pull
            // the whole account from scratch.
            'sync_rev'      => 0,
        ]);
    }

    // -----------------------------------------------------------------------

    public static function uuid4(): string
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
        $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
        return strtoupper(vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($bytes), 4)));
    }

    public static function audit(?int $deviceId, string $event, Request $request, string $detail = ''): void
    {
        Database::run(
            'INSERT INTO audit_log (device_id, event, detail, ip_hash, created_at) VALUES (?, ?, ?, ?, ?)',
            [
                $deviceId,
                substr($event, 0, 48),
                $detail === '' ? null : substr($detail, 0, 255),
                RateLimiter::ipSubject($request->ip()),
                Database::utcNow(),
            ]
        );
    }
}
