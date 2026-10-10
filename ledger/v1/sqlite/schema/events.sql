CREATE TABLE events (
    id INTEGER NOT NULL,
    layer_id VARCHAR NOT NULL,
    seq INTEGER NOT NULL,
    event_id VARCHAR NOT NULL,
    finding_ref VARCHAR,
    fingerprint VARCHAR,
    fingerprint_algo VARCHAR,
    recorded_at DATETIME,
    occurred_at DATETIME,
    source_type VARCHAR,
    source_ref VARCHAR,
    actor_kind VARCHAR,
    actor_identity VARCHAR,
    validity VARCHAR,
    resolution VARCHAR,
    evidence_grade VARCHAR,
    auto_accept_tier BOOLEAN,
    event_payload BLOB NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT ck_ledger_events_seq_nonnegative CHECK (seq >= 0),
    CONSTRAINT ck_ledger_events_event_id_nonempty CHECK (event_id <> ''),
    CONSTRAINT uq_ledger_events_layer_seq UNIQUE (layer_id, seq),
    CONSTRAINT uq_ledger_events_layer_event_id UNIQUE (layer_id, event_id),
    FOREIGN KEY (layer_id) REFERENCES layers(layer_id) ON DELETE RESTRICT
);

CREATE INDEX idx_ledger_events_clock ON events (fingerprint, occurred_at);

CREATE INDEX idx_ledger_events_finding_ref ON events (layer_id, finding_ref);

CREATE INDEX idx_ledger_events_recorded_at ON events (layer_id, recorded_at);

CREATE INDEX idx_ledger_events_resolution ON events (resolution, occurred_at);

CREATE INDEX idx_ledger_events_source ON events (source_type, occurred_at);

CREATE TRIGGER IF NOT EXISTS events_reject_update
BEFORE UPDATE ON events BEGIN
  SELECT RAISE(ABORT, 'ledger events are append-only');
END;

CREATE TRIGGER IF NOT EXISTS events_reject_delete
BEFORE DELETE ON events BEGIN
  SELECT RAISE(ABORT, 'ledger events are append-only');
END;

CREATE TRIGGER IF NOT EXISTS events_validate_append
BEFORE INSERT ON events
WHEN NEW.event_id IS NULL OR NEW.event_id = '' OR NEW.seq != COALESCE(
  (SELECT MAX(seq) + 1 FROM events WHERE layer_id = NEW.layer_id), 0
)
BEGIN
  SELECT RAISE(ABORT, 'ledger event must have an ID and append at the next sequence');
END;
