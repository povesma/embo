import pytest
import rlm_repl


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def match(pattern: str, path: str) -> bool:
    """Thin wrapper so tests read naturally."""
    return rlm_repl._match_gitignore(path, pattern)


# ---------------------------------------------------------------------------
# 1.3  *  and  ?  single-segment wildcards
# ---------------------------------------------------------------------------

class TestSingleSegmentWildcards:
    # * matches any chars within one segment (no /)
    def test_star_matches_basename(self):
        assert match("*.py", "foo.py")

    def test_star_matches_any_chars_in_segment(self):
        assert match("*.py", "some_module.py")

    def test_star_does_not_cross_separator(self):
        assert not match("*.py", "sub/foo.py")

    def test_star_does_not_cross_two_separators(self):
        assert not match("*.py", "a/b/foo.py")

    def test_star_prefix(self):
        assert match("foo*", "foobar")

    def test_star_both_sides(self):
        assert match("*bar*", "foobarbaz")

    def test_star_bare_wildcard_matches_any_file_in_root(self):
        # bare "*" should match a plain filename (single segment)
        assert match("*", "anything")

    # ? matches exactly one char within a segment
    def test_question_matches_one_char(self):
        assert match("fo?.py", "foo.py")

    def test_question_matches_different_char(self):
        assert match("fo?.py", "fox.py")

    def test_question_does_not_match_two_chars(self):
        assert not match("fo?.py", "food.py")

    def test_question_does_not_match_zero_chars(self):
        assert not match("fo?.py", "fo.py")

    def test_question_does_not_cross_separator(self):
        assert not match("fo?.py", "sub/foo.py")

    def test_star_and_question_combined(self):
        assert match("*.?y", "module.py")
        assert match("*.?y", "module.ry")
        assert not match("*.?y", "module.pyz")


# ---------------------------------------------------------------------------
# 1.5  **  recursion
# ---------------------------------------------------------------------------

class TestDoubleStarRecursion:
    def test_trailing_double_star_matches_direct_child(self):
        assert match("html/**", "html/a.php")

    def test_trailing_double_star_matches_deep_descendant(self):
        assert match("html/**", "html/vendor/core/x.php")

    def test_trailing_double_star_does_not_match_prefix_only(self):
        assert not match("html/**", "htmlfoo/a.php")

    def test_trailing_double_star_does_not_match_sibling(self):
        assert not match("html/**", "other/a.php")

    def test_leading_double_star_any_depth(self):
        assert match("**/node_modules/**", "a/node_modules/x.js")
        assert match("**/node_modules/**", "a/b/c/node_modules/deep/x.js")

    def test_leading_double_star_matches_at_root(self):
        assert match("**/node_modules/**", "node_modules/x.js")

    def test_middle_double_star(self):
        assert match("a/**/z.txt", "a/z.txt")
        assert match("a/**/z.txt", "a/b/z.txt")
        assert match("a/**/z.txt", "a/b/c/z.txt")

    def test_double_star_does_not_cross_unrelated_dirs(self):
        assert not match("html/**", "other/html/a.php")


# ---------------------------------------------------------------------------
# 1.7  Bracket character classes
# ---------------------------------------------------------------------------

class TestBracketClasses:
    def test_enum_class_matches_each_member(self):
        assert match("[abc].py", "a.py")
        assert match("[abc].py", "b.py")
        assert match("[abc].py", "c.py")

    def test_enum_class_rejects_non_member(self):
        assert not match("[abc].py", "d.py")

    def test_range_class_matches_lowercase(self):
        for ch in "abcxyz":
            assert match("[a-z].py", f"{ch}.py")

    def test_range_class_rejects_outside(self):
        assert not match("[a-z].py", "A.py")
        assert not match("[a-z].py", "1.py")

    def test_negated_class_rejects_members(self):
        assert not match("[!xyz].py", "x.py")
        assert not match("[!xyz].py", "y.py")

    def test_negated_class_matches_non_members(self):
        assert match("[!xyz].py", "a.py")
        assert match("[!xyz].py", "b.py")

    def test_bracket_does_not_cross_separator(self):
        # bracket is a single-segment construct
        assert not match("[abc].py", "sub/a.py")


# ---------------------------------------------------------------------------
# 1.9  Anchoring rules
# ---------------------------------------------------------------------------

class TestAnchoring:
    # Leading / anchors to repo root
    def test_leading_slash_anchors_at_root(self):
        assert match("/html", "html")

    def test_leading_slash_rejects_nested(self):
        assert not match("/html", "docs/html")

    # Internal / anchors to repo root (no leading / needed)
    def test_internal_slash_anchors_at_root(self):
        assert match("html/vendor", "html/vendor")

    def test_internal_slash_rejects_nested(self):
        assert not match("html/vendor", "docs/html/vendor")

    # Bare name matches at any depth
    def test_bare_name_matches_at_root(self):
        assert match("node_modules", "node_modules")

    def test_bare_name_matches_one_level_deep(self):
        assert match("node_modules", "a/node_modules")

    def test_bare_name_matches_many_levels_deep(self):
        assert match("node_modules", "a/b/c/node_modules")

    def test_bare_name_matches_as_file(self):
        # bare name should also match a file with that name at any depth
        assert match("README", "docs/sub/README")


# ---------------------------------------------------------------------------
# 1.11 Trailing / (directory-only)
# ---------------------------------------------------------------------------

