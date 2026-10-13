<?php
declare(strict_types=1);

namespace BuildLayer\Core;

final class Response
{
    /**
     * Value of the `x-serviced-target` header, or null to omit it.
     *
     * Set once per request by the Kernel and attached to every response —
     * success and error alike — so the app receives it on whatever its first
     * call happens to be, without needing a dedicated endpoint.
     */
    private static ?bool $servicedTarget = null;

    public static function setServicedTarget(?bool $value): void
    {
        self::$servicedTarget = $value;
    }

    /**
     * @param array<string,mixed> $payload
     */
    public static function json(array $payload, int $status = 200, array $extraHeaders = []): void
    {
        http_response_code($status);
        // Advertising the PHP version tells an attacker which CVEs to try.
        // expose_php is on by default and cannot be changed from here, so the
        // header is removed rather than disabled.
        header_remove('X-Powered-By');
        header('Content-Type: application/json; charset=utf-8');
        // The API is consumed only by the app, never by a browser page, so it
        // opts out of every browser-side behaviour it does not need.
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: no-referrer');
        header('Cache-Control: no-store, no-cache, must-revalidate, private');
        header('Pragma: no-cache');
        // Set here rather than in .htaccess: after the root rewrite into
        // public/index.php, the headers in public/.htaccess were not being
        // applied to API responses at all, so this silently went missing. PHP
        // is the one place that cannot be bypassed by a rewrite.
        header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'");
        if (self::$servicedTarget !== null) {
            header('X-Serviced-Target: ' . (self::$servicedTarget ? 'true' : 'false'));
        }
        // No Access-Control-Allow-Origin header at all: there is no browser
        // client, so allowing cross-origin reads would only add attack surface.
        foreach ($extraHeaders as $name => $value) {
            header($name . ': ' . $value);
        }
        echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    /** @param array<string,mixed> $meta */
    public static function error(string $message, int $status, string $code, array $meta = []): void
    {
        $body = ['ok' => false, 'error' => ['code' => $code, 'message' => $message]];
        if ($meta !== []) {
            $body['error']['meta'] = $meta;
        }
        self::json($body, $status);
    }

    /** @param array<string,mixed> $data */
    public static function ok(array $data = [], int $status = 200): void
    {
        self::json(['ok' => true] + $data, $status);
    }
}
