"""Shared bootstrap ordering and SQL statement loading for v1 contracts."""

from __future__ import annotations

import sqlite3
from collections.abc import Iterator
from pathlib import Path
from typing import Literal

Dialect = Literal["postgres", "sqlite"]


def bootstrap_files(
    root: Path,
    dialect: Dialect,
    *,
    first_tables: tuple[str, ...],
    view_order: tuple[str, ...] = (),
    exact_tables: bool = False,
) -> list[Path]:
    """Order authored tables and views, with an optional exact table inventory."""
    directory = root / dialect
    schema = {path.stem: path for path in (directory / "schema").glob("*.sql")}
    missing = [name for name in first_tables if name not in schema]
    namespace = [directory / "namespace.sql"] if dialect == "postgres" else []
    if dialect == "postgres" and not namespace[0].is_file():
        missing.append("namespace")
    if missing:
        raise FileNotFoundError(f"missing {dialect} SQL contract: {', '.join(missing)}")
    tables = [schema.pop(name) for name in first_tables]
    if exact_tables and schema:
        raise ValueError(f"unexpected {dialect} SQL tables: {', '.join(sorted(schema))}")
    views = {path.name: path for path in (directory / "views").glob("*.sql")}
    ordered_views = [views.pop(name) for name in view_order if name in views]
    return [*namespace, *tables, *sorted(schema.values()), *ordered_views, *sorted(views.values())]


def bootstrap_statements(dialect: Dialect, path: Path) -> Iterator[str]:
    """Yield driver-safe statements while preserving authored file boundaries."""
    sql = path.read_text(encoding="utf-8")
    if dialect == "postgres":
        yield sql
        return
    statement = ""
    for line in sql.splitlines(keepends=True):
        statement += line
        if sqlite3.complete_statement(statement):
            yield statement
            statement = ""
    leftover = [line for line in statement.splitlines() if not line.lstrip().startswith("--")]
    if any(line.strip() for line in leftover):
        raise ValueError(f"incomplete SQLite statement in {path.name}")
