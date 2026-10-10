-- A source repository, once, however many products include it.
--
-- id is a database-assigned identifier; repo_url is the natural key, an
-- exact string (storage does not canonicalize URLs). A library scanned for
-- several products is one repo row and several product_repo rows.
CREATE TABLE IF NOT EXISTS repo (
    id INTEGER PRIMARY KEY,
    repo_url TEXT NOT NULL CHECK (repo_url <> ''),
    registered_at TEXT NOT NULL,
    UNIQUE (repo_url)
);
