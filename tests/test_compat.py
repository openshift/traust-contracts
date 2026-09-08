"""Compatibility gates for schema versioning.

Breaking-change gate: no property removal, enum shrinkage, or new required
fields versus the previous git tag.

The vector-hash gate that pinned the golden-vector suite to a deterministic
digest was removed with the suite itself on 2026-08-18 (only the harness computes
identity, so there is no second-language port for a shared oracle to hold). The
recipe's regression fixtures now live in the ledger package, beside the
implementation they guard.
"""

import json
import os
import subprocess
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCHEMA_DIR = REPO_ROOT / "schemas" / "v1"


class TestBreakingChangeDetection:
    """Detect schema evolution breaking backward compatibility."""

    @staticmethod
    def _get_latest_tag() -> str:
        """Return the latest git tag (e.g., 'v0.1.0')."""
        try:
            result = subprocess.run(
                ["git", "describe", "--tags", "--abbrev=0"],
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
            return None

    @staticmethod
    def _extract_json_pointer_path(path_list: list) -> str:
        """Convert a path list to JSON pointer notation."""
        return "/" + "/".join(str(p) for p in path_list)

    @staticmethod
    def _walk_schema(schema: dict, path: list) -> list:
        """Yield (json_pointer, schema_node) for all nodes in schema."""
        results = []

        def walk(node: Any, current_path: list):
            if isinstance(node, dict):
                pointer = "/" + "/".join(str(p) for p in current_path) if current_path else ""
                results.append((pointer, node))
                for key, value in node.items():
                    if key not in ("$schema", "$id", "title", "description", "examples"):
                        walk(value, [*current_path, key])
            elif isinstance(node, list):
                for i, item in enumerate(node):
                    walk(item, [*current_path, i])

        walk(schema, path)
        return results

    @staticmethod
    def _collect_properties(node: dict) -> set:
        """Collect all property names from a schema node."""
        if "properties" in node and isinstance(node["properties"], dict):
            return set(node["properties"].keys())
        return set()

    @staticmethod
    def _collect_enum_values(node: dict) -> set:
        """Collect enum values from a schema node."""
        if "enum" in node and isinstance(node["enum"], list):
            return set(node["enum"])
        return set()

    @staticmethod
    def _collect_conditional_required(schema: dict) -> set:
        """Collect (json_pointer, frozenset[fields]) for every `required` that sits
        under a conditional construct — the paths the node-by-node diff cannot see
        when the whole construct is new."""
        found = set()
        # Only branches that IMPOSE obligations count. A requirement inside `if`
        # narrows which artifacts the rule applies to, so it can never invalidate
        # one — including it would bury the real signal in noise.
        enter = ("then", "else", "allOf", "anyOf", "oneOf", "dependentRequired", "dependentSchemas")

        def walk(node, path, under_conditional):
            if isinstance(node, dict):
                if under_conditional and isinstance(node.get("required"), list):
                    found.add(("/" + "/".join(str(p) for p in path), frozenset(node["required"])))
                for key, value in node.items():
                    if key == "if":
                        continue
                    walk(value, [*path, key], under_conditional or key in enter)
            elif isinstance(node, list):
                for i, item in enumerate(node):
                    walk(item, [*path, i], under_conditional)

        walk(schema, [], False)
        return found

    @staticmethod
    def _collect_required(node: dict) -> set:
        """Collect required field names."""
        if "required" in node and isinstance(node["required"], list):
            return set(node["required"])
        return set()

    @pytest.mark.skipif(
        os.getenv("CONTRACTS_ALLOW_BREAKING") == "1",
        reason="Skipped when CONTRACTS_ALLOW_BREAKING=1",
    )
    def test_no_breaking_changes_vs_previous_tag(self):
        """Detect breaking schema changes: property removal, enum shrinkage, new required fields.

        Breaking changes (require MAJOR version bump):
        - Removing a property from a 'properties' object
        - Removing a value from an 'enum' array
        - Adding a new field to 'required'

        Allowed (MINOR/PATCH):
        - Adding properties
        - Adding enum values
        - Removing from required
        - Documentation changes

        If this fails: you have a breaking change. Bump VERSION to the next MAJOR
        and tag accordingly.
        """
        latest_tag = self._get_latest_tag()
        if not latest_tag:
            pytest.skip("No prior git tag found")

        breaking_changes = []

        for schema_file in sorted(SCHEMA_DIR.glob("*.schema.json")):
            # Fetch schema from the previous tag. Try the current (versioned) path first;
            # fall back to the pre-v1 unversioned path so the one-time schemas/ -> schemas/v1/
            # move doesn't make every schema look "new" and silently skip the gate.
            candidate_paths = [
                schema_file.relative_to(REPO_ROOT),
                Path("schemas") / schema_file.name,
            ]
            old_schema = None
            for candidate in candidate_paths:
                try:
                    result = subprocess.run(
                        ["git", "show", f"{latest_tag}:{candidate}"],
                        cwd=REPO_ROOT,
                        capture_output=True,
                        text=True,
                        check=True,
                    )
                    old_schema = json.loads(result.stdout)
                    break
                except subprocess.CalledProcessError:
                    continue
            if old_schema is None:
                # Schema didn't exist in previous tag under any known path — not a breaking change
                continue

            # Load current schema
            current_schema = json.loads(schema_file.read_text(encoding="utf-8"))

            # Walk both and compare
            old_nodes = {path: node for path, node in self._walk_schema(old_schema, [])}
            current_nodes = {path: node for path, node in self._walk_schema(current_schema, [])}

            for path, old_node in old_nodes.items():
                current_node = current_nodes.get(path)
                if not current_node:
                    continue

                # Check: removed properties
                old_props = self._collect_properties(old_node)
                new_props = self._collect_properties(current_node)
                removed = old_props - new_props
                if removed:
                    breaking_changes.append(
                        f"{schema_file.name}{path}: removed properties: {removed}"
                    )

                # Check: removed enum values
                old_enum = self._collect_enum_values(old_node)
                new_enum = self._collect_enum_values(current_node)
                if old_enum and new_enum:
                    removed_enum = old_enum - new_enum
                    if removed_enum:
                        breaking_changes.append(
                            f"{schema_file.name}{path}: removed enum values: {removed_enum}"
                        )

                # Check: new required fields
                old_required = self._collect_required(old_node)
                new_required = self._collect_required(current_node)
                new_req = new_required - old_required
                if new_req:
                    breaking_changes.append(
                        f"{schema_file.name}{path}: new required fields: {new_req}"
                    )

            # Check: newly introduced conditional requirements (if/then, allOf, oneOf,
            # dependentRequired). Node-by-node comparison above only sees paths present
            # in BOTH versions, so a brand-new conditional rule slips past it — yet a
            # conditional `required` rejects artifacts just as hard as a root one.
            old_conds = self._collect_conditional_required(old_schema)
            new_conds = self._collect_conditional_required(current_schema)
            for pointer, fields in sorted(new_conds - old_conds):
                breaking_changes.append(
                    f"{schema_file.name}{pointer}: new conditional requirement: {fields} "
                    "(artifacts not satisfying it become invalid)"
                )

        if breaking_changes:
            msg = "Breaking schema changes detected — requires MAJOR version bump and new tag:\n"
            for change in breaking_changes:
                msg += f"  - {change}\n"
            pytest.fail(msg)
