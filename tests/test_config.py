"""Config resolution and load_context behavior."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest
import yaml

from traust_contracts.config import (
    MANIFEST,
    TRAUST_CONFIG_HOME_ENV,
    DeploymentConfigMissing,
    config_completeness_audit,
    config_path,
    deployment_config_dir,
    load_context,
    load_section,
    optional_config_path,
)

_TRAUST_FIXTURES = Path(__file__).resolve().parents[2] / "traust" / "tests" / "fixtures" / "config"


def _write_minimal_config(home: Path) -> None:
    shutil.copytree(_TRAUST_FIXTURES, home, dirs_exist_ok=True)


def test_manifest_covers_harness_context_sections():
    manifest_sections = {entry.section for entry in MANIFEST}
    required = {
        "feeds",
        "external_tools",
        "model_registry",
        "corpus",
        "safe_exec",
        "signing_pubkey",
        "locations",
        "budget_policy",
        "product_map",
        "rule_pack_allowlist",
        "internal_vocabulary",
        "hardening_risk_weights",
        "rpm_distgit_watch",
    }
    assert manifest_sections == required


def test_deployment_config_dir_honors_env(tmp_path, monkeypatch):
    home = tmp_path / "cfg"
    home.mkdir()
    monkeypatch.setenv(TRAUST_CONFIG_HOME_ENV, str(home))
    assert deployment_config_dir() == home


def test_load_context_resolves_relative_locations(tmp_path):
    home = tmp_path / "cfg"
    ws = tmp_path / "workspace"
    ar = tmp_path / "analysis-results"
    ws.mkdir()
    ar.mkdir()
    _write_minimal_config(home)
    (home / "locations.yaml").write_text(
        yaml.safe_dump(
            {
                "workspace": "../workspace",
                "analysis_results": "../analysis-results",
            }
        ),
        encoding="utf-8",
    )
    ctx = load_context(config_home=home)
    assert ctx.locations is not None
    assert ctx.locations.workspace == str(ws.resolve())
    assert ctx.locations.analysis_results == str(ar.resolve())


def test_load_section_locations_empty_file_loads(tmp_path):
    home = tmp_path / "cfg"
    _write_minimal_config(home)
    (home / "locations.yaml").write_text("{}\n", encoding="utf-8")
    loc = load_section("locations.yaml", config_home=home)
    assert loc is not None
    assert loc.progress_tracker is None


def test_config_completeness_flags_empty_corpus(tmp_path):
    home = tmp_path / "cfg"
    _write_minimal_config(home)
    (home / "corpus-config.yaml").write_text("version: 1\ntrees: {}\n", encoding="utf-8")
    errors, _warnings = config_completeness_audit(config_home=home)
    assert any("trees is empty" in e for e in errors)
    assert load_context(config_home=home).corpus.trees == {}


def test_config_completeness_warns_on_example_vocabulary(tmp_path):
    home = tmp_path / "cfg"
    _write_minimal_config(home)
    _, warnings = config_completeness_audit(config_home=home)
    assert any("yourorg.invalid" in w for w in warnings)
    assert any("rule-pack-allowlist" in w for w in warnings)
    assert any("1970-01-01" in w for w in warnings)


def test_config_path_and_optional(tmp_path, monkeypatch):
    home = tmp_path / "cfg"
    _write_minimal_config(home)
    monkeypatch.setenv(TRAUST_CONFIG_HOME_ENV, str(home))
    assert config_path("feeds.yaml") == home / "feeds.yaml"
    assert optional_config_path("locations.yaml") is None
    (home / "locations.yaml").write_text("workspace: /x\n", encoding="utf-8")
    assert optional_config_path("locations.yaml") == home / "locations.yaml"


def test_load_section_locations_normalizes(tmp_path):
    home = tmp_path / "cfg"
    ws = tmp_path / "workspace"
    ws.mkdir()
    _write_minimal_config(home)
    (home / "locations.yaml").write_text(
        yaml.safe_dump({"workspace": "../workspace"}),
        encoding="utf-8",
    )
    loc = load_section("locations.yaml", config_home=home)
    assert loc.workspace == str(ws.resolve())


def test_config_path_fails_when_home_unset(monkeypatch):
    monkeypatch.setattr("traust_contracts.config.deployment_config_dir", lambda: None)
    with pytest.raises(DeploymentConfigMissing, match=r"feeds.yaml"):
        config_path("feeds.yaml")
