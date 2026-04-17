import pytest
from pathlib import Path
import rlm_repl


def _compile(raw: str, source: str = "cli") -> rlm_repl.CompiledPattern:
    return rlm_repl._compile_pattern(raw)._replace(source=source)


def _spec(excludes=(), includes=()):
    return {
        "excludes": [_compile(p) for p in excludes],
        "includes": [_compile(p) for p in includes],
    }


def _paths(repo_root: Path, names):
    return [repo_root / n for n in names]


# ---------------------------------------------------------------------------
# 4.1  _apply_filters baseline
# ---------------------------------------------------------------------------

class TestApplyFiltersBaseline:
    def test_no_excludes_no_includes_passes_all_through(self, tmp_path: Path):
        files = _paths(tmp_path, ["a.py", "sub/b.py", "sub/c.js"])
        kept, stats = rlm_repl._apply_filters(files, tmp_path, _spec())
        assert kept == files
        assert stats["excluded_total"] == 0
        assert stats["included_total"] == 0
        assert stats["per_exclude"] == []
        assert stats["per_include"] == []

    def test_single_exclude_drops_matching_files(self, tmp_path: Path):
        files = _paths(tmp_path, ["a.py", "html/x.php", "html/y.php", "src/b.py"])
        kept, stats = rlm_repl._apply_filters(files, tmp_path, _spec(excludes=["html/**"]))
        rel = [p.relative_to(tmp_path).as_posix() for p in kept]
        assert sorted(rel) == ["a.py", "src/b.py"]
        assert stats["excluded_total"] == 2
        assert stats["per_exclude"] == [("html/**", "cli", 2)]

    def test_multiple_excludes_per_pattern_counts(self, tmp_path: Path):
        files = _paths(
            tmp_path,
            ["a.py", "html/x.php", "html/y.php", "vendor/z.php", "vendor/core/a.php", "src/b.py"],
        )
        kept, stats = rlm_repl._apply_filters(
            files, tmp_path, _spec(excludes=["html/**", "vendor/**"])
        )
        rel = [p.relative_to(tmp_path).as_posix() for p in kept]
        assert sorted(rel) == ["a.py", "src/b.py"]
        assert stats["excluded_total"] == 4
        # per-pattern counts
        assert ("html/**", "cli", 2) in stats["per_exclude"]
        assert ("vendor/**", "cli", 2) in stats["per_exclude"]


# ---------------------------------------------------------------------------
# 4.3  Include semantics (allowlist)
# ---------------------------------------------------------------------------

class TestApplyFiltersIncludes:
    def test_include_only_keeps_matching(self, tmp_path: Path):
        files = _paths(
            tmp_path,
            ["scripts/a.sh", "tests/t.py", "docs/x.md", "html/y.php"],
        )
        kept, stats = rlm_repl._apply_filters(
            files, tmp_path, _spec(includes=["scripts/**", "tests/**"])
        )
        rel = sorted(p.relative_to(tmp_path).as_posix() for p in kept)
        assert rel == ["scripts/a.sh", "tests/t.py"]
        assert stats["included_total"] == 2

    def test_exclude_wins_over_include(self, tmp_path: Path):
        files = _paths(tmp_path, ["scripts/a.sh", "scripts/secret.py"])
        kept, stats = rlm_repl._apply_filters(
            files, tmp_path, _spec(excludes=["scripts/secret.py"], includes=["scripts/**"])
        )
        rel = [p.relative_to(tmp_path).as_posix() for p in kept]
        assert rel == ["scripts/a.sh"]


# ---------------------------------------------------------------------------
# 4.5  Negation in excludes
# ---------------------------------------------------------------------------

class TestApplyFiltersNegation:
    def test_negation_rescues_single_file(self, tmp_path: Path):
        files = _paths(
            tmp_path,
            ["html/a.php", "html/b.php", "html/README.md", "src/x.py"],
        )
        kept, stats = rlm_repl._apply_filters(
            files, tmp_path, _spec(excludes=["html/**", "!html/README.md"])
        )
        rel = sorted(p.relative_to(tmp_path).as_posix() for p in kept)
        assert rel == ["html/README.md", "src/x.py"]

    def test_last_match_wins(self, tmp_path: Path):
        # Exclude html, un-exclude README, re-exclude via another pattern
        files = _paths(tmp_path, ["html/README.md", "html/a.php"])
        kept, stats = rlm_repl._apply_filters(
            files,
            tmp_path,
            _spec(excludes=["html/**", "!html/README.md", "*.md"]),
        )
        # html/README.md: html/** matches -> excluded; !html/README.md -> kept;
        # *.md is root-only single-segment, does NOT match 'html/README.md',
        # so it stays kept.
        rel = [p.relative_to(tmp_path).as_posix() for p in kept]
        assert rel == ["html/README.md"]


