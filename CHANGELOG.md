# Changelog

All notable changes to traust-contracts are documented here.

## [1.2.2] - 2026-09-08

### Added

README License section and `license = "Apache-2.0"` in package metadata,
matching `LICENSE`.

## [1.2.1] - 2026-09-08

### Changed

`CODEOWNERS` names the `@openshift/traust-maintainers` team instead of
individual accounts.

## [1.2.0] - 2026-09-6

### Added

Schemas and config loader for app layer config management. This allows for
all paths and configuration related items to be loaded and managed at
the app level instead of it being sprinkled and resolved differently everywhere.

## [1.0.1] — 2026-09-03

### Fixed
- **`ci/setup-uv.sh` no longer hardcodes the forge hostname.** The
  `insteadOf` rewrite that maps `uv.lock`'s `ssh://` sibling-dep URLs to
  authenticated HTTPS now takes the host from `$CI_SERVER_HOST`, which
  GitLab sets on every job, instead of a literal. An internal hostname
  compiled into a tracked file is a disclosure, and the value is
  deployment identity the environment already carries.
  The script is CI-only (it already requires `$CI_JOB_TOKEN` and a
  runner CA), so it now fails closed when `$CI_SERVER_HOST` is unset
  rather than installing a rewrite that matches nothing and failing later
  on an opaque auth error. Assumes the sibling deps live on the same
  GitLab as the pipeline — noted in the script, because a dep on another
  forge would need its own rewrite.

## [0.7.1] — 2026-09-02

**Open-source readiness clean-up.**

### Changed
- Schema `$id` placeholders updated to `traust-contracts`.
- Genericized internal references, corpus metrics, and product-specific
  examples across all schema descriptions and test docstrings.
- Renamed remediation verification methods: `validate-operator-live` →
  `validate-live`, `validate-core-ocp` → `validate-platform`.
- Added `SECURITY.md`.

### Notes
- Two enum values renamed (`validate-operator-live`, `validate-core-ocp`) —
  breaking under the compat gate; use `CONTRACTS_ALLOW_BREAKING=1` to skip.
- No schema shape changes. All existing data validates unchanged.

## [0.7.0] — 2026-08-25

### Added
- `review_item.queue_reason` gains **`needs_identity`** — a submitted finding
  carrying no `fingerprint`. The receiver cannot say *which* finding the
  statement is about, so the submission is accepted and the statement queues
  instead of being recorded.

### Notes
- Resolves a design decision (unstamped-report behaviour):
  accept and quarantine, not reject, and explicitly not "compute one at the
  receiver". Identity is computed by the producer, which holds the repository
  URL, the location paths and the CWE at audit time. A receiver hashing what
  the envelope happens to carry gives a confident wrong answer rather than no
  answer: with `metadata.repository` absent, `canon_repo(None)` is `""`, and two
  findings in unrelated repositories sharing a path and CWE hash to the same
  value — measured, both to `45cb7c4c…`. Downstream that reads as one finding
  and merges two disposition histories.
- Additive enum value; existing layers stay valid.

## [0.6.1] — 2026-08-24

**Identity descriptions corrected** — both pointed at things that no longer exist.

### Fixed
- `report.schema.json` `finding.fingerprint` said "Script-computed
  (a now-removed script)". That path has not existed since a design decision
  retired the cross-language oracle; the recipe lives in
  the identity fingerprint is stamped via
  the finding-identity utility, and is recomputed-and-compared at
  validation. Now says so, and records the two rules a consumer needs: only the
  harness computes identity, and a fingerprint is never the sole key of a
  disposition record.
- `layer.schema.json` event `fingerprint_algo` said "'v1' today". It has been
  `v2` since 2026-08-18 (empty-canonicalizing paths were dropped from the hashed
  set), and both versions coexist in the corpus. The
  description now explains why both coexist rather than implying one current
  value: a stamp is a historical observation, so matching across an epoch
  boundary means comparing this field too.

### Notes
- Descriptions only — no shape, pattern or requiredness change, so no consumer
  needs to move. Patch-released so pinned consumers can pick the corrections up.

## [0.5.4] — 2026-08-20

**CVE provenance** — record which external identifier a finding became.

