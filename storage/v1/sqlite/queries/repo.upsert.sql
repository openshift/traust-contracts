INSERT INTO repo (
    repo_url,
    registered_at
)
VALUES (
    :repo_url,
    :registered_at
)
ON CONFLICT (repo_url) DO NOTHING;
