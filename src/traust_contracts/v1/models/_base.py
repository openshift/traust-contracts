"""Shared Pydantic base for contract models."""

from __future__ import annotations

from typing import Any, Self

from pydantic import BaseModel, ConfigDict


class ContractModel(BaseModel):
    """Base for schema-derived models with JSON round-trip helpers."""

    # validate_assignment keeps field constraints (IsoTimestamp, enums) binding
    # after construction; without it `event.recorded_at = "banana"` is accepted.
    model_config = ConfigDict(extra="ignore", validate_assignment=True)

    def to_dict(self) -> dict[str, Any]:
        return self.model_dump(mode="json", exclude_none=True)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Self:
        return cls.model_validate(data)
