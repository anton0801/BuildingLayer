<?php
declare(strict_types=1);

/**
 * PSR-4 autoloader for the BuildLayer\ namespace.
 *
 * Hand-written because shared hosting has no Composer. It is ~15 lines and has
 * no dependency to keep up to date, which for a project this size is a feature.
 */
spl_autoload_register(static function (string $class): void {
    $prefix = 'BuildLayer\\';
    if (strpos($class, $prefix) !== 0) {
        return;
    }
    $relative = substr($class, strlen($prefix));
    $path = __DIR__ . '/' . str_replace('\\', '/', $relative) . '.php';
    // realpath + prefix check: defence in depth against a crafted class name
    // ever reaching this and escaping the source directory.
    $real = realpath($path);
    if ($real !== false && strpos($real, realpath(__DIR__) . DIRECTORY_SEPARATOR) === 0) {
        require $real;
    }
});
