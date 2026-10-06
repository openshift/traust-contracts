# ci/bump_downstream.py

Drives the contracts → ledger → engine → traust pin chain. Lives here
because contracts sits at the root — every one of ledger, engine, and traust
carries a **direct** `[tool.uv.sources]` pin on contracts (not just a
transitive one through each other), so a contracts change is the most common
trigger for the whole walk. See each repo's `AGENTS.md`/`CONTRIBUTING.md`
"Downstream pin(s)" section for the short version; this file is the
how-it-works and troubleshooting companion.

Bridges the manual propagation toil until the platform-API work lands and
reshapes what "downstream" even means for these repos — not the permanent
answer, just the thing that replaces four hand-edited `pyproject.toml`s and a
changelog-reading guessing game with one deterministic command.

Assumes the mono-checkout layout: this repo and ledger/engine/traust are
sibling directories. Default root is computed from this file's own location
(`ci/bump_downstream.py` → `traust-contracts` → its parent); override with
`TRAUST_CHAIN_ROOT` if your checkout differs. This never touches the network
except through `uv lock`, `git push`, and `gh`.

## What one hop does (`bump <target>`)

```mermaid
flowchart LR
    A["resolve upstream sibling's local HEAD sha"] --> B["rewrite uv.sources:<br/>tag = 'vX' -> rev = '&lt;sha&gt;'"]
    B --> C["drop the floor in [project.dependencies]<br/>(the rev IS the floor now)"]
    C --> D["git checkout -b deps/&lt;repo&gt;-pin-&lt;dep&gt;-&lt;shortsha&gt;"]
    D --> E["uv lock"]
    E --> F["make test (the repo's OWN Makefile target) -- the gate"]
    F -->|pass| G["git commit"]
    F -->|fail| X["stop, leave branch dirty, report"]
    G -->|--push| H["git push"]
    H -->|--open-pr| I["gh pr create against upstream, record in .chain-state.json"]
```

A failing test *is* the breaking-change signal — propagation stops there
instead of you reading three changelogs to guess if it's safe.

## Chain topology (hardcoded in `CHAIN`)

| Repo | Pins (upstream deps it tracks) |
|---|---|
| `traust-contracts` | none (root) |
| `traust-ledger` | `traust-contracts` |
| `traust-engine` | `traust-contracts`, `traust-ledger` |
| `traust` | `traust-contracts`, `traust-ledger`, `traust-engine` |

Each hop reads its upstream dep's **local, currently-checked-out HEAD** —
after a hop runs, that repo sits on its new branch, so the *next* hop picks up
the branch tip, not `main`. That's what lets the chain walk PR-to-PR without
waiting for merges in between.

## Commands

```
python3 ci/bump_downstream.py status
python3 ci/bump_downstream.py bump ledger|engine|traust [--push] [--open-pr]
python3 ci/bump_downstream.py chain [--push] [--open-pr]
python3 ci/bump_downstream.py reconcile [ledger|engine|traust]
```

