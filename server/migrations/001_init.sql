-- BuildLayer API — initial schema
--
-- Target: MySQL 5.7+ / MariaDB 10.3+ on shared hosting (cPanel).
-- Deliberately avoids CHECK constraints, JSON column functions and window
-- functions so it imports on the older MySQL builds shared hosts still run.
--
-- Sync model: every device owns its rows outright. Each device carries its own
-- monotonic revision counter; any row the device changes is stamped with the
-- next value, so the client can ask "give me everything after rev N" and get a
-- minimal delta instead of the whole dataset.

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS devices (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  public_id         CHAR(36)        NOT NULL,
  -- SHA-256 of the install secret the app keeps in the Keychain. The secret
  -- itself is never stored, so a database dump cannot be replayed as a device.
  install_hash      CHAR(64)        NOT NULL,
  sync_rev          BIGINT UNSIGNED NOT NULL DEFAULT 0,
  platform          VARCHAR(16)     NOT NULL DEFAULT 'ios',
  app_version       VARCHAR(24)     NULL,
  os_version        VARCHAR(24)     NULL,
  model             VARCHAR(48)     NULL,
  created_at        DATETIME        NOT NULL,
  last_seen_at      DATETIME        NULL,
  -- Set when abuse is detected; every authenticated call then 403s.
  blocked_at        DATETIME        NULL,
  block_reason      VARCHAR(120)    NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_devices_public (public_id),
  UNIQUE KEY uq_devices_install (install_hash),
  KEY ix_devices_last_seen (last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS device_tokens (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id         BIGINT UNSIGNED NOT NULL,
  -- Tokens are stored hashed for the same reason passwords are: whoever reads
  -- the table must not be able to authenticate with what they read.
  token_hash        CHAR(64)        NOT NULL,
  kind              ENUM('access','refresh') NOT NULL,
  created_at        DATETIME        NOT NULL,
  expires_at        DATETIME        NOT NULL,
  last_used_at      DATETIME        NULL,
  revoked_at        DATETIME        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_token_hash (token_hash),
  KEY ix_token_device (device_id, kind),
  KEY ix_token_expiry (expires_at),
  CONSTRAINT fk_token_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- One-time codes that move an anonymous account to a new device. Without this
-- an anonymous install loses everything the moment the app is reinstalled,
-- which would make the backup pointless.
CREATE TABLE IF NOT EXISTS transfer_codes (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id         BIGINT UNSIGNED NOT NULL,
  code_hash         CHAR(64)        NOT NULL,
  created_at        DATETIME        NOT NULL,
  expires_at        DATETIME        NOT NULL,
  consumed_at       DATETIME        NULL,
  consumed_by       BIGINT UNSIGNED NULL,
  attempts          TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  UNIQUE KEY uq_transfer_hash (code_hash),
  KEY ix_transfer_device (device_id),
  KEY ix_transfer_expiry (expires_at),
  CONSTRAINT fk_transfer_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Request hygiene: replay protection and rate limiting
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS request_nonces (
  nonce             CHAR(32)        NOT NULL,
  seen_at           DATETIME        NOT NULL,
  PRIMARY KEY (nonce),
  KEY ix_nonce_seen (seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS rate_limits (
  bucket            VARCHAR(96)     NOT NULL,
  window_start      INT UNSIGNED    NOT NULL,
  hits              INT UNSIGNED    NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket, window_start),
  KEY ix_rate_window (window_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Security-relevant events only. Deliberately not a general request log: this
-- table should stay small enough to actually read.
CREATE TABLE IF NOT EXISTS audit_log (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id         BIGINT UNSIGNED NULL,
  event             VARCHAR(48)     NOT NULL,
  detail            VARCHAR(255)    NULL,
  ip_hash           CHAR(64)        NULL,
  created_at        DATETIME        NOT NULL,
  PRIMARY KEY (id),
  KEY ix_audit_event (event, created_at),
  KEY ix_audit_device (device_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- User data. Every table is scoped by device_id and carries rev + deleted_at,
-- so the sync endpoint can treat them all the same way.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS elements (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id         BIGINT UNSIGNED NOT NULL,
  uuid              CHAR(36)        NOT NULL,
  rev               BIGINT UNSIGNED NOT NULL,
  name              VARCHAR(120)    NOT NULL DEFAULT '',
  type              VARCHAR(16)     NOT NULL DEFAULT 'Wall',
  area              DOUBLE          NOT NULL DEFAULT 0,
  target_u          DOUBLE          NOT NULL DEFAULT 0,
  tolerance         DOUBLE          NOT NULL DEFAULT 0,
  inside_temp       DOUBLE          NOT NULL DEFAULT 20,
  outside_temp      DOUBLE          NOT NULL DEFAULT -5,
  indoor_rh         DOUBLE          NOT NULL DEFAULT 55,
  outdoor_rh        DOUBLE          NOT NULL DEFAULT 85,
  status            VARCHAR(16)     NOT NULL DEFAULT 'In Progress',
  manual_status     VARCHAR(16)     NULL,
  insulation_name   VARCHAR(120)    NOT NULL DEFAULT '',
  notes             TEXT            NULL,
  has_vapor_control TINYINT(1)      NOT NULL DEFAULT 0,
  existing_u        DOUBLE          NOT NULL DEFAULT 0,
  cost_insulation   DOUBLE          NOT NULL DEFAULT 0,
  cost_membrane     DOUBLE          NOT NULL DEFAULT 0,
  cost_finish       DOUBLE          NOT NULL DEFAULT 0,
  cost_reserve_pct  DOUBLE          NOT NULL DEFAULT 10,
  signoff_by        VARCHAR(120)    NOT NULL DEFAULT '',
  signoff_date      DATETIME        NULL,
  -- Signature strokes stay as JSON text: they are an opaque blob of points
  -- that nothing server-side ever queries into.
  signature_json    MEDIUMTEXT      NULL,
  photo_uuid        CHAR(36)        NULL,
  -- Client wall-clock of the last edit, in milliseconds. Drives last-write-wins.
  client_updated_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
  date_created      DATETIME        NOT NULL,
  updated_at        DATETIME        NOT NULL,
  deleted_at        DATETIME        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_element_device_uuid (device_id, uuid),
  KEY ix_element_rev (device_id, rev),
  CONSTRAINT fk_element_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Layers are replaced wholesale whenever their element is pushed: the stack is
-- an ordered list that only ever changes as a unit, so per-layer sync would add
-- ordering conflicts for no benefit.
CREATE TABLE IF NOT EXISTS element_layers (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  element_id        BIGINT UNSIGNED NOT NULL,
  uuid              CHAR(36)        NOT NULL,
  position          SMALLINT UNSIGNED NOT NULL,
  material_name     VARCHAR(120)    NOT NULL,
  lambda            DOUBLE          NOT NULL,
  vapor_resistance  DOUBLE          NOT NULL DEFAULT 1,
  thickness_mm      DOUBLE          NOT NULL DEFAULT 0,
  is_insulation     TINYINT(1)      NOT NULL DEFAULT 0,
  side              VARCHAR(16)     NOT NULL DEFAULT 'Core',
  PRIMARY KEY (id),
  KEY ix_layer_element (element_id, position),
  CONSTRAINT fk_layer_element FOREIGN KEY (element_id) REFERENCES elements (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS materials (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id         BIGINT UNSIGNED NOT NULL,
  uuid              CHAR(36)        NOT NULL,
  rev               BIGINT UNSIGNED NOT NULL,
  name              VARCHAR(120)    NOT NULL,
  lambda            DOUBLE          NOT NULL,
  density           DOUBLE          NOT NULL DEFAULT 0,
  vapor_resistance  DOUBLE          NOT NULL DEFAULT 1,
  is_insulation     TINYINT(1)      NOT NULL DEFAULT 0,
  is_custom         TINYINT(1)      NOT NULL DEFAULT 1,
  client_updated_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
  updated_at        DATETIME        NOT NULL,
  deleted_at        DATETIME        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_material_device_uuid (device_id, uuid),
  KEY ix_material_rev (device_id, rev),
  CONSTRAINT fk_material_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS reminders (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id         BIGINT UNSIGNED NOT NULL,
  uuid              CHAR(36)        NOT NULL,
  rev               BIGINT UNSIGNED NOT NULL,
  kind              VARCHAR(48)     NOT NULL,
  fire_at           DATETIME        NOT NULL,
  is_on             TINYINT(1)      NOT NULL DEFAULT 1,
  element_uuid      CHAR(36)        NULL,
  element_name      VARCHAR(120)    NOT NULL DEFAULT '',
  client_updated_ms BIGINT UNSIGNED NOT NULL DEFAULT 0,
  updated_at        DATETIME        NOT NULL,
  deleted_at        DATETIME        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_reminder_device_uuid (device_id, uuid),
  KEY ix_reminder_rev (device_id, rev),
  CONSTRAINT fk_reminder_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS history_entries (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id         BIGINT UNSIGNED NOT NULL,
  uuid              CHAR(36)        NOT NULL,
  rev               BIGINT UNSIGNED NOT NULL,
  title             VARCHAR(120)    NOT NULL,
  detail            VARCHAR(255)    NOT NULL DEFAULT '',
  icon              VARCHAR(64)     NOT NULL DEFAULT '',
  happened_at       DATETIME        NOT NULL,
  updated_at        DATETIME        NOT NULL,
  deleted_at        DATETIME        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_history_device_uuid (device_id, uuid),
  KEY ix_history_rev (device_id, rev),
  CONSTRAINT fk_history_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Photo bytes live on disk outside the webroot; only metadata is in the DB.
-- Storing a few hundred KB of base64 per row would bloat both the table and
-- every sync response that touches it.
CREATE TABLE IF NOT EXISTS photos (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  device_id         BIGINT UNSIGNED NOT NULL,
  uuid              CHAR(36)        NOT NULL,
  rev               BIGINT UNSIGNED NOT NULL,
  storage_name      VARCHAR(80)     NOT NULL,
  byte_size         INT UNSIGNED    NOT NULL,
  sha256            CHAR(64)        NOT NULL,
  created_at        DATETIME        NOT NULL,
  deleted_at        DATETIME        NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_photo_device_uuid (device_id, uuid),
  KEY ix_photo_rev (device_id, rev),
  CONSTRAINT fk_photo_device FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- Server-managed reference library. Lets the material list and build-up
-- templates be corrected without shipping an App Store update.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS library_materials (
  id                INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  slug              VARCHAR(64)     NOT NULL,
  name              VARCHAR(120)    NOT NULL,
  lambda            DOUBLE          NOT NULL,
  density           DOUBLE          NOT NULL DEFAULT 0,
  vapor_resistance  DOUBLE          NOT NULL DEFAULT 1,
  is_insulation     TINYINT(1)      NOT NULL DEFAULT 0,
  sort_order        SMALLINT        NOT NULL DEFAULT 0,
  is_active         TINYINT(1)      NOT NULL DEFAULT 1,
  updated_at        DATETIME        NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_libmat_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS library_templates (
  id                INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  slug              VARCHAR(64)     NOT NULL,
  name              VARCHAR(120)    NOT NULL,
  detail            VARCHAR(255)    NOT NULL DEFAULT '',
  element_type      VARCHAR(16)     NOT NULL DEFAULT 'Wall',
  -- Ordered layer list as JSON text. This one is genuinely a document: it is
  -- read as a whole, written by hand, and never queried field-by-field.
  layers_json       MEDIUMTEXT      NOT NULL,
  sort_order        SMALLINT        NOT NULL DEFAULT 0,
  is_active         TINYINT(1)      NOT NULL DEFAULT 1,
  updated_at        DATETIME        NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_libtpl_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Single-row table holding the library version, so the app can ask "changed?"
-- with one cheap request instead of downloading the catalogue every launch.
CREATE TABLE IF NOT EXISTS library_meta (
  id                TINYINT UNSIGNED NOT NULL DEFAULT 1,
  version           BIGINT UNSIGNED  NOT NULL DEFAULT 1,
  updated_at        DATETIME         NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO library_meta (id, version, updated_at)
VALUES (1, 1, UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE id = id;