### Added
- `layer_metadata.external_refs` — map of finding id -> external identifiers
  (`cve` | `bugzilla` | `ghsa` | `jira`) with optional `url`, `confidence`
  (`confirmed` | `probable`), `matched_on` and `stamped_at`. Written by the
  CVE-provenance reconciler so "our finding X became CVE-Y" is answerable
  from the ledger rather than from a person's memory — the gap that made a
  team member's CVE filing invisible to first-discovery metrics.
- `ExternalRef` model, exported from `traust_contracts.models`.

### Notes
- Deliberately **metadata, not an event**. The data is derived and
  recomputable, `disposition` carries `minProperties: 1` so a state-free
  event is not expressible, and a reconciler re-run must not perturb the
  Merkle-signed event chain. It sits beside `claim_hashes` and
  `finding_aliases`, which are the existing finding-keyed annotation maps.
- Asserts nothing about validity, resolution or severity.

## [0.5.3] — 2026-08-19

**LayerEvent disposition fields** — round-trip fix for auto-accept metadata.

### Added
- `LayerEvent.auto_accept_tier` — whether the event came from the machine
  auto-accept tier (schema already allowed; model now preserves on round-trip).
- `LayerEvent.evidence_grade` — E0–E3 evidence grade stamped on disposition events
  (same round-trip fix).

### Notes
- Additive and optional: no Merkle or signature payload changes.

## [0.5.2] — 2026-08-19

**OIDC-era actor identity stamps** — ledger authentication path for human events.

### Added
- `actor.identity_verified` — true when an authentication mechanism confirmed this
  identity (OIDC, LDAP bind, keypair, etc.).
- `actor.identity_provider` — which IdP type authenticated the actor: `oidc`, `ldap`,
  `bearer`, `keypair`, `mtls`, etc.
- `actor.identity_issuer` — credential issuer (OIDC issuer URL, LDAP server URI, key
  fingerprint, etc.).
- `actor.identity_subject` — raw IdP subject before canonicalization (OIDC `sub` UUID,
  LDAP `uid`, etc.) for audit reversibility.
- `actor.employee_status` — directory enrichment result: `active`, `terminated`,
  `contingent`, or `not_found`.
- All five on the `LayerActor` model as well as the schema — `ContractModel` is
  `extra="ignore"`, so a schema-only addition would be silently dropped on round-trip.

### Changed
- `actor.identity` description — canonical email for humans (was Kerberos ID or
  corporate email).
- `actor.ldap_verified` description — marked legacy; superseded by
  `identity_verified` + `employee_status`, retained for backward compatibility with
  existing events.

### Notes
- Additive and optional: all existing layers stay valid; no Merkle or signature
  payload changes.

## [0.5.1] — 2026-08-18

**Content-addressed report reference** — reports move to object storage, the ledger
stays in git.

### Added
- `layer_metadata.audit_report_sha256` — sha256 of the annotated baseline's exact
  bytes. Makes the layer's link to its report **content**-addressed instead of
  path-addressed, which is the prerequisite for the report living anywhere but beside
  the layer. Complements `claim_hashes`: the digest answers "are these the bytes I
  annotated?", the claim hashes answer "did any finding's claim change?".
- `layer_metadata.audit_report_ref` — opaque object key/URI, absent while reports sit
  beside the layer. Opaque on purpose: consumers resolve it through the `report_store`
  accessor, never by string-munging a path, so one layer works against a local
  checkout, a bucket, or a future ledger database unedited.
- Both on the `LayerMetadata` model as well as the schema — `ContractModel` is
  `extra="ignore"`, so a schema-only addition would have been silently dropped on
  round-trip (the `event.fingerprint` lesson from 0.4.3).

### Notes
- Additive and optional: all existing layers stay valid, and the backfill is a
  pure metadata write — **neither field is inside `merkle_signature_payload`**, so no
  Merkle root moves and nothing needs re-signing.
- That last point is also a limitation worth stating: because the digest is unsigned,
  it is not yet tamper-evidence. Binding it into the signed payload is a **format-3**
  change requiring all layers to be re-signed, and is called out as
  a deliberate decision rather than assumed here.

## [0.5.0] — 2026-08-18

**BREAKING: the finding-identity vector suite is retired** (a design
decision).

### Removed
- `vectors/v1/finding-identity-golden-vectors.json` and the whole `vectors/`
  tree — it held only that file.
