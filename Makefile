PYTHON ?= python3
RELEASE := ./release.py
BUMP_PARTS := patch minor major
DOCS_DIR ?= ../traust/docs

DB_CONTAINER := traust-postgres
DB_IMAGE := docker.io/library/postgres:16
DB_PORT := 5432
DB_TEST_NAME := traust_test

.PHONY: help setup sync hooks lint lint-fix test storage-check db-up db-down db-setup db-teardown check-release status bump docs $(BUMP_PARTS) \
	downstream-status downstream-bump-ledger downstream-bump-engine downstream-bump-traust \
	downstream-chain downstream-chain-push downstream-chain-pr downstream-reconcile

help:
	@echo "Targets ($(notdir $(CURDIR))):"
	@echo "  make setup          — uv sync + enable .githooks (run once per clone)"
	@echo "  make sync           — uv sync only"
	@echo "  make hooks          — git config core.hooksPath .githooks"
	@echo "  make lint           — ruff check + format --check"
	@echo "  make lint-fix       — ruff check --fix + format"
	@echo "  make test           — pytest tests (database e2e included when db-up)"
	@echo "  make db-setup       — start/reuse shared container, ensure traust_test exists"
	@echo "  make db-teardown    — drop traust_test only (leave container and migration DB)"
	@echo "  make db-up          — alias for db-setup"
	@echo "  make db-down        — stop shared container (also affects migration)"
	@echo "  make check-release  — VERSION + CHANGELOG gate for current branch vs main"
	@echo "  make status         — current version, tag, git state"
	@echo "  make bump patch|minor|major — bump VERSION + pyproject.toml"
	@echo "  make docs           — regenerate DDL model docs (DOCS_DIR=$(DOCS_DIR))"
	@echo ""
	@echo "Downstream pin chain (contracts -> ledger -> engine -> traust, see ci/README.md):"
	@echo "  make downstream-status       — drift report across all four sibling repos"
	@echo "  make downstream-bump-ledger  — pin ledger to this repo's HEAD, test-gate, commit (local only)"
	@echo "  make downstream-bump-engine  — pin engine to contracts+ledger HEAD, test-gate, commit"
	@echo "  make downstream-bump-traust  — pin traust to contracts+ledger+engine HEAD, test-gate, commit"
	@echo "  make downstream-chain        — walk all three hops, stop at first failure (local only)"
	@echo "  make downstream-chain-push   — same, pushing each hop's branch as it lands"
	@echo "  make downstream-chain-pr     — same, push + open a PR against traust-security/* at each hop"
	@echo "  make downstream-reconcile    — re-pin any hop whose tracked upstream PR merged via squash/rebase"

setup: sync hooks
	@echo "ready — local hooks enabled (.githooks). Bypass: git commit --no-verify"

sync:
	uv sync

hooks:
	git config core.hooksPath .githooks
	@chmod +x .githooks/* 2>/dev/null || true

lint:
	uv run ruff check .
	uv run ruff format --check .

lint-fix:
	uv run ruff check --fix .
	uv run ruff format .

storage-check:
	uv run pytest tests/test_storage_sql.py tests/test_compat.py -q

test:
	uv run pytest tests/ -q

db-up: db-setup

db-setup:
	@if podman ps --format '{{.Names}}' | grep -Fxq '$(DB_CONTAINER)'; then \
		echo "$(DB_CONTAINER) already running"; \
	elif podman container exists $(DB_CONTAINER) 2>/dev/null; then \
		podman start $(DB_CONTAINER); \
	else \
		podman run --name $(DB_CONTAINER) --rm -d \
			-e POSTGRES_USER=traust \
			-e POSTGRES_PASSWORD=traust-test-only \
			-e POSTGRES_DB=$(DB_TEST_NAME) \
			-p 127.0.0.1:$(DB_PORT):5432 \
			-v traust-postgres-data:/var/lib/postgresql/data \
			$(DB_IMAGE); \
	fi
	@ready=0; for i in $$(seq 1 30); do \
		if podman exec $(DB_CONTAINER) pg_isready -U traust -d postgres -q 2>/dev/null; then \
			ready=1; break; \
		fi; \
		sleep 1; \
	done; \
	if [ "$$ready" -ne 1 ]; then echo "$(DB_CONTAINER) not ready" >&2; exit 1; fi
	@if podman exec $(DB_CONTAINER) psql -X -U traust -d postgres -Atq \
		-c "SELECT 1 FROM pg_database WHERE datname = '$(DB_TEST_NAME)'" | grep -qx 1; then \
		echo "$(DB_TEST_NAME) already exists"; \
	else \
		podman exec $(DB_CONTAINER) createdb -U traust -O traust $(DB_TEST_NAME); \
	fi
	@podman exec $(DB_CONTAINER) psql -X -U traust -d $(DB_TEST_NAME) -Atq -c 'SELECT 1' | grep -qx 1
	@echo "$(DB_TEST_NAME) ready on port $(DB_PORT)"

db-teardown:
	@if ! podman ps --format '{{.Names}}' | grep -Fxq '$(DB_CONTAINER)'; then \
		echo "$(DB_CONTAINER) is not running; cannot tear down $(DB_TEST_NAME)" >&2; exit 1; \
	fi
	@podman exec $(DB_CONTAINER) dropdb -U traust --maintenance-db=postgres --if-exists $(DB_TEST_NAME)
	@echo "removed $(DB_TEST_NAME); shared container and traust_migration unchanged"

db-down:
	@podman stop $(DB_CONTAINER) 2>/dev/null || true

docs:
	@if [ ! -d "$(DOCS_DIR)" ]; then \
		echo "DOCS_DIR '$(DOCS_DIR)' does not exist; pass DOCS_DIR=/path/to/docs" >&2; \
		exit 1; \
	fi
	uv run python -m traust_contracts.v1.storage.build_storage_ddl_model \
		--out "$(DOCS_DIR)/storage-v1-ddl-model.md"
	uv run python -m traust_contracts.v1.ledger.build_ledger_ddl_model \
		--out "$(DOCS_DIR)/ledger-v1-ddl-model.md"

check-release:
	@base="$${RELEASE_BASE:-origin/main}"; \
	head="$${RELEASE_HEAD:-HEAD}"; \
	$(PYTHON) ci/gates.py mr "$$base" "$$head"

$(BUMP_PARTS):
	@:

status:
	$(PYTHON) $(RELEASE) status

bump:
	@part="$(filter $(BUMP_PARTS),$(MAKECMDGOALS))"; \
	if [ -z "$$part" ]; then \
		echo "usage: make bump patch|minor|major" >&2; \
		exit 1; \
	fi; \
	$(PYTHON) $(RELEASE) bump $$part

# --- Downstream pin chain: contracts -> ledger -> engine -> traust ---
# Drives sibling checkouts on disk (ci/README.md). Local-only unless noted.

downstream-status:
	$(PYTHON) ci/bump_downstream.py status

downstream-bump-ledger:
	$(PYTHON) ci/bump_downstream.py bump ledger

downstream-bump-engine:
	$(PYTHON) ci/bump_downstream.py bump engine

downstream-bump-traust:
	$(PYTHON) ci/bump_downstream.py bump traust

downstream-chain:
	$(PYTHON) ci/bump_downstream.py chain

downstream-chain-push:
	$(PYTHON) ci/bump_downstream.py chain --push

downstream-chain-pr:
	$(PYTHON) ci/bump_downstream.py chain --open-pr

downstream-reconcile:
	$(PYTHON) ci/bump_downstream.py reconcile
