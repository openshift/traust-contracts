-- Storage v1 revision 3 -> 4: product -> repo registry.
--
-- Deltas only. Store.migrate() creates the new product, repo, product_repo,
-- product_repo_version and repo_owner tables from schema/ before this file
-- runs, and re-runs every schema and view file after it, so new indexes and
-- views come from those files. This file holds what re-running them cannot do.
ALTER TABLE traust_storage.artifact_binding
    ADD COLUMN product_repo_id TEXT REFERENCES traust_storage.product_repo(product_repo_id);

ALTER TABLE traust_storage.artifact_binding
    ADD COLUMN commit_sha TEXT;