class TestDirOnly:
    def test_dir_only_matches_file_in_directory(self):
        assert match("html/", "html/a.php")

    def test_dir_only_matches_file_nested_under_directory(self):
        assert match("html/", "html/vendor/x.php")

    def test_dir_only_matches_directory_at_any_depth(self):
        assert match("html/", "sub/html/b.php")
        assert match("html/", "a/b/html/c.php")

    def test_dir_only_does_not_match_file_literally_named_segment(self):
        # A file literally named `html` (no directory) should NOT match
        # `html/` — directory semantics require at least one child path.
        assert not match("html/", "html")

    def test_dir_only_does_not_match_unrelated_sibling(self):
        assert not match("html/", "htmlfoo/a.php")

    def test_dir_only_anchored_rejects_nested(self):
        # `/html/` anchors at root: should NOT match sub/html/a.php
        assert match("/html/", "html/a.php")
        assert not match("/html/", "sub/html/a.php")


# ---------------------------------------------------------------------------
# 1.13 Escape \
# ---------------------------------------------------------------------------

class TestEscape:
    def test_escape_literal_star(self):
        # \*.py should match a file literally named "*.py"
        assert match(r"\*.py", "*.py")

    def test_escape_literal_star_does_not_match_wildcard(self):
        # and it should NOT match arbitrary .py files
        assert not match(r"\*.py", "foo.py")

    def test_escape_literal_question(self):
        assert match(r"fo\?.py", "fo?.py")
        assert not match(r"fo\?.py", "foo.py")

    def test_escape_literal_bang_at_front(self):
        # \!foo should match literal "!foo", not be negation
        cp = rlm_repl._compile_pattern(r"\!foo")
        assert cp.is_negation is False
        assert cp.regex.fullmatch("!foo") is not None

    def test_escape_literal_bracket(self):
        assert match(r"\[abc\]", "[abc]")
        assert not match(r"\[abc\]", "a")

    def test_dangling_backslash_raises(self):
        with pytest.raises(rlm_repl.RlmReplError):
            rlm_repl._compile_pattern("foo\\")


# ---------------------------------------------------------------------------
# 1.15 Negation marker detection
# ---------------------------------------------------------------------------

class TestNegationMarker:
    def test_negation_flag_set(self):
        cp = rlm_repl._compile_pattern("!foo")
        assert cp.is_negation is True

    def test_negation_inner_matches_stripped(self):
        # The regex should match `foo`, not `!foo`
        cp = rlm_repl._compile_pattern("!foo")
        assert cp.regex.fullmatch("foo") is not None
        assert cp.regex.fullmatch("!foo") is None

    def test_negation_preserves_anchoring_and_wildcards(self):
        cp = rlm_repl._compile_pattern("!/html/**")
        assert cp.is_negation is True
        assert cp.anchored is True
        assert cp.regex.fullmatch("html/a.php") is not None

    def test_escaped_bang_is_literal_not_negation(self):
        cp = rlm_repl._compile_pattern(r"\!foo")
        assert cp.is_negation is False
        assert cp.regex.fullmatch("!foo") is not None

    def test_raw_preserves_original_text(self):
        cp = rlm_repl._compile_pattern("!foo")
        assert cp.raw == "!foo"
        cp2 = rlm_repl._compile_pattern(r"\!foo")
        assert cp2.raw == r"\!foo"


# ---------------------------------------------------------------------------
# 1.17 Regression: determinism + perf smoke
# ---------------------------------------------------------------------------

class TestRegression:
    def test_determinism_sorted_input_yields_sorted_filtered_subset(self):
        # filter a sorted input list; output (kept) must remain sorted
        import random

        paths = sorted([f"a/{i:04d}/x.py" for i in range(200)] + [f"b/{i:04d}/x.js" for i in range(200)])
        # Shuffle and re-sort — verify the matcher is stable / pure
        shuffled = list(paths)
        random.Random(42).shuffle(shuffled)
        kept = sorted([p for p in shuffled if not rlm_repl._match_gitignore(p, "a/**")])
        expected = [p for p in paths if not rlm_repl._match_gitignore(p, "a/**")]
        assert kept == expected
        # All `a/**` dropped; only `b/*` survive
        assert all(p.startswith("b/") for p in kept)
        assert len(kept) == 200

    def test_perf_smoke_1000_paths_5_patterns_under_200ms(self):
        import time

        patterns = ["html/**", "vendor/**", "*.log", "**/node_modules/**", "build/"]
        compiled = [rlm_repl._compile_pattern(p) for p in patterns]
        paths = []
        for i in range(200):
            paths.append(f"src/a/{i:04d}.py")
            paths.append(f"html/{i:04d}.php")
            paths.append(f"vendor/{i:04d}/x.php")
            paths.append(f"logs/{i:04d}.log")
            paths.append(f"tests/a/node_modules/{i:04d}/x.js")

        start = time.perf_counter()
        matched_count = 0
        for path in paths:
            for cp in compiled:
                if cp.regex.fullmatch(path) is not None:
                    matched_count += 1
        elapsed_ms = (time.perf_counter() - start) * 1000
        assert elapsed_ms < 200, f"perf smoke too slow: {elapsed_ms:.1f} ms"
        # Sanity: html/, vendor/, node_modules patterns each cover 200
        # paths; *.log does not match `logs/xxxx.log` (has `/`), `build/`
        # matches nothing. Expect ~600 matches.
        assert matched_count >= 500
