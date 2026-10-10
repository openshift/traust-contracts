"""SQL-first Ledger v1 inventory, execution and metadata gates."""

from __future__ import annotations

import contextlib
import re
import sqlite3
import tomllib
from pathlib import Path

import pytest

from traust_contracts.paths import ledger_dir, storage_dir
from traust_contracts.v1.ledger import (
    CONTRACT_VERSION,
    POSTGRES_SCHEMA,
    REVISION,
    TABLE_ORDER,
    assert_identity_shape,
    bootstrap_files,
    bootstrap_statements,
    migration_files,
)
from traust_contracts.v1.storage import Store

ROOT = Path(__file__).parents[1]
TABLES = ("schema_revision", "layers", "events", "materialized_findings")
ACM_CLI = "https://github.com/stolostron/acm-cli"


def _ledger_on_storage(ledger_sql: dict[str, str] | None = None) -> sqlite3.Connection:
    """Storage first, then the ledger, in one SQLite file: the ledger's FK target."""
    connection = sqlite3.connect(":memory:")
    Store(connection).init()
    for path in bootstrap_files("sqlite"):
        connection.executescript((ledger_sql or {}).get(path.stem) or path.read_text("utf-8"))
    return connection


def _product_repo(connection: sqlite3.Connection, product: str = "rhacm") -> int:
    store = Store(connection)
    return store.register_product_repo(
        store.register_product(product), store.register_repo(ACM_CLI)
    )


def _layer(connection: sqlite3.Connection, product_repo_id: int | None) -> int:
    return connection.execute(
        "INSERT INTO layers (metadata_payload, needs_review_payload, "
        "extensions_payload, root_keys_payload, product_repo_id) "
        "VALUES (x'00', x'00', x'00', x'00', ?) RETURNING id",
        (product_repo_id,),
    ).fetchone()[0]


@pytest.mark.parametrize("dialect", ["postgres", "sqlite"])
def test_exact_sql_inventory_and_bootstrap_order(dialect: str) -> None:
    root = ledger_dir() / dialect
    namespace = [root / "namespace.sql"] if dialect == "postgres" else []
    expected = [*namespace, *(root / "schema" / f"{name}.sql" for name in TABLES)]
    assert CONTRACT_VERSION == "v1"
    assert REVISION == 1
    assert POSTGRES_SCHEMA == "traust_ledger"
    assert TABLE_ORDER == TABLES
    assert bootstrap_files(dialect) == expected
    assert {p.name for p in (root / "schema").glob("*.sql")} == {f"{name}.sql" for name in TABLES}
    assert migration_files(dialect, REVISION) == []
    placeholder = root / "migrations" / f"{REVISION:03d}_to_{REVISION + 1:03d}.sql"
    assert {p.relative_to(root).as_posix() for p in root.rglob("*.sql")} == {
        *(p.relative_to(root).as_posix() for p in [*expected, placeholder]),
    }
    assert not (ledger_dir() / "manifest.json").exists()
    assert not (ledger_dir() / "manifest.schema.json").exists()
    assert not (root / "queries").exists()


def test_sqlite_bootstrap_metadata_and_relations() -> None:
    with contextlib.closing(_ledger_on_storage()) as connection:
        relations = {
            name
            for (name,) in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
            )
        }
        assert set(TABLES) <= relations
        assert_identity_shape(connection, "sqlite")
        connection.execute(
            "INSERT INTO schema_revision VALUES (:id, :contract_version, :revision, :applied_at)",
            {
                "id": 1,
                "contract_version": CONTRACT_VERSION,
                "revision": REVISION,
                "applied_at": "2026-01-01",
            },
        )
        assert connection.execute(
            "SELECT contract_version, revision FROM schema_revision"
        ).fetchone() == ("v1", 1)
        assert connection.execute("SELECT id, applied_at FROM schema_revision").fetchone() == (
            1,
            "2026-01-01",
        )
        with pytest.raises(sqlite3.IntegrityError):
            connection.execute("INSERT INTO schema_revision VALUES (2, 'v1', 1, '2026-01-01')")
        with pytest.raises(sqlite3.IntegrityError):
            connection.execute(
                "INSERT INTO events (layer_id, seq, event_id, event_payload) "
                "VALUES ('missing', 0, 'event', x'00')"
            )