Or via `make` (run from this repo's root):

| Make target | Effect |
|---|---|
| `make downstream-status` | Drift report, read-only |
| `make downstream-bump-ledger` / `-engine` / `-traust` | One hop, local commit only, nothing pushed |
| `make downstream-chain` | All three hops in order, local only, stops at first test failure |
| `make downstream-chain-push` | Same, pushing each hop's branch right after its commit |
| `make downstream-chain-pr` | Same, push + `gh pr create` against `traust-security/*` at each hop |
| `make downstream-reconcile` | Fix pins left dangling by a squash/rebase merge |

(No single-hop `-pr` targets wired into the Makefile today — call the script
directly with `bump <target> --open-pr` if you need just one.)

## Example: `make downstream-status`

```
traust-contracts: HEAD 104519f
traust-ledger: HEAD f8a7324  pins: traust-contracts=v0.48.1 (upstream 104519f DRIFT)
traust-engine: HEAD 399bca3  pins: traust-contracts=v0.47.0 (upstream 104519f DRIFT), traust-ledger=v0.8.5 (upstream f8a7324 DRIFT)
traust: HEAD 3de1247  pins: traust-contracts=v0.48.0 (upstream 104519f DRIFT), traust-ledger=v0.9.1 (upstream f8a7324 DRIFT), traust-engine=v0.19.0 (upstream 399bca3 DRIFT)
```

Every repo behind the one in front of it — this is the normal starting state.

## Example: `make downstream-bump-ledger`

```
[deps/ledger-pin-contracts-104519f 47b0dba] chore(deps): pin traust-contracts@104519f
 2 files changed, 4 insertions(+), 4 deletions(-)
==> test traust-ledger
1004 passed, 14 skipped in 23.89s
traust-ledger: committed on deps/ledger-pin-contracts-104519f (chore(deps): pin traust-contracts@104519f)
```

`pyproject.toml` diff it produced:

```diff
-    "traust-contracts>=0.47.0",
+    "traust-contracts",
...
-traust-contracts = { git = "...traust-contracts.git", tag = "v0.48.1" }
+traust-contracts = { git = "...traust-contracts.git", rev = "104519fd18f724e121c492c160e3dc2d67408f90" }
```

`status` right after confirms ledger is current and shows engine/traust now
drifted off ledger's **new** HEAD (the branch tip, since nothing merged yet):

```
traust-ledger: HEAD 47b0dba  pins: traust-contracts=104519f (upstream 104519f)
traust-engine: HEAD 399bca3  pins: ..., traust-ledger=v0.8.5 (upstream 47b0dba DRIFT)
```

Nothing pushed. Branch sits locally for you to review:

```
git -C ../traust-ledger push -u origin deps/ledger-pin-contracts-104519f
```

## Full stacked-PR walk

```
make downstream-chain-pr
```

walks all three hops in order: pins, tests, commits, pushes, and opens a PR
against `traust-security/*` at each one before moving to the next. Each
hop's PR diffs against `main`, so engine's PR will show ledger's
not-yet-merged change too until ledger's PR lands — normal for stacked PRs,
just don't be surprised by it in review.

## After PRs merge: `make downstream-reconcile`

Merge-commit or fast-forward merges keep the pinned sha reachable from
`main` — no action needed. **Squash and rebase merges mint a new sha**, so
the branch-tip sha you pinned goes dangling the moment the upstream PR
merges. `reconcile`:

1. Reads `.chain-state.json` for each hop's tracked upstream PR number.
2. `gh pr view --json state,mergeCommit` on it.
3. Not merged yet → prints current state, no action.
4. Merged, same sha → prints "already canonical", no action.
5. Merged, different sha (squash/rebase) → re-pins to the real merge
   commit, `uv lock`, re-test, then:
   - hop's own PR still open → pushes the fix to that same branch
   - hop's own PR already merged too → prints a message telling you to
     run `make downstream-bump-<hop>` fresh instead of auto-chaining a new PR

## Fork safety (origin vs upstream)

Every repo here has two remotes: `origin` (your fork) and `upstream`
(`traust-security/*`). Three things that would otherwise silently use the
wrong one are guarded explicitly:

- **Shas are never trusted from raw local HEAD.** `verified_head()` fetches
  `origin` and requires local HEAD to equal `origin/main` or be a descendant
  of it (the normal state mid-chain, before you've pushed). A stale,
  diverged, or accidentally-checked-out-elsewhere repo raises instead of
  quietly pinning against whatever happened to be on disk. `status` does the
  same check read-only and flags it as `CHECKOUT-STALE` instead of raising.
- **`PinWriter` retargets the git URL, not just the rev.** Every repo's
  committed `uv.sources` points at `https://github.com/traust-security/*`
  (upstream) by default. This chain only ever pushes to `origin`. If the URL
  stayed pointed at upstream, `uv lock` would try to fetch the new sha from a
  remote that never received it and fail with `failed to find branch, tag,
  or commit <sha>` — hit this for real before the fix. `pin()` now rewrites
  both the url and the rev to `origin`'s slug.
- **Preflight checks the sha is actually on `origin` before locking.**
  `Git.remote_has()` fetches and checks `git branch -r --contains <sha>` for
  an `origin/*` ref. A hop whose upstream dep was bumped without `--push`
  fails fast with "push {dep}'s branch first", instead of a confusing `uv
  lock` git error three steps later.
- **`gh` calls are always `--repo`'d explicitly.** Left to its own defaults,
  `gh` prefers a remote literally named `upstream` over `origin` for repo
  resolution — confirmed here: `gh repo view` with no flags resolved to the
  upstream repo, not the fork, even though every branch this script creates
  is pushed to `origin` only. `origin_slug()`/`upstream_slug()` parse the
  real targets from `git remote get-url <remote>` so this can't drift.

## PRs target upstream, cross-repo

`gh pr create`/`gh pr view` target `upstream` (`traust-security/*`) as
`--repo`, with `--head <fork-owner>:<branch>` — head and base live in
different repos, so the owner qualifier on `--head` is required (gh silently
looks for the branch in the base repo otherwise). `uv.sources` pins still
target `origin` (the sha only ever lives on your fork until the PR merges) —
only the PR's repo target is `upstream`.

## Push is not optional past the first hop

`uv lock` resolves purely over the network from the URL in `uv.sources` —
it has no idea the sibling repo sits right there on disk. So **every hop
beyond the first needs its upstream dep already pushed to `origin`** before
it can succeed. `make downstream-chain` (no push) only really works for a
single hop whose dep is already fully in sync with `origin/main`; use `make
downstream-chain-push` or `downstream-chain-pr` as the normal way to run this
end to end.

The dirty-tree guard distinguishes three states, not two: unrelated local
changes block with an error; a previous failed attempt on this hop's own
branch resumes (re-tests, doesn't re-checkout); a hop whose branch is already
fully committed (and maybe already pushed) is detected and skipped straight
to the push/PR step instead of trying to re-commit nothing.

## Gate = `make test`, not a hardcoded pytest call

Each repo's `make test` differs and that difference matters:

| Repo | `make test` |
|---|---|
| contracts | `uv run pytest tests/ -q` |
| ledger | `uv run pytest tests/ -q -m "not integration"` |
| engine | `uv run pytest tests/ -q -m "not integration"` |
| traust | `uv run pytest tests/ -n auto` (parallel, pytest-xdist) |

A hardcoded `uv run pytest tests/ -q` for every hop would run slower than
necessary against traust (serial instead of `-n auto`) and, worse, run
integration tests against ledger/engine that their own `make test`
deliberately excludes. Every hop shells out to `make test` in that repo
instead, so the gate always matches what the repo itself considers "tests
pass."

## Known rough edges

- Doesn't touch inline comments next to a dropped floor (e.g. ledger's
  `# 0.1.1 is the floor...`) — glance at the diff per hop.
- `reconcile` won't auto-recurse past a hop whose own PR already merged;
  that's deliberate, keeps a human in the loop for cascades.
- Assumes `gh` is authenticated and the mono-checkout layout matches (sibling
  directories, `origin`/`upstream` remotes named as such).
