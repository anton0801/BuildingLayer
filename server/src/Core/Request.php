<?php
declare(strict_types=1);

namespace BuildLayer\Core;

/**
 * The incoming HTTP request, already parsed and size-checked.
 */
final class Request
{
    public string $method;
    public string $path;
    /** @var array<string,string> lower-cased header names */
    public array $headers;
    /** @var array<string,string> */
    public array $query;
    public string $rawBody;
    /** @var array<string,mixed> */
    public array $json;

    private function __construct()
    {
        $this->method  = 'GET';
        $this->path    = '/';
        $this->headers = [];
        $this->query   = [];
        $this->rawBody = '';
        $this->json    = [];
    }

    public static function capture(): self
    {
        $r = new self();
        $r->method = strtoupper((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET'));

        $uri = (string) ($_SERVER['REQUEST_URI'] ?? '/');
        $path = parse_url($uri, PHP_URL_PATH);
        $r->path = is_string($path) ? $path : '/';

        // The API may be mounted anywhere — /api, /api/public, the domain root —
        // and under Apache, the built-in server or a proxy, each of which
        // reports SCRIPT_NAME differently. Since every route begins with the
        // version segment, the mount prefix is simply whatever precedes it.
        // Deriving the prefix from SCRIPT_NAME instead was correct for exactly
        // one of those deployments.
        $marker = strpos($r->path, '/v1/');
        if ($marker !== false) {
            $r->path = substr($r->path, $marker);
        } elseif (substr($r->path, -3) === '/v1') {
            $r->path = '/v1';
        }
        $r->path = '/' . ltrim($r->path, '/');
        if ($r->path !== '/') {
            $r->path = rtrim($r->path, '/');
        }

        foreach ($_SERVER as $key => $value) {
            if (strpos($key, 'HTTP_') === 0) {
                $name = strtolower(str_replace('_', '-', substr($key, 5)));
                $r->headers[$name] = (string) $value;
            } elseif (strpos($key, 'REDIRECT_HTTP_') === 0 || strpos($key, 'REDIRECT_REDIRECT_HTTP_') === 0) {
                // Variables an internal rewrite renamed (see authorizationHeader).
                $name = strtolower(str_replace('_', '-', $key));
                $r->headers[$name] = (string) $value;
            }
        }
        if (isset($_SERVER['CONTENT_TYPE'])) {
            $r->headers['content-type'] = (string) $_SERVER['CONTENT_TYPE'];
        }

        /** @var array<string,string> $query */
        $query = [];
        foreach ($_GET as $k => $v) {
            if (is_string($v)) {
                $query[(string) $k] = $v;
            }
        }
        $r->query = $query;

        $max = (int) Config::get('limits.max_body_bytes', 2097152);
        $declared = (int) ($_SERVER['CONTENT_LENGTH'] ?? 0);
        if ($declared > $max) {
            throw new ApiException('Request body too large.', 413, 'body_too_large');
        }

        $body = file_get_contents('php://input');
        $r->rawBody = $body === false ? '' : $body;
        if (strlen($r->rawBody) > $max) {
            throw new ApiException('Request body too large.', 413, 'body_too_large');
        }

        if ($r->rawBody !== '' && strpos($r->header('content-type'), 'application/json') !== false) {
            $decoded = json_decode($r->rawBody, true);
            if (!is_array($decoded)) {
                throw new ApiException('Body is not valid JSON.', 400, 'invalid_json');
            }
            /** @var array<string,mixed> $decoded */
            $r->json = $decoded;
        }

        return $r;
    }

    public function header(string $name): string
    {
        return $this->headers[strtolower($name)] ?? '';
    }

    public function bearerToken(): string
    {
        $auth = $this->authorizationHeader();
        if (stripos($auth, 'Bearer ') === 0) {
            return trim(substr($auth, 7));
        }
        return '';
    }

    /**
     * Finds the Authorization header wherever Apache left it.
     *
     * Under CGI/FastCGI Apache does not pass Authorization to PHP at all; the
     * .htaccess copies it into an environment variable instead. Each internal
     * rewrite then prefixes that variable with REDIRECT_, and this project
     * rewrites twice when the whole folder sits in the webroot (root .htaccess
     * into public/, then public/.htaccess). So the token can arrive under any
     * of four names — reading only HTTP_AUTHORIZATION means every authenticated
     * request fails with "Authentication required" on a real host, while
     * working perfectly against PHP's built-in server.
     */
    private function authorizationHeader(): string
    {
        foreach (['authorization', 'redirect-http-authorization',
                  'redirect-redirect-http-authorization'] as $name) {
            if (($this->headers[$name] ?? '') !== '') {
                return $this->headers[$name];
            }
        }
        foreach (['HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION',
                  'REDIRECT_REDIRECT_HTTP_AUTHORIZATION'] as $key) {
            if (!empty($_SERVER[$key])) {
                return (string) $_SERVER[$key];
            }
        }
        // Last resort: ask Apache directly, which sees the original header even
        // when it declined to export it.
        if (function_exists('apache_request_headers')) {
            $headers = apache_request_headers();
            if (is_array($headers)) {
                foreach ($headers as $name => $value) {
                    if (strcasecmp($name, 'Authorization') === 0) {
                        return (string) $value;
                    }
                }
            }
        }
        return '';
    }

    /**
     * The client's IP, trusting no proxy header by default.
     *
     * X-Forwarded-For is attacker-controlled unless a known proxy set it, and
     * believing it would let anyone sidestep per-IP rate limits by making one up.
     */
    public function ip(): string
    {
        return (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');
    }

    /** @return mixed */
    public function input(string $key, $default = null)
    {
        return array_key_exists($key, $this->json) ? $this->json[$key] : $default;
    }
}
