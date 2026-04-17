"""End-to-end tests for `cmd_init_repo` filtering pipeline.

Covers Stories 6 (backward-compat) and 8 (acceptance scenarios).
Each test builds a fixture repo under `tmp_path`, invokes
`cmd_init_repo` via a thin Namespace, captures stdout, and asserts
shape of both stdout and the produced state pickle.
"""

import argparse
import contextlib
import io
import os
import pickle
import stat
from pathlib import Path

import pytest

import rlm_repl


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_args(repo_path: Path, state_path: Path, **overrides):
    """Build an argparse.Namespace matching what `p_init_repo` produces."""
    defaults = {
        "repo_path": str(repo_path),
        "state": str(state_path),
        "max_file_size_mb": 10,
        "exclude": [],
        "include": [],
        "exclude_from": None,
        "no_rlmignore": False,
    }
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def _run_init_repo(args) -> str:
    """Run cmd_init_repo, capture stdout, return captured output."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = rlm_repl.cmd_init_repo(args)
    assert rc == 0, f"cmd_init_repo returned {rc}"
    return buf.getvalue()


def _build_tiny_repo(root: Path) -> None:
    """A minimal 3-file repo with no .git for fallback discovery."""
    (root / "a.py").write_text("x = 1\n")
    (root / "b.js").write_text("var y = 2;\n")
    (root / "c.md").write_text("# hello\n")


def _no_filter_lines(text: str) -> bool:
    """Return True if stdout contains none of the filter summary markers."""
    return ("Excluded:" not in text) and ("Allowlist" not in text)


# ---------------------------------------------------------------------------
# Story 6: Backward compatibility
# ---------------------------------------------------------------------------

class TestBackwardCompat:
    def test_no_flags_produces_no_filter_lines(self, tmp_path: Path):
        repo = tmp_path / "repo"
        repo.mkdir()
        _build_tiny_repo(repo)
        state = tmp_path / "state.pkl"

        out = _run_init_repo(_make_args(repo, state))
        assert _no_filter_lines(out), f"unexpected filter lines in:\n{out}"

    def test_no_flags_pickle_structurally_matches_baseline(self, tmp_path: Path):
        # 6.2: pickle structure unchanged — same top-level keys, same file
        # count, same language breakdown (modulo timestamps).
        repo = tmp_path / "repo"
        repo.mkdir()
        _build_tiny_repo(repo)
        state = tmp_path / "state.pkl"
        _run_init_repo(_make_args(repo, state))

        with open(state, "rb") as f:
            payload = pickle.load(f)

        assert set(payload.keys()) == {
            "version", "context", "buffers", "globals", "repo_index"
        }
        idx = payload["repo_index"]
        assert set(idx.keys()) >= {
            "repo_root", "indexed_at", "total_files", "total_size",
            "files", "languages",
        }
        assert idx["total_files"] == 3
        # Languages: Python, JavaScript, Markdown expected
        langs = set(idx["languages"].keys())
        assert any("Python" in lang for lang in langs)

    def test_fallback_walker_parity_with_exclude(self, tmp_path: Path):
        # 6.3: without a .git directory, the fallback walker is used;
        # confirm `--exclude vendor/**` drops the same files the git
        # path would have dropped.
        repo = tmp_path / "repo"
        repo.mkdir()
        (repo / "src").mkdir()
        (repo / "vendor").mkdir()
        (repo / "src" / "main.py").write_text("x = 1\n")
        (repo / "src" / "util.py").write_text("y = 2\n")
        (repo / "vendor" / "lib.py").write_text("z = 3\n")
        (repo / "vendor" / "helper.py").write_text("w = 4\n")
        state = tmp_path / "state.pkl"

        out = _run_init_repo(
            _make_args(repo, state, exclude=["vendor/**"])
        )
        with open(state, "rb") as f:
            idx = pickle.load(f)["repo_index"]
        # Only src/main.py and src/util.py should remain
        kept = set(idx["files"].keys())
        assert kept == {"src/main.py", "src/util.py"}
        assert "Excluded: 2" in out


# ---------------------------------------------------------------------------
# Story 8: Acceptance scenarios
# ---------------------------------------------------------------------------

class TestVendorHeavy:
    def test_vendor_heavy_repo_104_nonvendor_plus_many_vendor(self, tmp_path: Path):
        # 8.1 — scaled-down from 17k to 1k to keep test fast on CI.
        repo = tmp_path / "repo"
        repo.mkdir()
        (repo / "src").mkdir()
        (repo / "html").mkdir()
        # 104 real files
        for i in range(104):
            (repo / "src" / f"f{i:03d}.py").write_text(f"x = {i}\n")
        # 1_000 vendor files (fast enough for unit tests)
        N_VENDOR = 1000
        for i in range(N_VENDOR):
            (repo / "html" / f"v{i:04d}.php").write_text("<?php ?>")
        state = tmp_path / "state.pkl"

        out = _run_init_repo(
            _make_args(repo, state, exclude=["html/**"])
        )
        with open(state, "rb") as f:
            idx = pickle.load(f)["repo_index"]

        assert idx["total_files"] == 104
        assert f"{N_VENDOR}" in out
        assert "html/**" in out
        # No vendor files in the index
        assert not any(k.startswith("html/") for k in idx["files"].keys())


class TestRlmignoreAutoDiscovery:
    def test_rlmignore_in_repo_root_auto_discovered(self, tmp_path: Path):
        # 8.2
        repo = tmp_path / "repo"
        repo.mkdir()
        (repo / "html").mkdir()
        (repo / "src").mkdir()
        (repo / "html" / "a.php").write_text("<?php ?>")
        (repo / "html" / "b.php").write_text("<?php ?>")
        (repo / "src" / "main.py").write_text("x = 1\n")
        rlmignore = repo / ".rlmignore"
        rlmignore.write_text("html/**\n")
        state = tmp_path / "state.pkl"

        # Work from a CWD inside repo so _find_rlmignore picks it up
        old_cwd = os.getcwd()
        try:
            os.chdir(repo)
            out = _run_init_repo(_make_args(repo, state))
        finally:
            os.chdir(old_cwd)

        assert "rlmignore:" in out
        assert "html/**" in out
        with open(state, "rb") as f:
            idx = pickle.load(f)["repo_index"]
        kept = set(idx["files"].keys())
        # .rlmignore itself is kept (it's not excluded by its own patterns);
        # html/** files must all be gone.
        assert "src/main.py" in kept
        assert not any(k.startswith("html/") for k in kept)


class TestAllowlistMode:
    def test_include_only_keeps_matching_trees(self, tmp_path: Path):
        # 8.3
        repo = tmp_path / "repo"
        repo.mkdir()
        for d in ("scripts", "tests", "vendor", "docs"):
            (repo / d).mkdir()
            (repo / d / "f.py").write_text("x = 1\n")
        state = tmp_path / "state.pkl"

        out = _run_init_repo(
            _make_args(
                repo, state,
                include=["scripts/**", "tests/**"],
            )
        )
        with open(state, "rb") as f:
            idx = pickle.load(f)["repo_index"]
        kept = set(idx["files"].keys())
        assert kept == {"scripts/f.py", "tests/f.py"}
        assert "Allowlist" in out


class TestNegationInExcludes:
    def test_negation_rescues_file(self, tmp_path: Path):
        # 8.4
        repo = tmp_path / "repo"
        repo.mkdir()
        (repo / "html").mkdir()
        (repo / "html" / "a.php").write_text("<?php ?>")
        (repo / "html" / "README.md").write_text("# html\n")
        state = tmp_path / "state.pkl"

        _run_init_repo(
            _make_args(
                repo, state,
                exclude=["html/**", "!html/README.md"],
            )
        )
        with open(state, "rb") as f:
            idx = pickle.load(f)["repo_index"]
        kept = set(idx["files"].keys())
        assert kept == {"html/README.md"}


class TestErrorPaths:
    def test_exclude_from_nonexistent_raises(self, tmp_path: Path):
        # 8.6
        repo = tmp_path / "repo"
        repo.mkdir()
        _build_tiny_repo(repo)
        state = tmp_path / "state.pkl"
        missing = tmp_path / "does-not-exist"
        args = _make_args(repo, state, exclude_from=str(missing))

        with pytest.raises(rlm_repl.RlmReplError) as exc:
            rlm_repl.cmd_init_repo(args)
        assert str(missing) in str(exc.value)