def test_same_revision_stamp_rejects_legacy_ledger_shape() -> None:
    legacy = "CREATE TABLE layers (layer_id VARCHAR PRIMARY KEY, product_repo_id TEXT)"
    with contextlib.closing(_ledger_on_storage({"layers": legacy})) as connection:
        connection.execute("INSERT INTO schema_revision VALUES (1, 'v1', 1, 'now')")
        with pytest.raises(ValueError, match="manual conversion required"):
            assert_identity_shape(connection, "sqlite")
        assert connection.execute("SELECT revision FROM schema_revision").fetchone() == (1,)


def test_sqlite_append_only_guards() -> None:
    """Verify that bootstrapped schema installs append-only triggers."""
    with contextlib.closing(_ledger_on_storage()) as conn:
        # verify triggers exist
        triggers = {
            name
            for (name,) in conn.execute("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        }
        assert "events_reject_update" in triggers
        assert "events_reject_delete" in triggers
        assert "events_validate_append" in triggers
        assert "layers_reject_delete" in triggers
        # insert valid data
        layer_id = _layer(conn, _product_repo(conn))
        conn.execute(
            "INSERT INTO events (layer_id, seq, event_id, event_payload) "
            "VALUES (?, 0, 'e0', x'AA')",
            (layer_id,),
        )
        # UPDATE on events must fail
        with pytest.raises(sqlite3.IntegrityError, match="append-only"):
            conn.execute("UPDATE events SET event_payload = x'BB' WHERE event_id = 'e0'")
        # DELETE on events must fail
        with pytest.raises(sqlite3.IntegrityError, match="append-only"):
            conn.execute("DELETE FROM events WHERE event_id = 'e0'")
        # DELETE on layers must fail
        with pytest.raises(sqlite3.IntegrityError, match="cannot be deleted"):
            conn.execute("DELETE FROM layers WHERE id = ?", (layer_id,))
        # out-of-order seq must fail
        with pytest.raises(sqlite3.IntegrityError, match="append at the next sequence"):
            conn.execute(
                "INSERT INTO events (layer_id, seq, event_id, event_payload) "
                "VALUES (?, 5, 'e5', x'CC')",
                (layer_id,),
            )


def test_layers_reference_a_registered_product_repo() -> None:
    with contextlib.closing(_ledger_on_storage()) as conn:
        owner = _product_repo(conn)
        layer_id = _layer(conn, owner)
        assert isinstance(layer_id, int)
        with pytest.raises(sqlite3.IntegrityError, match="FOREIGN KEY"):
            _layer(conn, 999_999_999)
        with pytest.raises(sqlite3.IntegrityError, match="UNIQUE"):
            _layer(conn, owner)
        with pytest.raises(sqlite3.IntegrityError, match="NOT NULL"):
            _layer(conn, None)
        joined = conn.execute(
            "SELECT l.id, pr.ref FROM layers l JOIN product_repo pr ON pr.id = l.product_repo_id"
        ).fetchall()
        assert joined == [(layer_id, "")]
        for table, column, parent in (
            ("layers", "product_repo_id", "product_repo"),
            ("events", "layer_id", "layers"),
            ("materialized_findings", "layer_id", "layers"),
        ):
            assert any(
                row[2:5] == (parent, column, "id")
                for row in conn.execute(f"PRAGMA foreign_key_list({table})")
            ), table
        with pytest.raises(sqlite3.IntegrityError, match="FOREIGN KEY"):
            conn.execute(
                "INSERT INTO materialized_findings "
                "(layer_id, finding_ref, validity, resolution, event_count) "
                "VALUES (999999999, 'ref', 'valid', 'open', 0)"
            )
        assert conn.execute("PRAGMA foreign_key_check").fetchall() == []


def test_ledger_requires_storage_in_the_same_database() -> None:
    with contextlib.closing(sqlite3.connect(":memory:")) as conn:
        conn.execute("PRAGMA foreign_keys = ON")
        for path in bootstrap_files("sqlite"):
            for statement in bootstrap_statements("sqlite", path):
                conn.execute(statement)
        with pytest.raises(sqlite3.OperationalError, match="no such table"):
            _layer(conn, 1)


def test_postgres_layers_reference_storage_product_repo(postgres_dsn: str) -> None:
    import psycopg

    with psycopg.connect(postgres_dsn, autocommit=True) as conn:
        conn.execute("DROP SCHEMA IF EXISTS traust_ledger CASCADE")
        conn.execute("DROP SCHEMA IF EXISTS traust_storage CASCADE")
        try:
            store = Store(conn)
            store.init()
            for path in bootstrap_files("postgres"):
                for statement in bootstrap_statements("postgres", path):
                    conn.execute(statement)
            owner = store.register_product_repo(
                store.register_product("rhacm"), store.register_repo(ACM_CLI)
            )
            insert = (
                "INSERT INTO traust_ledger.layers (metadata_payload, "
                "needs_review_payload, extensions_payload, root_keys_payload, product_repo_id) "
                "VALUES ('\\x00', '\\x00', '\\x00', '\\x00', %s) RETURNING id"
            )
            assert isinstance(conn.execute(insert, (owner,)).fetchone()[0], int)
            assert_identity_shape(conn, "postgres")
            with pytest.raises(psycopg.errors.ForeignKeyViolation):
                conn.execute(insert, (999_999_999,))
            with pytest.raises(psycopg.errors.UniqueViolation):
                conn.execute(insert, (owner,))
            with pytest.raises(psycopg.errors.NotNullViolation):
                conn.execute(insert, (None,))
        finally:
            conn.execute("DROP SCHEMA IF EXISTS traust_ledger CASCADE")
            conn.execute("DROP SCHEMA IF EXISTS traust_storage CASCADE")


def test_generated_ledger_ids_and_typed_references_in_authored_sql() -> None:
    for dialect, id_type, fk_type in (
        ("postgres", "BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY", "BIGINT"),
        ("sqlite", "INTEGER PRIMARY KEY", "INTEGER"),
    ):
        schema = ledger_dir() / dialect / "schema"
        layers = (schema / "layers.sql").read_text()
        assert f"id {id_type}" in layers
        assert f"product_repo_id {fk_type} NOT NULL UNIQUE REFERENCES" in layers
        assert "product_repo(id)" in layers
        for table in ("events", "materialized_findings"):
            child = (schema / f"{table}.sql").read_text()
            assert f"layer_id {fk_type} NOT NULL" in child
            assert "layers(id)" in child


def test_postgres_sql_qualified_and_metadata_shape() -> None:
    root = ledger_dir() / "postgres"
    ns = (root / "namespace.sql").read_text()
    assert "CREATE SCHEMA IF NOT EXISTS traust_ledger;" in ns
    assert "reject_authoritative_mutation" in ns
    assert "validate_event_append" in ns
    for name in TABLES:
        sql = (root / "schema" / f"{name}.sql").read_text()
        assert re.findall(r"CREATE TABLE ([\w.]+) \(", sql) == [f"traust_ledger.{name}"]
    assert "REFERENCES traust_ledger.layers" in (root / "schema" / "events.sql").read_text()
    revision = (root / "schema" / "schema_revision.sql").read_text()
    assert "id INTEGER PRIMARY KEY CHECK (id = 1)" in revision
    assert "contract_version TEXT NOT NULL" in revision
    assert "revision INTEGER NOT NULL" in revision
    assert "applied_at TIMESTAMPTZ NOT NULL" in revision


def test_packaging_and_baseline_independence() -> None:
    includes = tomllib.loads((ROOT / "pyproject.toml").read_text())["tool"]["hatch"]["build"][
        "targets"
    ]["wheel"]["force-include"]
    assert includes["ledger/v1"] == "traust_contracts/ledger/v1"
    assert includes["storage/v1"] == "traust_contracts/storage/v1"
    assert not any(
        "traust_ledger." in p.read_text().lower() or "schema_revision" in p.read_text().lower()
        for p in storage_dir().rglob("*.sql")
    )
    # The ledger may depend on storage (always present with a database), only
    # through product_repo; storage never depends on the ledger.
    for path in ledger_dir().rglob("*.sql"):
        for reference in re.findall(r"traust_storage\.\w+", path.read_text().lower()):
            assert reference == "traust_storage.product_repo", f"{path.name}: {reference}"
