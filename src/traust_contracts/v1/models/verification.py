"""Verification report — from verification.schema.json."""

from __future__ import annotations

from enum import StrEnum

from pydantic import Field

from traust_contracts.v1.models._base import ContractModel
from traust_contracts.v1.models.finding import Finding


class VerificationVerdict(StrEnum):
    RESOLVED = "resolved"
    PARTIALLY_RESOLVED = "partially_resolved"
    UNRESOLVED = "unresolved"
    NEW_APPROACH = "new_approach"
    REGRESSION = "regression"
    FALSE_POSITIVE = "false_positive"
    RISK_ACCEPTED = "risk_accepted"


class VerificationMetadata(ContractModel):
    date: str
    harness_version: str
    original_report: str
    original_commit: str
    patched_commit: str
    repository: str
    patched_ref: str | None = None
    ref: str | None = None


class VerificationSummary(ContractModel):
    total: int
    resolved: int
    partially_resolved: int = 0
    unresolved: int = 0
    new_approach: int = 0
    regression: int = 0
    false_positive: int = 0
    risk_accepted: int = 0


class VerifiedFinding(ContractModel):
    finding_id: str
    title: str
    verdict: VerificationVerdict
    original_severity: str | None = None
    fix_commits: list[str] = Field(default_factory=list)
    rationale: str | None = None


class Regression(Finding):
    """Regression finding extends report finding shape."""


class TimelineEntry(ContractModel):
    commit: str
    date: str
    message: str | None = None
    findings_addressed: list[str] = Field(default_factory=list)


class Verification(ContractModel):
    """Remediation verification report."""

    title: str
    metadata: VerificationMetadata
    summary: VerificationSummary
    verified_findings: list[VerifiedFinding]
    regressions: list[Regression] = Field(default_factory=list)
    commit_timeline: list[TimelineEntry] = Field(default_factory=list)
    recommendations: list[str] = Field(default_factory=list)
    notes: str | None = None
    footer: str | None = None
