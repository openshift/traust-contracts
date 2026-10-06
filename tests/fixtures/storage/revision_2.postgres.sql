-- storage v1 revision 2 DDL as shipped (HEAD); test fixture, do not edit.

CREATE SCHEMA IF NOT EXISTS traust_storage;

CREATE TABLE IF NOT EXISTS traust_storage.artifact_evidence (
    digest TEXT NOT NULL,
    byte_size BIGINT NOT NULL CHECK (byte_size >= 0),
    first_ingested_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (digest)
);

CREATE TABLE IF NOT EXISTS traust_storage.artifact_binding (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL REFERENCES traust_storage.artifact_evidence(digest),
    artifact_name TEXT NOT NULL,
    artifact_role TEXT,
    scope_id TEXT NOT NULL,
    subject_id TEXT,
    run_id TEXT,
    layer_id TEXT,
    supersedes_binding_id TEXT,
    bound_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (binding_id),
    UNIQUE (binding_id, artifact_digest)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_artifact_binding_successor
    ON traust_storage.artifact_binding (supersedes_binding_id)
    WHERE supersedes_binding_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_artifact_binding_context
    ON traust_storage.artifact_binding (scope_id, subject_id, run_id, artifact_name, artifact_role);

CREATE INDEX IF NOT EXISTS idx_artifact_binding_layer
    ON traust_storage.artifact_binding (scope_id, layer_id)
    WHERE layer_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS traust_storage.artifact_location (
    binding_id TEXT NOT NULL REFERENCES traust_storage.artifact_binding(binding_id),
    reference TEXT NOT NULL CHECK (reference <> ''),
    registered_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (binding_id, reference)
);

CREATE TABLE IF NOT EXISTS traust_storage.adapter_result (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    target TEXT NOT NULL,
    scanned_at TEXT NOT NULL,
    metadata JSONB NOT NULL,
    findings JSONB NOT NULL,
    summary JSONB,
    focus_areas JSONB,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_adapter_result_artifact ON traust_storage.adapter_result (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.adr_registry (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    version BIGINT NOT NULL,
    note TEXT,
    registers JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_adr_registry_artifact ON traust_storage.adr_registry (artifact_digest);

-- Per-chain projection of a live-validation run.
--
-- validation.attack_chains[] is the multi-step half of the evidence lens: a
-- path from an entry point to a terminal asset, with a verdict for the PATH
-- rather than for any one finding on it. It lived in a JSON column, so
-- ATT&CK coverage could only be derived by a script walking artifacts.
--
-- `mitre_attack_refs` is the join to the technique catalogue and the reason
-- this table exists: a chain confirmed end to end is the strongest evidence
-- the estate has that a technique is not merely modelled but reachable.
--
-- `verdict` carries the same five values as a validated finding, and for
-- the same reason -- not_attempted dominates, so collapsing to
-- confirmed/other would report the unexercised majority as refuted.
CREATE TABLE IF NOT EXISTS traust_storage.attack_chain (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    chain_id TEXT NOT NULL,
    name TEXT,
    entry_point TEXT,
    terminal_asset TEXT,
    mitre_attack_refs JSONB,
    steps JSONB,
    verdict TEXT,
    narrative TEXT,
    PRIMARY KEY (binding_id, chain_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_attack_chain_verdict
    ON traust_storage.attack_chain (verdict);

CREATE TABLE IF NOT EXISTS traust_storage.attack_mapping (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    mapping_version TEXT NOT NULL,
    attack_version TEXT NOT NULL,
    source TEXT NOT NULL,
    documentation TEXT,
    schema TEXT,
    attribution TEXT NOT NULL,
    capability_map JSONB NOT NULL,
    category_map JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_attack_mapping_artifact ON traust_storage.attack_mapping (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.benchmark_target (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    version BIGINT NOT NULL,
    updated TEXT NOT NULL,
    targets JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_benchmark_target_artifact ON traust_storage.benchmark_target (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.cloud_config_audit (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    summary JSONB NOT NULL,
    findings JSONB NOT NULL,
    gaps JSONB,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_cloud_config_audit_artifact ON traust_storage.cloud_config_audit (artifact_digest);

-- Per-finding projection of a cloud-config findings-current report.
--
-- The cloud-config analogue of report_finding, and needed for the same
-- reason: cloud-config-findings-current is a ONE-ROW projection, so its
-- findings lived only inside a JSON column. Measured 2026-09-19: a whole
-- class of repos and their findings were absent from every storage/v1
-- dashboard query while being present in findings.db, and that was the
-- entire v_open shortfall attributable to this family.
--
-- Carries the IaC columns a policy finding is actually cut by: check_id is
-- what separates two findings on one resource, and framework/provider are
-- how a compliance view slices them.
CREATE TABLE IF NOT EXISTS traust_storage.cloud_config_finding (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    finding_id TEXT NOT NULL,
    title TEXT,
    severity TEXT,
    fingerprint TEXT,
    validation_status TEXT,
    check_id TEXT,
    framework TEXT,
    provider TEXT,
    status TEXT,
    scanner_severity TEXT,
    validity TEXT,
    resolution TEXT,
    assurance TEXT,
    last_updated TEXT,
    conflict INTEGER,
    fp_overridden INTEGER,
    fp_reassertion_blocked INTEGER,
    refuted_awaiting_signoff INTEGER,
    severity_override JSONB,
    -- The body and the analytical axes, same omission as
    -- report_finding: a policy finding's `cwe`, `rationale` and
    -- `control_refs` are what a compliance view cuts by.
    rationale TEXT,
    remediation TEXT,
    cwe TEXT,
    control_refs JSONB,
    locations JSONB,
    fact_ids JSONB,
    external_correlation JSONB,
    effective_severity TEXT,
    fingerprint_algo TEXT,
    isolation_boundary TEXT,
    isolation_dimensions JSONB,
    PRIMARY KEY (binding_id, finding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_cloud_config_finding_fingerprint
    ON traust_storage.cloud_config_finding (fingerprint)
    WHERE fingerprint IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_cloud_config_finding_disposition
    ON traust_storage.cloud_config_finding (validity, resolution);

CREATE INDEX IF NOT EXISTS idx_cloud_config_finding_check
    ON traust_storage.cloud_config_finding (check_id);

CREATE TABLE IF NOT EXISTS traust_storage.cloud_config_findings_current (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    summary JSONB NOT NULL,
    findings JSONB NOT NULL,
    gaps JSONB,
    disposition_summary JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_cloud_config_findings_current_artifact ON traust_storage.cloud_config_findings_current (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.compliance_assessment (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    metadata JSONB NOT NULL,
    coverage JSONB NOT NULL,
    results JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_compliance_assessment_artifact ON traust_storage.compliance_assessment (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.compliance_mapping (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    version BIGINT NOT NULL,
    note TEXT,
    controls JSONB NOT NULL,
    checks JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_compliance_mapping_artifact ON traust_storage.compliance_mapping (artifact_digest);

-- Per-control projection of a compliance assessment.
--
-- compliance-assessment.results[] is the assessment: one row per control per
-- framework, each with a verdict and -- the part that matters -- WHERE the
-- verdict came from. The family projected one row per artifact with results
-- in a JSON column, so "which controls are not satisfied" could not be asked
-- of SQL at all, and no compliance dashboard could be expressed as a view.
--
-- verdict_source is carried, never collapsed into verdict. A control
-- satisfied by a deterministic check, one satisfied by an agent reading
-- evidence, and one satisfied by a human override are three different
-- claims about assurance, and a posture that reports only "satisfied"
-- erases the distinction an auditor is there to examine.
--
-- The override block travels with the row for the same reason: an override
-- records who set it aside and why, which is precisely what a reviewer
-- needs and what a bare verdict hides.
CREATE TABLE IF NOT EXISTS traust_storage.compliance_result (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    framework TEXT NOT NULL,
    control_id TEXT NOT NULL,
    title TEXT,
    classification TEXT,
    verdict TEXT,
    verdict_source TEXT,
    check_id TEXT,
    reason TEXT,
    narrative TEXT,
    evidence JSONB,
    override JSONB,
    n_pass_agreement JSONB,
    PRIMARY KEY (binding_id, framework, control_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_compliance_result_verdict
    ON traust_storage.compliance_result (framework, verdict);

CREATE INDEX IF NOT EXISTS idx_compliance_result_control
    ON traust_storage.compliance_result (control_id);

CREATE TABLE IF NOT EXISTS traust_storage.compliance_scope (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    version BIGINT NOT NULL,
    updated TEXT NOT NULL,
    boundaries JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_compliance_scope_artifact ON traust_storage.compliance_scope (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.doc_variance (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    metadata JSONB NOT NULL,
    records JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_doc_variance_artifact ON traust_storage.doc_variance (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.finding (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    finding_id TEXT NOT NULL,
    target TEXT NOT NULL,
    scanned_at TEXT NOT NULL,
    title TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN (
        'critical', 'high', 'medium', 'low', 'informational'
    )),
    description TEXT NOT NULL,
    category TEXT,
    file TEXT NOT NULL,
    line BIGINT,
    cwe TEXT,
    recommendation TEXT NOT NULL,
    confidence DOUBLE PRECISION NOT NULL,
    PRIMARY KEY (binding_id, finding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_finding_severity
    ON traust_storage.finding (severity);

CREATE TABLE IF NOT EXISTS traust_storage.fleet_fix (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    id TEXT NOT NULL,
    pattern_ref TEXT NOT NULL,
    description TEXT NOT NULL,
    matcher JSONB NOT NULL,
    resolver JSONB,
    rewrite JSONB NOT NULL,
    guards JSONB NOT NULL,
    tests JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_fleet_fix_artifact ON traust_storage.fleet_fix (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.impact_analysis (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    metadata JSONB NOT NULL,
    summary JSONB NOT NULL,
    repos JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_impact_analysis_artifact ON traust_storage.impact_analysis (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.isolation_review (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    interfaces JSONB NOT NULL,
    gaps JSONB NOT NULL,
    posture JSONB NOT NULL,
    notes TEXT,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_isolation_review_artifact ON traust_storage.isolation_review (artifact_digest);

-- Per-event projection of a ledger layer: the TIME DIMENSION.
--
-- layer.events is an append-only, chronologically ordered disposition
-- stream -- every validity and resolution change a finding ever went
-- through, each one dated. It was ingested and then discarded:
-- layer_metadata kept only repo, created_at and the merkle root, so
-- storage/v1 could answer "what is open now" and nothing at all about
-- "what was open in July", "how long did this take to fix", or "how long
-- was that regression live".
--
-- Same relationship report_finding has to report.findings: the layer blob
-- stays authoritative and this is a queryable index over it. Measured on
-- the live corpus: tens of events for every layer, across every layer.
--
-- This is why trending needs no scheduled snapshot. An append-only log of
-- dated transitions IS a time series; a snapshot is that log folded at one
-- moment. Keep the log and any past date stays reconstructable; keep only
-- snapshots and everything before the first run is gone forever, from a
-- second source of truth that can drift from the events.
CREATE TABLE IF NOT EXISTS traust_storage.layer_event (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    event_id TEXT NOT NULL,
    finding_ref TEXT NOT NULL,
    -- Identity across re-audits. finding_ref is scan-scoped, so a trend
    -- keyed on it alone breaks the moment a report renumbers.
    fingerprint TEXT,
    fingerprint_algo TEXT,
    -- recorded_at is when the ledger appended; occurred_at is when the
    -- determination actually happened. Durations MUST use occurred_at --
    -- a bulk re-stamp moves recorded_at for thousands of events at once
    -- and would report every one of them as fixed that day.
    recorded_at TEXT NOT NULL,
    occurred_at TEXT,
    source_type TEXT,
    source_ref TEXT,
    actor_kind TEXT,
    validity TEXT,
    resolution TEXT,
    evidence_grade TEXT,
    auto_accept_tier INTEGER,
    -- Why the determination was made. REQUIRED by layer.schema.json
    -- and dropped: an event stream without rationale records that
    -- something changed and never why.
    rationale TEXT,
    harness_version TEXT,
    evidence_refs JSONB,
    source_reported_by TEXT,
    -- The rest of the disposition. An event asserts a severity and an
    -- embargo state alongside validity/resolution; keeping only the
    -- latter two loses every severity change in the history.
    severity TEXT,
    embargo TEXT,
    -- risk_weight flattened the way source and disposition already are.
    -- `lambda` is the number a trend's risk index multiplies by, so
    -- leaving it inside a blob is what kept that index in Python.
    risk_lambda DOUBLE PRECISION,
    risk_weights_version TEXT,
    risk_tenancy_profile TEXT,
    risk_profile_source TEXT,
    -- Kept whole rather than flattened. `alias` is a rename record and
    -- `finding` is an event-carried finding body -- both optional,
    -- both with their own sub-shape, and no view cuts by them yet.
    alias JSONB,
    finding JSONB,
    -- An administrative restatement of data this layer already committed
    -- to. Kept whole for the same reason as the two above, and queryable
    -- because "which values were restated, by whom, under what ticket"
    -- is the first question asked of a ledger that admits restatements.
    restatement JSONB,
    PRIMARY KEY (binding_id, event_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

-- The trend fold walks the stream in time order per finding.
CREATE INDEX IF NOT EXISTS idx_layer_event_clock
    ON traust_storage.layer_event (fingerprint, occurred_at);

CREATE INDEX IF NOT EXISTS idx_layer_event_resolution
    ON traust_storage.layer_event (resolution, occurred_at);

CREATE TABLE IF NOT EXISTS traust_storage.org_parameters (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    version BIGINT NOT NULL,
    declared_by TEXT NOT NULL,
    declared_on TEXT,
    note TEXT,
    parameters JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_org_parameters_artifact ON traust_storage.org_parameters (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.pqc_blockers (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    artifact TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    executive_summary JSONB NOT NULL,
    severity_criteria JSONB NOT NULL,
    findings JSONB NOT NULL,
    findings_summary JSONB NOT NULL,
    remediation_roadmap JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_pqc_blockers_artifact ON traust_storage.pqc_blockers (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.pqc_decision_tree (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    tree_version TEXT NOT NULL,
    plan TEXT,
    schema TEXT,
    provenance_tree JSONB NOT NULL,
    remediation_effort JSONB NOT NULL,
    readiness_buckets JSONB NOT NULL,
    tls_control_crosswalk JSONB NOT NULL,
    fips_interaction JSONB NOT NULL,
    pqc_classification_map JSONB NOT NULL,
    server_side_caveat JSONB,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_pqc_decision_tree_artifact ON traust_storage.pqc_decision_tree (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.pqc_facts (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    artifact TEXT NOT NULL,
    repository TEXT NOT NULL,
    stamps JSONB NOT NULL,
    coverage JSONB NOT NULL,
    summary JSONB NOT NULL,
    facts JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_pqc_facts_artifact ON traust_storage.pqc_facts (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.pqc_readiness (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    scores JSONB NOT NULL,
    flags JSONB NOT NULL,
    provenance_summary JSONB NOT NULL,
    clock_items JSONB,
    readiness_bucket TEXT,
    fips_interaction JSONB,
    runtime_evidence JSONB,
    server_side_caveats JSONB,
    notes TEXT,
    remediations JSONB,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_pqc_readiness_artifact ON traust_storage.pqc_readiness (artifact_digest);

-- Operator privilege profile: the privilege an operator ASKS FOR.
--
-- DECLARED state, parsed from shipped manifests -- never a live cluster
-- read. "What would this grant if installed", not "what is granted now".
--
-- Columns mirror the schema's ROOT properties, one per artifact, which is
-- the invariant every one-row projection here holds to. The summary counts
-- a dashboard cuts by live one level down in `summary`, so they are lifted
-- in the operator_privilege VIEW rather than duplicated as columns: two
-- copies of one number is how they drift.
CREATE TABLE IF NOT EXISTS traust_storage.priv_profile (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    repo TEXT NOT NULL,
    tier TEXT,
    workloads JSONB,
    rbac_rules JSONB,
    rbac_flags JSONB,
    scc_requests JSONB,
    sccs_shipped JSONB,
    namespaces JSONB,
    install_modes JSONB,
    operatorgroups JSONB,
    tier2_required_vs_granted JSONB,
    example_or_test_manifests_excluded JSONB,
    summary JSONB,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_priv_profile_repo ON traust_storage.priv_profile (repo);

CREATE TABLE IF NOT EXISTS traust_storage.refuted_register (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    source TEXT NOT NULL,
    sources JSONB,
    generated_at TEXT NOT NULL,
    entries JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE TABLE IF NOT EXISTS traust_storage.remediation (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    source_findings JSONB NOT NULL,
    fork JSONB NOT NULL,
    patch JSONB NOT NULL,
    checks JSONB NOT NULL,
    evidence JSONB,
    revalidation JSONB,
    pull_request JSONB,
    summary JSONB NOT NULL,
    notes TEXT,
    footer TEXT,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_remediation_artifact ON traust_storage.remediation (artifact_digest);

-- Per-finding projection of what a remediation set out to fix.
--
-- remediation.source_findings[] links a fix back to the findings that
-- justified it, with the triage confidence and live-validation verdict that
-- were known at the time. In a JSON column it could not be joined to
-- current_finding, so "which open findings already have a fix in flight"
-- had no answer in SQL.
--
-- `validation_verdict` is the state AT REMEDIATION TIME, not now. It is
-- evidence about why the work was started and must not be read as the
-- finding's current disposition, which lives on current_finding.
CREATE TABLE IF NOT EXISTS traust_storage.remediation_source (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    finding_ref TEXT NOT NULL,
    title TEXT,
    severity TEXT,
    cwes JSONB,
    locations JSONB,
    triage_confidence DOUBLE PRECISION,
    validation_verdict TEXT,
    audit_report_path TEXT,
    triage_report_path TEXT,
    validation_report_path TEXT,
    PRIMARY KEY (binding_id, finding_ref),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_remediation_source_severity
    ON traust_storage.remediation_source (severity);

CREATE TABLE IF NOT EXISTS traust_storage.report (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    executive_summary JSONB NOT NULL,
    severity_criteria JSONB NOT NULL,
    findings JSONB NOT NULL,
    findings_summary JSONB NOT NULL,
    remediation_roadmap JSONB NOT NULL,
    dependency_audit JSONB,
    negative_results JSONB,
    asvs_coverage JSONB,
    scanner_correlation JSONB,
    peach_isolation_review JSONB,
    disposition_summary JSONB,
    footer TEXT,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_report_artifact ON traust_storage.report (artifact_digest);

-- Per-finding projection of a cumulative report.
--
-- report.findings is an opaque JSON column: the disposition every dashboard
-- filters on (validity, resolution) and the identity every distinct-exposure
-- count needs (fingerprint) were present in the contract but unqueryable.
-- This makes them columns without changing what the schema models.
--
-- One row per finding per report binding. Disposition is optional on the
-- artifact -- it appears only on cumulative reports -- so a finding without
-- one still projects, carrying its identity with NULL disposition.
CREATE TABLE IF NOT EXISTS traust_storage.report_finding (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    finding_id TEXT NOT NULL,
    title TEXT,
    severity TEXT,
    -- Secondary correlation key, never the sole key of a disposition record
    -- (report.schema.json): the scan-scoped finding_id stays primary.
    fingerprint TEXT,
    validation_status TEXT,
    validity TEXT,
    resolution TEXT,
    assurance TEXT,
    last_updated TEXT,
    -- The four flags that carry the two-person rule and the countersign
    -- queue. Dropping them is how a dashboard loses sight of whether an FP
    -- was overridden by execution evidence.
    conflict INTEGER,
    fp_overridden INTEGER,
    fp_reassertion_blocked INTEGER,
    refuted_awaiting_signoff INTEGER,
    severity_override JSONB,
    -- The body of the finding. `description` and `remediation` are
    -- REQUIRED by report.schema.json and were the two largest strings
    -- the projection dropped; a finding without them is a title.
    description TEXT,
    remediation TEXT,
    -- The analytical axes. `category` and `cwes` are what an
    -- insecure-patterns rollup groups by, and neither was reachable:
    -- the pattern dashboard is the one consumer that cannot be
    -- expressed on this table without them.
    category TEXT,
    cwes JSONB,
    locations JSONB,
    asvs_references JSONB,
    peach_references JSONB,
    capec JSONB,
    attack_pattern TEXT,
    cvss JSONB,
    evidence JSONB,
    -- Provenance and downgrade context. `effective_severity` is the
    -- severity after disposition; reading `severity` alone reports a
    -- downgraded finding at its original rating.
    effective_severity TEXT,
    origin TEXT,
    source_findings JSONB,
    passes JSONB,
    remediation_effort TEXT,
    pqc_classification TEXT,
    fingerprint_algo TEXT,
    isolation_boundary TEXT,
    isolation_dimensions JSONB,
    dependency JSONB,
    PRIMARY KEY (binding_id, finding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_report_finding_fingerprint
    ON traust_storage.report_finding (fingerprint)
    WHERE fingerprint IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_report_finding_disposition
    ON traust_storage.report_finding (validity, resolution);

CREATE TABLE IF NOT EXISTS traust_storage.risk_rating_methodology (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    methodology TEXT NOT NULL,
    methodology_version TEXT NOT NULL,
    source TEXT NOT NULL,
    documentation TEXT,
    schema TEXT,
    bands JSONB NOT NULL,
    bucket_thresholds JSONB NOT NULL,
    likelihood_factors JSONB NOT NULL,
    impact_factors JSONB NOT NULL,
    matrix JSONB NOT NULL,
    fallback JSONB NOT NULL,
    threat_intel_factor JSONB,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_risk_rating_methodology_artifact ON traust_storage.risk_rating_methodology (artifact_digest);

CREATE TABLE IF NOT EXISTS traust_storage.sla_policy (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    policy_name TEXT NOT NULL,
    source JSONB NOT NULL,
    severity_mapping JSONB NOT NULL,
    clock_start TEXT,
    profiles JSONB NOT NULL,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_sla_policy_artifact ON traust_storage.sla_policy (artifact_digest);

-- Ownership for each audited subject: the denominator every dashboard cut
-- divides by.
--
-- Nothing in the contract modelled this. Ownership lived only in the
-- deployment's corpus-config and in the harness's own SQLite projection, so
-- "X% of our repos" could not be computed from storage/v1 at all. Projected
-- from the corpus-registry artifact, keyed on the same subject_id that
-- artifact_binding carries, so findings join to ownership in SQL.
CREATE TABLE IF NOT EXISTS traust_storage.subject_ownership (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    subject_id TEXT NOT NULL,
    tree TEXT NOT NULL,
    ownership TEXT NOT NULL,
    business_unit TEXT NOT NULL,
    label TEXT,
    product TEXT,
    repo_url TEXT,
    ref TEXT,
    ref_kind TEXT,
    -- Load-bearing: a large share of audits are branch re-audits of the same
    -- code, so a denominator that does not exclude them overstates coverage.
    is_branch_audit INTEGER,
    PRIMARY KEY (binding_id, subject_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_subject_ownership_subject
    ON traust_storage.subject_ownership (subject_id);

CREATE INDEX IF NOT EXISTS idx_subject_ownership_cut
    ON traust_storage.subject_ownership (ownership, business_unit);

-- Per-threat projection of the threat register.
--
-- Threat MODELS are prose Markdown and cannot be projected; the register is
-- their structured restatement, and this is one row per threat in it. The
-- register blob stays authoritative -- this is an index over it, the same
-- relationship report_finding has to report.findings.
--
-- `threat_key` is the identity, not `threat_id`: every model numbers its
-- threats from T1, so threat_id alone collides across every model.
CREATE TABLE IF NOT EXISTS traust_storage.threat (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    threat_key TEXT NOT NULL,
    threat_id TEXT NOT NULL,
    model TEXT NOT NULL,
    subject_id TEXT,
    product TEXT,
    statement TEXT,
    surface TEXT,
    asset TEXT,
    -- LEGACY labels, present only on a threat not yet re-rated with the
    -- OWASP Risk Rating Methodology (threat-model schema: impact/likelihood).
    impact TEXT,
    likelihood TEXT,
    -- OWASP Risk Rating Methodology rating (schema `risk_rating`): the whole
    -- block, factors and reasons included, and its derived values as typed
    -- columns so a view can filter and order by them. All NULL on a threat
    -- not yet re-rated. Severity is one of critical, high, medium, low, note.
    risk_rating JSONB,
    severity TEXT,
    likelihood_score DOUBLE PRECISION,
    likelihood_level TEXT,
    impact_score DOUBLE PRECISION,
    impact_level TEXT,
    impact_basis TEXT,
    -- Four states, and partially_mitigated is the largest in practice.
    -- Folding it into mitigated is the single biggest way to overstate
    -- threat coverage, so it stays its own value all the way to the view.
    status TEXT,
    controls TEXT,
    actors JSONB,
    -- Empty means modelled but NOT evidenced, which is a different claim
    -- from unmitigated. Kept so a view can tell the two apart.
    evidence JSONB,
    linddun INTEGER,
    -- LEGACY ordering for a threat not yet re-rated: impact weight x
    -- likelihood weight over the legacy labels. Never a calibrated risk value
    -- and never comparable to CVSS; NULL on an OWASP-rated threat, which
    -- orders by severity instead.
    score INTEGER,
    -- Column 11 of the threats table, default since harness 0.82.0.
    -- This is what an ATT&CK coverage rollup reads; omitting it drops
    -- every MITRE mapping the estate has recorded.
    attack_refs JSONB,
    isolation_dimensions JSONB,
    isolation_boundaries JSONB,
    PRIMARY KEY (binding_id, threat_key),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_threat_subject ON traust_storage.threat (subject_id);
CREATE INDEX IF NOT EXISTS idx_threat_rank ON traust_storage.threat (status, score);
CREATE INDEX IF NOT EXISTS idx_threat_severity ON traust_storage.threat (status, severity);

CREATE TABLE IF NOT EXISTS traust_storage.traust_storage_meta (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    contract_version TEXT NOT NULL,
    revision INTEGER NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS traust_storage.triage_verdict (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    finding_id TEXT NOT NULL,
    source_finding_id TEXT,
    triage_completed TEXT NOT NULL,
    verdict TEXT NOT NULL CHECK (verdict IN (
        'true_positive', 'hardening', 'undetermined', 'false_positive', 'duplicate'
    )),
    severity TEXT CHECK (severity IN (
        'critical', 'high', 'medium', 'low', 'informational'
    )),
    vote_breakdown JSONB,
    rationale TEXT,
    PRIMARY KEY (binding_id, finding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_triage_verdict_source
    ON traust_storage.triage_verdict (source_finding_id, verdict);

CREATE TABLE IF NOT EXISTS traust_storage.validation (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    source_reports JSONB NOT NULL,
    summary JSONB NOT NULL,
    validated_findings JSONB NOT NULL,
    attack_chains JSONB NOT NULL,
    novel_findings JSONB NOT NULL,
    negative_results JSONB,
    execution_log_ref TEXT NOT NULL,
    execution_log_sha256 TEXT,
    footer TEXT,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_validation_artifact ON traust_storage.validation (artifact_digest);

-- Per-finding projection of a live-validation run.
--
-- validation.validated_findings is an opaque JSON column holding the
-- ACTUAL OUTCOME of attempting each claimed finding against a running
-- system: confirmed, refuted, inconclusive, blocked by scope, or not
-- attempted and why. Hundreds of thousands across a live corpus, none of
-- it was queryable.
--
-- Same relationship report_finding has to report.findings: the blob stays
-- authoritative and this is an index over it.
--
-- `source_finding_id` is the link back to the finding that was claimed, so
-- "was this ever proven against a live system" becomes a join rather than
-- a separate spreadsheet.
CREATE TABLE IF NOT EXISTS traust_storage.validation_finding (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    source_id TEXT NOT NULL,
    -- Parsed tail of source_id. The scan-scoped finding id, which is what
    -- report_finding is keyed on.
    source_finding_id TEXT,
    title TEXT,
    claimed_severity TEXT,
    surface TEXT,
    -- confirmed | refuted | inconclusive | blocked_by_scope | not_attempted.
    -- not_attempted DOMINATES in practice, by a wide margin, and carries
    -- its reason separately: a validation lane that reported only attempts
    -- would describe 12% of its own work.
    verdict TEXT,
    skip_reason TEXT,
    technique TEXT,
    observed_impact TEXT,
    -- The rest of what validated_findings[] declares. Projected as
    -- COLUMNS rather than joined out of the blob at query time: the
    -- join is source_id against every entry of the same array, which
    -- is quadratic per artifact and unusable at corpus scale. Same
    -- reason report_finding and threat are projections, not views.
    --
    -- evidence_grade (E0-E3) and soundness_flag are the two that say
    -- how far a verdict can be trusted -- soundness_flag is the
    -- machine-readable reason a refutation was un-emittable. A view
    -- without them reports outcomes with no way to weigh them.
    evidence_grade TEXT,
    grade_rationale TEXT,
    soundness_flag TEXT,
    severity_validation TEXT,
    deviation_from_claim TEXT,
    rollback_performed INTEGER,
    chain_context JSONB,
    not_attempted_reason TEXT,
    PRIMARY KEY (binding_id, source_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_validation_finding_verdict
    ON traust_storage.validation_finding (verdict);

CREATE INDEX IF NOT EXISTS idx_validation_finding_source
    ON traust_storage.validation_finding (source_finding_id);

CREATE TABLE IF NOT EXISTS traust_storage.verification (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    title TEXT NOT NULL,
    metadata JSONB NOT NULL,
    summary JSONB NOT NULL,
    verified_findings JSONB NOT NULL,
    regressions JSONB NOT NULL,
    commit_timeline JSONB NOT NULL,
    evidence JSONB,
    recommendations JSONB,
    notes TEXT,
    footer TEXT,
    PRIMARY KEY (binding_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_verification_artifact ON traust_storage.verification (artifact_digest);

-- Per-finding projection of a remediation verification.
--
-- verification.verified_findings[] is the answer to "did the fix hold", one
-- row per original finding re-audited. It lived in a JSON column, so the
-- regression count -- the single most consequential number this lane
-- produces -- could not be queried, only counted by a script walking files.
--
-- `verdict` is kept at five values, never folded to fixed/not-fixed.
-- partially_resolved and new_approach are real outcomes that a binary
-- reading reports as one of the two things they are not, and `regression`
-- is a verdict here as well as a separate array: the same re-audit can
-- resolve the original finding and introduce another.
--
-- `unattributed` marks a fix nobody could tie to a commit. It is evidence
-- about the evidence, and dropping it lets an unexplained pass read exactly
-- like a demonstrated one.
CREATE TABLE IF NOT EXISTS traust_storage.verification_finding (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    original_id TEXT NOT NULL,
    original_title TEXT,
    original_severity TEXT,
    verdict TEXT,
    remediation_commits JSONB,
    unattributed INTEGER,
    -- The evidence block flattened into its four declared members.
    -- Kept apart rather than stored whole because a nested evidence
    -- block is exactly where fields go missing unnoticed: 15 of
    -- impact-analysis's 19 did, inside one opaque column.
    evidence_explanation TEXT,
    evidence_framework_reference TEXT,
    evidence_original_code TEXT,
    evidence_patched_code TEXT,
    disposition_rationale TEXT,
    residual_risk TEXT,
    residual_severity TEXT,
    cross_repo JSONB,
    PRIMARY KEY (binding_id, original_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_verification_finding_verdict
    ON traust_storage.verification_finding (verdict);

CREATE INDEX IF NOT EXISTS idx_verification_finding_unattributed
    ON traust_storage.verification_finding (unattributed);

-- Per-regression projection of a remediation verification.
--
-- A regression is a NEW finding the fix introduced, not a restatement of the
-- one it was meant to close, so it carries a finding's full shape --
-- severity, cwes, locations, description, remediation -- and `introduced_by`,
-- the commit that caused it.
--
-- Separate from verification_finding on purpose. Folding the two would make
-- "how many findings did this verification touch" ambiguous, and the
-- regressions are the half a remediation review must not miss.
CREATE TABLE IF NOT EXISTS traust_storage.verification_regression (
    binding_id TEXT NOT NULL,
    artifact_digest TEXT NOT NULL,
    regression_id TEXT NOT NULL,
    title TEXT,
    severity TEXT,
    cwes JSONB,
    cvss JSONB,
    locations JSONB,
    description TEXT,
    remediation TEXT,
    evidence JSONB,
    attack_pattern TEXT,
    category TEXT,
    introduced_by TEXT,
    routed_id TEXT,
    fingerprint TEXT,
    fingerprint_algo TEXT,
    PRIMARY KEY (binding_id, regression_id),
    FOREIGN KEY (binding_id, artifact_digest)
        REFERENCES traust_storage.artifact_binding(binding_id, artifact_digest)
);

CREATE INDEX IF NOT EXISTS idx_verification_regression_severity
    ON traust_storage.verification_regression (severity);

CREATE INDEX IF NOT EXISTS idx_verification_regression_fingerprint
    ON traust_storage.verification_regression (fingerprint);

CREATE OR REPLACE VIEW traust_storage.current_binding AS
SELECT b.*
FROM traust_storage.artifact_binding b
WHERE NOT EXISTS (
    SELECT 1
    FROM traust_storage.artifact_binding successor
    WHERE successor.supersedes_binding_id = b.binding_id
      AND successor.scope_id = b.scope_id
);

-- One report per subject: the contract's answer to "which restatement of
-- this repo's finding set do we count?"
--
-- A repo's findings are restated across artifacts -- a plain audit and a
-- disposition-aware findings-current report describe the SAME findings. Both
-- are legitimately current (neither supersedes the other; they are different
-- layers, not corrections), so counting report_finding directly counts every
-- finding once per restatement. The harness resolver has always applied this
-- preference in Python; storage/v1 had no concept of it.
--
-- Rank: a disposition-aware report outranks one that is not, matching the
-- resolver's LAYER PREFERENCE rule. disposition_summary is the discriminator
-- because it is already projected and, measured across the live corpus,
-- present on every findings-current report and no plain audit.
-- Among equals the most recently bound wins, with binding_id breaking ties so
-- the view is deterministic rather than arbitrary.
CREATE OR REPLACE VIEW traust_storage.report_current AS
SELECT b.scope_id,
       b.subject_id,
       b.run_id,
       b.layer_id,
       b.binding_id,
       r.artifact_digest,
       CASE WHEN r.disposition_summary IS NULL THEN 0 ELSE 1 END AS disposition_aware
FROM traust_storage.current_binding b
JOIN traust_storage.report r
  ON r.binding_id = b.binding_id
WHERE b.artifact_name = 'report'
  AND b.subject_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM traust_storage.current_binding rival
      JOIN traust_storage.report rival_report
        ON rival_report.binding_id = rival.binding_id
      WHERE rival.artifact_name = 'report'
        AND rival.subject_id = b.subject_id
        AND rival.scope_id = b.scope_id
        AND (
            (rival_report.disposition_summary IS NOT NULL
             AND r.disposition_summary IS NULL)
         OR ((rival_report.disposition_summary IS NULL)
              = (r.disposition_summary IS NULL)
             AND (rival.bound_at > b.bound_at
                  OR (rival.bound_at = b.bound_at
                      AND rival.binding_id > b.binding_id)))
        )
  );

-- One ownership declaration per subject: the contract's answer to "which
-- corpus-registry do we believe?"
--
-- corpus-registry is an aggregate artifact restating the WHOLE population,
-- and it carries an `updated` timestamp, so every import produces new
-- content, a new digest and a new binding. subject_ownership is keyed on
-- (binding_id, subject_id), so those rows ACCUMULATE rather than replace.
--
-- Every view above this joins ownership on subject_id, so without this the
-- second import fans each finding out across N registry generations.
-- Measured on the live corpus: one re-import took current_finding from
-- DOUBLED both the finding count and the census population. It
-- stayed invisible because the store was always rebuilt from empty.
--
-- Most recently bound wins, with binding_id breaking ties, matching the
-- rule report_current already applies to restated reports.
CREATE OR REPLACE VIEW traust_storage.ownership_current AS
SELECT b.scope_id,
       b.binding_id,
       o.subject_id,
       o.tree,
       o.ownership,
       o.business_unit,
       o.label,
       o.product,
       o.repo_url,
       o.ref,
       o.ref_kind,
       o.is_branch_audit
FROM traust_storage.subject_ownership o
JOIN traust_storage.artifact_binding b
  ON b.binding_id = o.binding_id
WHERE NOT EXISTS (
    SELECT 1
    FROM traust_storage.subject_ownership rival
    JOIN traust_storage.artifact_binding rival_binding
      ON rival_binding.binding_id = rival.binding_id
    WHERE rival.subject_id = o.subject_id
      AND (rival_binding.bound_at > b.bound_at
           OR (rival_binding.bound_at = b.bound_at
               AND rival_binding.binding_id > b.binding_id))
);

-- The dashboard spine: one row per CURRENT finding, with its owner.
--
-- Three things a dashboard must not have to rediscover, unified here so
-- every view above it inherits them:
--
--   1. BOTH finding families. Code findings project to report_finding and
--      policy findings to cloud_config_finding. A query that reads only the
--      first silently omits every cloud-config finding.
--   2. ONE report per subject. A repo's findings are restated across a plain
--      audit and a disposition-aware findings-current report, and both are
--      legitimately current -- counting report_finding directly inflates by
--      49% (measured across 155 real paired reports).
--   3. OWNERSHIP. The denominator every cut divides by, and it lives in
--      neither finding table.
--
--
-- category, cwes and effective_severity ride the spine as of REVISION 15.
-- They are the axes a pattern rollup groups by, and a view above this one
-- should not have to re-join the finding tables to reach them. A policy
-- finding declares a single `cwe` rather than a list, so it is wrapped into
-- a one-element array: one column, one meaning, whichever family a row came
-- from. effective_severity is the severity AFTER disposition -- reading
-- `severity` alone reports a downgraded finding at its original rating.
-- Deliberately UNFILTERED on disposition: open/hardening are policy and
-- belong in the views above, not in the spine.
CREATE OR REPLACE VIEW traust_storage.current_finding AS
SELECT binding.scope_id,
       binding.subject_id,
       binding.run_id,
       f.finding_id,
       f.title,
       f.severity,
       f.fingerprint,
       f.validity,
       f.resolution,
       f.assurance,
       f.category,
       f.cwes,
       f.effective_severity,
       'code' AS family,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.is_branch_audit
FROM traust_storage.report_finding f
JOIN traust_storage.report_current current_report
  ON current_report.binding_id = f.binding_id
JOIN traust_storage.artifact_binding binding
  ON binding.binding_id = f.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = binding.subject_id
UNION ALL
SELECT binding.scope_id,
       binding.subject_id,
       binding.run_id,
       f.finding_id,
       f.title,
       f.severity,
       f.fingerprint,
       f.validity,
       f.resolution,
       f.assurance,
       NULL AS category,
       CASE WHEN f.cwe IS NULL THEN NULL ELSE jsonb_build_array(f.cwe) END AS cwes,
       f.effective_severity,
       'policy' AS family,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.is_branch_audit
FROM traust_storage.cloud_config_finding f
JOIN traust_storage.current_binding binding
  ON binding.binding_id = f.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = binding.subject_id;

-- Current threats, with the owner of the subject they were modelled against.
--
-- One threat model per subject, and a re-modelled subject must not count
-- twice. Same rule report_current applies to restated reports: most
-- recently bound wins, binding_id breaking ties.
--
-- Resolved per SUBJECT, not per scope. An earlier cut of this view read a
-- fleet-wide register and resolved one current document for the whole
-- scope -- wrong grain, and fed from the dashboard's own output. The
-- estate has one model per subject; that is what this counts.
--
-- Ownership is LEFT JOINed: a threat model can exist for a subject the
-- corpus registry does not declare, and such a model is still real. It
-- simply has no denominator.
CREATE OR REPLACE VIEW traust_storage.threat_current AS
SELECT b.scope_id,
       t.threat_key,
       t.threat_id,
       t.model,
       t.subject_id,
       t.product,
       t.statement,
       t.surface,
       t.asset,
       t.impact,
       t.likelihood,
       t.status,
       t.controls,
       t.evidence,
       t.attack_refs,
       t.linddun,
       t.score,
       t.isolation_dimensions,
       t.isolation_boundaries,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.is_branch_audit,
       t.risk_rating,
       t.severity,
       t.likelihood_score,
       t.likelihood_level,
       t.impact_score,
       t.impact_level,
       t.impact_basis
FROM traust_storage.threat t
JOIN traust_storage.artifact_binding b
  ON b.binding_id = t.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = b.subject_id
WHERE b.artifact_name = 'threat-model'
  AND NOT EXISTS (
      SELECT 1
      FROM traust_storage.artifact_binding rival
      WHERE rival.artifact_name = 'threat-model'
        AND rival.scope_id = b.scope_id
        AND rival.subject_id = b.subject_id
        AND (rival.bound_at > b.bound_at
             OR (rival.bound_at = b.bound_at AND rival.binding_id > b.binding_id))
  );

-- Current live-validation outcomes, one row per claimed finding, with the
-- owner of the subject they were validated against.
--
-- EVERY FIELD THE CONTRACT DECLARES ON A VALIDATED FINDING IS CARRIED.
-- The first cut dropped `evidence_grade` (E0-E3)
-- and `soundness_flag` -- the machine-readable reason a refutation was
-- un-emittable. Those two say how far a verdict can be trusted, and a
-- view reporting outcomes without them gives no way to weigh them.
-- Projected as columns, never joined out of the blob: matching
-- source_id against every entry of the same array is quadratic per
-- artifact. tests/test_view_contract_coverage.py enforces the coverage.
--
-- SUPERSESSION IS PER ENVIRONMENT, NOT PER SUBJECT. A run against a hub
-- cluster and a run against a spoke are not re-runs of each other. Measured
-- measured: one subject's hub and spoke runs covered the SAME findings
-- and disagreed on a material share of the verdicts, some confirmed
-- against one target and refuted against the other. Collapsing on
-- subject alone silently
-- picked one and deleted the disagreement, which is the single most
-- interesting thing the evidence lens has to say.
--
-- `metadata.environment` is extracted rather than stored a second time,
-- the way operator_privilege reads its summary counts out of JSON.
--
-- ABSENT ENVIRONMENT MEANS UNKNOWN, NOT "THE SAME AS THE OTHERS". The
-- partition falls back to run_id, so every run of an unlabelled subject
-- stays distinct rather than being merged on an assumption. That is
-- deliberately noisier: many artifacts predate the field, and merging
-- them is exactly the guess that produced the 290-verdict conflict. The
-- noise is the honest reading and it shrinks as producers adopt the field.
--
-- Within one environment the newest run wins, binding_id breaking ties --
-- the rule report_current and threat_current already apply.
--
-- Ownership is LEFT JOINed: a validation against a subject the registry
-- does not declare is still real; it simply has no denominator.
CREATE OR REPLACE VIEW traust_storage.validation_current WITH (security_barrier) AS
SELECT b.scope_id,
       b.subject_id,
       b.run_id,
       v.metadata->>'target_environment' AS target_environment,
       vf.source_id,
       vf.source_finding_id,
       vf.title,
       vf.claimed_severity,
       vf.surface,
       vf.verdict,
       vf.skip_reason,
       vf.technique,
       vf.observed_impact,
       vf.evidence_grade,
       vf.grade_rationale,
       vf.soundness_flag,
       vf.severity_validation,
       vf.deviation_from_claim,
       vf.rollback_performed,
       vf.chain_context,
       vf.not_attempted_reason,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.product,
       owner.is_branch_audit
FROM traust_storage.validation_finding vf
JOIN traust_storage.artifact_binding b
  ON b.binding_id = vf.binding_id
JOIN traust_storage.validation v
  ON v.binding_id = vf.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = b.subject_id
WHERE b.artifact_name = 'validation'
  AND NOT EXISTS (
      SELECT 1
      FROM traust_storage.artifact_binding rival
      JOIN traust_storage.validation rv ON rv.binding_id = rival.binding_id
      WHERE rival.artifact_name = 'validation'
        AND rival.scope_id = b.scope_id
        AND rival.subject_id = b.subject_id
        AND COALESCE(rv.metadata->>'target_environment', rival.run_id)
          = COALESCE(v.metadata->>'target_environment', b.run_id)
        AND (rival.bound_at > b.bound_at
             OR (rival.bound_at = b.bound_at AND rival.binding_id > b.binding_id))
  );

-- When each finding was FIRST observed, across every report that carried it.
--
-- The birth half of the time dimension. The ledger's earliest event is a
-- triage verdict, which is when a finding was first ADJUDICATED, not when
-- it was first seen -- and only 60% of findings have any event at all
-- (measured: well over half). Using the ledger alone as the clock start
-- therefore undercounts the population and overstates how fast things move.
--
-- report_finding keeps a row per report BINDING, including superseded
-- ones, so the earliest report carrying a fingerprint is still on record
-- even after re-audits. That is the true first observation, and it covers
-- every finding because report.metadata.date is required.
CREATE OR REPLACE VIEW traust_storage.finding_first_seen AS
SELECT b.scope_id,
       f.fingerprint,
       MIN((r.metadata->>'date')) AS first_seen,
       MAX((r.metadata->>'date')) AS last_seen,
       COUNT(DISTINCT b.subject_id) AS subjects
FROM traust_storage.report_finding f
JOIN traust_storage.artifact_binding b ON b.binding_id = f.binding_id
JOIN traust_storage.report r ON r.binding_id = f.binding_id
WHERE f.fingerprint IS NOT NULL
GROUP BY b.scope_id, f.fingerprint;

-- One row per finding identity with its full clock: born, adjudicated,
-- closed, and how long each step took.
--
-- Joins the two halves of the time dimension -- first observation from the
-- reports, transitions from the ledger -- because neither alone is right:
-- reports know when a finding appeared but not what was decided about it,
-- and the ledger knows the decisions but only for the 60% that have any.
--
-- Durations use occurred_at, NEVER recorded_at. recorded_at is when the
-- ledger appended, and a bulk re-stamp moves it for thousands of events at
-- once -- computing MTTR on it would report the whole corpus as fixed on
-- the day of the re-stamp. The offset is normalised before the
-- subtraction, which matters: real events carry non-UTC offsets and a
-- naive string comparison is wrong by hours.
--
-- days_to_resolve is NULL while a finding is open. That is deliberate: a
-- mean over closed findings only is CENSORED and reads faster than reality,
-- so a consumer must see the open ones rather than have them silently
-- excluded by a zero.
CREATE OR REPLACE VIEW traust_storage.finding_timeline AS
SELECT seen.scope_id,
       seen.fingerprint,
       seen.first_seen,
       seen.last_seen,
       seen.subjects,
       clock.first_adjudicated,
       clock.first_routed_or_filed,
       clock.resolved_at,
       clock.regression_at,
       -- NULL when the clock is inconsistent rather than a negative
       -- number: a resolution dated BEFORE the first report we still hold
       -- means the report that first showed the finding is not in the
       -- corpus (superseded, or it failed validation), so the duration is
       -- unknown, not negative. Measured: 1 of 698 resolved findings.
       CASE WHEN clock.resolved_at IS NOT NULL
                 AND clock.resolved_at::timestamptz >= seen.first_seen::timestamptz
            THEN EXTRACT(EPOCH FROM (clock.resolved_at::timestamptz - seen.first_seen::timestamptz)) / 86400
       END AS days_to_resolve,
       CASE WHEN clock.resolved_at IS NOT NULL
                 AND clock.resolved_at::timestamptz < seen.first_seen::timestamptz
            THEN 1 ELSE 0 END AS clock_inconsistent,
       CASE WHEN clock.resolved_at IS NOT NULL AND clock.first_adjudicated IS NOT NULL
            THEN EXTRACT(EPOCH FROM (clock.resolved_at::timestamptz - clock.first_adjudicated::timestamptz)) / 86400
       END AS days_adjudicated_to_resolve,
       -- Only when the regression actually CLOSED. Running the clock to
       -- the last report date was wrong: a regression is often recorded
       -- after the last audit of that subject, which produced negative
       -- dwell on real data. An open regression's dwell is "as of when you
       -- ask", which belongs in the query alongside :as_of, not baked in
       -- here where every caller would inherit one arbitrary end date.
       CASE WHEN clock.regression_at IS NOT NULL
                 AND clock.resolved_after_regression IS NOT NULL
                 AND clock.resolved_after_regression::timestamptz >= clock.regression_at::timestamptz
            THEN EXTRACT(EPOCH FROM (clock.resolved_after_regression::timestamptz - clock.regression_at::timestamptz)) / 86400
       END AS regression_days,
       CASE WHEN clock.regression_at IS NOT NULL
                 AND clock.resolved_after_regression IS NULL
            THEN 1 ELSE 0 END AS regression_still_open,
       clock.events
FROM traust_storage.finding_first_seen seen
LEFT JOIN (
    SELECT b.scope_id,
           e.fingerprint,
           COUNT(*) AS events,
           MIN(e.occurred_at) AS first_adjudicated,
           -- The routing/filing clock an SLA policy may choose to
           -- start from: when the finding reached a tracker or a
           -- review, not when a scanner first emitted it.
           MIN(CASE WHEN e.source_type IN ('jira', 'mr_comment')
                    THEN e.occurred_at END) AS first_routed_or_filed,
           MIN(CASE WHEN e.resolution = 'resolved' THEN e.occurred_at END) AS resolved_at,
           MIN(CASE WHEN e.resolution = 'regression_introduced' THEN e.occurred_at END)
               AS regression_at,
           MAX(CASE WHEN e.resolution = 'resolved' THEN e.occurred_at END)
               AS resolved_after_regression
    FROM traust_storage.layer_event e
    JOIN traust_storage.artifact_binding b ON b.binding_id = e.binding_id
    WHERE e.fingerprint IS NOT NULL AND e.occurred_at IS NOT NULL
    GROUP BY b.scope_id, e.fingerprint
) clock
  ON clock.scope_id = seen.scope_id AND clock.fingerprint = seen.fingerprint;

-- Post-quantum readiness per subject, with its owner.
--
-- readiness_bucket is the headline: which repos can survive the migration
-- and which cannot. It is a projected COLUMN already; the flags that
-- decide urgency are one level down in JSON and are lifted here so a
-- consumer filters rather than parsing blobs.
--
-- `not-applicable` is a real bucket and NOT a gap: a repo with no
-- key-establishment surface has nothing to migrate. Folding it into
-- "not ready" would invent a backlog roughly the size of the ready one.
--
-- Ownership is LEFT JOINed. A PQC assessment exists for repos the corpus
-- registry may not declare, and such an assessment is still real -- it
-- simply has no denominator, and dropping it would hide it entirely.
CREATE OR REPLACE VIEW traust_storage.pqc_posture AS
SELECT b.scope_id,
       b.subject_id,
       r.readiness_bucket,
       (r.flags->>'has_2030_clock_items')::boolean::int AS has_2030_clock,
       (r.flags->>'hndl_priority')::boolean::int AS hndl_priority,
       (r.flags->>'runtime_verification_required')::boolean::int
           AS runtime_verification_required,
       r.provenance_summary->>'dominant' AS dominant_provenance,
       jsonb_array_length(COALESCE(r.clock_items, '[]'::jsonb)) AS clock_items,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.is_branch_audit
FROM traust_storage.pqc_readiness r
JOIN traust_storage.current_binding b ON b.binding_id = r.binding_id
LEFT JOIN traust_storage.ownership_current owner ON owner.subject_id = b.subject_id;

-- The policy-level SLA clock, one row per scope.
--
-- Separate from sla_threshold ON PURPOSE. clock_start is a property of
-- the POLICY, not of a severity, and resolving it through the per-severity
-- join meant a severity the profile does not clock fell back to a
-- different clock than its siblings. Measured on a live corpus, findings
-- split roughly evenly between ageing from the report date and the ledger
-- event, under one policy that names a single clock.
--
-- A severity may legitimately have no threshold (unclocked) while the
-- policy still says where every clock starts.
CREATE OR REPLACE VIEW traust_storage.sla_clock AS
SELECT b.scope_id,
       p.policy_name,
       profile.key AS profile_name,
       COALESCE(p.clock_start, 'first_routed_or_filed') AS clock_start
FROM traust_storage.sla_policy p
JOIN traust_storage.current_binding b ON b.binding_id = p.binding_id
JOIN LATERAL jsonb_each(p.profiles) profile ON TRUE
WHERE (profile.value->>'default')::boolean IS TRUE;

-- Per-severity SLA thresholds from the deployment's OWN policy.
--
-- SLAs are policy data, never code. sla-policy is a contract artifact, so
-- an adopter states their own numbers, their own severity mapping and
-- their own clock start, and a per-business-unit policy is a different
-- binding rather than a fork of this view.
--
-- The DEFAULT profile is selected here. A deployment ships several
-- (baseline, a stricter contractual one, a regulated one) and marks one
-- default; picking a non-default profile is a query-time choice, not a
-- schema change.
--
-- resolve_days NULL means TRACKED BUT NEVER OVERDUE, which is a real
-- policy position and must not read as zero days. A severity absent from
-- the profile is unclocked under it, so it yields no row at all rather
-- than a fabricated threshold.
CREATE OR REPLACE VIEW traust_storage.sla_threshold AS
SELECT b.scope_id,
       p.policy_name,
       profile.key AS profile_name,
       COALESCE(p.clock_start, 'first_routed_or_filed') AS clock_start,
       sla.key AS severity,
       (sla.value->>'resolve_days')::int AS resolve_days,
       (sla.value->>'acknowledge_days')::int AS acknowledge_days
FROM traust_storage.sla_policy p
JOIN traust_storage.current_binding b ON b.binding_id = p.binding_id
JOIN LATERAL jsonb_each(p.profiles) profile ON TRUE
JOIN LATERAL jsonb_each(profile.value->'slas') sla ON TRUE
WHERE (profile.value->>'default')::boolean IS TRUE;

-- Recurring weakness patterns: one row per CWE per cut, fanned out of the
-- finding's cwes[] rather than counted per finding.
--
-- The dashboard this replaces grouped by a PRIMARY cwe -- the first entry of
-- the list -- because that is what a Python loop makes easy. A finding
-- declaring CWE-78 and CWE-88 is an instance of both patterns, and reporting
-- it only against the first understates the second. Fanning the array out
-- means one finding can appear under several CWEs, so `occurrences` here sums
-- to more than the finding count. That is the correct reading of "how many
-- findings involve this weakness" and the reason the column is not named
-- `findings`.
--
-- json_each over cwes is a small flat array of strings, not the quadratic
-- join storage/v1/README.md rule 3 warns about: that rule is about matching
-- an id against every entry of the same array, which this does not do.
--
-- Classified, never filtered -- the census convention. `family` separates
-- code findings from policy findings, `exposure_class` carries disposition
-- exactly as census_exposure defines it, and a consumer wanting only open
-- source-code patterns filters on both rather than restating the policy.
CREATE OR REPLACE VIEW traust_storage.pattern_exposure AS
SELECT f.scope_id,
       f.tree,
       f.ownership,
       f.business_unit,
       f.family,
       cwe.value AS cwe,
       f.category,
       f.severity,
       f.effective_severity,
       CASE
           WHEN COALESCE(f.validity, 'confirmed') = 'false_positive' THEN 'false_positive'
           WHEN COALESCE(f.validity, 'confirmed') = 'hardening' THEN 'hardening'
           WHEN COALESCE(f.resolution, 'open') IN ('resolved', 'risk_accepted') THEN 'closed'
           ELSE 'open'
       END AS exposure_class,
       COUNT(*) AS occurrences,
       COUNT(DISTINCT f.fingerprint) AS distinct_fingerprints,
       COUNT(DISTINCT f.subject_id) AS subjects
FROM traust_storage.current_finding f
CROSS JOIN LATERAL jsonb_array_elements_text(f.cwes) AS cwe(value)
GROUP BY f.scope_id, f.tree, f.ownership, f.business_unit, f.family,
         cwe.value, f.category, f.severity, f.effective_severity,
         CASE
             WHEN COALESCE(f.validity, 'confirmed') = 'false_positive' THEN 'false_positive'
             WHEN COALESCE(f.validity, 'confirmed') = 'hardening' THEN 'hardening'
             WHEN COALESCE(f.resolution, 'open') IN ('resolved', 'risk_accepted') THEN 'closed'
             ELSE 'open'
         END;

-- ATT&CK coverage: one row per technique per scope, with the STRONGEST
-- evidence the estate has for it.
--
-- Two sources, unioned and then ranked, because they are different claims:
--   modelled    a threat model names the technique (threat.attack_refs)
--   validated   a live-validation chain exercised it
--               (attack_chain.mitre_attack_refs)
--
-- `evidence_tier` orders them so a consumer sorts without restating the
-- rule, and the ordering is the whole point of the view:
--   3  chain CONFIRMED end to end -- reachable, demonstrated
--   2  chain attempted, not confirmed -- tried, did not land
--   1  modelled only -- nobody has attempted it
--
-- Collapsing those to "covered" is the failure this replaces. A technique
-- somebody wrote down and a technique somebody proved are not the same
-- coverage, and a Navigator layer coloured from the union of the two
-- overstates the estate's evidence everywhere it matters most.
--
-- Not filtered to confirmed. not_attempted dominates the validation lane,
-- so a coverage map showing only confirmations would describe a fraction
-- of the work and read as though the rest had been refuted.
CREATE OR REPLACE VIEW traust_storage.attack_coverage AS
SELECT scope_id,
       technique,
       source,
       evidence_tier,
       COUNT(*) AS occurrences,
       COUNT(DISTINCT subject_id) AS subjects
FROM (
    SELECT b.scope_id,
           ref.value AS technique,
           'validated' AS source,
           CASE WHEN c.verdict = 'confirmed' THEN 3 ELSE 2 END AS evidence_tier,
           b.subject_id
    FROM traust_storage.attack_chain c
    JOIN traust_storage.current_binding b
      ON b.binding_id = c.binding_id
    CROSS JOIN LATERAL jsonb_array_elements_text(c.mitre_attack_refs) AS ref(value)
    UNION ALL
    SELECT t.scope_id,
           ref.value AS technique,
           'modelled' AS source,
           1 AS evidence_tier,
           t.subject_id
    FROM traust_storage.threat_current t
    CROSS JOIN LATERAL jsonb_array_elements_text(t.attack_refs) AS ref(value)
) AS coverage
GROUP BY scope_id, technique, source, evidence_tier;

-- Blast radius: which repositories one advisory reaches, and on what
-- evidence.
--
-- An impact analysis is scope-bound, not subject-bound: one advisory
-- assessed across many repositories at once. Fanned out here because the
-- question is always "which repos, how strongly", and that is a row per
-- repo, not a row per advisory.
--
-- EVERY FIELD THE CONTRACT DECLARES IS CARRIED. The first cut exposed 14
-- of 40 and matched the legacy projection exactly on every classification
-- bucket -- because that projection dropped the same fields. Agreement
-- between two impoverished projections proves nothing; the SCHEMA is the
-- reference. tests/test_view_contract_coverage.py now enforces it.
--
-- `evidence_level` is the contract's own tier and the column to rank on:
-- symbol (govulncheck reachability) > binary (ELF) > manifest (lockfile
-- grep). The nineteen evidence flags beside it are how that tier was
-- reached, and they are the whole point of an impact analysis -- dropping
-- them leaves a verdict with no way to audit it.
--
-- Null in an evidence column means NOT ESTABLISHED, never "no". `direct`
-- separates a first-order dependency from a transitive one: the same
-- advisory is a different remediation job depending on which.
CREATE OR REPLACE VIEW traust_storage.advisory_exposure WITH (security_barrier) AS
SELECT b.scope_id,
       ia.metadata->>'cve' AS advisory,
       ia.metadata->>'ecosystem' AS ecosystem,
       ia.metadata->>'module' AS module,
       ia.metadata->>'fixed_version' AS fixed_version,
       ia.metadata->>'vulnerable_range' AS vulnerable_range,
       ia.metadata->>'generated_at' AS generated_at,
       ia.metadata->>'tiers_executed' AS tiers_executed,
       ia.metadata->>'vulnerable_symbols' AS vulnerable_symbols,
       ia.metadata->>'vulnerable_packages' AS vulnerable_packages,
       ia.metadata->>'advisory_sources' AS advisory_sources,
       ia.metadata->>'feature_description' AS feature_description,
       ia.metadata->>'harness_version' AS harness_version,
       ia.metadata->>'options' AS options,
       ia.metadata->>'portfolio_graph_db' AS portfolio_graph_db,
       ia.metadata->>'portfolio_graph_version' AS portfolio_graph_version,
       entry.value->>'repo' AS repo,
       entry.value->>'classification' AS classification,
       entry.value->>'version' AS version,
       entry.value->>'direct' AS direct,
       entry.value->>'products' AS products,
       entry.value->'evidence'->>'binary_linked_library' AS binary_linked_library,
       entry.value->'evidence'->>'binary_string_scan' AS binary_string_scan,
       entry.value->'evidence'->>'binary_symbol_scan' AS binary_symbol_scan,
       entry.value->'evidence'->>'evidence_level' AS evidence_level,
       entry.value->'evidence'->>'feature_pattern_matches' AS feature_pattern_matches,
       entry.value->'evidence'->>'govulncheck' AS govulncheck,
       entry.value->'evidence'->>'govulncheck_trace' AS govulncheck_trace,
       entry.value->'evidence'->>'l1_depends_on' AS l1_depends_on,
       entry.value->'evidence'->>'l1_version_in_range' AS l1_version_in_range,
       entry.value->'evidence'->>'l4_package_imported' AS l4_package_imported,
       entry.value->'evidence'->>'l4_packages_found' AS l4_packages_found,
       entry.value->'evidence'->>'manifest_scan' AS manifest_scan,
       entry.value->'evidence'->>'manifest_version' AS manifest_version,
       entry.value->'evidence'->>'needs_manual_trace' AS needs_manual_trace,
       entry.value->'evidence'->>'notes' AS notes,
       entry.value->'evidence'->>'sbom_scan' AS sbom_scan,
       entry.value->'evidence'->>'sbom_shipped_version' AS sbom_shipped_version,
       entry.value->'evidence'->>'source_import_scan' AS source_import_scan,
       entry.value->'evidence'->>'symbol_usage_scan' AS symbol_usage_scan
FROM traust_storage.impact_analysis ia
JOIN traust_storage.artifact_binding b
  ON b.binding_id = ia.binding_id
CROSS JOIN LATERAL jsonb_array_elements(ia.repos) AS entry(value)
WHERE b.artifact_name = 'impact-analysis'
  AND NOT EXISTS (
      SELECT 1
      FROM traust_storage.artifact_binding rival
      JOIN traust_storage.impact_analysis riv ON riv.binding_id = rival.binding_id
      WHERE rival.artifact_name = 'impact-analysis'
        AND rival.scope_id = b.scope_id
        AND riv.metadata->>'cve' = ia.metadata->>'cve'
        AND (rival.bound_at > b.bound_at
             OR (rival.bound_at = b.bound_at AND rival.binding_id > b.binding_id))
  );

-- Census exposure: every finding classified once, so no consumer
-- re-derives the disposition policy.
--
-- `distinct_exposure` answers one question (Lens 2 over owned HEAD).
-- The census answers several at once -- owned, upstream, external-bu,
-- cloud-config, branch re-audits, open against all -- and each is the same
-- data cut differently. Classifying here means a consumer FILTERS rather
-- than reimplements, which is where the numbers drifted before.
--
-- exposure_class is exhaustive and mutually exclusive:
--   false_positive  not real
--   hardening       real, posture debt, never folded into the headline
--   closed          affirmatively resolved or risk-accepted
--   open            everything else -- partial fixes and regressions included
CREATE OR REPLACE VIEW traust_storage.census_exposure AS
SELECT scope_id,
       tree,
       ownership,
       business_unit,
       is_branch_audit,
       family,
       severity,
       CASE
           WHEN COALESCE(validity, 'confirmed') = 'false_positive' THEN 'false_positive'
           WHEN COALESCE(validity, 'confirmed') = 'hardening' THEN 'hardening'
           WHEN COALESCE(resolution, 'open') IN ('resolved', 'risk_accepted') THEN 'closed'
           ELSE 'open'
       END AS exposure_class,
       COUNT(*) AS occurrences,
       COUNT(DISTINCT fingerprint) AS distinct_fingerprints
FROM traust_storage.current_finding
GROUP BY scope_id, tree, ownership, business_unit, is_branch_audit, family,
         severity,
         CASE
             WHEN COALESCE(validity, 'confirmed') = 'false_positive' THEN 'false_positive'
             WHEN COALESCE(validity, 'confirmed') = 'hardening' THEN 'hardening'
             WHEN COALESCE(resolution, 'open') IN ('resolved', 'risk_accepted') THEN 'closed'
             ELSE 'open'
         END;

-- Census population: the denominator, per tree.
--
-- Counted from subject_ownership rather than from findings, because a
-- subject with no findings is still coverage -- and a denominator that
-- only counts repos that happen to have a finding is the classic way to
-- overstate a percentage.
--
-- `with_report` is how many of those subjects actually produced a current
-- report, which is the coverage numerator.
CREATE OR REPLACE VIEW traust_storage.census_population AS
SELECT owner.scope_id,
       owner.tree,
       owner.ownership,
       owner.business_unit,
       COUNT(*) AS subjects,
       SUM(CASE WHEN owner.is_branch_audit = 1 THEN 1 ELSE 0 END) AS branch_reaudits,
       SUM(CASE WHEN reported.subject_id IS NULL THEN 0 ELSE 1 END) AS with_report
FROM traust_storage.ownership_current owner
LEFT JOIN (
    SELECT DISTINCT scope_id, subject_id FROM traust_storage.current_finding
) reported
  ON reported.scope_id = owner.scope_id
 AND reported.subject_id = owner.subject_id
GROUP BY owner.scope_id, owner.tree, owner.ownership, owner.business_unit;

-- Compliance posture: control verdicts of the CURRENT assessment, with the
-- owner of the subject assessed.
--
-- One row per control per framework, never an aggregate: a posture rollup
-- that reports "72% satisfied" and cannot name the unsatisfied controls is
-- not an assessment, and the control list is what an auditor asks for
-- first. A consumer wanting the percentage groups this; a consumer wanting
-- the gaps filters it.
--
-- verdict_source is carried UNCOLLAPSED. Satisfied-by-check,
-- satisfied-by-agent and satisfied-by-human-override are three different
-- assurance claims, and `assurance_tier` orders them so a consumer can sort
-- without restating the rule:
--   1  check            a deterministic collector said so
--   2  agent            an agent read evidence and judged
--   3  human_override   a person set the check's verdict aside
--
-- Ownership is LEFT JOINed for the reason ownership always is here: an
-- assessment of a subject the registry does not declare is still real, it
-- simply has no denominator.
--
-- Supersession follows current_binding: the newest assessment of a subject
-- wins, which is the rule report_current and threat_current already apply.
CREATE OR REPLACE VIEW traust_storage.compliance_posture AS
SELECT b.scope_id,
       b.subject_id,
       b.run_id,
       r.framework,
       r.control_id,
       r.title,
       r.classification,
       r.verdict,
       r.verdict_source,
       CASE r.verdict_source
           WHEN 'check' THEN 1
           WHEN 'agent' THEN 2
           WHEN 'human_override' THEN 3
       END AS assurance_tier,
       r.check_id,
       r.reason,
       r.narrative,
       r.evidence,
       r.override,
       r.n_pass_agreement,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.product,
       owner.is_branch_audit
FROM traust_storage.compliance_result r
JOIN traust_storage.current_binding b
  ON b.binding_id = r.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = b.subject_id;

-- Distinct exposure (Lens 2): how many actual problems, not how many rows.
--
-- ONE ROW PER FINGERPRINT. Grouping by severity or business_unit as well
-- splits a single problem into several when it surfaces at different
-- severities across repos -- measured +219 against findings.db's
-- v_distinct_owned before this was corrected. severity and business_unit
-- are reported as EXAMPLES, which is what they are once collapsed.
--
-- Two filters carry the whole meaning and are easy to omit by accident:
--   ownership = 'owned'   upstream and external-bu engagements are Lens 1
--                         (work performed) only, never in risk numbers
--   is_branch_audit FALSE  a large share of audits re-audit the same code on
--                         a branch; counting them overstates coverage
CREATE OR REPLACE VIEW traust_storage.distinct_exposure AS
SELECT scope_id,
       fingerprint,
       COUNT(*) AS occurrences,
       MAX(severity) AS severity_example,
       MIN(business_unit) AS business_unit_example,
       MIN(subject_id) AS first_subject
FROM traust_storage.current_finding
WHERE fingerprint IS NOT NULL
  AND ownership = 'owned'
  AND is_branch_audit = 0
  AND COALESCE(resolution, 'open') NOT IN ('resolved', 'risk_accepted')
  AND COALESCE(validity, 'confirmed') NOT IN ('false_positive', 'hardening')
GROUP BY scope_id, fingerprint;

-- Findings opened and closed per month: the direction-of-travel view.
--
-- Counts each finding identity ONCE, in the month it was first observed
-- and (if it closed) the month it closed. A finding restated across twenty
-- re-audits contributes one open, not twenty -- which is the difference
-- between a trend and a measure of how often we re-scanned.
--
-- `net` is opened minus closed for that month. It is NOT the running
-- total: a cumulative figure depends on the window a consumer chose, so it
-- belongs in the query, not baked in here where two callers with different
-- windows would silently disagree.
CREATE OR REPLACE VIEW traust_storage.exposure_trend AS
SELECT scope_id, period, SUM(opened) AS opened, SUM(closed) AS closed,
       SUM(opened) - SUM(closed) AS net
FROM (
    SELECT scope_id, substring(first_seen from 1 for 7) AS period, 1 AS opened, 0 AS closed
    FROM traust_storage.finding_timeline WHERE first_seen IS NOT NULL
    UNION ALL
    SELECT scope_id, substring(resolved_at from 1 for 7) AS period, 0 AS opened, 1 AS closed
    FROM traust_storage.finding_timeline WHERE resolved_at IS NOT NULL
) periods
GROUP BY scope_id, period;

-- SLA state per finding, judged against the DEPLOYMENT'S OWN policy.
--
-- Nothing here is hardcoded. The threshold, the profile and the clock
-- start all come from the sla-policy artifact, so an adopter states their
-- numbers once and every consumer inherits them -- which is the point: a
-- dashboard that reimplements thresholds is a second place for them to be
-- wrong.
--
-- CLOCK START is policy, not opinion. The same finding has three
-- defensible start times and they give different answers:
--   audit_date              when a scanner first reported it
--   first_event             when someone first adjudicated it
--   first_routed_or_filed   when it reached a tracker or review (default),
--                           falling back to first_event, then audit_date
--
-- Still-open findings are INCLUDED. The breaches are precisely the ones
-- that never closed, so a closed-only SLA view inverts the metric it
-- claims to report.
--
-- No policy ingested means NULL threshold and NULL breached -- unknown,
-- never a silent pass. resolve_days NULL is a real policy position
-- ("tracked, never overdue") and also yields NULL breached, never false.
CREATE OR REPLACE VIEW traust_storage.finding_sla AS
SELECT t.scope_id,
       t.fingerprint,
       c.severity,
       c.ownership,
       c.business_unit,
       c.tree,
       clock.policy_name,
       clock.profile_name,
       COALESCE(clock.clock_start, 'audit_date') AS clock_start,
       CASE COALESCE(clock.clock_start, 'audit_date')
            WHEN 'first_event' THEN COALESCE(t.first_adjudicated, t.first_seen)
            WHEN 'first_routed_or_filed'
                 THEN COALESCE(t.first_routed_or_filed, t.first_adjudicated,
                               t.first_seen)
            ELSE t.first_seen
       END AS clock_started_at,
       t.resolved_at,
       CASE WHEN t.resolved_at IS NULL THEN 1 ELSE 0 END AS still_open,
       policy.resolve_days,
       EXTRACT(EPOCH FROM (COALESCE(t.resolved_at, t.last_seen)::timestamptz
           - (CASE COALESCE(clock.clock_start, 'audit_date')
                WHEN 'first_event' THEN COALESCE(t.first_adjudicated, t.first_seen)
                WHEN 'first_routed_or_filed'
                     THEN COALESCE(t.first_routed_or_filed, t.first_adjudicated,
                                   t.first_seen)
                ELSE t.first_seen
           END)::timestamptz)) / 86400 AS age_days,
       CASE WHEN policy.resolve_days IS NULL THEN NULL
            WHEN EXTRACT(EPOCH FROM (COALESCE(t.resolved_at, t.last_seen)::timestamptz
                 - (CASE COALESCE(clock.clock_start, 'audit_date')
                      WHEN 'first_event' THEN COALESCE(t.first_adjudicated, t.first_seen)
                      WHEN 'first_routed_or_filed'
                           THEN COALESCE(t.first_routed_or_filed, t.first_adjudicated,
                                         t.first_seen)
                      ELSE t.first_seen
                 END)::timestamptz)) / 86400 > policy.resolve_days
            THEN 1 ELSE 0
       END AS breached,
       t.days_to_resolve
FROM traust_storage.finding_timeline t
JOIN (
    SELECT scope_id, fingerprint,
           MIN(severity) AS severity,
           MIN(ownership) AS ownership,
           MIN(business_unit) AS business_unit,
           MIN(tree) AS tree
    FROM traust_storage.current_finding
    WHERE fingerprint IS NOT NULL
      AND COALESCE(validity, 'confirmed') NOT IN ('false_positive', 'hardening')
    GROUP BY scope_id, fingerprint
) c ON c.scope_id = t.scope_id AND c.fingerprint = t.fingerprint
LEFT JOIN traust_storage.sla_clock clock
       ON clock.scope_id = t.scope_id
LEFT JOIN traust_storage.sla_threshold policy
       ON policy.scope_id = t.scope_id AND policy.severity = c.severity;

-- Provisional findings summary for the Security Posture dashboard; not the future compliance posture dashboard.
CREATE OR REPLACE VIEW traust_storage.findings_summary WITH (security_barrier) AS
SELECT finding_binding.scope_id,
       finding_binding.subject_id,
       finding_binding.run_id,
       finding_binding.layer_id,
       ownership.repo_url AS repo,
       finding.severity,
       triage.verdict,
       COUNT(DISTINCT finding.finding_id) AS finding_count
FROM traust_storage.current_binding finding_binding
JOIN traust_storage.finding finding
  ON finding.binding_id = finding_binding.binding_id
LEFT JOIN traust_storage.current_binding triage_binding
  ON triage_binding.scope_id = finding_binding.scope_id
 AND triage_binding.subject_id = finding_binding.subject_id
 AND triage_binding.run_id = finding_binding.run_id
 AND triage_binding.artifact_name = 'triage'
LEFT JOIN traust_storage.triage_verdict triage
  ON triage.binding_id = triage_binding.binding_id
 AND triage.source_finding_id = finding.finding_id
LEFT JOIN traust_storage.ownership_current ownership
  ON ownership.scope_id = finding_binding.scope_id
 AND ownership.subject_id = finding_binding.subject_id
WHERE finding_binding.artifact_name = 'vuln-findings'
  AND finding_binding.scope_id IN (
      SELECT jsonb_array_elements_text(
          COALESCE(current_setting('traust.scope_ids', true), '[]')::jsonb
      )
  )
GROUP BY finding_binding.scope_id,
         finding_binding.subject_id,
         finding_binding.run_id,
         finding_binding.layer_id,
         ownership.repo_url,
         finding.severity,
         triage.verdict;

-- Posture debt: accurately-described defence-in-depth gaps with no
-- concrete exploit path. Real and risk-bearing, never a false positive,
-- and kept out of open exposure so the two are never blended.
CREATE OR REPLACE VIEW traust_storage.hardening_findings AS
SELECT scope_id, subject_id, run_id, finding_id, title, severity,
       fingerprint, validity, resolution, assurance, family,
       ownership, business_unit, tree, is_branch_audit
FROM traust_storage.current_finding
WHERE validity = 'hardening';

-- Open exposure: the census convention, expressed on the contract.
--
-- "Open" is anything not AFFIRMATIVELY closed, so partial fixes and
-- regressions still count as shipped exposure. False positives are not
-- real and hardening is posture debt tracked separately, so both come out.
--
-- The value lists are GENERATED from the contract enums, never typed: the
-- harness projection once excluded 'in_progress' where the enum says
-- 'fix_in_progress', and every in-progress finding silently vanished. A
-- test asserts these lists still match the enums.
CREATE OR REPLACE VIEW traust_storage.open_findings AS
SELECT scope_id, subject_id, run_id, finding_id, title, severity,
       fingerprint, validity, resolution, assurance, family,
       ownership, business_unit, tree, is_branch_audit
FROM traust_storage.current_finding
WHERE COALESCE(resolution, 'open') NOT IN ('resolved', 'risk_accepted')
  AND COALESCE(validity, 'confirmed') NOT IN ('false_positive', 'hardening');

-- Operator privilege asks, with ownership, one row per current profile.
--
-- DECLARED state throughout: parsed from shipped manifests, never a live
-- cluster read. Every number here answers "what would this grant if
-- installed", and a consumer that reads it as a runtime grant is wrong.
--
-- The counts are EXTRACTED from the summary blob rather than stored twice.
-- The projection holds one column per root property of the artifact, which
-- is the invariant every one-row projection here keeps; lifting derived
-- numbers into their own columns would put two copies of each in the
-- database, and two copies of one number is how they drift.
--
-- The high-privilege flags become booleans because that is what a
-- least-privilege dashboard filters on. A key is present in rbac_flags
-- ONLY when it matched, so presence IS the signal and an absent key means
-- no match rather than unknown -- hence 0, never NULL, or a filter silently
-- drops the row.
CREATE OR REPLACE VIEW traust_storage.operator_privilege AS
SELECT b.scope_id,
       b.subject_id,
       b.run_id,
       p.repo,
       p.tier,
       (p.summary->>'workloads')::int AS workload_count,
       (p.summary->>'privileged_or_host_workloads')::int
           AS privileged_or_host_workloads,
       (p.summary->>'rbac_rules')::int AS rbac_rule_count,
       (p.summary->>'distinct_rule_triples')::int AS distinct_rule_triples,
       (p.summary->>'distinct_cluster_triples')::int AS distinct_cluster_triples,
       (p.summary->>'cluster_scoped_rules')::int AS cluster_scoped_rules,
       (p.summary->>'wildcard_rules')::int AS wildcard_rules,
       (p.summary->>'no_scc_request_recorded')::boolean::int AS no_scc_request_recorded,
       CASE WHEN NOT jsonb_exists(p.rbac_flags, 'secrets_access') THEN 0 ELSE 1 END
           AS flag_secrets_access,
       CASE WHEN NOT jsonb_exists(p.rbac_flags, 'nodes_access') THEN 0 ELSE 1 END
           AS flag_nodes_access,
       CASE WHEN NOT jsonb_exists(p.rbac_flags, 'wildcard_verbs') THEN 0 ELSE 1 END
           AS flag_wildcard_verbs,
       CASE WHEN NOT jsonb_exists(p.rbac_flags, 'wildcard_resources') THEN 0 ELSE 1 END
           AS flag_wildcard_resources,
       CASE WHEN NOT jsonb_exists(p.rbac_flags, 'rbac_write') THEN 0 ELSE 1 END
           AS flag_rbac_write,
       CASE WHEN NOT jsonb_exists(p.rbac_flags, 'pods_exec') THEN 0 ELSE 1 END
           AS flag_pods_exec,
       -- The three verbs that let a principal grant itself more than it
       -- holds. Highest-signal flag here.
       CASE WHEN NOT jsonb_exists(p.rbac_flags, 'escalate_bind_impersonate')
            THEN 0 ELSE 1 END AS flag_escalate_bind_impersonate,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.is_branch_audit
FROM traust_storage.priv_profile p
JOIN traust_storage.current_binding b
  ON b.binding_id = p.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = b.subject_id;

-- PQC readiness aggregated: the shape a portfolio dashboard renders.
--
-- Counts SUBJECTS, not assessments. A repo re-assessed five times is one
-- repo in a readiness bucket, and counting assessments would inflate the
-- portfolio by however often it was re-scanned.
CREATE OR REPLACE VIEW traust_storage.pqc_readiness_rollup AS
SELECT scope_id,
       tree,
       ownership,
       business_unit,
       readiness_bucket,
       COUNT(DISTINCT subject_id) AS subjects,
       SUM(CASE WHEN has_2030_clock = 1 THEN 1 ELSE 0 END) AS with_2030_clock,
       SUM(CASE WHEN hndl_priority = 1 THEN 1 ELSE 0 END) AS hndl_priority,
       SUM(clock_items) AS clock_items
FROM traust_storage.pqc_posture
GROUP BY scope_id, tree, ownership, business_unit, readiness_bucket;

-- What each remediation set out to fix: one row per source finding of the
-- CURRENT remediation, with the owner.
--
-- The join that was missing. A remediation names the findings that
-- justified it, but they lived in a JSON column, so "which open findings
-- already have a fix in flight" had no answer in SQL and a reviewer had to
-- read the artifact.
--
-- `validation_verdict` is the state AT REMEDIATION TIME. It says why the
-- work was started; the finding's CURRENT disposition is on
-- current_finding, and reading this one as current is the mistake the
-- column name is trying to prevent.
CREATE OR REPLACE VIEW traust_storage.remediation_current AS
SELECT b.scope_id,
       b.subject_id,
       b.run_id,
       s.finding_ref,
       s.title,
       s.severity,
       s.cwes,
       s.locations,
       s.triage_confidence,
       s.validation_verdict,
       s.audit_report_path,
       s.triage_report_path,
       s.validation_report_path,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.product,
       owner.is_branch_audit
FROM traust_storage.remediation_source s
JOIN traust_storage.current_binding b
  ON b.binding_id = s.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = b.subject_id;

-- Threat exposure: every modelled threat classified once, aggregated.
--
-- The census equivalent for the threat lens. `status` is carried through
-- UNCOLLAPSED -- partially_mitigated is the largest bucket in practice
-- (the largest bucket by far), so folding it into mitigated is the single
-- biggest way to overstate threat coverage.
--
-- `severity` is the OWASP Risk Rating Methodology severity, NULL for threats
-- whose model has not been re-rated; those still group by their legacy
-- impact and likelihood labels, which are NULL on a rated threat. The two
-- never blend: a row is either rated or legacy.
--
-- `evidenced` separates a threat backed by a finding or validation from one
-- that is only modelled. "Unmitigated" and "unevidenced" are different
-- claims and a rollup that blends them cannot be acted on.
CREATE OR REPLACE VIEW traust_storage.threat_exposure AS
SELECT scope_id,
       tree,
       ownership,
       business_unit,
       product,
       impact,
       likelihood,
       status,
       CASE WHEN evidence IS NULL OR jsonb_array_length(evidence) = 0 THEN 0 ELSE 1 END AS evidenced,
       linddun,
       COUNT(*) AS threats,
       COUNT(DISTINCT subject_id) AS subjects,
       MAX(score) AS top_score,
       severity
FROM traust_storage.threat_current
GROUP BY scope_id, tree, ownership, business_unit, product, severity, impact,
         likelihood, status,
         CASE WHEN evidence IS NULL OR jsonb_array_length(evidence) = 0 THEN 0 ELSE 1 END,
         linddun;

-- Validation exposure: every claimed finding classified once by what
-- actually happened when it was attempted against a running system.
--
-- The census equivalent for the evidence lens. A finding CONFIRMED by
-- execution and a finding believed by inspection are different claims,
-- and this is the view that can tell them apart.
--
-- `verdict` stays uncollapsed and `attempted` is derived rather than
-- filtered, so a consumer can report "of what we tried, N% held up"
-- without restating the lane's own definition of an attempt. Folding
-- not_attempted into refuted would read as though the estate had
-- disproved the bulk of its findings; folding it away entirely would
-- hide most of the lane's work.
CREATE OR REPLACE VIEW traust_storage.validation_exposure WITH (security_barrier) AS
SELECT scope_id,
       target_environment,
       tree,
       ownership,
       business_unit,
       product,
       claimed_severity,
       verdict,
       CASE WHEN verdict IN ('confirmed', 'refuted', 'inconclusive')
            THEN 1 ELSE 0 END AS attempted,
       skip_reason,
       COUNT(*) AS findings,
       COUNT(DISTINCT subject_id) AS subjects,
       COUNT(DISTINCT source_finding_id) AS distinct_claims
FROM traust_storage.validation_current
GROUP BY scope_id, target_environment, tree, ownership, business_unit, product,
         claimed_severity, verdict,
         CASE WHEN verdict IN ('confirmed', 'refuted', 'inconclusive')
              THEN 1 ELSE 0 END,
         skip_reason;

-- Did the fix hold: one row per re-audited finding of the CURRENT
-- verification, with the owner of the subject.
--
-- `verdict` keeps all SEVEN contract values. Folding to fixed/not-fixed
-- reports partially_resolved and new_approach as one of the two things they
-- are not, and false_positive and risk_accepted as failures when neither is
-- a fix that failed.
--
-- `held` is the derived binary beside it, and it is deliberately narrow:
-- ONLY `resolved`. A false_positive means the original finding was not real,
-- so nothing held; risk_accepted means nobody fixed it. Both are reasonable
-- outcomes and neither is evidence that a fix worked, which is the single
-- question `held` answers.
--
-- `unattributed` rides along because it is evidence about the evidence: a
-- fix nobody could tie to a commit. Without it an unexplained pass reads
-- exactly like a demonstrated one.
--
-- Regressions are NOT here. They are new findings the fix introduced and
-- live in verification_regression; counting them as verified findings would
-- make "how many findings did this verification touch" ambiguous.
CREATE OR REPLACE VIEW traust_storage.verification_current AS
SELECT b.scope_id,
       b.subject_id,
       b.run_id,
       f.original_id,
       f.original_title,
       f.original_severity,
       f.verdict,
       CASE WHEN f.verdict = 'resolved' THEN 1 ELSE 0 END AS held,
       f.unattributed,
       f.remediation_commits,
       f.evidence_explanation,
       f.evidence_framework_reference,
       f.evidence_original_code,
       f.evidence_patched_code,
       f.disposition_rationale,
       f.residual_risk,
       f.residual_severity,
       f.cross_repo,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.product,
       owner.is_branch_audit
FROM traust_storage.verification_finding f
JOIN traust_storage.current_binding b
  ON b.binding_id = f.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = b.subject_id;

-- What the fix BROKE: one row per regression of the current verification.
--
-- Separate from verification_current because a regression is a new finding,
-- not a restatement of the one the fix closed. This is the half a
-- remediation review must not miss, and it was unreachable from SQL: the
-- regressions lived inside the verification blob.
--
-- `introduced_by` names the commit, and `routed_id` the finding it was
-- filed as when it was routed onward -- the join back into the ordinary
-- findings flow.
CREATE OR REPLACE VIEW traust_storage.verification_regression_current AS
SELECT b.scope_id,
       b.subject_id,
       b.run_id,
       r.regression_id,
       r.title,
       r.severity,
       r.cwes,
       r.cvss,
       r.locations,
       r.description,
       r.remediation,
       r.evidence,
       r.attack_pattern,
       r.category,
       r.introduced_by,
       r.routed_id,
       r.fingerprint,
       r.fingerprint_algo,
       owner.ownership,
       owner.business_unit,
       owner.tree,
       owner.product,
       owner.is_branch_audit
FROM traust_storage.verification_regression r
JOIN traust_storage.current_binding b
  ON b.binding_id = r.binding_id
LEFT JOIN traust_storage.ownership_current owner
  ON owner.subject_id = b.subject_id;
