INSERT INTO repo (
    repo_id,
    repo_url,
    registered_at
)
VALUES (
    :repo_id,
    :repo_url,
    :registered_at
)
ON CONFLICT (repo_url) DO NOTHING;
