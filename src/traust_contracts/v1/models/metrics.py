"""MetricsRecord — engine-internal ledger row; not part of the public contracts schema surface."""

from __future__ import annotations

from typing import Any

from pydantic import Field

from traust_contracts.v1.models._base import ContractModel


class MetricsRecord(ContractModel):
    """A single metrics ledger entry."""

    timestamp: str = ""
    source: str = ""
    harness_version: str = ""
    metrics: dict[str, Any] = Field(default_factory=dict)
    note: str = ""
