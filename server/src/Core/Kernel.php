<?php
declare(strict_types=1);

namespace BuildLayer\Core;

use BuildLayer\Controllers\DeviceController;
use BuildLayer\Controllers\LibraryController;
use BuildLayer\Controllers\PhotoController;
use BuildLayer\Controllers\SyncController;

use BuildLayer\Security\RateLimiter;
use BuildLayer\Security\Signature;
use BuildLayer\Security\Tokens;

/**
 * Wires routes and runs the request through the fixed pipeline:
 *
 *   HTTPS check -> signature -> rate limit -> token -> handler
 *
 * The order matters. Signature verification is cheap and rejects unsigned junk
 * before it can cost a database round-trip; rate limiting sits ahead of token
 * lookup so a flood of bad tokens cannot be used to hammer the tokens table.
 */
final class Kernel
{
    private Router $router;

    public function __construct()
    {
        $this->router = new Router();
        $this->registerRoutes();
    }

    private function registerRoutes(): void
    {
        $device  = new DeviceController();
        $sync    = new SyncController();
        $library = new LibraryController();
        $photo   = new PhotoController();

        // Public: no bearer token yet, but still signed and rate limited.
        $this->router->add('GET',  '/v1/health',           [$this, 'health'], false);
        $this->router->add('POST', '/v1/devices/register', [$device, 'register'], false);
        $this->router->add('POST', '/v1/devices/refresh',  [$device, 'refresh'], false);
        $this->router->add('POST', '/v1/transfer/redeem',  [$device, 'redeemTransferCode'], false);

        // Authenticated.
        $this->router->add('GET',  '/v1/devices/me',       [$device, 'me']);
        $this->router->add('POST', '/v1/devices/delete',   [$device, 'deleteAccount']);
        $this->router->add('POST', '/v1/transfer/create',  [$device, 'createTransferCode']);
        $this->router->add('GET',  '/v1/sync/pull',        [$sync, 'pull']);
        $this->router->add('POST', '/v1/sync/push',        [$sync, 'push']);
        $this->router->add('GET',  '/v1/library/version',  [$library, 'version']);
        $this->router->add('GET',  '/v1/library',          [$library, 'fetch']);
        $this->router->add('POST', '/v1/photos/upload',    [$photo, 'upload']);
        $this->router->add('GET',  '/v1/photos/get',       [$photo, 'download']);
        $this->router->add('POST', '/v1/photos/delete',    [$photo, 'delete']);
    }

    public function run(): void
    {
        try {
            $request = Request::capture();

            // Read before dispatch so the header is present even on an error
            // response — the app's very first call may well be a 401.
            Response::setServicedTarget(RemoteFlags::servicedTarget());

            $this->requireHttps();

            $route = $this->router->match($request->method, $request->path);
            if ($route === null) {
                // 405 when the path exists under another verb, so a client bug
                // is distinguishable from a wrong URL.
                if ($this->router->pathExists($request->path)) {
                    throw new ApiException('Method not allowed for this endpoint.', 405, 'method_not_allowed');
                }
                throw new ApiException('Unknown endpoint.', 404, 'not_found');
            }

            [$handler, $requiresAuth] = $route;

            Signature::verify($request);

            if ($requiresAuth) {
                $device = Tokens::authenticate($request->bearerToken());
                RateLimiter::hit($this->scopeFor($request->path), (string) $device['id']);
                Tokens::pruneExpired();
                $handler($request, $device);
            } else {
                $handler($request);
            }
        } catch (ApiException $e) {
            Response::error($e->getMessage(), $e->status(), $e->errorCode(), $e->meta());
        } catch (\Throwable $e) {
            // Never leak an internal message. In debug the detail is echoed
            // back; in production it goes to the server log only.
            error_log('[buildlayer-api] ' . $e->getMessage() . ' @ ' . $e->getFile() . ':' . $e->getLine());
            if (Config::isDebug()) {
                Response::error($e->getMessage(), 500, 'server_error', [
                    'file' => $e->getFile(),
                    'line' => $e->getLine(),
                ]);
            } else {
                Response::error('Something went wrong on our side.', 500, 'server_error');
            }
        }
    }

    /**
     * Refuses plaintext outright rather than redirecting.
     *
     * A redirect would mean the first request — the one carrying the token —
     * had already crossed the network in the clear. There is nothing to salvage
     * at that point, so the correct answer is to fail and force the client to
     * use HTTPS from the start.
     */
    private function requireHttps(): void
    {
        if (Config::isDebug() || Scheme::isSecure()) {
            if (!Config::isDebug()) {
                header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
            }
            return;
        }

        // The signals are attached so a misfire is diagnosable from the
        // response itself. They are hostnames and ports, not secrets — and
        // without them this failure is indistinguishable from a broken
        // .htaccess, which is exactly the confusion it used to cause.
        throw new ApiException(
            'HTTPS is required. If this site is served over HTTPS, the server is not telling PHP so — '
            . 'set trust_proxy_https to true in config.php.',
            403,
            'https_required',
            ['detected' => Scheme::signals()]
        );
    }

    private function scopeFor(string $path): string
    {
        if (strpos($path, '/v1/sync') === 0) {
            return 'sync';
        }
        if (strpos($path, '/v1/photos') === 0) {
            return 'photo';
        }
        return 'default';
    }

    public function health(Request $request): void
    {
        // Touches the database so the check means "the API can serve", not
        // merely "PHP is running".
        Database::first('SELECT 1 AS ok');
        Response::ok(['status' => 'healthy', 'time' => gmdate('c')]);
    }
}
