<?php
declare(strict_types=1);

namespace BuildLayer\Core;

/**
 * An error that is safe to show the client verbatim.
 *
 * Anything thrown that is NOT one of these becomes a generic 500, so an
 * unexpected PDO or filesystem message can never reach the response body.
 */
final class ApiException extends \RuntimeException
{
    private string $errorCode;
    /** @var array<string,mixed> */
    private array $meta;

    /** @param array<string,mixed> $meta */
    public function __construct(string $message, int $status = 400, string $errorCode = 'bad_request', array $meta = [])
    {
        parent::__construct($message, $status);
        $this->errorCode = $errorCode;
        $this->meta = $meta;
    }

    public function status(): int
    {
        $code = (int) $this->getCode();
        return ($code >= 400 && $code <= 599) ? $code : 400;
    }

    public function errorCode(): string
    {
        return $this->errorCode;
    }

    /** @return array<string,mixed> */
    public function meta(): array
    {
        return $this->meta;
    }
}
