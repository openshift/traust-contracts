-- A product: the parent every repo it ships is registered under.
--
-- id is a database-generated identifier;
-- slug is the natural key. segment is the inventory grouping (openshift,
-- operator-catalog, services, ...), refreshed on each load.
CREATE TABLE IF NOT EXISTS traust_storage.product (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    slug TEXT NOT NULL CHECK (slug <> ''),
    segment TEXT,
    registered_at TIMESTAMPTZ NOT NULL,
    UNIQUE (slug)
);
