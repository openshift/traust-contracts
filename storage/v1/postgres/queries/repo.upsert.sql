INSERT INTO traust_storage.repo (
    repo_id,
    repo_url,
    registered_at
)
VALUES (
    %(repo_id)s,
    %(repo_url)s,
    %(registered_at)s
)
ON CONFLICT (repo_url) DO NOTHING;
