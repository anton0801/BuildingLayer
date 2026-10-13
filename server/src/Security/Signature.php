<?php
declare(strict_types=1);

namespace BuildLayer\Security;

use BuildLayer\Core\ApiException;
use BuildLayer\Core\Config;
use BuildLayer\Core\Database;
use BuildLayer\Core\Request;

/**
 * Verifies that a request came from a genuine app build and has not been
 * replayed.
 *
 * What this buys: an attacker who finds the endpoint cannot simply curl it, and
 * a captured request cannot be resent later. What it does not buy: secrecy. The
 * signing key ships inside the IPA and can be extracted by anyone determined
 * enough, so this is a cost-raiser layered under the bearer token, never a
 * substitute for it. Authorisation of *data* is always by token.
 */
final class Signature
{
    /**
     * canonical string =
     *   METHOD \n PATH \n TIMESTAMP \n NONCE \n sha256hex(rawBody)
     *
     * The body hash is what stops a valid signature being reused with swapped
     * contents, and the path is included so a signature for one endpoint cannot
     * be replayed against another.
     */
    public static function verify(Request $request): void
    {
        $secret = (string) Config::get('app_secret', '');
        if ($secret === '' || $secret === 'CHANGE_ME_64_HEX_CHARS') {
            throw new ApiException('Server is not configured.', 500, 'server_misconfigured');
        }

        $timestamp = $request->header('x-bl-timestamp');
        $nonce     = $request->header('x-bl-nonce');
        $provided  = $request->header('x-bl-signature');

        if ($timestamp === '' || $nonce === '' || $provided === '') {
            throw new ApiException('Request is not signed.', 401, 'signature_missing');
        }
        if (!ctype_digit($timestamp)) {
            throw new ApiException('Malformed signature timestamp.', 401, 'signature_invalid');
        }
        if (strlen($nonce) !== 32 || ctype_xdigit($nonce) === false) {
            throw new ApiException('Malformed signature nonce.', 401, 'signature_invalid');
        }

        $window = (int) Config::get('limits.signature_window', 300);
        $skew = abs(time() - (int) $timestamp);
        if ($skew > $window) {
            throw new ApiException('Request timestamp is outside the accepted window.', 401, 'signature_expired');
        }

        $canonical = implode("\n", [
            $request->method,
            $request->path,
            $timestamp,
            $nonce,
            hash('sha256', $request->rawBody),
        ]);
        $expected = base64_encode(hash_hmac('sha256', $canonical, $secret, true));

        // Constant-time: a plain === leaks how much of the signature matched
        // through timing, which is enough to forge one byte at a time.
        if (!hash_equals($expected, $provided)) {
            throw new ApiException('Signature does not match.', 401, 'signature_invalid');
        }

        self::consumeNonce($nonce, $window);
    }

    /**
     * Burns the nonce so the exact same signed request cannot be sent twice.
     * The primary key does the work: a duplicate insert is the replay.
     */
    private static function consumeNonce(string $nonce, int $window): void
    {
        try {
            Database::run(
                'INSERT INTO request_nonces (nonce, seen_at) VALUES (?, ?)',
                [$nonce, Database::utcNow()]
            );
        } catch (\PDOException $e) {
            if ($e->getCode() === '23000') {
                throw new ApiException('Request has already been used.', 401, 'replay_detected');
            }
            throw $e;
        }

        // No cron on shared hosting, so expired rows are swept opportunistically.
        if (random_int(1, 50) === 1) {
            Database::run(
                'DELETE FROM request_nonces WHERE seen_at < ?',
                [gmdate('Y-m-d H:i:s', time() - ($window * 4))]
            );
        }
    }
}
