import os
import pytest
from pathlib import Path
import rlm_repl


# ---------------------------------------------------------------------------
# 2.1  _find_rlmignore
# ---------------------------------------------------------------------------

class TestFindRlmignore:
    def test_returns_path_in_cwd(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        rlmignore = repo_root / ".rlmignore"
        rlmignore.write_text("html/**\n")
        assert rlm_repl._find_rlmignore(repo_root, repo_root) == rlmignore

    def test_returns_path_in_ancestor_of_cwd(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        sub = repo_root / "packages" / "foo"
        sub.mkdir(parents=True)
        rlmignore = repo_root / ".rlmignore"
        rlmignore.write_text("vendor/**\n")
        assert rlm_repl._find_rlmignore(sub, repo_root) == rlmignore

    def test_returns_repo_root_fallback_when_cwd_outside(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        rlmignore = repo_root / ".rlmignore"
        rlmignore.write_text("node_modules/**\n")
        outside = tmp_path / "elsewhere"
        outside.mkdir()
        assert rlm_repl._find_rlmignore(outside, repo_root) == rlmignore

    def test_returns_none_when_neither_exists(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        assert rlm_repl._find_rlmignore(repo_root, repo_root) is None

    def test_prefers_cwd_over_ancestor(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        sub = repo_root / "packages" / "foo"
        sub.mkdir(parents=True)
        (repo_root / ".rlmignore").write_text("root-pattern\n")
        inner = sub / ".rlmignore"
        inner.write_text("inner-pattern\n")
        assert rlm_repl._find_rlmignore(sub, repo_root) == inner


# ---------------------------------------------------------------------------
# 2.3  _parse_pattern_file
# ---------------------------------------------------------------------------

class TestParsePatternFile:
    def test_reads_one_pattern_per_line(self, tmp_path: Path):
        f = tmp_path / "rlmignore.txt"
        f.write_text("html/**\nvendor/**\n")
        result = rlm_repl._parse_pattern_file(f)
        assert [p for _, p in result] == ["html/**", "vendor/**"]

    def test_skips_comment_lines(self, tmp_path: Path):
        f = tmp_path / ".rlmignore"
        f.write_text("# this is a comment\nhtml/**\n# another\nvendor/**\n")
        result = rlm_repl._parse_pattern_file(f)
        assert [p for _, p in result] == ["html/**", "vendor/**"]

    def test_skips_blank_lines(self, tmp_path: Path):
        f = tmp_path / ".rlmignore"
        f.write_text("\nhtml/**\n\n\nvendor/**\n\n")
        result = rlm_repl._parse_pattern_file(f)
        assert [p for _, p in result] == ["html/**", "vendor/**"]

    def test_preserves_order(self, tmp_path: Path):
        f = tmp_path / ".rlmignore"
        f.write_text("a\nb\nc\nd\n")
        result = rlm_repl._parse_pattern_file(f)
        assert [p for _, p in result] == ["a", "b", "c", "d"]

    def test_returns_lineno_with_pattern(self, tmp_path: Path):
        f = tmp_path / ".rlmignore"
        f.write_text("# comment\n\nhtml/**\n")
        result = rlm_repl._parse_pattern_file(f)
        # html/** is on line 3
        assert result == [(3, "html/**")]

    def test_unreadable_file_raises(self, tmp_path: Path):
        f = tmp_path / "nonexistent"
        with pytest.raises(rlm_repl.RlmReplError) as exc:
            rlm_repl._parse_pattern_file(f)
        assert str(f) in str(exc.value)


# ---------------------------------------------------------------------------
# 2.5  _load_filter_spec
# ---------------------------------------------------------------------------

class _Args:
    """Minimal object with the expected argparse attributes."""
    def __init__(self, exclude=None, include=None, exclude_from=None, no_rlmignore=False):
        self.exclude = exclude or []
        self.include = include or []
        self.exclude_from = exclude_from
        self.no_rlmignore = no_rlmignore


class TestLoadFilterSpec:
    def test_cli_exclude_only(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        args = _Args(exclude=["html/**"])
        spec = rlm_repl._load_filter_spec(args, repo_root)
        raws = [cp.raw for cp in spec["excludes"]]
        assert raws == ["html/**"]
        sources = [cp.source for cp in spec["excludes"]]
        assert sources == ["cli"]

    def test_exclude_from_only(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        f = tmp_path / "exfile"
        f.write_text("html/**\nvendor/**\n")
        args = _Args(exclude_from=str(f))
        spec = rlm_repl._load_filter_spec(args, repo_root)
        raws = [cp.raw for cp in spec["excludes"]]
        assert raws == ["html/**", "vendor/**"]
        assert all(cp.source == f"exclude-from:{f}" for cp in spec["excludes"])

    def test_rlmignore_auto_discovery(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        rlmignore = repo_root / ".rlmignore"
        rlmignore.write_text("html/**\n")
        args = _Args()
        # simulate "cwd is repo_root" by not passing cwd — helper signature below
        spec = rlm_repl._load_filter_spec(args, repo_root, cwd=repo_root)
        raws = [cp.raw for cp in spec["excludes"]]
        assert raws == ["html/**"]
        assert spec["excludes"][0].source == f"rlmignore:{rlmignore}"

    def test_exclude_from_overrides_rlmignore_auto(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        (repo_root / ".rlmignore").write_text("auto-pattern\n")
        exf = tmp_path / "exfile"
        exf.write_text("explicit-pattern\n")
        args = _Args(exclude_from=str(exf))
        spec = rlm_repl._load_filter_spec(args, repo_root, cwd=repo_root)
        raws = [cp.raw for cp in spec["excludes"]]
        assert raws == ["explicit-pattern"]

    def test_no_rlmignore_flag_suppresses_auto(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        (repo_root / ".rlmignore").write_text("auto-pattern\n")
        args = _Args(no_rlmignore=True)
        spec = rlm_repl._load_filter_spec(args, repo_root, cwd=repo_root)
        assert spec["excludes"] == []

    def test_includes_from_cli(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        args = _Args(include=["scripts/**", "tests/**"])
        spec = rlm_repl._load_filter_spec(args, repo_root, cwd=repo_root)
        raws = [cp.raw for cp in spec["includes"]]
        assert raws == ["scripts/**", "tests/**"]
        assert all(cp.source == "cli" for cp in spec["includes"])

    def test_cli_and_rlmignore_combined(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        (repo_root / ".rlmignore").write_text("auto/**\n")
        args = _Args(exclude=["cli/**"])
        spec = rlm_repl._load_filter_spec(args, repo_root, cwd=repo_root)
        raws = [cp.raw for cp in spec["excludes"]]
        # CLI excludes come first, then rlmignore
        assert raws == ["cli/**", "auto/**"]


# ---------------------------------------------------------------------------
# 2.7  Negative: unreadable .rlmignore
# ---------------------------------------------------------------------------

class TestUnreadableRlmignore:
    def test_unreadable_rlmignore_raises(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        rlmignore = repo_root / ".rlmignore"
        rlmignore.write_text("html/**\n")
        rlmignore.chmod(0o000)
        try:
            args = _Args()
            with pytest.raises(rlm_repl.RlmReplError) as exc:
                rlm_repl._load_filter_spec(args, repo_root, cwd=repo_root)
            assert str(rlmignore) in str(exc.value)
        finally:
            # Restore perms so tmp_path cleanup works
            rlmignore.chmod(0o644)

    def test_explicit_exclude_from_missing_raises(self, tmp_path: Path):
        repo_root = tmp_path / "repo"
        repo_root.mkdir()
        missing = tmp_path / "does-not-exist"
        args = _Args(exclude_from=str(missing))
        with pytest.raises(rlm_repl.RlmReplError) as exc:
            rlm_repl._load_filter_spec(args, repo_root, cwd=repo_root)
        assert str(missing) in str(exc.value)
