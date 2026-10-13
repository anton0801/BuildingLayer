<?php
declare(strict_types=1);

namespace BuildLayer\Core;

/**
 * Routes are exact strings — the API has no path parameters, every identifier
 * travels in the body or the query. That keeps matching trivial and removes a
 * whole class of path-parsing mistakes.
 */
final class Router
{
    /** @var array<string,array{0:callable,1:bool}> "METHOD /path" => [handler, requiresAuth] */
    private array $routes = [];

    public function add(string $method, string $path, callable $handler, bool $requiresAuth = true): void
    {
        $this->routes[strtoupper($method) . ' ' . $path] = [$handler, $requiresAuth];
    }

    /** @return array{0:callable,1:bool}|null */
    public function match(string $method, string $path): ?array
    {
        $method = strtoupper($method);
        // HEAD is a GET without a body. Anything that polls the API for uptime
        // uses it, and answering 405 makes a healthy server look broken.
        if ($method === 'HEAD') {
            $method = 'GET';
        }
        return $this->routes[$method . ' ' . $path] ?? null;
    }

    public function pathExists(string $path): bool
    {
        foreach (array_keys($this->routes) as $key) {
            if (substr($key, strpos($key, ' ') + 1) === $path) {
                return true;
            }
        }
        return false;
    }
}
