<?php
declare(strict_types=1);

namespace BuildLayer\Core;

use PDO;

/**
 * Thin PDO wrapper. Every query in the codebase goes through here with bound
 * parameters — there is no string interpolation of user input anywhere, which
 * is what keeps SQL injection off the table rather than any filtering.
 */
final class Database
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            (string) Config::get('db.host', 'localhost'),
            (int) Config::get('db.port', 3306),
            (string) Config::get('db.name', ''),
            (string) Config::get('db.charset', 'utf8mb4')
        );

        self::$pdo = new PDO(
            $dsn,
            (string) Config::get('db.user', ''),
            (string) Config::get('db.pass', ''),
            [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                // Real prepared statements, not driver-side emulation: with
                // emulation on, the driver interpolates values itself and the
                // protection depends on its quoting rather than the server's.
                PDO::ATTR_EMULATE_PREPARES   => false,
                PDO::ATTR_STRINGIFY_FETCHES  => false,
            ]
        );

        return self::$pdo;
    }

    /**
     * @param  array<int|string,mixed> $params
     */
    public static function run(string $sql, array $params = []): \PDOStatement
    {
        $stmt = self::pdo()->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    /**
     * @param  array<int|string,mixed> $params
     * @return array<string,mixed>|null
     */
    public static function first(string $sql, array $params = []): ?array
    {
        $row = self::run($sql, $params)->fetch();
        return $row === false ? null : $row;
    }

    /**
     * @param  array<int|string,mixed> $params
     * @return array<int,array<string,mixed>>
     */
    public static function all(string $sql, array $params = []): array
    {
        return self::run($sql, $params)->fetchAll();
    }

    public static function transaction(callable $work)
    {
        $pdo = self::pdo();
        // Nested calls just join the outer transaction rather than failing.
        if ($pdo->inTransaction()) {
            return $work();
        }
        $pdo->beginTransaction();
        try {
            $result = $work();
            $pdo->commit();
            return $result;
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
    }

    public static function utcNow(): string
    {
        return gmdate('Y-m-d H:i:s');
    }
}
