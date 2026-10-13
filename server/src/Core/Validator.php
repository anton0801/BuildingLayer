<?php
declare(strict_types=1);

namespace BuildLayer\Core;

/**
 * Typed, clamping readers for untrusted input.
 *
 * The server does not trust the app even though we wrote it: a token is easy to
 * lift off a jailbroken device, and at that point the "client validates it"
 * assumption is worth nothing. Every numeric field is clamped to the same
 * domain the app enforces, so a hostile client cannot store values that later
 * break arithmetic or a report.
 */
final class Validator
{
    /** @param array<string,mixed> $row */
    public static function str(array $row, string $key, int $maxLen, string $default = ''): string
    {
        $value = $row[$key] ?? $default;
        if (!is_string($value)) {
            return $default;
        }
        $value = str_replace(["\0", "\r"], '', $value);
        if (function_exists('mb_substr')) {
            return mb_substr($value, 0, $maxLen, 'UTF-8');
        }
        return substr($value, 0, $maxLen);
    }

    /** @param array<string,mixed> $row */
    public static function num(array $row, string $key, float $min, float $max, float $default = 0.0): float
    {
        $value = $row[$key] ?? $default;
        if (is_string($value) && is_numeric($value)) {
            $value = (float) $value;
        }
        if (!is_int($value) && !is_float($value)) {
            return $default;
        }
        $value = (float) $value;
        if (!is_finite($value)) {
            return $default;
        }
        return max($min, min($max, $value));
    }

    /** @param array<string,mixed> $row */
    public static function bool(array $row, string $key, bool $default = false): bool
    {
        $value = $row[$key] ?? $default;
        if (is_bool($value)) {
            return $value;
        }
        if (is_int($value)) {
            return $value !== 0;
        }
        if (is_string($value)) {
            return in_array(strtolower($value), ['1', 'true', 'yes'], true);
        }
        return $default;
    }

    /**
     * Milliseconds since the Unix epoch, bounded to a believable range so a bad
     * clock or a hostile client cannot park a row in the year 30000 and win
     * every last-write-wins comparison for ever.
     *
     * @param array<string,mixed> $row
     */
    public static function epochMs(array $row, string $key, ?int $default = null): int
    {
        $value = $row[$key] ?? $default;
        if (is_string($value) && ctype_digit($value)) {
            $value = (int) $value;
        }
        if (is_float($value)) {
            $value = (int) $value;
        }
        if (!is_int($value)) {
            return $default ?? (int) (time() * 1000);
        }
        $minMs = 946684800000;                       // 2000-01-01
        $maxMs = (time() + 86400) * 1000;            // one day into the future
        return max($minMs, min($maxMs, $value));
    }

    /** @param array<string,mixed> $row */
    public static function uuid(array $row, string $key): string
    {
        $value = $row[$key] ?? '';
        if (!is_string($value)) {
            throw new ApiException('Missing or malformed identifier.', 422, 'invalid_uuid');
        }
        $value = strtoupper(trim($value));
        if (preg_match('/^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/', $value) !== 1) {
            throw new ApiException('Missing or malformed identifier.', 422, 'invalid_uuid');
        }
        return $value;
    }

    /** @param array<string,mixed> $row */
    public static function optionalUuid(array $row, string $key): ?string
    {
        $value = $row[$key] ?? null;
        if ($value === null || $value === '') {
            return null;
        }
        return self::uuid($row, $key);
    }

    /**
     * One of a fixed set, falling back rather than throwing: an unknown status
     * from a newer client build should not fail the whole sync batch.
     *
     * @param array<string,mixed> $row
     * @param array<int,string>   $allowed
     */
    public static function enum(array $row, string $key, array $allowed, string $default): string
    {
        $value = $row[$key] ?? $default;
        if (is_string($value) && in_array($value, $allowed, true)) {
            return $value;
        }
        return $default;
    }

    /** @param array<string,mixed> $row */
    public static function optionalEnum(array $row, string $key, array $allowed): ?string
    {
        $value = $row[$key] ?? null;
        if (is_string($value) && in_array($value, $allowed, true)) {
            return $value;
        }
        return null;
    }

    /**
     * @param  array<string,mixed> $row
     * @return array<int,array<string,mixed>>
     */
    public static function objectList(array $row, string $key, int $maxItems): array
    {
        $value = $row[$key] ?? [];
        if (!is_array($value)) {
            return [];
        }
        $out = [];
        foreach ($value as $item) {
            if (is_array($item)) {
                $out[] = $item;
            }
            if (count($out) >= $maxItems) {
                break;
            }
        }
        return $out;
    }

    public static function msToSql(int $ms): string
    {
        return gmdate('Y-m-d H:i:s', (int) floor($ms / 1000));
    }

    public static function sqlToMs(?string $sql): ?int
    {
        if ($sql === null || $sql === '') {
            return null;
        }
        $ts = strtotime($sql . ' UTC');
        return $ts === false ? null : $ts * 1000;
    }
}
