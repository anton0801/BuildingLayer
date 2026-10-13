<?php
declare(strict_types=1);

/**
 * BuildLayer API — front controller.
 *
 * Deployment note: this file is the ONLY thing that belongs in the webroot.
 * src/, config/ and storage/ must live above it, so a webserver
 * misconfiguration cannot serve the database password or a customer's photo.
 */

// Errors are logged, never printed: a stack trace in a JSON response hands an
// attacker the filesystem layout and often the SQL.
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

// Adjust only if the layout differs from the documented one.
$appRoot = dirname(__DIR__);

require $appRoot . '/src/autoload.php';

use BuildLayer\Core\Config;
use BuildLayer\Core\Kernel;
use BuildLayer\Core\Response;

try {
    $configPath = is_file($appRoot . '/config/config.php')
        ? $appRoot . '/config/config.php'
        : $appRoot . '/config/config.sample.php';
    Config::load($configPath);
} catch (\Throwable $e) {
    error_log('[buildlayer-api] config load failed: ' . $e->getMessage());
    Response::error('Service is not configured.', 503, 'unconfigured');
    exit;
}

(new Kernel())->run();
