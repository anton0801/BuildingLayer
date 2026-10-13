# BuildLayer API

PHP 8.0+ / MySQL. No Composer, no cron, no extensions beyond `pdo_mysql` and
`gd` — it is written to run on ordinary cPanel shared hosting.

Serves `buildinglayer.site` for BuildLayer 1.1.

---

## What it does

Anonymous, device-scoped backup and sync. There are no accounts, no email
addresses and no passwords: the app generates a random install secret on first
launch, keeps it in the iOS Keychain, and proves ownership with it. The server
stores project data and knows nothing about who owns it.

Because that ties an account to one install, there is a **transfer flow**: the
old phone generates a 9-digit code, the new phone redeems it, and the account
moves. Without it, reinstalling the app would lose the backup and the whole
feature would be pointless.

---

## Layout on the server

There are two ways to deploy. Pick A if your host lets you; B is what the
shipped `.htaccess` files support out of the box.

### A. Split layout (better)

Only `public/` is reachable over HTTP. Everything else sits above the webroot,
so no webserver misconfiguration can serve your database password or a
customer's photograph.

```
/home/USER/
├── buildinglayer_app/          <- NOT web-accessible
│   ├── src/  config/  migrations/  storage/
└── public_html/
    └── api/                    <- webroot
        ├── index.php           <- copied from public/index.php
        └── .htaccess           <- copied from public/.htaccess
```

Then **edit one line** in `public_html/api/index.php`, because
`dirname(__DIR__)` would otherwise resolve to `public_html`:

```php
$appRoot = '/home/USER/buildinglayer_app';
```

### B. Whole folder in the webroot (simplest)

Upload `server/` as-is, either to `public_html/api/` or straight into
`public_html/`. Nothing needs editing either way: `public/index.php` finds the
rest via `dirname(__DIR__)`, and the API answers on `/api/v1/...` in both cases
— the front controller locates the version segment rather than assuming a mount
point.

Static pages (`privacy.html`, `support.html`) can sit beside it: the root
`.htaccess` serves anything that exists on disk as itself and only forwards the
rest to the API.

```
public_html/
└── api/                        <- the whole server/ folder
    ├── .htaccess               <- forwards everything into public/
    ├── public/index.php
    ├── src/  config/  migrations/  storage/   <- each denied by its own .htaccess
    └── Tools/  README.md
```

The root `.htaccess` forwards every request into `public/index.php` and refuses
`src/`, `config/`, `migrations/`, `storage/` and `Tools/`, each of which also
carries its own deny file.

Be clear about the trade-off: in layout A those directories are unreachable
because the webserver cannot see them; in layout B they are reachable and merely
refused, so the protection depends on `.htaccess` being honoured. It requires
`AllowOverride All` (or at least `FileInfo Limit Options`) — which is the cPanel
default. **If `AllowOverride` is `None`, the deny rules are ignored *and* the
forwarding stops working**, so a working API is itself evidence that the deny
rules are active. Verify anyway with the check below.

---

## Install

**1. Database.** In cPanel → MySQL Databases, create a database and a user, and
grant that user ALL PRIVILEGES on it. Then in phpMyAdmin, select the database
and import:

```
migrations/001_init.sql
migrations/002_seed_library.sql
```

**2. Configuration.** Copy `config/config.sample.php` to `config/config.php` and
fill in the database credentials. Generate the two secrets:

```bash
php -r "echo bin2hex(random_bytes(32)), \"\n\";"   # app_secret
php -r "echo bin2hex(random_bytes(16)), \"\n\";"   # ip_pepper
```

Leave `'debug' => false`. With debug on, exception messages are returned to the
client, which hands an attacker your filesystem layout.

**3. The app's copy of the secret.** `app_secret` must match
`APIConfig.signingKey` in the iOS app. It is stored XOR-masked there rather than
as a plain literal; regenerate the mask with:

```bash
swift Tools/mask-secret.swift "<your app_secret>"
```

and paste the result over `maskedSecret` in `BuildLayer/Sync/APIConfig.swift`.

**4. Permissions.**

```bash
chmod 700 /home/USER/buildinglayer_app/config
chmod 600 /home/USER/buildinglayer_app/config/config.php
chmod 750 /home/USER/buildinglayer_app/storage
```

**5. HTTPS.** Enable AutoSSL in cPanel for `buildinglayer.site`. The API refuses
plaintext outright rather than redirecting: a redirect would mean the token had
already crossed the network in the clear.

**6. Check it.** Two commands, both of which must give the answer shown.

```bash
# Routed, and enforcing signatures. 200 would mean requests are NOT being checked.
curl -s -o /dev/null -w '%{http_code}\n' https://buildinglayer.site/api/v1/health
# expect: 401

# Secrets are not served. 200 here means your database password is public.
curl -s -o /dev/null -w '%{http_code}\n' https://buildinglayer.site/api/config/config.php
# expect: 403
```

Anything else — 403 `https_required`, 503 `unconfigured`, 500 — points at the
step above it. On layout B, also spot-check `/api/src/Core/Database.php` and
`/api/migrations/001_init.sql`; both must be 403.

**Everything answers 403.** Almost always the HTTPS check, not the `.htaccess`.
Some hosts terminate TLS upstream and do not tell PHP, so the API believes the
request arrived in the clear.

Upload `public/diagnose.php` and open `https://buildinglayer.site/api/diagnose.php`
— it prints every signal the server passes through and says whether the request
was seen as secure. Or read the 403 body: it lists the same signals.

