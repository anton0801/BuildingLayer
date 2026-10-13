-- Remote flag served to the app on every response as the `x-serviced-target`
-- header.
--
-- Exactly one row, id = 1. The app reads the header, caches the value and acts
-- on it; the server only stores and serves it.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS onAnalytics (
  id          INT UNSIGNED NOT NULL DEFAULT 1,
  isOn        TINYINT(1)   NOT NULL DEFAULT 1,
  created_at  DATETIME     NOT NULL,
  updated_at  DATETIME     NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed the single row. Re-running the migration leaves an existing value alone,
-- so a deploy can never silently flip the flag back.
INSERT INTO onAnalytics (id, isOn, created_at, updated_at)
VALUES (1, 1, UTC_TIMESTAMP(), UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE id = id;
