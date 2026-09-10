"""RFC 3339 timestamps: the one definition shared by producers, models, and migrations.

Validation delegates to ``rfc3339-validator`` rather than
``datetime.fromisoformat``, which is looser than RFC 3339 and would accept bare
dates and naive datetimes the schemas forbid.
"""

from __future__ import annotations

from typing import Annotated

from pydantic import AfterValidator
from rfc3339_validator import validate_rfc3339

DATE_LENGTH = 10
MIDNIGHT_UTC = "T00:00:00+00:00"

_HINT = "expected RFC 3339, e.g. '2026-06-24T09:15:00+00:00' (offset required)"


class TimestampError(ValueError):
    """A value is not an RFC 3339 timestamp and cannot be converted to one."""


def is_rfc3339(value: object) -> bool:
    """True for a string in RFC 3339 date-time form."""
    return isinstance(value, str) and bool(value) and validate_rfc3339(value)


def _is_bare_date(value: str) -> bool:
    return len(value) == DATE_LENGTH and is_rfc3339(value + MIDNIGHT_UTC)


def to_rfc3339(value: object) -> str:
    """Convert ``value`` to an RFC 3339 date-time, or raise ``TimestampError``.

    Conforming input is returned unchanged byte-for-byte: ``event_id`` and the
    Merkle leaf hash the serialized event, so rewriting '+00:00' to 'Z' would
    void every signature. A bare date is padded to midnight UTC.

    Naive datetimes and non-strings raise rather than being coerced — an offset
    would be invented, and stringifying ``True`` is how 'TrueT00:00:00+00:00'
    was produced.
    """
    if is_rfc3339(value):
        return value  # type: ignore[return-value]
    if not isinstance(value, str):
        raise TimestampError(f"{value!r} is a {type(value).__name__}, not a string — {_HINT}")
    stripped = value.strip()
    if _is_bare_date(stripped):
        return stripped + MIDNIGHT_UTC
    raise TimestampError(f"{value!r} is not an RFC 3339 timestamp — {_HINT}")


def _assert_rfc3339(value: str) -> str:
    if not is_rfc3339(value):
        raise ValueError(f"{value!r} is not an RFC 3339 timestamp — {_HINT}")
    return value


IsoTimestamp = Annotated[str, AfterValidator(_assert_rfc3339)]
"""An RFC 3339 date-time. Enforced only — use ``to_rfc3339`` to convert."""


__all__ = [
    "MIDNIGHT_UTC",
    "IsoTimestamp",
    "TimestampError",
    "is_rfc3339",
    "to_rfc3339",
]
