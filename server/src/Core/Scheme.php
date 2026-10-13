<?php
declare(strict_types=1);

namespace BuildLayer\Core;

/**
 * Works out whether the request arrived over TLS.
 *
 * Harder than it looks on shared hosting. TLS is often terminated upstream —
 * by LiteSpeed, a load balancer, or Cloudflare — and the backend is then told
 * so through one of half a dozen different headers, or not told at all. An
 * earlier version of this check recognised exactly two signals and refused
 * everything else, which meant a perfectly good HTTPS request was answered with
 * 403 on any host that advertised it a third way.
 */
final class Scheme
{
    /**
     * Every signal consulted, with what it said. Used for the error body and
     * the diagnose script, so a misfire can be read rather than guessed at.
     *
     * @return array<string,string>
     */
    public static function signals(): array
    {
        $keys = [
            'HTTPS', 'REQUEST_SCHEME', 'SERVER_PORT',
            'HTTP_X_FORWARDED_PROTO', 'HTTP_X_FORWARDED_SSL', 'HTTP_X_FORWARDED_PORT',
            'HTTP_X_URL_SCHEME', 'HTTP_CF_VISITOR', 'HTTP_FRONT_END_HTTPS',
        ];
        $out = [];
        foreach ($keys as $key) {
            $out[$key] = isset($_SERVER[$key]) ? (string) $_SERVER[$key] : '(unset)';
        }
        return $out;
    }

    public static function isSecure(): bool
    {
        // Direct TLS at this server.
        $https = strtolower((string) ($_SERVER['HTTPS'] ?? ''));
        if ($https !== '' && $https !== 'off' && $https !== '0') {
            return true;
        }
        if (strtolower((string) ($_SERVER['REQUEST_SCHEME'] ?? '')) === 'https') {
            return true;
        }
        if ((int) ($_SERVER['SERVER_PORT'] ?? 0) === 443) {
            return true;
        }

        // Terminated upstream. These headers are only meaningful because a
        // proxy in front of us sets them; a client could forge them over
        // plaintext, which is why this check is defence in depth and never the
        // thing protecting the data — the signature and the bearer token are.
        // The app itself only ever uses an https:// URL compiled into the
        // binary, so in practice nothing legitimate arrives in the clear.
        $forwardedProto = strtolower((string) ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? ''));
        // May be a list, "https,http", when more than one proxy is in the path.
        if ($forwardedProto !== '' && strpos($forwardedProto, 'https') === 0) {
            return true;
        }
        if (strtolower((string) ($_SERVER['HTTP_X_FORWARDED_SSL'] ?? '')) === 'on') {
            return true;
        }
        if ((int) ($_SERVER['HTTP_X_FORWARDED_PORT'] ?? 0) === 443) {
            return true;
        }
        if (strtolower((string) ($_SERVER['HTTP_X_URL_SCHEME'] ?? '')) === 'https') {
            return true;
        }
        if (strtolower((string) ($_SERVER['HTTP_FRONT_END_HTTPS'] ?? '')) === 'on') {
            return true;
        }
        // Cloudflare: {"scheme":"https"}
        $cf = (string) ($_SERVER['HTTP_CF_VISITOR'] ?? '');
        if ($cf !== '' && strpos($cf, '"scheme":"https"') !== false) {
            return true;
        }

        // Last resort, opt-in: the host terminates TLS and advertises nothing
        // at all. Set only when you have confirmed the site is HTTPS-only.
        return (bool) Config::get('trust_proxy_https', false);
    }
}
