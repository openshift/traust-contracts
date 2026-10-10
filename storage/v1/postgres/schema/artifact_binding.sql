CREATE TABLE IF NOT EXISTS traust_storage.artifact_binding (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL REFERENCES traust_storage.artifact_evidence(digest),
    artifact_name TEXT NOT NULL,
    artifact_role TEXT,
    scope_id TEXT NOT NULL,
    subject_id TEXT,
    run_id TEXT,
    layer_id TEXT,
    supersedes_binding_id TEXT,
    bound_at TIMESTAMPTZ NOT NULL,
    product_repo_id BIGINT REFERENCES traust_storage.product_repo(id),
    commit_sha TEXT,
    PRIMARY KEY (binding_id),
    UNIQUE (binding_id, artifact_digest)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_binding_successor
    ON traust_storage.artifact_binding (supersedes_binding_id)
    WHERE supersedes_binding_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_artifact_binding_context
    ON traust_storage.artifact_binding (scope_id, subject_id, run_id, artifact_name, artifact_role);

CREATE INDEX IF NOT EXISTS idx_artifact_binding_layer
    ON traust_storage.artifact_binding (scope_id, layer_id)
    WHERE layer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_artifact_binding_product_repo
    ON traust_storage.artifact_binding (product_repo_id)
    WHERE product_repo_id IS NOT NULL;

-- One findings-current chain per product_repo and run. A cumulative report
-- with no predecessor starts a chain; every later one must supersede, and
-- idx_artifact_binding_successor allows one successor per binding, so the
-- chain stays linear and exactly one cumulative report is current.
CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_binding_cumulative_root
    ON traust_storage.artifact_binding (scope_id, product_repo_id, run_id)
    WHERE artifact_name = 'report'
      AND artifact_role = 'cumulative'
      AND supersedes_binding_id IS NULL
      AND product_repo_id IS NOT NULL;
