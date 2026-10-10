-- A repo as a product ships it, at one ref: the owner of artifact bindings
-- and ledger layers.
--
-- Products and repos are many-to-many; the natural key is
-- (product_id, repo_id, ref), with ref '' for the default branch. A release
-- branch the product ships (e.g. release-5.0) is its own row: it has its own
-- audits and its own ledger. id is database-assigned; child tables reference
-- it through their product_repo_id columns.
-- sub_service and resource_type are inventory attributes, refreshed on load.
CREATE TABLE IF NOT EXISTS product_repo (
    id INTEGER PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES product(id),
    repo_id INTEGER NOT NULL REFERENCES repo(id),
    ref TEXT NOT NULL DEFAULT '',
    sub_service TEXT,
    resource_type TEXT,
    registered_at TEXT NOT NULL,
    UNIQUE (product_id, repo_id, ref)
);

CREATE INDEX IF NOT EXISTS idx_product_repo_repo
    ON product_repo (repo_id);
