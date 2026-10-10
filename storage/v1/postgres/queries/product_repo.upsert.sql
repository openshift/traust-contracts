INSERT INTO traust_storage.product_repo (
    product_id,
    repo_id,
    ref,
    sub_service,
    resource_type,
    registered_at
)
VALUES (
    %(product_id)s,
    %(repo_id)s,
    %(ref)s,
    %(sub_service)s,
    %(resource_type)s,
    %(registered_at)s
)
ON CONFLICT (product_id, repo_id, ref) DO UPDATE SET
    sub_service = EXCLUDED.sub_service,
    resource_type = EXCLUDED.resource_type;
