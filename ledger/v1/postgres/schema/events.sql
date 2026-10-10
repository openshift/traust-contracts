CREATE TABLE traust_ledger.events (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    layer_id VARCHAR NOT NULL,
    seq INTEGER NOT NULL,
    event_id VARCHAR NOT NULL,
    finding_ref VARCHAR,
    fingerprint VARCHAR,
    fingerprint_algo VARCHAR,
    recorded_at TIMESTAMP WITH TIME ZONE,
    occurred_at TIMESTAMP WITH TIME ZONE,
    source_type VARCHAR,
    source_ref VARCHAR,
    actor_kind VARCHAR,
    actor_identity VARCHAR,
    validity VARCHAR,
    resolution VARCHAR,
    evidence_grade VARCHAR,
    auto_accept_tier BOOLEAN,
    event_payload BYTEA NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT ck_ledger_events_seq_nonnegative CHECK (seq >= 0),
    CONSTRAINT ck_ledger_events_event_id_nonempty CHECK (event_id <> ''),
    CONSTRAINT uq_ledger_events_layer_seq UNIQUE (layer_id, seq),
    CONSTRAINT uq_ledger_events_layer_event_id UNIQUE (layer_id, event_id),
    FOREIGN KEY (layer_id) REFERENCES traust_ledger.layers(layer_id) ON DELETE RESTRICT
);

CREATE INDEX idx_ledger_events_clock ON traust_ledger.events (fingerprint, occurred_at);

CREATE INDEX idx_ledger_events_finding_ref ON traust_ledger.events (layer_id, finding_ref);

CREATE INDEX idx_ledger_events_recorded_at ON traust_ledger.events (layer_id, recorded_at);

CREATE INDEX idx_ledger_events_resolution ON traust_ledger.events (resolution, occurred_at);

CREATE INDEX idx_ledger_events_source ON traust_ledger.events (source_type, occurred_at);

DROP TRIGGER IF EXISTS events_reject_mutation ON traust_ledger.events;
CREATE TRIGGER events_reject_mutation
BEFORE UPDATE OR DELETE ON traust_ledger.events
FOR EACH ROW EXECUTE FUNCTION traust_ledger.reject_authoritative_mutation();

DROP TRIGGER IF EXISTS events_reject_truncate ON traust_ledger.events;
CREATE TRIGGER events_reject_truncate
BEFORE TRUNCATE ON traust_ledger.events
FOR EACH STATEMENT EXECUTE FUNCTION traust_ledger.reject_authoritative_mutation();

DROP TRIGGER IF EXISTS events_validate_append ON traust_ledger.events;
CREATE TRIGGER events_validate_append
BEFORE INSERT ON traust_ledger.events
FOR EACH ROW EXECUTE FUNCTION traust_ledger.validate_event_append();
