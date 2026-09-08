# traust-contracts

Python 3.11+ contract library (`traust_contracts`). Schemas and enums — semver-breaking by default.

Identity vectors are **not** here: the finding-fingerprint suite was retired on 2026-08-18 (only the harness computes identity, so no second-language port needs a shared oracle). Regression fixtures for the recipe live beside the implementation in the ledger package.

- **Before done:** `make lint-fix` then `make test` — CI enforces both; do not skip
- **Lint:** line length 100; ruff E/W/F/I/UP/B/SIM/PTH/RUF (`pyproject.toml`) — `Path` not `os.path`, no bare `except: pass`
- **Commits:** conventional `type(scope): subject` (`feat`, `fix`, `perf`, `chore`, `ci`, …)
- **Releases:** `feat`/`fix`/`perf`/breaking PRs need `make check-release`, `VERSION` + `CHANGELOG.md` bump
- **Compat:** schema/vector breaks need major bump; escape hatch `CONTRACTS_ALLOW_BREAKING=1 uv run pytest tests/ -q`
- **Setup:** `make setup` once per clone (hooks). More: [CONTRIBUTING.md](CONTRIBUTING.md), [README.md](README.md)
