-- Ledger v1 revision 1 -> 2: layers.product_repo_id.
--
-- Ledger schema files are not re-runnable, so this delta carries the index
-- as well as the column. Storage must be at revision 4 or later in the same
-- database (the foreign key target). Existing layers keep product_repo_id
-- NULL until backfilled.
ALTER TABLE traust_ledger.layers
    ADD COLUMN product_repo_id TEXT REFERENCES traust_storage.product_repo(product_repo_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_layers_product_repo
    ON traust_ledger.layers (product_repo_id)
    WHERE product_repo_id IS NOT NULL;
