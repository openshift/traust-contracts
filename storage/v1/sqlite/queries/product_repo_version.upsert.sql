INSERT INTO product_repo_version (
    product_repo_id,
    version,
    category,
    cluster_operators,
    images,
    registered_at
)
VALUES (
    :product_repo_id,
    :version,
    :category,
    :cluster_operators,
    :images,
    :registered_at
)
ON CONFLICT (product_repo_id, version) DO UPDATE SET
    category = EXCLUDED.category,
    cluster_operators = EXCLUDED.cluster_operators,
    images = EXCLUDED.images;
