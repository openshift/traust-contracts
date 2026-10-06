INSERT INTO repo_owner (
    product_repo_id,
    team,
    manager,
    individuals,
    source,
    jira_project,
    jira_component,
    registered_at
)
VALUES (
    :product_repo_id,
    :team,
    :manager,
    :individuals,
    :source,
    :jira_project,
    :jira_component,
    :registered_at
)
ON CONFLICT (product_repo_id, team) DO UPDATE SET
    manager = EXCLUDED.manager,
    individuals = EXCLUDED.individuals,
    source = EXCLUDED.source,
    jira_project = EXCLUDED.jira_project,
    jira_component = EXCLUDED.jira_component;
