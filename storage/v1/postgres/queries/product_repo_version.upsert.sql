INSERT INTO traust_storage.product_repo_version (
    product_repo_id,
    version,
    category,
    cluster_operators,
    images,
    registered_at
)
VALUES (
    %(product_repo_id)s,
    %(version)s,
    %(category)s,
    %(cluster_operators)s,
    %(images)s,
    %(registered_at)s
)
ON CONFLICT (product_repo_id, version) DO UPDATE SET
    category = EXCLUDED.category,
    cluster_operators = EXCLUDED.cluster_operators,
    images = EXCLUDED.images;
