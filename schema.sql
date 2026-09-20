PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS competitions (
    contest_id             INTEGER PRIMARY KEY,
    contest_url            TEXT NOT NULL UNIQUE,
    contest_name           TEXT NOT NULL,
    level_code             INTEGER,
    level_name             TEXT,
    category_first_id      INTEGER,
    category_second_id     INTEGER,
    category_second_code   TEXT,
    status_code            INTEGER,
    status_name            TEXT,
    is_exam                INTEGER NOT NULL DEFAULT 0,
    can_register           INTEGER,
    enter_type             INTEGER,
    team_type              INTEGER,
    register_start_at      INTEGER,
    register_end_at        INTEGER,
    contest_start_at       INTEGER,
    contest_end_at         INTEGER,
    cover_url              TEXT,
    banner_url             TEXT,
    source_url             TEXT NOT NULL,
    content_html           TEXT,
    content_text           TEXT,
    content_hash           TEXT,
    view_count             INTEGER,
    follow_count           INTEGER,
    rank_number            INTEGER,
    is_new                 INTEGER NOT NULL DEFAULT 0,
    raw_json               TEXT,
    first_seen_at          INTEGER NOT NULL,
    last_seen_at           INTEGER NOT NULL,
    detail_fetched_at      INTEGER,
    updated_at             INTEGER NOT NULL,
    is_active              INTEGER NOT NULL DEFAULT 1,
    removed_at             INTEGER
);

CREATE TABLE IF NOT EXISTS competition_stages (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    contest_id     INTEGER NOT NULL,
    stage_order    INTEGER NOT NULL,
    stage_name     TEXT,
    stage_content  TEXT,
    start_at       INTEGER,
    end_at         INTEGER,
    FOREIGN KEY (contest_id) REFERENCES competitions(contest_id) ON DELETE CASCADE,
    UNIQUE (contest_id, stage_order)
);

CREATE TABLE IF NOT EXISTS organizers (
    id                   INTEGER PRIMARY KEY AUTOINCREMENT,
    source_organizer_id  INTEGER,
    organizer_name       TEXT NOT NULL UNIQUE,
    link_url             TEXT,
    avatar_url           TEXT
);

CREATE TABLE IF NOT EXISTS competition_organizers (
    contest_id    INTEGER NOT NULL,
    organizer_id  INTEGER NOT NULL,
    role          TEXT NOT NULL,
    sort_order    INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (contest_id, organizer_id, role),
    FOREIGN KEY (contest_id) REFERENCES competitions(contest_id) ON DELETE CASCADE,
    FOREIGN KEY (organizer_id) REFERENCES organizers(id) ON DELETE CASCADE,
    CHECK (role IN ('main', 'other', 'support'))
);

CREATE TABLE IF NOT EXISTS competition_attachments (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    contest_id     INTEGER NOT NULL,
    file_name      TEXT NOT NULL,
    file_url       TEXT NOT NULL,
    file_type      TEXT,
    discovered_at  INTEGER NOT NULL,
    FOREIGN KEY (contest_id) REFERENCES competitions(contest_id) ON DELETE CASCADE,
    UNIQUE (contest_id, file_url)
);

CREATE TABLE IF NOT EXISTS crawl_runs (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at        INTEGER NOT NULL,
    finished_at       INTEGER,
    status            TEXT NOT NULL,
    start_page        INTEGER NOT NULL DEFAULT 1,
    current_page      INTEGER NOT NULL DEFAULT 0,
    total_pages       INTEGER,
    pages_fetched     INTEGER NOT NULL DEFAULT 0,
    items_seen        INTEGER NOT NULL DEFAULT 0,
    items_inserted    INTEGER NOT NULL DEFAULT 0,
    items_updated     INTEGER NOT NULL DEFAULT 0,
    details_fetched   INTEGER NOT NULL DEFAULT 0,
    error_count       INTEGER NOT NULL DEFAULT 0,
    error_message     TEXT,
    CHECK (status IN ('running', 'success', 'partial', 'failed'))
);

CREATE INDEX IF NOT EXISTS idx_competitions_register_end
    ON competitions(register_end_at);
CREATE INDEX IF NOT EXISTS idx_competitions_contest_start
    ON competitions(contest_start_at);
CREATE INDEX IF NOT EXISTS idx_competitions_category
    ON competitions(category_first_id, category_second_id);
CREATE INDEX IF NOT EXISTS idx_competitions_status
    ON competitions(status_code, can_register);
CREATE INDEX IF NOT EXISTS idx_competitions_last_seen
    ON competitions(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_stages_start
    ON competition_stages(start_at);
CREATE INDEX IF NOT EXISTS idx_competition_organizers_org
    ON competition_organizers(organizer_id);

