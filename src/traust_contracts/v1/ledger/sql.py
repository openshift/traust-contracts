"""Read authored Ledger SQL in deterministic bootstrap order."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from traust_contracts.paths import ledger_dir
from traust_contracts.v1.sql import Dialect
from traust_contracts.v1.sql import bootstrap_files as _bootstrap_files
from traust_contracts.v1.sql import bootstrap_statements as bootstrap_statements

CONTRACT_VERSION = "v1"
#: Ledger schema revision. 1: baseline (0.50.0), including layers.product_repo_id,
#: a foreign key into traust_storage.product_repo (storage initialized first,
#: same database). Pre-stable identity correction keeps revision 1: existing
#: installations require explicit conversion and assert_identity_shape().
REVISION = 1
POSTGRES_SCHEMA = "traust_ledger"
# Foreign-key dependency order; this is the complete v1 table inventory.
TABLE_ORDER: tuple[str, ...] = (
    "schema_revision",
    "layers",
    "events",
    "materialized_findings",
)


def assert_identity_shape(conn: Any, dialect: Dialect) -> None:
    """Reject legacy revision-1 layer IDs before a database Ledger serves writes."""
    if dialect == "sqlite":
        columns = {
            row[1]: (row[2].upper(), row[3], row[5])
            for row in conn.execute("PRAGMA table_info(layers)").fetchall()
        }
        children = (
            ("events", "layer_id"),
            ("materialized_findings", "layer_id"),
        )
        child_types = all(
            any(
                row[1] == name and row[2].upper() == "INTEGER"
                for row in conn.execute(f"PRAGMA table_info({table})").fetchall()
            )
            for table, name in children
        )
        unique = any(
            [row[2] for row in conn.execute(f"PRAGMA index_info({index[1]})")]
            == ["product_repo_id"]
            and index[2]
            for index in conn.execute("PRAGMA index_list(layers)").fetchall()
        )
        owner_fk = any(
            row[2] == "product_repo" and row[3:5] == ("product_repo_id", "id")
            for row in conn.execute("PRAGMA foreign_key_list(layers)").fetchall()
        )
        valid = (
            columns.get("id") == ("INTEGER", 0, 1)
            and columns.get("product_repo_id") == ("INTEGER", 1, 0)
            and child_types
            and unique
            and owner_fk
        )
    else:
        columns = {
            (row[0], row[1]): (row[2], row[3], row[4])
            for row in conn.execute(
                "SELECT table_name, column_name, data_type, is_identity, is_nullable "
                "FROM information_schema.columns WHERE table_schema = 'traust_ledger' "
                "AND table_name IN ('layers', 'events', 'materialized_findings')"
            ).fetchall()
        }
        unique_owner = conn.execute(
            "SELECT EXISTS (SELECT 1 FROM pg_constraint c "
            "JOIN pg_attribute a ON a.attrelid = c.conrelid "
            "WHERE c.conrelid = 'traust_ledger.layers'::regclass "
            "AND c.contype = 'u' AND array_length(c.conkey, 1) = 1 "
            "AND a.attname = 'product_repo_id' AND a.attnum = c.conkey[1])"
        ).fetchone()[0]
        valid = (
            columns.get(("layers", "id")) == ("bigint", "YES", "NO")
            and unique_owner
            and columns.get(("layers", "product_repo_id")) == ("bigint", "NO", "NO")
            and all(
                columns.get((table, "layer_id")) == ("bigint", "NO", "NO")
                for table in ("events", "materialized_findings")
            )
        )
    if not valid:
        raise ValueError(
            "ledger: incompatible v1 revision-1 identity shape; reviewed manual conversion required"
        )


def bootstrap_files(dialect: Dialect, version: str = "v1") -> list[Path]:
    """Return the namespace followed by authored tables in dependency order."""
    return _bootstrap_files(
        ledger_dir(version), dialect, first_tables=TABLE_ORDER, exact_tables=True
    )


def migration_files(dialect: Dialect, from_revision: int, version: str = "v1") -> list[Path]:
    """Return the delta files that take ``from_revision`` to ``REVISION``, in order."""
    directory = ledger_dir(version) / dialect / "migrations"
    paths = [
        directory / f"{step:03d}_to_{step + 1:03d}.sql" for step in range(from_revision, REVISION)
    ]
    missing = [path.name for path in paths if not path.is_file()]
    if missing:
        raise FileNotFoundError(f"missing ledger {dialect} migration: {', '.join(missing)}")
    return paths
