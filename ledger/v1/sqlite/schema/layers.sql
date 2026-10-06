-- product_repo_id: the storage product_repo whose dispositions this layer holds.
-- A real foreign key into traust_storage: storage is always present when a
-- database is used, the ledger is optional, so the ledger depends on storage
-- (never the reverse). Requires storage initialized first in the same
-- database. Nullable for layers created before revision 2; one layer per
-- product_repo when set. layer_id stays independent of it.
CREATE TABLE layers (
    layer_id VARCHAR NOT NULL,
    metadata_payload BLOB NOT NULL,
    needs_review_payload BLOB NOT NULL,
    extensions_payload BLOB NOT NULL,
    root_keys_payload BLOB NOT NULL,
    repository TEXT,
    created_at DATETIME,
    merkle_root VARCHAR,
    merkle_epoch INTEGER,
    merkle_size INTEGER,
    merkle_root_signature TEXT,
    merkle_signing_method VARCHAR,
    merkle_signature_format INTEGER,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    product_repo_id TEXT REFERENCES product_repo(product_repo_id),
    PRIMARY KEY (layer_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ledger_layers_product_repo
    ON layers (product_repo_id)
    WHERE product_repo_id IS NOT NULL;

CREATE TRIGGER IF NOT EXISTS layers_reject_delete
BEFORE DELETE ON layers BEGIN
  SELECT RAISE(ABORT, 'ledger layers cannot be deleted');
END;
