<?php
declare(strict_types=1);

namespace BuildLayer\Core;

/**
 * Loads config.php once and exposes it by dotted path.
 */
final class Config
{
    /** @var array<string,mixed> */
    private static array $data = [];

    public static function load(string $path): void
    {
        if (!is_file($path)) {
            throw new \RuntimeException('Configuration file is missing.');
        }
        /** @var array<string,mixed> $loaded */
        $loaded = require $path;
        self::$data = $loaded;
    }

    /**
     * @param  string $key     dotted path, e.g. "db.host"
     * @param  mixed  $default
     * @return mixed
     */
    public static function get(string $key, $default = null)
    {
        $node = self::$data;
        foreach (explode('.', $key) as $segment) {
            if (!is_array($node) || !array_key_exists($segment, $node)) {
                return $default;
            }
            $node = $node[$segment];
        }
        return $node;
    }

    public static function isDebug(): bool
    {
        return (bool) self::get('debug', false);
    }
}