- `paths.vectors_dir()`. Keeping a resolver for a directory that no longer exists
  would be an API that lies; callers of the retired suite must move to
  the ledger package's in-repo fixtures.
- The vector-hash gate in `tests/test_compat.py` (`EXPECTED_VECTOR_SUITE_DIGEST`)
  and the vector tests in `tests/test_contracts.py`.
- `validate.py`'s `validate_vectors()` check, and the `vectors/v1` packaging
  entries.

### Why
The suite's stated purpose was cross-language conformance: *"any port (e.g.
the Go SDK) must reproduce every expected_fingerprint byte-for-byte."* That design decision settles
that **only the harness computes identity** — consumers read the stamp, and no
non-harness producer computes one either — so there is no port left for a shared
oracle to hold.

### What did not go away
Regression coverage of the recipe. All 12 cases were ported to
the ledger package's `tests/fixtures/identity-recipe-vectors.json` **before** this
removal (ledger 0.4.0), with every expected value recomputed under
`algo_version` v2 and each case retaining its v1 value so a future recipe move
cannot be silently re-baselined. They now sit beside the implementation they
guard rather than in a package it depends on.

### Migration
Consumers pinning `>=0.4,<0.5` are unaffected until they move. Anything importing
`vectors_dir` must stop; the fixtures are the ledger package's and are not published as a
contract.

## [0.4.5] — 2026-08-18

**Location paths: the rule that keeps identity from collapsing.**

