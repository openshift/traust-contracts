"""AdapterResult — lightweight typed output from scanner adapters.

This is NOT the vuln-findings.schema.json ScanResult (which is a higher-level
skill output with repo_slug, baseline, etc.). This is the common shape all
engine-lib adapters return from their scan() functions.
"""

from __future__ import annotations

from pydantic import Field

from traust_contracts.v1.models._base import ContractModel
from traust_contracts.v1.models.finding import Finding


class AdapterMetadata(ContractModel):
    tool: str
    scanner_version: str = ""


class AdapterSummary(ContractModel):
    total: int
    by_severity: dict[str, int] = Field(default_factory=dict)


class AdapterResult(ContractModel):
    """Common typed output of engine-lib scanner adapters."""

    target: str
    scanned_at: str
    metadata: AdapterMetadata
    findings: list[Finding] = Field(default_factory=list)
    summary: AdapterSummary | None = None
    focus_areas: list[str] = Field(default_factory=list)
