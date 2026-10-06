-- Storage v1 revision 1 -> 2 (0.48.0): binding roles and artifact locations.
--
-- Deltas only. Store.migrate() creates artifact_location from schema/ before
-- this file runs and re-runs every schema and view file after it, which
-- recreates idx_artifact_binding_context with artifact_role.
--
-- 0.48.0 itself wrote this revision-2 schema but stamped revision 1. Such a
-- database fails here (artifact_role already exists) and nothing is written;
-- set traust_storage_meta.revision = 2 and migrate again.
ALTER TABLE traust_storage.artifact_binding ADD COLUMN artifact_role TEXT;

DROP INDEX IF EXISTS traust_storage.idx_artifact_binding_context;

INSERT INTO traust_storage.artifact_location (binding_id, reference, registered_at)
SELECT binding.binding_id, evidence.reference, evidence.first_ingested_at
FROM traust_storage.artifact_evidence evidence
JOIN traust_storage.artifact_binding binding ON binding.artifact_digest = evidence.digest
WHERE evidence.reference IS NOT NULL AND evidence.reference <> '';

ALTER TABLE traust_storage.artifact_evidence DROP COLUMN reference;