### Added
- `enums/v1/repo-scope-path.json` — controlled pseudo-paths (`repo:maintenance`,
  `repo:scorecard-onboarding`, …) for findings about the repository itself rather
  than any artifact in it. The ledger fingerprint is
  `repo | sorted paths | primary CWE`, so a location of `.` or `/` yields an empty
  path set and collapses identity to `(repo, '', cwe)` — e.g. "no SECURITY.md" and "not
  onboarded to OpenSSF Scorecard" in one repo were one identity. Most such
  findings do have an artifact (an absent `SECURITY.md` is still `SECURITY.md`,
  and a missing file's path is both stable and actionable); these values exist
  for the residue that genuinely has none.

### Changed
- `report.schema.json` `location.path` now documents the rule: a real
  repository-relative artifact path, never a repo-root marker, never prose.

**Enforcement is deliberately staged**, following this project's own
precedent of backfill-then-flip: the pattern sits in a `$comment` rather than
being applied, because applying it today invalidates all existing reports.
It becomes an error after the migration, in step with identity strict mode.

## [0.4.4] — 2026-08-17

**Event-carried alias and finding blocks become schema-legal.**

### Added
- `event.alias` (`$defs/event_alias`) in `layer.schema.json` — rebaseline
  mapping carried on the event. Projected by `events.aliases_from_events()`
  and merged over the legacy `metadata.finding_aliases` table by `build_cumulative`.
- `event.finding` (`$defs/event_finding`) in `layer.schema.json` — a finding
  discovered between audits, carried on the event because only baseline-writing skills
  may emit report findings. `build_cumulative` unions these with the
  baseline's findings.

### Why
A prior release shipped alias support in the ledger but never declared `alias` on `$defs/event`
(`additionalProperties: false`), so every alias event failed validation. Engine support
without schema support produces code that reads what validation rejects.

### Compatibility
Non-breaking: both blocks are optional on events. Consumers on 0.4.3 ignore them;
consumers needing event-carried claims should require `>=0.4.4`.

## [0.4.3] — 2026-08-17

**The ledger's own identity stamps become legal.**

### Added
- `event.fingerprint` and `event.fingerprint_algo` in `layer.schema.json` —
  both optional, both already written in practice. `$defs.event` is
  `additionalProperties: false`, and the sanctioned write path
  (`events.attach_identity`) stamps these onto every event it
  writes, so **every stamped layer file failed validation** — 49 files / 198
  events in the test corpus when this was caught on 2026-08-17. The
  fields were undeclared in 0.3.0 through 0.4.2 alike; this is not a
  regression from the 0.4.x line.
- Both fields on the `LayerEvent` Pydantic model. `ContractModel` is
  `extra="ignore"`, so a `from_dict`/`to_dict` round-trip was silently
  dropping the identity stamp.
- `test_stamped_event_validates` pins the schema half so the class cannot
  recur.

### Known gap (not fixed here)
`LayerEvent` still omits `evidence_refs`, `risk_weight`, `auto_accept_tier`
and `evidence_grade`, all of which the schema allows and `extra="ignore"`
silently discards on round-trip. Same defect class, wider blast radius —
worth its own change.

## [0.4.2] — 2026-08-17

**Dependency findings become self-describing.**

### Added
- `finding.dependency` (optional) in `report.schema.json` — supply-chain
  provenance carried ON the finding: `advisory`, `module` (both required when
  the block is present), plus optional `ecosystem`, `purl`,
  `vulnerable_range`, `fixed_version`, `installed_version`, `evidence_level`,
  `classification`, `impact_artifact`.
- `DependencyProvenance` model, exported from `traust_contracts.models`
  and `…v1.models`.

### Why
Routed dependency findings previously carried their advisory and module only
in **prose** (`description`) and positionally in `source_findings`, e.g.
`['CVE-2024-1597', 'impact/cve-2024-1597-impact-analysis.json']`.
Measured across 2,019 routed findings: 100% carried an advisory id and an
artifact reference, and 100% of those references resolved — but **0 had a
machine-queryable advisory or module**. Two consequences:

- **Object storage.** Findings are moving to S3-type storage, where a
  relative path to a sibling artifact is not guaranteed to resolve. The
  finding must stand alone; `impact_artifact` is therefore a provenance
  pointer, explicitly NOT the source of truth.
- **Consumer consistency.** Consumers that build their own database (e.g. a
  downstream PostgreSQL consumer) read the artifacts, not the harness's local SQLite projection.
  Adding derived columns to that projection would have given one consumer
  queries and every other consumer nothing. The join key belongs in the
  contract.

The Pydantic models are hand-written with `extra="ignore"`, so a schema-only
change would have been **silently dropped** by any model-based reader — the
model is updated in the same release for that reason.

### Compatibility
Non-breaking by the repo's own gate: an optional property, no removals, no
enum shrinkage, no new required fields on `finding`. `required: [advisory,
module]` applies only inside the block when present. Consumers on 0.4.0
ignore the field; consumers needing it should require `>=0.4.1`.


## [0.4.1] — 2026-08-14

**Layer disposition enum vocabulary and Python bindings for downstream consumers.**

### Added

- `enums/v1/source-type.json` — event source type (`mr_comment`, `commit`, `jira`,
  `interactive`, `validation_report`, `verification_report`, `triage_report`,
  `impact_report`) for evidence-origin classification in disposition events.
- `enums/v1/actor-kind.json` — actor type (`human`, `machine`) for disposition
  events; drives LDAP verification requirements and auto-accept eligibility.
- `enums/v1/event-validity.json` — 4-value event validity set (`confirmed`,
  `false_positive`, `corrected`, `hardening`); distinct from the 5-value
  `validity` enum which includes `not_verified` as the audit-stage default.
- `SourceType`, `ActorKind`, and `EventValidity` StrEnum classes in
  `src/traust_contracts/v1/enums.py`.

### Notes

- Additive and backward-compatible: new vocabulary files and bindings only; no
  property removed, no enum shrunk, no new required field.

## [0.4.0] — 2026-08-14

**Embargo handling axis on the disposition ledger.**

### Added

- `disposition.embargo` on `schemas/v1/layer.schema.json` — optional enum
  (`required` / `active` / `not_required` / `uncertain`) recording whether a
  finding must be handled under Product Security embargo criteria. Orthogonal to
  the validity and resolution axes; an embargo assertion alone never changes
  finding state. Human-only, on the same LDAP-verified footing as
  `disposition.severity`. Idempotency follows the severity precedent: the status
  is encoded in `source.ref` (`interactive:<date>:embargo:<status>`), leaving the
  canonical `event_id` formula unchanged.
- `enums/v1/disposition-embargo.json` vocabulary file.
- `DispositionEmbargo` enum and `LayerDisposition.embargo` in the Pydantic
  bindings, re-exported through the `enums` shim and the package root.

### Notes

- Additive and backward-compatible: no property removed, no enum shrunk, no new
  required field. Existing layers validate unchanged.
- Motivation: embargo existed only at the consumer's issue-filing layer and
  in no schema, so embargo-worthy findings could not be recorded or queried
  as ledger state.

## [0.3.0] — 2026-08-13

**Versioned data-contract layout (`v1/`) — Go SDK extracted to `traust-sdk`.**

### Added

- `release.py` + root `Makefile` — tag/bump/test/push workflow
- README "Versioning" section split into the two independent axes (data-contract version vs. package release version) plus a downstream-usage guide for Python, raw-schema, and ledger/fingerprint consumers

### Removed

- `bindings/go/` — moved to [`traust-sdk`](https://github.com/openshift/traust-sdk) as a standalone Go module (`github.com/openshift/traust-sdk/go`)

### Changed

- **Structural, non-breaking**: `schemas/`, `enums/`, and `vectors/` moved to `schemas/v1/`, `enums/v1/`, `vectors/v1/`; all `$id` values gained a `/v1/` segment
- `bindings/go/` extracted to `traust-sdk/go/` (see Removed above)
- `src/traust_contracts/{models,enums.py}` moved to `src/traust_contracts/v1/{models,enums.py}`; new top-level `models.py`/`enums.py` re-export shims alias the current major so all existing `from traust_contracts.models import ...` / `from traust_contracts.enums import ...` call sites are unaffected
- `traust_contracts.paths` (`schema_dir`, `enum_dir`, `vectors_dir`, `schema_path`, `enum_path`) gained an optional `version: str = "v1"` parameter; all existing calls resolve unchanged
- `pyproject.toml` wheel `force-include` and `validate.py`'s `SCHEMA_DIR`/`VECTORS_DIR` repointed at the `v1/` paths

### Notes

- Go bindings extracted to `traust-sdk`; zero external consumers existed in this repo prior to the move — no migration burden.
- Python has ~41 call sites across the engine and the ledger, all going through the `models`/`enums`/`paths` shim seam kept compatible above — see each consumer's own changelog for their pin bump to `>=0.3,<0.4`.
- One Python call site used a submodule-level import (`traust_contracts.models.finding`) that the flat shim can't satisfy; fixed as part of that consumer's pin bump, not here.
- Future `v2` schemas/types only duplicate what actually changed; unchanged pieces `$ref`/import back into `v1/`.

## [0.2.0] — 2026-08-11

**Schema versioning, compatibility gates, and Pydantic Python bindings.**

### Added

- `$id` field on all schemas (format: `https://example.com/traust-contracts/schemas/<filename>`; `example.com` is a documented placeholder for the final domain at open-source time)
- Vector-hash compatibility gate (`tests/test_compat.py`): pins golden vector suite digest to enforce recipe stability
- Breaking-change compatibility gate: detects property removal, enum shrinkage, and new required fields against prior git tag
- Comprehensive versioning policy in README.md, including compatibility gate escape hatches
- `adapter-result.schema.json` — normalized adapter output contract
- Pydantic v2 models under `src/traust_contracts/` with `paths.py` for schema/enum resolution from the installed wheel
- Split queue-reason enums: `triage-queue-reason.json`, `layer-review-queue-reason.json`; added `verdict`, `validation-verdict`, `compliance-verdict`, `impact-classification`
- `tests/test_models.py` — schema round-trip fixtures for core models

### Changed

- validate.py registry builder now registers schemas by both `$id` and filename for compatibility
- Enum count: 28 schemas, expanded enum vocabulary files (replaces monolithic `queue-reason.json`)

### Notes

- The `example.com` placeholder in all `$id` values will be swapped to the final domain at open-sourcing time (project rename pending). This is a recorded, mechanical follow-up.
- Compatibility gates are enforced in CI; use `CONTRACTS_ALLOW_BREAKING=1 pytest tests/` to skip during major-version bumps.

## [0.1.0] — 2026-08-10

**Initial release.** Extracted contract surface from the security harness.

### Added

- 27 JSON Schema Draft 2020-12 schemas (report, vuln-findings, cloud-config-audit, compliance-assessment, remediation, validation, triage, layer, isolation-review, pqc-readiness, and others)
- finding-identity-golden-vectors.json (cross-language algorithm oracle for finding fingerprint identity)
- Shared enum vocabularies (severity, validity, disposition-resolution, disposition-assurance, ref-kind, queue-reason)
- validate.py CLI validator for structural conformance
- pytest suite for schema and vector integrity

### Rationale

Extracted to enable independent schema versioning, reduce coupling between the harness and its downstream consumers, and serve as the single source of truth for the ledger ecosystem's data contracts.