# ---------------------------------------------------------------------------
# 4.7  _build_repo_index backward-compat with optional files=
# ---------------------------------------------------------------------------

class TestBuildRepoIndexWithFiles:
    def test_accepts_prefiltered_files(self, tmp_path: Path):
        # Build a tiny fake repo with a couple of files; pass a pre-filtered
        # list and confirm index respects it.
        (tmp_path / "a.py").write_text("x = 1\n")
        (tmp_path / "b.py").write_text("y = 2\n")
        (tmp_path / "skip.py").write_text("z = 3\n")
        files = [tmp_path / "a.py", tmp_path / "b.py"]
        idx = rlm_repl._build_repo_index(tmp_path, max_file_size_mb=10, files=files)
        rel_keys = sorted(idx["files"].keys())
        assert rel_keys == ["a.py", "b.py"]
        assert idx["total_files"] == 2

    def test_default_behaviour_when_files_none(self, tmp_path: Path):
        # Create files + a .git so git path is tried; fallback also fine.
        (tmp_path / "one.py").write_text("a = 1\n")
        (tmp_path / "two.js").write_text("var b = 2;\n")
        idx = rlm_repl._build_repo_index(tmp_path, max_file_size_mb=10)
        # Both files must be present
        all_paths = set(idx["files"].keys())
        assert any("one.py" in p for p in all_paths)
        assert any("two.js" in p for p in all_paths)


# ---------------------------------------------------------------------------
# 5.1  _format_filter_stats
# ---------------------------------------------------------------------------

class TestFormatFilterStats:
    def test_empty_stats_returns_empty_list(self):
        assert rlm_repl._format_filter_stats(None) == []
        assert rlm_repl._format_filter_stats({}) == []
        # Also: active stats object but everything zeroed → still no lines
        # because per_exclude and per_include are empty
        empty = {
            "excluded_total": 0,
            "included_total": 0,
            "per_exclude": [],
            "per_include": [],
        }
        assert rlm_repl._format_filter_stats(empty) == []

    def test_excludes_only_renders_summary_and_per_pattern(self):
        stats = {
            "excluded_total": 500,
            "included_total": 0,
            "per_exclude": [
                ("html/**", "cli", 300),
                ("vendor/**", "cli", 200),
            ],
            "per_include": [],
        }
        lines = rlm_repl._format_filter_stats(stats)
        # One summary line + 2 per-pattern lines
        assert len(lines) == 3
        assert "500" in lines[0] and "2 pattern" in lines[0]
        assert "html/**" in lines[1] and "300" in lines[1] and "[cli]" in lines[1]
        assert "vendor/**" in lines[2] and "200" in lines[2]

    def test_includes_only_renders_allowlist_section(self):
        stats = {
            "excluded_total": 0,
            "included_total": 150,
            "per_exclude": [],
            "per_include": [("scripts/**", "cli", 100), ("tests/**", "cli", 50)],
        }
        lines = rlm_repl._format_filter_stats(stats)
        assert len(lines) == 3
        assert "Allowlist" in lines[0]
        assert "scripts/**" in lines[1]
        assert "tests/**" in lines[2]

    def test_both_sections_rendered(self):
        stats = {
            "excluded_total": 10,
            "included_total": 20,
            "per_exclude": [("a", "cli", 10)],
            "per_include": [("b", "cli", 20)],
        }
        lines = rlm_repl._format_filter_stats(stats)
        assert len(lines) == 4  # 1 exclude header + 1 excl pattern + 1 include header + 1 incl pattern
        assert "Excluded" in lines[0]
        assert "Allowlist" in lines[2]

    def test_source_label_appears_in_each_line(self):
        stats = {
            "excluded_total": 7,
            "included_total": 0,
            "per_exclude": [("html/**", "rlmignore:/abs/.rlmignore", 7)],
            "per_include": [],
        }
        lines = rlm_repl._format_filter_stats(stats)
        assert "[rlmignore:/abs/.rlmignore]" in lines[1]
