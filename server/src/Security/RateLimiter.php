<?php
declare(strict_types=1);

namespace BuildLayer\Security;

use BuildLayer\Core\ApiException;
use BuildLayer\Core\Config;
use BuildLayer\Core\Database;

/**
 * Fixed-window counters in MySQL.
 *
 * A token bucket in Redis would be smoother, but shared hosting has no Redis,
 * and a fixed window is honest about what it is: at worst a caller gets two
 * windows' worth across a boundary, which is fine for the magnitudes here.
 */
final class RateLimiter
{
    /**
     * @param string $scope  key into config "rate"
     * @param string $subject stable identity — an IP hash or a device id
     */
    public static function hit(string $scope, string $subject): void
    {
        /** @var array{0:int,1:int} $rule */
        $rule = Config::get('rate.' . $scope, Config::get('rate.default', [600, 3600]));
        $max = (int) $rule[0];
        $windowSeconds = max(1, (int) $rule[1]);

        $windowStart = (int) (floor(time() / $windowSeconds) * $windowSeconds);
        $bucket = substr($scope . ':' . $subject, 0, 96);

        Database::run(
            'INSERT INTO rate_limits (bucket, window_start, hits) VALUES (?, ?, 1)
             ON DUPLICATE KEY UPDATE hits = hits + 1',
            [$bucket, $windowStart]
        );

        $row = Database::first(
            'SELECT hits FROM rate_limits WHERE bucket = ? AND window_start = ?',
            [$bucket, $windowStart]
        );
        $hits = (int) ($row['hits'] ?? 0);

        if ($hits > $max) {
            $retryAfter = ($windowStart + $windowSeconds) - time();
            throw new ApiException(
                'Too many requests. Try again shortly.',
                429,
                'rate_limited',
                ['retry_after' => max(1, $retryAfter)]
            );
        }
    }

    /** Hashed so the rate table and audit log never hold a raw IP. */
    public static function ipSubject(string $ip): string
    {
        return substr(hash_hmac('sha256', $ip, (string) Config::get('ip_pepper', 'pepper')), 0, 40);
    }
}
