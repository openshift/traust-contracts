-- A product: the parent every repo it ships is registered under.
--
-- product_id is a database-assigned identifier (a UUID the Store generates);
-- slug is the natural key. segment is the inventory grouping (openshift,
-- operator-catalog, services, ...), refreshed on each load.
CREATE TABLE IF NOT EXISTS traust_storage.product (
    product_id TEXT NOT NULL,
    slug TEXT NOT NULL CHECK (slug <> ''),
    segment TEXT,
    registered_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (product_id),
    UNIQUE (slug)
);
