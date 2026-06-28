-- =============================================================================
--  VideoVault – Vollständiges Datenbankschema
--  Zusammengeführt aus: 01-schema.sql, 02-extensions.sql, 03-blink.sql,
--  04-blink-cameras.sql, 05-sync-jobs.sql, 06-live-stream.sql,
--  07-retention-settings.sql, 08-live-recordings.sql
--
--  Wird automatisch beim ersten PostgreSQL-Start ausgeführt
--  (docker-entrypoint-initdb.d) wenn das Datenverzeichnis leer ist.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
--  Benutzer
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    username      VARCHAR(64) UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role          VARCHAR(16) NOT NULL DEFAULT 'reader'
                  CHECK (role IN ('admin', 'operator', 'reader')),
    can_download  BOOLEAN NOT NULL DEFAULT TRUE,
    active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login    TIMESTAMPTZ
);

-- ---------------------------------------------------------------------------
--  Kategorien
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS categories (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(128) UNIQUE NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO categories (name, description)
VALUES ('Allgemein', 'Standardkategorie')
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
--  Kameras
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cameras (
    id               SERIAL PRIMARY KEY,
    name             VARCHAR(128) UNIQUE NOT NULL,
    description      TEXT,
    location         VARCHAR(255),
    source           VARCHAR(16) NOT NULL DEFAULT 'manual',
    stream_url       TEXT,
    blink_camera_id  TEXT,
    blink_network_id TEXT,
    blink_synced_at  TIMESTAMPTZ,
    snapshot_path    TEXT,
    snapshot_at      TIMESTAMPTZ,
    battery_powered  BOOLEAN,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  Videos
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS videos (
    id            SERIAL PRIMARY KEY,
    title         VARCHAR(255) NOT NULL,
    description   TEXT,
    filename      VARCHAR(255) NOT NULL,
    storage_path  TEXT NOT NULL,
    thumbnail     TEXT,
    mime_type     VARCHAR(64),
    size_bytes    BIGINT NOT NULL DEFAULT 0,
    duration_sec  NUMERIC(10,2),
    width         INTEGER,
    height        INTEGER,
    category_id   INTEGER REFERENCES categories(id) ON DELETE SET NULL,
    camera_id     INTEGER REFERENCES cameras(id)    ON DELETE SET NULL,
    uploaded_by   INTEGER REFERENCES users(id)      ON DELETE SET NULL,
    recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ,
    search_vector tsvector
);

CREATE INDEX IF NOT EXISTS idx_videos_recorded  ON videos (recorded_at);
CREATE INDEX IF NOT EXISTS idx_videos_deleted   ON videos (deleted_at);
CREATE INDEX IF NOT EXISTS idx_videos_category  ON videos (category_id);
CREATE INDEX IF NOT EXISTS idx_videos_camera    ON videos (camera_id);
CREATE INDEX IF NOT EXISTS idx_videos_search    ON videos USING GIN (search_vector);

CREATE OR REPLACE FUNCTION videos_search_trigger() RETURNS trigger AS $$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('simple', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(NEW.description, '')), 'B') ||
        setweight(to_tsvector('simple', coalesce(NEW.filename, '')), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_videos_search ON videos;
CREATE TRIGGER trg_videos_search BEFORE INSERT OR UPDATE
    ON videos FOR EACH ROW EXECUTE FUNCTION videos_search_trigger();

-- ---------------------------------------------------------------------------
--  Tags
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tags (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(64) UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS video_tags (
    video_id INTEGER REFERENCES videos(id) ON DELETE CASCADE,
    tag_id   INTEGER REFERENCES tags(id)   ON DELETE CASCADE,
    PRIMARY KEY (video_id, tag_id)
);

-- ---------------------------------------------------------------------------
--  API-Schlüssel
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS api_keys (
    id         SERIAL PRIMARY KEY,
    label      VARCHAR(128) NOT NULL,
    key_hash   TEXT NOT NULL,
    prefix     VARCHAR(12) NOT NULL,
    owner_id   INTEGER REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used  TIMESTAMPTZ,
    revoked    BOOLEAN NOT NULL DEFAULT FALSE
);

-- ---------------------------------------------------------------------------
--  Sync-Log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_log (
    id           SERIAL PRIMARY KEY,
    started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at  TIMESTAMPTZ,
    status       VARCHAR(16) NOT NULL DEFAULT 'running'
                 CHECK (status IN ('running','success','error','interrupted')),
    target       TEXT,
    files_synced INTEGER DEFAULT 0,
    bytes_synced BIGINT DEFAULT 0,
    message      TEXT
);

-- ---------------------------------------------------------------------------
--  Lösch-Log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deletion_log (
    id           SERIAL PRIMARY KEY,
    video_id     INTEGER,
    title        VARCHAR(255),
    reason       VARCHAR(32) NOT NULL,
    deleted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    performed_by INTEGER REFERENCES users(id) ON DELETE SET NULL
);

-- ---------------------------------------------------------------------------
--  Audit-Log
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action     VARCHAR(64) NOT NULL,
    detail     TEXT,
    ip         VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  Netzwerkfreigaben
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS network_shares (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(64) UNIQUE NOT NULL,
    protocol   VARCHAR(8) NOT NULL CHECK (protocol IN ('smb','nfs')),
    subpath    VARCHAR(255) NOT NULL DEFAULT '',
    writable   BOOLEAN NOT NULL DEFAULT FALSE,
    allowed    TEXT,
    guest_ok   BOOLEAN NOT NULL DEFAULT FALSE,
    enabled    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  NAS-Ziele
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nas_targets (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(128) NOT NULL,
    protocol    VARCHAR(8) NOT NULL CHECK (protocol IN ('smb','nfs','webdav')),
    vendor      VARCHAR(32) NOT NULL DEFAULT 'generic',
    host        VARCHAR(255) NOT NULL,
    remote_path VARCHAR(255) NOT NULL DEFAULT '',
    username    VARCHAR(128),
    password    TEXT,
    options     TEXT,
    enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  Einstellungen
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS settings (
    key        VARCHAR(64) PRIMARY KEY,
    value      TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO settings (key, value) VALUES
    ('storage_mode',            'local'),
    ('active_nas_target',       ''),
    ('nas_sync_cron',           '0 */6 * * *'),
    ('nas_sync_enabled',        'false'),
    ('delete_local_after_sync', 'false'),
    ('retention_enabled',       'true'),
    ('retention_days',          '90'),
    ('trash_retention_days',    '14'),
    ('blink_last_clip_import',  '')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
--  Blink-Konto
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS blink_account (
    id               INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    email            TEXT,
    password_enc     TEXT,
    token_enc        TEXT,
    status           VARCHAR(24) NOT NULL DEFAULT 'disconnected'
                     CHECK (status IN ('disconnected','connecting','twofa_required','connected','error')),
    account_info     JSONB,
    last_login       TIMESTAMPTZ,
    token_updated_at TIMESTAMPTZ,
    last_error       TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  Blink-Clips
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS blink_clips (
    clip_id     TEXT PRIMARY KEY,
    video_id    INTEGER REFERENCES videos(id) ON DELETE SET NULL,
    camera      TEXT,
    created_at  TIMESTAMPTZ,
    imported_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
--  Sync-Jobs (geplante Aufgaben)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sync_jobs (
    id           SERIAL PRIMARY KEY,
    name         VARCHAR(128) NOT NULL,
    type         VARCHAR(32)  NOT NULL DEFAULT 'blink_check_all'
                 CHECK (type IN ('blink_check_all','hdd_sync','nas_sync')),
    cron         VARCHAR(64)  NOT NULL DEFAULT '*/5 * * * *',
    enabled      BOOLEAN      NOT NULL DEFAULT TRUE,
    last_run     TIMESTAMPTZ,
    last_status  VARCHAR(16),
    last_message TEXT,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

INSERT INTO sync_jobs (name, type, cron, enabled)
SELECT 'Alle Kameras pruefen', 'blink_check_all', '*/5 * * * *', TRUE
WHERE NOT EXISTS (SELECT 1 FROM sync_jobs);

-- ---------------------------------------------------------------------------
--  Live-Aufnahmen
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS live_recordings (
    id           SERIAL PRIMARY KEY,
    camera_id    INTEGER REFERENCES cameras(id) ON DELETE SET NULL,
    camera_name  TEXT,
    filename     TEXT NOT NULL,
    file_path    TEXT NOT NULL,
    size_bytes   BIGINT DEFAULT 0,
    duration_sec NUMERIC(10,2) DEFAULT 0,
    started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at  TIMESTAMPTZ,
    title        TEXT
);

CREATE INDEX IF NOT EXISTS idx_live_recordings_started ON live_recordings (started_at DESC);
CREATE INDEX IF NOT EXISTS idx_live_recordings_camera  ON live_recordings (camera_id);

-- ---------------------------------------------------------------------------
--  Migration-Log (verhindert dass das Backend Migrationen doppelt ausführt)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS migration_log (
    id         TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO migration_log (id) VALUES
    ('001_live_recordings'),
    ('002_cameras_stream_url'),
    ('003_cameras_blink_cols'),
    ('004_blink_clips'),
    ('005_retention_settings'),
    ('006_sync_jobs'),
    ('007_videos_search_vector')
ON CONFLICT DO NOTHING;
