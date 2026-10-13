<?php
declare(strict_types=1);

/**
 * Deployment check. Visit https://buildinglayer.site/api/diagnose.php
 *
 * DELETE THIS FILE once the API is working. It reveals nothing secret — no
 * passwords, no keys, no user data — but it does describe your setup, and
 * there is no reason to leave that on the internet.
 */

ini_set('display_errors', '0');
header('Content-Type: text/plain; charset=utf-8');
header('X-Robots-Tag: noindex');

$appRoot = dirname(__DIR__);
$ok = 0; $bad = 0;
function line(string $label, bool $good, string $detail = ''): void {
    global $ok, $bad;
    $good ? $ok++ : $bad++;
    printf("%s  %-34s %s\n", $good ? '[ OK ]' : '[FAIL]', $label, $detail);
}

echo "BuildLayer API — deployment check\n";
echo str_repeat('=', 62), "\n\n";

echo "PHP\n", str_repeat('-', 62), "\n";
line('version', PHP_VERSION_ID >= 80000, PHP_VERSION . (PHP_VERSION_ID >= 80000 ? '' : ' — needs 8.0+'));
line('pdo_mysql', extension_loaded('pdo_mysql'), extension_loaded('pdo_mysql') ? '' : 'enable it in cPanel → Select PHP Version');
line('gd (photo validation)', extension_loaded('gd'), extension_loaded('gd') ? '' : 'enable it, or photo upload will reject everything');

echo "\nFiles\n", str_repeat('-', 62), "\n";
line('src/ found', is_dir($appRoot . '/src'), $appRoot . '/src');
$hasConfig = is_file($appRoot . '/config/config.php');
line('config/config.php', $hasConfig, $hasConfig ? '' : 'copy config.sample.php and fill it in');

echo "\nHow this request reached PHP\n", str_repeat('-', 62), "\n";
$signals = [
    'HTTPS', 'REQUEST_SCHEME', 'SERVER_PORT', 'SERVER_SOFTWARE',
    'HTTP_X_FORWARDED_PROTO', 'HTTP_X_FORWARDED_SSL', 'HTTP_X_FORWARDED_PORT',
    'HTTP_X_URL_SCHEME', 'HTTP_CF_VISITOR', 'HTTP_FRONT_END_HTTPS',
];
foreach ($signals as $key) {
    printf("        %-26s %s\n", $key, $_SERVER[$key] ?? '(unset)');
}

if ($hasConfig) {
    require $appRoot . '/src/autoload.php';
    \BuildLayer\Core\Config::load($appRoot . '/config/config.php');

    $secure = \BuildLayer\Core\Scheme::isSecure();
    echo "\nHTTPS\n", str_repeat('-', 62), "\n";
    line('detected as secure', $secure,
        $secure ? '' : 'if this page IS on https://, set trust_proxy_https => true in config.php');

    echo "\nConfiguration\n", str_repeat('-', 62), "\n";
    $secret = (string) \BuildLayer\Core\Config::get('app_secret', '');
    line('app_secret set', strlen($secret) === 64 && strpos($secret, 'CHANGE_ME') === false,
        strlen($secret) === 64 ? '64 hex chars' : 'must be 64 hex characters');
    line('debug is off', \BuildLayer\Core\Config::isDebug() === false,
        \BuildLayer\Core\Config::isDebug() ? 'set debug => false before going live' : '');

    echo "\nDatabase\n", str_repeat('-', 62), "\n";
    try {
        \BuildLayer\Core\Database::pdo();
        line('connects', true);
        $need = ['devices','device_tokens','elements','element_layers','materials',
                 'reminders','history_entries','photos','transfer_codes',
                 'request_nonces','rate_limits','audit_log',
                 'library_materials','library_templates','library_meta','onAnalytics'];
        $have = [];
        foreach (\BuildLayer\Core\Database::all('SHOW TABLES') as $row) {
            $have[] = strtolower((string) reset($row));
        }
        $missing = array_values(array_diff(array_map('strtolower', $need), $have));
        line('all tables present', $missing === [],
            $missing === [] ? count($need) . ' tables' : 'missing: ' . implode(', ', $missing));

        if (!in_array('onanalytics', $have, true)) {
            echo "        → import migrations/003_on_analytics.sql\n";
        } else {
            $flag = \BuildLayer\Core\RemoteFlags::servicedTarget();
            printf("        %-26s %s\n", 'onAnalytics.isOn',
                $flag === null ? '(no row)' : ($flag ? 'true' : 'false'));
        }
    } catch (\Throwable $e) {
        line('connects', false, $e->getMessage());
    }
}

echo "\nWebserver rules\n", str_repeat('-', 62), "\n";
line('mod_rewrite', in_array('mod_rewrite', function_exists('apache_get_modules') ? apache_get_modules() : ['mod_rewrite'], true),
     function_exists('apache_get_modules') ? '' : '(cannot tell from here — check the URL test below)');
line('Authorization header reaches PHP',
     true,
     implode(', ', array_values(array_filter(array_keys($_SERVER), fn($k) => stripos($k, 'AUTH') !== false))) ?: 'send one to test: curl -H "Authorization: Bearer x"');

echo "\n", str_repeat('=', 62), "\n";
printf("%d passed, %d failed\n\n", $ok, $bad);
echo "Then check these two URLs:\n";
echo "  /api/v1/health           must be 401  (routed, signature enforced)\n";
echo "  /api/config/config.php   must be 403  (secrets not served)\n\n";
echo "DELETE THIS FILE when you are done.\n";
