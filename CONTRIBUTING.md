# Contributing

## Setup

```bash
git clone <repo-url> && cd traust-contracts
make setup
```

Installs deps (`uv sync`) and enables git hooks. One time per clone.

## Commit messages

Conventional commits required. Format: `type(scope): subject`

Types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`, `ci`, `build`, `style`, `revert`

```
feat(schemas): add layer review queue reason
fix(enums): correct disposition resolution label
feat!: bump data-contract v2          ← breaking change
```

## Hooks

| Hook | Runs | Speed |
|------|------|-------|
| `commit-msg` | subject format check | instant |
| `pre-commit` | ruff lint on staged `.py` | <1s |
| `pre-push` | full lint + unit tests | ~10s |

Bypass: `--no-verify` on commit or push. CI still enforces.

## Releasing

If your PR has `feat:`, `fix:`, `perf:`, or `!` (breaking) commits:

```bash
make bump minor
# add ## [X.Y.Z] section to CHANGELOG.md
make check-release
git add VERSION pyproject.toml CHANGELOG.md uv.lock
git commit -m "chore: release X.Y.Z"
```

Run `uv lock` when changing dependencies. CI validates on MR. On merge to main, CI tags automatically.

## Compatibility tests

`tests/test_compat.py` gates breaking schema/vector changes. For intentional major bumps:

```bash
CONTRACTS_ALLOW_BREAKING=1 uv run pytest tests/ -q
```

## CI pipeline

**PR:** lint → conventional commits → release-ready → tests

**Main:** tag if `VERSION` > latest git tag

## Running tests

```bash
make test
uv run pytest -q
```

## Architecture

See [README.md](README.md) for versioning axes, validation, and consumption.
