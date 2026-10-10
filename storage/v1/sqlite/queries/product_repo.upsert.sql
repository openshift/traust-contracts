INSERT INTO product_repo (
    product_id,
    repo_id,
    ref,
    sub_service,
    resource_type,
    registered_at
)
VALUES (
    :product_id,
    :repo_id,
    :ref,
    :sub_service,
    :resource_type,
    :registered_at
)
ON CONFLICT (product_id, repo_id, ref) DO UPDATE SET
    sub_service = EXCLUDED.sub_service,
    resource_type = EXCLUDED.resource_type;
