INSERT INTO traust_storage.repo (
    repo_url,
    registered_at
)
VALUES (
    %(repo_url)s,
    %(registered_at)s
)
ON CONFLICT (repo_url) DO NOTHING;
