"""Round-trip tests for Pydantic contract models."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from traust_contracts.enums import Severity
from traust_contracts.models import (
    AdapterResult,
    Finding,
    Report,
)
from traust_contracts.v1.models.adapter import AdapterMetadata, AdapterSummary
from traust_contracts.v1.models.finding import Location

REPO_ROOT = Path(__file__).parent.parent
SCHEMA_DIR = REPO_ROOT / "schemas" / "v1"
FIXTURES = Path(__file__).parent / "fixtures"


def _registry() -> Registry:
    resources = {}
    for sf in sorted(SCHEMA_DIR.glob("*.schema.json")):
        doc = json.loads(sf.read_text(encoding="utf-8"))
        resources[doc.get("$id", sf.name)] = Resource.from_contents(doc)
    return Registry(resources=resources)


def _validate(schema_name: str, data: dict) -> None:
    schema = json.loads((SCHEMA_DIR / schema_name).read_text(encoding="utf-8"))
    validator = Draft202012Validator(schema, registry=_registry())
    errors = list(validator.iter_errors(data))
    assert not errors, errors[0].message if errors else ""


def test_finding_round_trip():
    raw = {
        "id": "REPO-abc1234-001",
        "title": "Test finding",
        "severity": "high",
        "cwes": ["CWE-79"],
        "locations": [{"path": "src/main.go", "lines": "10-20"}],
        "description": "desc",
        "remediation": "fix",
    }
    model = Finding.from_dict(raw)
    out = model.to_dict()
    assert out["id"] == raw["id"]
    assert out["severity"] == "high"


def test_adapter_result_round_trip():
    finding = Finding(
        id="REPO-abc1234-001",
        title="x",
        severity=Severity.HIGH,
        cwes=["CWE-79"],
        locations=[Location(path="a.go")],
        description="d",
        remediation="r",
    )
    model = AdapterResult(
        target="repo",
        scanned_at="2026-01-01T00:00:00Z",
        metadata=AdapterMetadata(tool="opengrep"),
        findings=[finding],
        summary=AdapterSummary(total=1, by_severity={"high": 1}),
    )
    restored = AdapterResult.from_dict(model.to_dict())
    assert restored.summary.total == 1


def test_report_optional_sections_round_trip():
    from traust_contracts.v1.models.report import (
        DispositionSummary,
        ExecutiveSummary,
        ReportMetadata,
        ResolutionCounts,
        SeverityCounts,
        ValidityCounts,
    )

    report = Report(
        title="Audit",
        metadata=ReportMetadata(date="2026-01-01", scope="test"),
        executive_summary=ExecutiveSummary(
            prose="ok",
            severity_counts=SeverityCounts(),
        ),
        disposition_summary=DispositionSummary(
            layer_ref="layer.json",
            generated_at="2026-01-01T00:00:00Z",
            by_resolution=ResolutionCounts(),
            by_validity=ValidityCounts(),
        ),
    )
    restored = Report.from_dict(report.to_dict())
    assert restored.disposition_summary is not None


@pytest.mark.skipif(not FIXTURES.exists(), reason="fixtures not present")
def test_fixture_round_trips():
    for path in FIXTURES.glob("*.json"):
        schema_hint = path.stem.replace("_", "-") + ".schema.json"
        if not (SCHEMA_DIR / schema_hint).is_file():
            continue
        raw = json.loads(path.read_text(encoding="utf-8"))
        _validate(schema_hint, raw)


def test_layer_external_refs_round_trip_and_validate():
    """CVE-provenance stamps must survive the model AND the schema.

    ContractModel ignores unknown keys, so a schema-only field round-trips
    to nothing (the failure 85cbdfe had to fix for auto_accept_tier). This
    asserts both halves, and that the map is metadata rather than an event:
    provenance is derived and must not perturb the Merkle-signed chain.
    """
    from traust_contracts.models import ExternalRef, LayerMetadata

    md = LayerMetadata(
        audit_report="r-security-audit.json",
        repository="https://github.com/o/r",
        created="2026-08-20T00:00:00Z",
        harness_version="0.4.0",
        external_refs={
            "FIND-002": [
                ExternalRef(
                    system="cve",
                    id="CVE-2026-66792",
                    url="https://nvd.nist.gov/vuln/detail/CVE-2026-66792",
                    confidence="confirmed",
                    matched_on="title-similarity:0.78",
                    stamped_at="2026-08-20T00:00:00Z",
                )
            ]
        },
    )
    raw = md.to_dict()
    assert raw["external_refs"]["FIND-002"][0]["id"] == "CVE-2026-66792"
    assert LayerMetadata.from_dict(raw).external_refs["FIND-002"][0].confidence == "confirmed"

    schema = json.loads((SCHEMA_DIR / "layer.schema.json").read_text(encoding="utf-8"))
    Draft202012Validator({**schema, **schema["$defs"]["layer_metadata"]}).validate(raw)

    # the event chain is deliberately untouched
    assert "external_refs" not in schema["$defs"]["event"]["properties"]


def test_layer_external_refs_rejects_unknown_system():
    schema = json.loads((SCHEMA_DIR / "layer.schema.json").read_text(encoding="utf-8"))
    validator = Draft202012Validator({**schema, **schema["$defs"]["layer_metadata"]})
    bad = {
        "audit_report": "r-security-audit.json",
        "repository": "https://github.com/o/r",
        "created": "2026-08-20T00:00:00Z",
        "harness_version": "0.4.0",
        "external_refs": {"FIND-001": [{"system": "pastebin", "id": "x"}]},
    }
    assert list(validator.iter_errors(bad))
