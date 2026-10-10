-- Who owns a product_repo, from the owners.csv in each product's inventory
-- folder. A product_repo can list several teams. Refreshed on each load.
CREATE TABLE IF NOT EXISTS repo_owner (
    product_repo_id INTEGER NOT NULL REFERENCES product_repo(id),
    team TEXT NOT NULL CHECK (team <> ''),
    manager TEXT,
    individuals TEXT CHECK (individuals IS NULL OR json_valid(individuals)),
    source TEXT,
    jira_project TEXT,
    jira_component TEXT,
    registered_at TEXT NOT NULL,
    PRIMARY KEY (product_repo_id, team)
);

CREATE INDEX IF NOT EXISTS idx_repo_owner_team
    ON repo_owner (team);
