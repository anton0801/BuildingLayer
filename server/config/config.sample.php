<?php
/**
 * BuildLayer API configuration.
 *
 * Copy to config.php and fill in. Keep config.php OUTSIDE the webroot — on
 * cPanel that means the home directory, not public_html. If it must live inside
 * the webroot, the shipped .htaccess denies it, but "outside" is the only
 * arrangement that survives a webserver misconfiguration.
 *
 * Never commit config.php.
 */

return [
    'db' => [
        'host'     => 'localhost',
        'port'     => 3306,
        'name'     => 'buildinglayer',
        'user'     => 'buildinglayer_api',
        'pass'     => 'CHANGE_ME',
        'charset'  => 'utf8mb4',
    ],

    /**
     * Shared secret the app signs every request with (HMAC-SHA256).
     *
     * This does not replace the bearer token — it authenticates the *client
     * build*, not the user. Anyone who unpacks the IPA can read it, so it is a
     * cost-raiser against casual scripted abuse, not a secret in the strong
     * sense. The bearer token is what actually guards a device's data.
     *
     * Generate with:  php -r "echo bin2hex(random_bytes(32));"
     * Must match APIConfig.signingKey in the iOS app.
     */
    'app_secret' => 'CHANGE_ME_64_HEX_CHARS',

    /**
     * Pepper mixed into hashes of IPs before they are written to audit_log, so
     * the log is useful for spotting abuse without storing raw addresses.
     */
    'ip_pepper' => 'CHANGE_ME_ANOTHER_32_HEX',

    'tokens' => [
        'access_ttl_days'  => 90,
        'refresh_ttl_days' => 400,
    ],

    'transfer' => [
        'code_ttl_seconds' => 600,   // 10 minutes
        'max_attempts'     => 5,
    ],

    'limits' => [
        // Largest JSON body accepted, in bytes. A sync push of a few hundred
        // elements is well under this.
        'max_body_bytes'   => 2 * 1024 * 1024,
        'max_photo_bytes'  => 3 * 1024 * 1024,
        'max_batch_items'  => 400,
        // Seconds a signed request stays valid. Short enough that a captured
        // request cannot be replayed later, long enough for clock skew.
        'signature_window' => 300,
    ],

    /**
     * Per-window request caps. Format: [max hits, window seconds].
     */
    'rate' => [
        'register' => [10, 3600],    // per IP — registration is the abuse target
        'transfer' => [10, 3600],    // per IP — brute-forcing a transfer code
        'sync'     => [240, 3600],   // per device
        'photo'    => [120, 3600],   // per device
        'default'  => [600, 3600],   // per device
    ],

    // Absolute path to photo storage. Must NOT be inside the webroot.
    /**
     * Set true ONLY if the site is served over HTTPS but the server does not
     * tell PHP so — some hosts terminate TLS upstream and forward nothing.
     * Symptom: every request answers 403 https_required while the site clearly
     * works in a browser. Run diagnose.php to confirm before changing this.
     */
    'trust_proxy_https' => false,

    'storage_path' => __DIR__ . '/../storage',

    // true only while debugging: turns on verbose error output.
    'debug' => false,
];
