CREATE TABLE traust_ledger.materialized_findings (
    layer_id VARCHAR NOT NULL,
    finding_ref VARCHAR NOT NULL,
    fingerprint VARCHAR,
    orphan BOOLEAN,
    validity VARCHAR NOT NULL,
    resolution VARCHAR NOT NULL,
    assurance VARCHAR,
    event_count INTEGER NOT NULL,
    conflict BOOLEAN,
    fp_overridden BOOLEAN,
    fp_reassertion_blocked BOOLEAN,
    severity_override JSON,
    last_updated VARCHAR,
    merkle_root VARCHAR,
    merkle_epoch INTEGER,
    materialized_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    PRIMARY KEY (layer_id, finding_ref)
);
