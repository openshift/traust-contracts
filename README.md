# Traust Contracts

Source of truth for JSON schemas and enums shared across the Traust ecosystem,
plus generated Python bindings **and the configuration contract** (the one place
that knows what config exists and how it loads).

## Configuration contract

Contracts owns the configuration *mechanism* for the whole stack — mechanism
only, never estate data:

- **MANIFEST** — the authoritative list of config files (name, required/optional,
  schema, typed model). The single source of truth for “what config exists.”
- **Schemas** — `config/v1/*.schema.json`, applied at load time (versioned
  separately from the `schemas/v1` data schemas).
- **Typed sections + `HarnessContext`** — each file parses into a typed model;
  `HarnessContext` is the frozen bundle of them all.
- **The loader** — `load_context()` (resolve the whole context at an entry point)
  and `load_section()` (one file, for narrow feature-gated readers). Resolution is
  `$TRAUST_CONFIG_HOME`, else the documented default `~/.traust/config` — no env
  overrides, no cwd scanning, no second root.

Consumers declare the subset they need and receive an injected `HarnessContext`
(`traust_engine` never loads config itself); the app (`traust`) is the config
*source* (templates + `install_traust`) and resolves the context once per entry
point. One loader → no two callers disagree about “what the config is.”
End-to-end architecture: `traust/docs/architecture.md` → *Configuration & context*.

## Install

```bash
uv add "traust-contracts @ git+https://github.com/openshift/traust-contracts.git"
```

Go SDK: see [traust-sdk](https://github.com/openshift/traust-sdk).

## Versioning

Two independent axes:

- **Data-contract version** (`v1`, `v2`, ...) — the shape of schemas/enums
  and everything generated from them. Lives as a real directory; `v2` sits
  beside `v1` once it exists.
- **Package release version** (`VERSION`) — normal semver for this repo.

`traust_contracts.models` / `.enums` / `.paths` alias the current major
(`v1` today). Pin to `traust_contracts.v1.*` directly if the shape must
never move under you.

## Validate an artifact

```bash
python validate.py --schema report myreport.json
python validate.py --list
```

## Test

```bash
make setup    # uv sync + enable .githooks
make test
```

Or manually:

```bash
uv sync
uv run pytest tests/ -q
```

`tests/test_compat.py` gates breaking schema/vector changes against the
previous git tag; see its docstrings for the escape hatch.

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).
