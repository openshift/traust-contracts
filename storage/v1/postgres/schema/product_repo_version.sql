-- Which product versions ship a product_repo, as the inventory records it
-- (openshift-4.21 payload, operator 0.10.5 bundle). One row per payload CSV
-- row: category, cluster operators and images are attributes of that
-- shipment, not entities. Refreshed on each inventory load.
CREATE TABLE IF NOT EXISTS traust_storage.product_repo_version (
    product_repo_id TEXT NOT NULL REFERENCES traust_storage.product_repo(product_repo_id),
    version TEXT NOT NULL CHECK (version <> ''),
    category TEXT,
    cluster_operators JSONB,
    images JSONB,
    registered_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (product_repo_id, version)
);

CREATE INDEX IF NOT EXISTS idx_product_repo_version_version
    ON traust_storage.product_repo_version (version);
