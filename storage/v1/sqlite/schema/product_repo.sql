-- A repo as a product ships it, at one ref: the owner of artifact bindings
-- and ledger layers.
--
-- Products and repos are many-to-many; the natural key is
-- (product_id, repo_id, ref), with ref '' for the default branch. A release
-- branch the product ships (e.g. release-5.0) is its own row: it has its own
-- audits and its own ledger. product_repo_id is a database-assigned
-- identifier, the single column artifact_binding and the ledger reference.
-- sub_service and resource_type are inventory attributes, refreshed on load.
CREATE TABLE IF NOT EXISTS product_repo (
    product_repo_id TEXT NOT NULL,
    product_id TEXT NOT NULL REFERENCES product(product_id),
    repo_id TEXT NOT NULL REFERENCES repo(repo_id),
    ref TEXT NOT NULL DEFAULT '',
    sub_service TEXT,
    resource_type TEXT,
    registered_at TEXT NOT NULL,
    PRIMARY KEY (product_repo_id),
    UNIQUE (product_id, repo_id, ref)
);

CREATE INDEX IF NOT EXISTS idx_product_repo_repo
    ON product_repo (repo_id);
