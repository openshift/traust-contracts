INSERT INTO artifact_binding (
    binding_id,
    artifact_digest,
    artifact_name,
    artifact_role,
    scope_id,
    subject_id,
    run_id,
    layer_id,
    supersedes_binding_id,
    bound_at,
    product_repo_id,
    commit_sha
)
VALUES (
    :binding_id,
    :artifact_digest,
    :artifact_name,
    :artifact_role,
    :scope_id,
    :subject_id,
    :run_id,
    :layer_id,
    :supersedes_binding_id,
    :bound_at,
    :product_repo_id,
    :commit_sha
)
ON CONFLICT (binding_id) DO NOTHING;
