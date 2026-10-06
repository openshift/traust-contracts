INSERT INTO traust_storage.repo_owner (
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
    %(product_repo_id)s,
    %(team)s,
    %(manager)s,
    %(individuals)s,
    %(source)s,
    %(jira_project)s,
    %(jira_component)s,
    %(registered_at)s
)
ON CONFLICT (product_repo_id, team) DO UPDATE SET
    manager = EXCLUDED.manager,
    individuals = EXCLUDED.individuals,
    source = EXCLUDED.source,
    jira_project = EXCLUDED.jira_project,
    jira_component = EXCLUDED.jira_component;