If the site really is HTTPS-only and none of the signals are set, switch on the
escape hatch in `config.php`:

```php
'trust_proxy_https' => true,
```

Do that only after confirming the site is HTTPS-only. It tells the API to stop
checking, and on a site that also answers on plain http it would let a request
through in the clear.

Delete `diagnose.php` once the deployment works.

**A page returns the API's JSON 404.** `{"code":"not_found"}` for something
like `/privacy.html` means the catch-all swallowed a real file. The root
`.htaccess` must contain this, immediately before the final rewrite:

```apache
RewriteCond %{REQUEST_FILENAME} -f [OR]
RewriteCond %{REQUEST_FILENAME} -d
RewriteRule ^ - [L]
```

Re-upload `.htaccess` if it is missing.

**A note on Authorization.** Apache does not pass the `Authorization` header to
PHP under CGI/FastCGI, so both `.htaccess` files copy it into an environment
variable, and the API reads it back from every name an internal rewrite can
leave it under. If authenticated calls ever start failing with
`unauthorized` while `/v1/health` still answers 401, this is the first thing to
check.

---

## Security model

| Layer | What it stops | What it does not |
|---|---|---|
| TLS + HSTS, plaintext refused | Reading or altering traffic | Anything on the device itself |
| HMAC request signature | Scripted calls from outside the app | A determined reverse-engineer — the key ships in the IPA |
| Nonce + 5-minute window | Replaying a captured request | — |
| Bearer token, stored hashed | Reading another device's data; a leaked DB being replayed | A token lifted off a jailbroken phone |
| `device_id` in every WHERE | One device reading another's rows | — |
| PDO prepared statements, no interpolation | SQL injection | — |
| Server-side clamping of every value | Hostile clients storing values that break the app | — |
| Per-IP and per-device rate limits | Brute force, registration floods | A large distributed botnet |

The signature authenticates the **build**, the token authorises the **data**.
They are not interchangeable, and the signature is deliberately not treated as a
secret in the strong sense.

---

## Endpoints

All paths are under `/api/v1`. Every request carries:

```
X-BL-Timestamp: <unix seconds>
X-BL-Nonce:     <32 hex chars, never reused>
X-BL-Signature: base64(HMAC-SHA256(app_secret, canonical))

canonical = METHOD \n PATH \n TIMESTAMP \n NONCE \n sha256hex(body)
```

Authenticated calls add `Authorization: Bearer <access_token>`.

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET  | `/health` | – | Liveness, including the database |
| POST | `/devices/register` | – | Register or re-attach an install |
| POST | `/devices/refresh` | – | Exchange a refresh token for a new access token |
| GET  | `/devices/me` | ✓ | Device info and row counts |
| POST | `/devices/delete` | ✓ | Erase everything this device owns |
| POST | `/transfer/create` | ✓ | Issue a 9-digit transfer code |
| POST | `/transfer/redeem` | – | Adopt an account with a code |
| GET  | `/sync/pull?since=N` | ✓ | Changes after revision N |
| POST | `/sync/push` | ✓ | Upload local changes |
| GET  | `/library/version` | ✓ | Catalogue version (cheap poll) |
| GET  | `/library` | ✓ | Materials and build-up templates |
| POST | `/photos/upload` | ✓ | Store an element photo |
| GET  | `/photos/get?uuid=…` | ✓ | Retrieve one |
| POST | `/photos/delete` | ✓ | Remove one |

Errors are `{"ok":false,"error":{"code":"…","message":"…"}}` with a matching
HTTP status.

---

## Sync semantics

Each device has its own monotonic `sync_rev`. Every row it changes is stamped
with the next value, so `?since=N` returns a minimal delta.

Conflicts resolve **last-write-wins on the client's edit timestamp**, evaluated
identically on both ends so the two cannot ping-pong. This is deliberately not a
merge: silently combining two versions of a build-up would produce a stack
nobody designed. Real conflicts only arise shortly after a transfer, when two
installs briefly hold the same account.

Deletions travel as tombstones. Without them a delete would simply be absent
from the next push and the following pull would hand the row straight back.

Layers are replaced wholesale with their element — an ordered stack only ever
changes as a unit.

---

## Housekeeping without cron

Shared hosting has no cron, so expired nonces, tokens, transfer codes and rate
counters are swept probabilistically: roughly 1 request in 50 prunes nonces, 1
in 200 prunes the rest. If you later move to a VPS, replace this with a nightly
job and remove the random gate in `Tokens::pruneExpired()`.

`audit_log` is **not** pruned — it is small by design and worth keeping. Check
it if something looks wrong:

```sql
SELECT event, COUNT(*) FROM audit_log
 WHERE created_at > DATE_SUB(UTC_TIMESTAMP(), INTERVAL 1 DAY)
 GROUP BY event;
```

---

## Updating the material catalogue

Edit `library_materials` / `library_templates`, then bump the version — the app
only re-downloads when it moves:

```sql
UPDATE library_meta SET version = version + 1, updated_at = UTC_TIMESTAMP() WHERE id = 1;
```

The app keeps its built-in catalogue as a fallback, so an unreachable server
degrades to a slightly stale library rather than an empty screen.

---

## Backups

`elements`, `element_layers`, `materials`, `reminders`, `history_entries` and
`photos` are user data. `storage/photos/` holds the image bytes and is **not**
in the database — a mysqldump alone is not a complete backup.
