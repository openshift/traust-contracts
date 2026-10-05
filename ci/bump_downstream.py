#!/usr/bin/env python3
"""Bump the traust-security downstream pin chain: contracts -> ledger ->
engine -> traust.

Lives in traust-contracts because contracts sits at the root of the chain --
every one of ledger, engine, and traust carries a direct `[tool.uv.sources]`
pin on contracts (not just a transitive one through each other), so a
contracts change is the most common trigger for this whole walk. Run it from
here; it drives the sibling repos on disk, same as `make bump-downstream`
below.

Local-only, no CI dependency. Each hop:
  1. resolve the upstream sibling's current HEAD sha
  2. rewrite this repo's uv.sources pin to that sha (tag/rev -> rev)
  3. drop the floor version in [project.dependencies] (the rev is the floor now)
  4. uv lock
  5. `make test` -- the gate, via the repo's OWN Makefile target, not a
     hardcoded pytest invocation (each repo's test target differs: xdist
     parallelism, `-m "not integration"` filters, etc. -- a generic pytest
     call either runs slower or runs tests the repo itself excludes). A
     failure here IS the breaking-change signal; it stops propagation
     instead of a changelog entry you have to go read and interpret.
  6. commit on a fresh, hop-named branch

With --push, each hop's branch is pushed. With --open-pr (implies --push),
`gh pr create` opens the PR against main and the PR number is recorded in
.chain-state.json, keyed by repo name.

Squash/rebase merges mint a new commit on main that doesn't match the PR
branch tip you pinned -- the pin goes dangling the moment the upstream PR
merges. `reconcile` checks .chain-state.json's tracked PRs via `gh pr view`;
if merged with a different commit than what's pinned, it re-pins to the
actual merge commit, re-tests, and pushes an update to the hop's own still-
open PR branch (or tells you to re-run `bump` if that PR already merged too).

Assumes the mono-checkout layout: this repo and ledger/engine/traust are
sibling directories (default ROOT is computed from this file's own location:
`ci/bump_downstream.py` -> `traust-contracts` -> its parent is ROOT; override
with the `TRAUST_CHAIN_ROOT` env var if your checkout differs). This never
touches the network except through `uv lock`, `git push`, and `gh`.

usage (run from this repo's root, or `make bump-downstream` etc.):
  python3 ci/bump_downstream.py status
  python3 ci/bump_downstream.py bump ledger|engine|traust [--push] [--open-pr]
  python3 ci/bump_downstream.py chain [--push] [--open-pr]
  python3 ci/bump_downstream.py reconcile [ledger|engine|traust]
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

ROOT = (
    Path(os.environ["TRAUST_CHAIN_ROOT"])
    if "TRAUST_CHAIN_ROOT" in os.environ
    else Path(__file__).resolve().parents[2]
)
STATE_FILE = Path(__file__).resolve().parent / ".chain-state.json"


class ChainError(Exception):
    pass


# --- Persisted PR tracking (survives across runs/days) ---


def load_state() -> dict[str, dict]:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def save_state(state: dict[str, dict]) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


# --- Git (minimal; same shape as each repo's own release.py Git class) ---


class Git:
    def __init__(self, cwd: Path) -> None:
        self.cwd = cwd

    def _run(self, *args: str, capture: bool = False) -> subprocess.CompletedProcess[str]:
        return subprocess.run(args, cwd=self.cwd, text=True, check=True, capture_output=capture)

    def head(self) -> str:
        return self._run("git", "rev-parse", "HEAD", capture=True).stdout.strip()

    def status(self) -> str:
        return self._run("git", "status", "--porcelain", capture=True).stdout.strip()

    @property
    def dirty(self) -> bool:
        return bool(self.status())

    def current_branch(self) -> str:
        return self._run("git", "rev-parse", "--abbrev-ref", "HEAD", capture=True).stdout.strip()

    def fetch(self, remote: str = "origin") -> None:
        self._run("git", "fetch", remote, "--quiet")

    def rev_parse(self, ref: str) -> str:
        return self._run("git", "rev-parse", ref, capture=True).stdout.strip()

    def is_descendant_of(self, ref: str) -> bool:
        """True if HEAD is ref itself or strictly ahead of it (ref is an ancestor)."""
        return (
            subprocess.run(
                ("git", "merge-base", "--is-ancestor", ref, "HEAD"),
                cwd=self.cwd,
                check=False,
            ).returncode
            == 0
        )

    def remote_has(self, sha: str, remote: str = "origin") -> bool:
        """True if some ref on `remote` (after fetching it) contains sha.

        A local commit existing is not enough -- uv.lock fetches over the
        network from whatever URL is in uv.sources, so the sha has to
        actually be reachable on that remote, not just sitting in your local
        working tree on an unpushed branch.
        """
        self.fetch(remote)
        out = self._run("git", "branch", "-r", "--contains", sha, capture=True).stdout
        return any(line.strip().startswith(f"{remote}/") for line in out.splitlines())

    def checkout_new(self, branch: str) -> None:
        self._run("git", "checkout", "-b", branch)

    def checkout(self, branch: str) -> None:
        self._run("git", "checkout", branch)

    def commit(self, message: str) -> None:
        self._run("git", "commit", "-am", message)

    def push(self, branch: str) -> None:
        self._run("git", "push", "-u", "origin", branch)


def verified_head(repo: str) -> str:
    """HEAD sha for a sibling repo, guarded against a stale/wrong checkout.

    Fetches origin (your fork -- the authoritative remote for this chain, see
    README) and refuses to trust local HEAD unless it IS origin/main or is
    strictly ahead of it (the expected state mid-chain, before you've pushed).
    Anything else -- diverged, behind, detached on an unrelated branch --
    raises instead of silently pinning against it.
    """
    git = Git(ROOT / repo)
    git.fetch("origin")
    origin_main = git.rev_parse("origin/main")
    if git.head() == origin_main or git.is_descendant_of(origin_main):
        return git.head()
    raise ChainError(
        f"{repo}: local checkout does not match origin/main and is not ahead of it "
        f"(local {short(git.head())}, origin/main {short(origin_main)}) -- "
        f"fetch/checkout main before bumping, this pin would be inaccurate"
    )


def _remote_slug(repo: str, remote: str) -> str:
    url = Git(ROOT / repo)._run("git", "remote", "get-url", remote, capture=True).stdout.strip()
    m = re.search(r"[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
    if not m:
        raise ChainError(f"{repo}: could not parse owner/repo from {remote} url {url!r}")
    return m.group(1)


def origin_slug(repo: str) -> str:
    """owner/repo for this sibling's `origin` remote (your fork). Still used
    for pinning uv.sources -- the sha only ever lives on your fork."""
    return _remote_slug(repo, "origin")


def upstream_slug(repo: str) -> str:
    """owner/repo for this sibling's `upstream` remote (traust-security/*).
    PRs open here, cross-repo, with an owner-qualified head."""
    return _remote_slug(repo, "upstream")


# --- gh (PR open + merge-state lookup; cwd-scoped, same as uv/git above) ---
#     Always --repo'd explicitly to `origin`'s slug: a remote literally named
#     `upstream` (traust-security/*) outranks `origin` in gh's own default
#     resolution, but this chain only ever pushes to `origin` (your fork) --
#     letting gh pick its own default silently targets the wrong repo.


def gh_pr_create(path: Path, repo: str, branch: str, title: str, body: str) -> int:
    """Opens cross-repo: base is `upstream` (traust-security/*), head is this
    fork's branch, owner-qualified (`<fork-owner>:branch`) since head and base
    live in different repos."""
    fork_owner = origin_slug(repo).split("/", 1)[0]
    out = subprocess.run(
        (
            "gh",
            "pr",
            "create",
            "--repo",
            upstream_slug(repo),
            "--base",
            "main",
            "--head",
            f"{fork_owner}:{branch}",
            "--title",
            title,
            "--body",
            body,
        ),
        cwd=path,
        text=True,
        check=True,
        capture_output=True,
    ).stdout.strip()
    return int(out.rstrip("/").split("/")[-1])


def gh_pr_view(path: Path, repo: str, pr_number: int) -> dict:
    out = subprocess.run(
        (
            "gh",
            "pr",
            "view",
            str(pr_number),
            "--repo",
            upstream_slug(repo),
            "--json",
            "state,mergeCommit,headRefOid,url",
        ),
        cwd=path,
        text=True,
        check=True,
        capture_output=True,
    ).stdout
    return json.loads(out)


def short(sha: str) -> str:
    return sha[:7]


# --- Chain topology ---


@dataclass(frozen=True)
class Hop:
    """One repo in the propagation chain and what it pins from upstream."""

    name: str
    pins: tuple[str, ...]  # package names this repo's uv.sources pins

    @property
    def path(self) -> Path:
        return ROOT / self.name

    @property
    def trigger(self) -> str | None:
        """Most-direct upstream dep -- names the branch and short-circuits status."""
        return self.pins[-1] if self.pins else None


CHAIN: tuple[Hop, ...] = (
    Hop("traust-contracts", pins=()),
    Hop("traust-ledger", pins=("traust-contracts",)),
    Hop("traust-engine", pins=("traust-contracts", "traust-ledger")),
    Hop("traust", pins=("traust-contracts", "traust-ledger", "traust-engine")),
)

_NAMES = [h.name for h in CHAIN]


def resolve_shas(upto: str) -> dict[str, str]:
    """Verified HEAD sha for every hop from traust-contracts through `upto`."""
    idx = _NAMES.index(upto)
    return {name: verified_head(name) for name in _NAMES[: idx + 1]}


# --- Pin rewriting (regex over the TOML text, same style as release.py's
#     VERSION_LINE substitution -- no TOML writer round-trip, no comment loss) ---


class PinWriter:
    """Rewrites one dependency's uv.sources entry: rev AND the git URL itself.

    The URL matters as much as the rev: this chain only ever pushes to
    `origin` (your fork), never `upstream`. If the URL stayed pointed at
    `upstream` (traust-security/*, the repo's committed default), `uv lock`
    would try to fetch the new sha from a remote that never received it and
    fail with a confusing git error. Retargeting to `origin`'s slug makes the
    just-pushed commit the one `uv lock` actually finds.
    """

    def __init__(self, pyproject: Path) -> None:
        self.pyproject = pyproject

    def current_pin(self, dep: str) -> str | None:
        text = self.pyproject.read_text()
        m = re.search(rf'{re.escape(dep)}\s*=\s*\{{[^}}]*?(?:tag|rev)\s*=\s*"([^"]+)"', text)
        return m.group(1) if m else None

    def pin(self, dep: str, sha: str) -> bool:
        text = self.pyproject.read_text()
        updated = self._retarget_url(text, dep, f"https://github.com/{origin_slug(dep)}.git")
        updated = self._pin_source(updated, dep, sha)
        updated = self._drop_floor(updated, dep)
        changed = updated != text
        if changed:
            self.pyproject.write_text(updated)
        return changed

    @staticmethod
    def _retarget_url(text: str, dep: str, url: str) -> str:
        pattern = re.compile(rf'({re.escape(dep)}\s*=\s*\{{\s*git\s*=\s*)"[^"]+"')
        if not pattern.search(text):
            raise ChainError(f"no [tool.uv.sources] git url for {dep!r}")
        return pattern.sub(rf'\g<1>"{url}"', text, count=1)

    @staticmethod
    def _pin_source(text: str, dep: str, sha: str) -> str:
        pattern = re.compile(rf'({re.escape(dep)}\s*=\s*\{{[^}}]*?)(?:tag|rev)(\s*=\s*)"[^"]+"')
        if not pattern.search(text):
            raise ChainError(f"no [tool.uv.sources] entry for {dep!r}")
        return pattern.sub(rf'\g<1>rev\g<2>"{sha}"', text, count=1)

    @staticmethod
    def _drop_floor(text: str, dep: str) -> str:
        pattern = re.compile(rf'"{re.escape(dep)}(?:[><=!~][^"]*)?"')
        return pattern.sub(f'"{dep}"', text, count=1)


# --- Bump strategy ---


class Bumper:
    """Advances one hop's pins and gates on its own test suite."""

    def __init__(self, hop: Hop, shas: dict[str, str]) -> None:
        self.hop = hop
        self.shas = shas  # dep name -> sha, covers every pin this hop needs

    def branch_name(self, trigger_sha: str) -> str:
        trigger = self.hop.trigger.removeprefix("traust-")  # type: ignore[union-attr]
        return f"deps/{self.hop.name.removeprefix('traust-')}-pin-{trigger}-{short(trigger_sha)}"

    def run(self, *, push: bool = False, open_pr: bool = False) -> bool:
        """Four states, not two:

        1. not resuming, no diff      -> fully done already (e.g. merged
           upstream), nothing to do, no branch to touch.
        2. not resuming, diff         -> fresh hop: new branch, lock, test,
           commit.
        3. resuming, tree was dirty   -> a PREVIOUS run's lock/test/commit
           failed partway; redo lock+test+commit on the same branch.
        4. resuming, tree was clean   -> this branch already has everything
           committed from a previous run (possibly already pushed too) --
           re-running lock/test/commit here would try to `git commit` with
           nothing staged and fail. Just (idempotently) push/open-PR and stop.
        """
        push = push or open_pr  # a PR needs a pushed branch
        path = self.hop.path
        git = Git(path)
        branch = self.branch_name(self.shas[self.hop.trigger])  # type: ignore[index]
        resuming = git.current_branch() == branch
        was_dirty = git.dirty

        if was_dirty and not resuming:
            raise ChainError(
                f"{self.hop.name}: working tree not clean, aborting (not on this hop's "
                f"branch {branch!r} -- commit or stash those unrelated changes first; "
                f"if they ARE this hop, `git checkout {branch}` and retry)"
            )

        for dep in self.hop.pins:
            if not Git(ROOT / dep).remote_has(self.shas[dep]):
                raise ChainError(
                    f"{self.hop.name}: {dep}@{short(self.shas[dep])} isn't on origin yet -- "
                    f"`uv lock` would fail trying to fetch it. Push {dep}'s branch first "
                    f"(bump/chain with --push), then retry this hop."
                )

        writer = PinWriter(path / "pyproject.toml")
        changed = [dep for dep in self.hop.pins if writer.pin(dep, self.shas[dep])]

        if not resuming and not changed:  # case 1
            print(f"{self.hop.name}: pins already current")
            return True

        if resuming and not was_dirty and not changed:  # case 4
            print(f"{self.hop.name}: {branch} already complete, nothing to redo")
            return self._finalize(git, branch, push=push, open_pr=open_pr, changed=self.hop.pins)

        if resuming:  # case 3
            print(
                f"{self.hop.name}: resuming in-flight branch {branch} (previously failed the gate)"
            )
        else:  # case 2
            git.checkout_new(branch)
        subprocess.run(("uv", "lock"), cwd=path, check=True)

        print(f"==> test {self.hop.name}")
        try:
            subprocess.run(("make", "test"), cwd=path, check=True)
        except subprocess.CalledProcessError:
            print(
                f"{self.hop.name}: FAILED on {branch} -- fix before propagating further "
                f"(pyproject.toml + uv.lock left modified, not committed; fix and re-run "
                f"this same hop to resume)",
                file=sys.stderr,
            )
            return False

        changed = changed or self.hop.pins
        message = "chore(deps): pin " + ", ".join(f"{d}@{short(self.shas[d])}" for d in changed)
        git.commit(message)
        print(f"{self.hop.name}: committed on {branch} ({message})")

        return self._finalize(git, branch, push=push, open_pr=open_pr, changed=changed)

    def _finalize(
        self,
        git: Git,
        branch: str,
        *,
        push: bool,
        open_pr: bool,
        changed: Sequence[str],
    ) -> bool:
        """Push (idempotent -- a no-op if the remote already has this branch's
        tip) and open-or-skip a PR. Shared by the normal path and case 4 above.
        """
        if not push:
            return True
        git.push(branch)
        print(f"{self.hop.name}: pushed {branch}")

        state = load_state()
        record = state.get(self.hop.name) or {}
        record.update(
            {
                "branch": branch,
                "dep": self.hop.trigger,
                "head_sha": self.shas[self.hop.trigger],
            }
        )
        if open_pr:
            if record.get("pr") and record.get("branch") == branch:
                print(f"{self.hop.name}: PR #{record['pr']} already open for {branch}")
            else:
                title = "chore(deps): pin " + ", ".join(
                    f"{d}@{short(self.shas[d])}" for d in changed
                )
                body = (
                    "Automated pin bump via traust-contracts/ci/bump_downstream.py.\n\nTracks: "
                    + ", ".join(f"{d}@{self.shas[d]}" for d in changed)
                )
                pr_number = gh_pr_create(git.cwd, self.hop.name, branch, title, body)
                record["pr"] = pr_number
                print(f"{self.hop.name}: opened PR #{pr_number}")
        state[self.hop.name] = record
        save_state(state)
        return True


# --- Reconcile: tracked PR merged with a different sha than what's pinned ---


def reconcile_hop(hop: Hop, state: dict[str, dict]) -> None:
    dep = hop.trigger
    dep_record = state.get(dep)  # type: ignore[arg-type]
    if dep_record is None or "pr" not in dep_record:
        print(f"{hop.name}: no tracked PR for {dep}, nothing to reconcile")
        return

    info = gh_pr_view(ROOT / dep, dep, dep_record["pr"])
    if info["state"] != "MERGED":
        print(
            f"{hop.name}: {dep} PR #{dep_record['pr']} still {info['state'].lower()}, pin unchanged"
        )
        return

    merged_sha = (info.get("mergeCommit") or {}).get("oid")
    pinned_sha = dep_record["head_sha"]
    if not merged_sha or merged_sha == pinned_sha:
        print(
            f"{hop.name}: {dep} merged as a fast-forward, pin {short(pinned_sha)} already canonical"
        )
        return

    print(
        f"{hop.name}: {dep} PR #{dep_record['pr']} merged via squash/rebase -- "
        f"pin {short(pinned_sha)} is dangling, re-pinning to merge commit {short(merged_sha)}"
    )

    shas = {dep: merged_sha}
    for other in hop.pins:
        if other != dep:
            shas[other] = (state.get(other) or {}).get("head_sha") or Git(ROOT / other).head()

    path = hop.path
    git = Git(path)
    hop_record = state.get(hop.name)

    if hop_record and hop_record.get("pr"):
        own_info = gh_pr_view(path, hop.name, hop_record["pr"])
        if own_info["state"] == "MERGED":
            print(
                f"{hop.name}: its own PR #{hop_record['pr']} already merged too -- "
                f"run `bump {hop.name.removeprefix('traust-')}` fresh to open a new reconciliation PR"
            )
            return
        if git.dirty:
            raise ChainError(f"{hop.name}: working tree not clean, aborting reconcile")
        git.checkout(hop_record["branch"])
        branch = hop_record["branch"]
    else:
        if git.dirty:
            raise ChainError(f"{hop.name}: working tree not clean, aborting reconcile")
        branch = Bumper(hop, shas).branch_name(merged_sha)
        git.checkout_new(branch)

    writer = PinWriter(path / "pyproject.toml")
    changed = [d for d in hop.pins if writer.pin(d, shas[d])]
    if not changed:
        print(f"{hop.name}: pin already matches, nothing to commit")
        return

    subprocess.run(("uv", "lock"), cwd=path, check=True)
    print(f"==> test {hop.name}")
    subprocess.run(("make", "test"), cwd=path, check=True)

    git.commit(f"chore(deps): reconcile pin to merged {dep}@{short(merged_sha)}")
    print(f"{hop.name}: committed reconciliation on {branch}")

    git.push(branch)
    if hop_record and hop_record.get("pr"):
        print(f"{hop.name}: pushed update to existing PR #{hop_record['pr']}")
    else:
        body = f"Reconciles pin after {dep} PR #{dep_record['pr']} merged via squash/rebase."
        pr_number = gh_pr_create(
            path,
            hop.name,
            branch,
            f"chore(deps): reconcile {dep}@{short(merged_sha)}",
            body,
        )
        print(f"{hop.name}: opened reconciliation PR #{pr_number}")
        hop_record = {"pr": pr_number}

    state[hop.name] = {
        **(hop_record or {}),
        "branch": branch,
        "dep": dep,
        "head_sha": merged_sha,
    }
    save_state(state)


def cmd_reconcile(target: str | None) -> int:
    state = load_state()
    hops = (
        [h for h in CHAIN if h.pins]
        if target is None
        else [next(h for h in CHAIN if h.name == target or h.name == f"traust-{target}")]
    )
    for hop in hops:
        reconcile_hop(hop, state)
    return 0


# --- CLI ---


def cmd_status() -> int:
    """Read-only -- never raises on a stale checkout, just flags it as CHECKOUT
    instead of silently reporting a sha that doesn't match origin/main."""
    for hop in CHAIN:
        git = Git(hop.path)
        git.fetch("origin")
        local = git.head()
        origin_main = git.rev_parse("origin/main")
        checkout_note = (
            "" if local == origin_main or git.is_descendant_of(origin_main) else " CHECKOUT-STALE"
        )
        if not hop.pins:
            print(f"{hop.name}: HEAD {short(local)}{checkout_note}")
            continue
        writer = PinWriter(hop.path / "pyproject.toml")
        drift = []
        for dep in hop.pins:
            dep_git = Git(ROOT / dep)
            dep_git.fetch("origin")
            upstream = short(dep_git.rev_parse("origin/main"))
            pinned = writer.current_pin(dep) or "?"
            pinned_short = pinned if not re.match(r"^[0-9a-f]{7,40}$", pinned) else short(pinned)
            flag = "" if pinned_short.lstrip("v") == upstream else " DRIFT"
            drift.append(f"{dep}=origin/main:{upstream}{flag} (pinned {pinned_short})")
        print(f"{hop.name}: HEAD {short(local)}{checkout_note}  pins: " + ", ".join(drift))
    return 0


def cmd_bump(target: str, *, push: bool, open_pr: bool = False) -> int:
    hop = next((h for h in CHAIN if h.name == target or h.name == f"traust-{target}"), None)
    if hop is None or not hop.pins:
        raise ChainError(f"no such bump target: {target!r}")
    shas = resolve_shas(upto=hop.trigger)  # type: ignore[arg-type]
    return 0 if Bumper(hop, shas).run(push=push, open_pr=open_pr) else 1


def cmd_chain(*, push: bool, open_pr: bool = False) -> int:
    for hop in CHAIN:
        if not hop.pins:
            continue
        shas = resolve_shas(upto=hop.trigger)  # type: ignore[arg-type]
        if not Bumper(hop, shas).run(push=push, open_pr=open_pr):
            return 1
    return 0


def main(argv: list[str] | None = None) -> int:
    import argparse

    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status")

    bump = sub.add_parser("bump")
    bump.add_argument("target", choices=["ledger", "engine", "traust"])
    bump.add_argument("--push", action="store_true")
    bump.add_argument("--open-pr", action="store_true")

    chain = sub.add_parser("chain")
    chain.add_argument("--push", action="store_true")
    chain.add_argument("--open-pr", action="store_true")

    reconcile = sub.add_parser("reconcile")
    reconcile.add_argument(
        "target", nargs="?", choices=["ledger", "engine", "traust"], default=None
    )

    args = p.parse_args(argv)

    try:
        match args.cmd:
            case "status":
                return cmd_status()
            case "bump":
                return cmd_bump(args.target, push=args.push, open_pr=args.open_pr)
            case "chain":
                return cmd_chain(push=args.push, open_pr=args.open_pr)
            case "reconcile":
                return cmd_reconcile(args.target)
    except ChainError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        print(f"error: command failed ({exc.cmd})", file=sys.stderr)
        return exc.returncode or 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
