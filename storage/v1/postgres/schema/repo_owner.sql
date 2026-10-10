-- Who owns a product_repo, from the owners.csv in each product's inventory
-- folder. A product_repo can list several teams. Refreshed on each load.
CREATE TABLE IF NOT EXISTS traust_storage.repo_owner (
    product_repo_id TEXT NOT NULL REFERENCES traust_storage.product_repo(product_repo_id),
    team TEXT NOT NULL CHECK (team <> ''),
    manager TEXT,
    individuals JSONB,
    source TEXT,
    jira_project TEXT,
    jira_component TEXT,
    registered_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (product_repo_id, team)
);

CREATE INDEX IF NOT EXISTS idx_repo_owner_team
    ON traust_storage.repo_owner (team);
