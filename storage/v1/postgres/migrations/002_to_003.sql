-- Storage v1 revision 2 -> 3: report_finding.blocked_external.
--
-- Deltas only. Store.migrate() re-runs every schema and view file after this
-- file, so new indexes and views come from those files. The column lands at
-- the end of a migrated table; queries name their columns.
ALTER TABLE traust_storage.report_finding
    ADD COLUMN blocked_external INTEGER;
