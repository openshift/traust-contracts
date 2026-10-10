"""Shared test fixtures."""

import json
import warnings
from typing import Never

import pytest
from storage_samples import encode, sample

from traust_contracts.v1.storage import Binding, Store

POSTGRES_DSN = "postgresql://traust:traust-test-only@127.0.0.1:5432/traust_test"
POSTGRES_SETUP = (
    "Run:\n  podman run --name traust-postgres --rm -d "
    "-e POSTGRES_USER=traust -e POSTGRES_PASSWORD=traust-test-only "
    "-e POSTGRES_DB=traust_test -p 127.0.0.1:5432:5432 "
    "-v traust-postgres-data:/var/lib/postgresql/data docker.io/library/postgres:16"
)


def skip_postgres(reason: str) -> Never:
    warnings.warn(
        f"PostgreSQL E2E skipped: {reason}. {POSTGRES_SETUP}",
        pytest.PytestWarning,
        stacklevel=2,
    )
    pytest.skip(reason)


@pytest.fixture(scope="session")
def postgres_dsn() -> str:
    try:
        import psycopg
    except ImportError:
        skip_postgres("psycopg is not installed")
    try:
        with psycopg.connect(POSTGRES_DSN, connect_timeout=2):
            pass
    except psycopg.OperationalError:
        skip_postgres("local database is unavailable")
    return POSTGRES_DSN


FINDINGS_SUMMARY_SCOPE = "local"
FINDINGS_SUMMARY_SUBJECT = "sci:inventory-item:42"
FINDINGS_SUMMARY_RUN = "sci:scan-result:7"
FINDINGS_SUMMARY_LAYER = "ledger:layer:1"

# Full rows, not a column slice: an earlier pair of tests compared only the
# repo/severity/verdict/count tail, so a divergence in the binding columns
# would have passed both.
FINDINGS_SUMMARY_ROWS = [
    (
        FINDINGS_SUMMARY_SCOPE,
        FINDINGS_SUMMARY_SUBJECT,
        FINDINGS_SUMMARY_RUN,
        FINDINGS_SUMMARY_LAYER,
        "https://example.test/repo",
        "high",
        "true_positive",
        1,
    ),
    (
        FINDINGS_SUMMARY_SCOPE,
        FINDINGS_SUMMARY_SUBJECT,
        FINDINGS_SUMMARY_RUN,
        FINDINGS_SUMMARY_LAYER,
        "https://example.test/repo",
        "low",
        None,
        1,
    ),
]


def seed_findings_summary(store: Store) -> None:
    """Ingest the one fixture both dialects' findings_summary tests assert on.

    Shared so a divergence between the SQLite and PostgreSQL views cannot hide
    behind two independently-authored setups.
    """
    finding_payload, _ = sample("vuln-findings")
    triage = json.loads(sample("triage")[0])
    triage["findings"][0]["orig_id"] = "REPO-abcdef0-001"
    layer_payload, _ = sample("layer")
    context = Binding(
        FINDINGS_SUMMARY_SCOPE,
        FINDINGS_SUMMARY_SUBJECT,
        FINDINGS_SUMMARY_RUN,
        FINDINGS_SUMMARY_LAYER,
    )
    store.ingest("vuln-findings", finding_payload, context)
    store.ingest("triage", encode(triage), context)
    store.ingest("layer", layer_payload, Binding(layer_id=FINDINGS_SUMMARY_LAYER))
    # findings_summary gets repo from ownership, not layer_metadata.
    store.ingest(
        "corpus-registry",
        encode(
            {
                "version": 1,
                "subjects": [
                    {
                        "subject_id": FINDINGS_SUMMARY_SUBJECT,
                        "tree": "findings",
                        "ownership": "owned",
                        "business_unit": "Test",
                        "repo_url": "https://example.test/repo",
                        "is_branch_audit": False,
                    }
                ],
            }
        ),
        Binding(scope_id=FINDINGS_SUMMARY_SCOPE),
    )


def report_with_findings() -> bytes:
    """A cumulative report: two findings, one fully disposed, one bare.

    The shipped sample has zero findings, so the fan-out was unexercised.
    """
    document = json.loads(sample("report")[0])
    document["findings"] = [
        {
            "id": "FIND-001",
            "title": "Disposed finding",
            "severity": "high",
            "description": "x" * 50,
            "cwes": ["CWE-79"],
            "locations": [{"path": "a/b.go"}],
            "remediation": "x" * 20,
            "fingerprint": "a" * 64,
            "validation_status": "confirmed",
            "disposition": {
                "validity": "confirmed",
                "resolution": "fix_in_progress",
                "assurance": "execution_proven",
                "last_updated": "2026-01-02T00:00:00Z",
                "events": [],
                "conflict": False,
                "fp_overridden": True,
                "fp_reassertion_blocked": True,
                "refuted_awaiting_signoff": False,
                "severity_override": {
                    "severity": "critical",
                    "by": "signer@example.test",
                    "at": "2026-01-02T00:00:00Z",
                },
            },
        },
        {
            "id": "FIND-002",
            "title": "Undisposed finding",
            "severity": "low",
            "description": "y" * 50,
            "cwes": ["CWE-200"],
            "locations": [{"path": "c/d.go"}],
            "remediation": "y" * 20,
        },
    ]
    return encode(document)


def report_with_external_blocking() -> bytes:
    """Independent true/false flags and an unmapped historical blocking label."""
    document = json.loads(report_with_findings())
    document["findings"][0].update(remediation_effort="m", blocked_external=True)
    document["findings"][1].update(remediation_effort="m", blocked_external=False)
    document["findings"].append(
        {
            **document["findings"][1],
            "id": "FIND-003",
            "remediation_effort": "blocked-external",
        }
    )
    del document["findings"][2]["blocked_external"]
    return encode(document)
