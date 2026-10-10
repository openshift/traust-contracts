-- A product: the parent every repo it ships is registered under.
--
-- id is a database-generated identifier;
-- slug is the natural key. segment is the inventory grouping (openshift,
-- operator-catalog, services, ...), refreshed on each load.
CREATE TABLE IF NOT EXISTS product (
    id INTEGER PRIMARY KEY,
    slug TEXT NOT NULL CHECK (slug <> ''),
    segment TEXT,
    registered_at TEXT NOT NULL,
    UNIQUE (slug)
);
