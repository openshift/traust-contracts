"""Remediation model — from remediation.schema.json."""

from __future__ import annotations

from pydantic import Field

from traust_contracts.v1.enums import Severity
from traust_contracts.v1.models._base import ContractModel
from traust_contracts.v1.models.finding import Location


class RemediationMetadata(ContractModel):
    date: str
    harness_version: str
    logical_product: str
    repository: str
    audited_commit: str | None = None
    language: str | None = None
    jira_keys: list[str] = Field(default_factory=list)
    operator: str | None = None


class SourceFinding(ContractModel):
    finding_ref: str
    title: str
    severity: Severity
    cwes: list[str]
    locations: list[Location]
    triage_confidence: float | None = None
    validation_verdict: str | None = None
    audit_report_path: str | None = None
    triage_report_path: str | None = None
    validation_report_path: str | None = None


class Fork(ContractModel):
    url: str
    visibility: str
    base_ref: str
    fix_branch: str
    host: str | None = None
    upstream_remote: str | None = None
    base_commit: str | None = None
    fix_commit: str | None = None
    synced_from_upstream_at: str | None = None


class FileChanged(ContractModel):
    path: str
    change_type: str
    hunks: int | None = None
    additions: int | None = None
    deletions: int | None = None


class Diffstat(ContractModel):
    files: int
    additions: int
    deletions: int


class Patch(ContractModel):
    strategy: str
    rationale: str
    files_changed: list[FileChanged]
    diffstat: Diffstat
    behaviour_change: str | None = None
    diff_path: str | None = None
    diff_sha256: str | None = None
    tests_added: list[str] = Field(default_factory=list)
    residual_risk: str | None = None


class Check(ContractModel):
    name: str
    command: str
    outcome: str
    duration_seconds: float | None = None
    log_path: str | None = None
    summary: str | None = None


class Revalidation(ContractModel):
    performed: bool
    method: str | None = None
    image_ref: str | None = None
    validation_report_path: str | None = None
    before_verdict: str | None = None
    after_verdict: str | None = None
    fixed: bool | None = None


class PullRequest(ContractModel):
    url: str
    target: str
    number: int | None = None
    base_branch: str | None = None
    reviewers: list[str] = Field(default_factory=list)
    state: str | None = None


class RemediationSummary(ContractModel):
    status: str
    checks_passed: int
    checks_total: int
    findings_addressed: int | None = None
    ready_for_review: bool | None = None


class Remediation(ContractModel):
    """Automated remediation report."""

    title: str
    metadata: RemediationMetadata
    source_findings: list[SourceFinding]
    fork: Fork
    patch: Patch
    checks: list[Check]
    summary: RemediationSummary
    revalidation: Revalidation | None = None
    pull_request: PullRequest | None = None
    notes: str | None = None
    footer: str | None = None
