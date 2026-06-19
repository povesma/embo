#!/usr/bin/env python3
"""Persistent mini-REPL for RLM-style workflows in Claude Code.

This script provides a *stateful* Python environment across invocations by
saving a pickle file to disk. It is intentionally small and dependency-free.

Typical flow:
  1) Initialise context:
       python rlm_repl.py init path/to/context.txt
  OR for code repositories:
       python rlm_repl.py init-repo /path/to/repo
  2) Execute code repeatedly (state persists):
       python rlm_repl.py exec -c 'print(len(content))'
       python rlm_repl.py exec <<'PYCODE'
       # you can write multi-line code
       hits = grep('TODO')
       print(hits[:3])
       PYCODE

The script injects these variables into the exec environment:
  - context: dict with keys {path, loaded_at, content}
  - content: string alias for context['content']
  - buffers: list[str] for storing intermediate text results
  - repo_index: dict with file index (when using init-repo)

It also injects helpers:
  - peek(start=0, end=1000) -> str
  - grep(pattern, max_matches=20, window=120, flags=0) -> list[dict]
  - chunk_indices(size=200000, overlap=0) -> list[(start,end)]
  - write_chunks(out_dir, size=200000, overlap=0, prefix='chunk') -> list[str]
  - add_buffer(text: str) -> None

Security note:
  This runs arbitrary Python via exec. Treat it like running code you wrote.
"""

from __future__ import annotations

import argparse
import io
import json
import mimetypes
import os
import pickle
import re
import subprocess
import sys
import textwrap
import time
import traceback
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any, Dict, List, NamedTuple, Tuple, Set, Optional


DEFAULT_STATE_PATH = Path(".claude/rlm_state/state.pkl")
DEFAULT_MAX_OUTPUT_CHARS = 8000

# Language detection by file extension
LANGUAGE_MAP = {
    # Programming languages
    '.py': 'Python',
    '.pyx': 'Python',
    '.pyi': 'Python',
    '.js': 'JavaScript',
    '.jsx': 'JavaScript',
    '.ts': 'TypeScript',
    '.tsx': 'TypeScript',
    '.java': 'Java',
    '.kt': 'Kotlin',
    '.cpp': 'C++',
    '.cc': 'C++',
    '.cxx': 'C++',
    '.c': 'C',
    '.h': 'C/C++',
    '.hpp': 'C++',
    '.cs': 'C#',
    '.go': 'Go',
    '.rs': 'Rust',
    '.rb': 'Ruby',
    '.php': 'PHP',
    '.swift': 'Swift',
    '.m': 'Objective-C',
    '.mm': 'Objective-C++',
    '.scala': 'Scala',
    '.r': 'R',
    '.R': 'R',
    '.lua': 'Lua',
    '.perl': 'Perl',
    '.pl': 'Perl',
    '.sh': 'Shell',
    '.bash': 'Bash',
    '.zsh': 'Zsh',
    '.fish': 'Fish',
    '.vim': 'VimScript',
    '.el': 'Emacs Lisp',
    '.clj': 'Clojure',
    '.cljs': 'ClojureScript',
    '.ex': 'Elixir',
    '.exs': 'Elixir',
    '.erl': 'Erlang',
    '.hrl': 'Erlang',
    '.ml': 'OCaml',
    '.mli': 'OCaml',
    '.hs': 'Haskell',
    '.lhs': 'Haskell',
    '.dart': 'Dart',
    '.v': 'Verilog',
    '.vhd': 'VHDL',
    '.vhdl': 'VHDL',
    '.sql': 'SQL',
    '.asm': 'Assembly',
    '.s': 'Assembly',
    '.S': 'Assembly',

    # Web/markup
    '.html': 'HTML',
    '.htm': 'HTML',
    '.xml': 'XML',
    '.svg': 'SVG',
    '.css': 'CSS',
    '.scss': 'SCSS',
    '.sass': 'Sass',
    '.less': 'Less',

    # Documentation
    '.md': 'Markdown',
    '.markdown': 'Markdown',
    '.rst': 'ReStructuredText',
    '.txt': 'Text',
    '.tex': 'LaTeX',
    '.adoc': 'AsciiDoc',

    # Data/config
    '.json': 'JSON',
    '.yaml': 'YAML',
    '.yml': 'YAML',
    '.toml': 'TOML',
    '.ini': 'INI',
    '.cfg': 'Config',
    '.conf': 'Config',
    '.xml': 'XML',
    '.csv': 'CSV',
    '.tsv': 'TSV',

    # Build/project files
    '.cmake': 'CMake',
    '.gradle': 'Gradle',
    '.make': 'Makefile',
    '.dockerfile': 'Dockerfile',

    # Binary/compiled (common ones)
    '.pyc': 'Python Bytecode',
    '.pyo': 'Python Bytecode',
    '.so': 'Shared Library',
    '.dll': 'Dynamic Library',
    '.dylib': 'Dynamic Library',
    '.a': 'Static Library',
    '.o': 'Object File',
    '.obj': 'Object File',
    '.exe': 'Executable',
    '.bin': 'Binary',
    '.class': 'Java Bytecode',
    '.jar': 'Java Archive',
    '.war': 'Web Archive',

    # Images
    '.png': 'PNG Image',
    '.jpg': 'JPEG Image',
    '.jpeg': 'JPEG Image',
    '.gif': 'GIF Image',
    '.bmp': 'BMP Image',
    '.ico': 'Icon',
    '.webp': 'WebP Image',

    # Archives
    '.zip': 'ZIP Archive',
    '.tar': 'TAR Archive',
    '.gz': 'Gzip Archive',
    '.bz2': 'Bzip2 Archive',
    '.xz': 'XZ Archive',
    '.7z': '7-Zip Archive',

    # Media
    '.mp3': 'Audio',
    '.wav': 'Audio',
    '.mp4': 'Video',
    '.avi': 'Video',
    '.mov': 'Video',
    '.pdf': 'PDF',
}

# Binary file extensions
BINARY_EXTENSIONS = {
    '.pyc', '.pyo', '.so', '.dll', '.dylib', '.a', '.o', '.obj',
    '.exe', '.bin', '.class', '.jar', '.war',
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.webp', '.svg',
    '.zip', '.tar', '.gz', '.bz2', '.xz', '.7z', '.rar',
    '.mp3', '.wav', '.ogg', '.flac', '.aac',
    '.mp4', '.avi', '.mov', '.mkv', '.wmv', '.flv',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.ttf', '.otf', '.woff', '.woff2', '.eot',
    '.db', '.sqlite', '.sqlite3',
}


class RlmReplError(RuntimeError):
    pass


def _ensure_parent_dir(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def _load_state(state_path: Path) -> Dict[str, Any]:
    if not state_path.exists():
        raise RlmReplError(
            f"No state found at {state_path}. Run: python rlm_repl.py init <context_path>"
        )
    with state_path.open("rb") as f:
        state = pickle.load(f)
    if not isinstance(state, dict):
        raise RlmReplError(f"Corrupt state file: {state_path}")
    return state


def _save_state(state: Dict[str, Any], state_path: Path) -> None:
    _ensure_parent_dir(state_path)
    tmp_path = state_path.with_suffix(state_path.suffix + ".tmp")
    with tmp_path.open("wb") as f:
        pickle.dump(state, f, protocol=pickle.HIGHEST_PROTOCOL)
    tmp_path.replace(state_path)


def _read_text_file(path: Path, max_bytes: int | None = None) -> str:
    if not path.exists():
        raise RlmReplError(f"Context file does not exist: {path}")
    data: bytes
    with path.open("rb") as f:
        data = f.read() if max_bytes is None else f.read(max_bytes)
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        # Fall back to a lossy decode that will not crash.
        return data.decode("utf-8", errors="replace")


def _truncate(s: str, max_chars: int) -> str:
    if max_chars <= 0:
        return ""
    if len(s) <= max_chars:
        return s
    return s[:max_chars] + f"\n... [truncated to {max_chars} chars] ...\n"


def _is_pickleable(value: Any) -> bool:
    try:
        pickle.dumps(value, protocol=pickle.HIGHEST_PROTOCOL)
        return True
    except Exception:
        return False


def _filter_pickleable(d: Dict[str, Any]) -> Tuple[Dict[str, Any], List[str]]:
    kept: Dict[str, Any] = {}
    dropped: List[str] = []
    for k, v in d.items():
        if _is_pickleable(v):
            kept[k] = v
        else:
            dropped.append(k)
    return kept, dropped


# Repository-specific helpers

def _detect_language(file_path: Path) -> str:
    """Detect language/type from file extension."""
    # Handle special cases
    if file_path.name.lower() in {'makefile', 'gnumakefile', 'dockerfile'}:
        name_lower = file_path.name.lower()
        if 'makefile' in name_lower:
            return 'Makefile'
        if 'dockerfile' in name_lower:
            return 'Dockerfile'

    # Check extension
    ext = file_path.suffix.lower()
    if ext in LANGUAGE_MAP:
        return LANGUAGE_MAP[ext]

    # Default to unknown
    return 'Unknown'


def _is_binary_file(file_path: Path) -> bool:
    """Check if a file is binary."""
    # Check by extension first
    ext = file_path.suffix.lower()
    if ext in BINARY_EXTENSIONS:
        return True

    # For files without recognized extensions, check content
    if not file_path.exists() or file_path.is_dir():
        return False

    try:
        # Read first 8KB and check for null bytes
        with file_path.open('rb') as f:
            chunk = f.read(8192)
            if not chunk:  # Empty file
                return False
            # If there are null bytes, it's likely binary
            return b'\x00' in chunk
    except (OSError, PermissionError):
        # If we can't read it, assume binary
        return True


class CompiledPattern(NamedTuple):
    """A compiled gitignore-lite pattern ready for matching."""

    raw: str
    is_negation: bool
    anchored: bool
    dir_only: bool
    regex: "re.Pattern"
    source: str = "cli"


def _translate_core(core: str) -> str:
    """Translate the inner body of a gitignore-lite pattern into a regex.

    Does not apply anchoring or directory-only wrapping — caller handles
    those. Supports `*`, `?`, `**`, `**/`, bracket classes `[abc]`,
    `[a-z]`, `[!xyz]`, and `\\` escape for the next metacharacter.
    """
    parts: List[str] = []
    i = 0
    n = len(core)
    while i < n:
        ch = core[i]
        if ch == "\\":
            if i + 1 >= n:
                raise RlmReplError(
                    f"dangling backslash in pattern: {core!r}"
                )
            parts.append(re.escape(core[i + 1]))
            i += 2
            continue
        if ch == "*" and i + 1 < n and core[i + 1] == "*":
            # ** handling
            if i + 2 < n and core[i + 2] == "/":
                # `**/` -> zero or more segments followed by /
                parts.append("(?:.*/)?")
                i += 3
                continue
            if i + 2 == n and parts and parts[-1].endswith("/"):
                # trailing `/` + `**` pair: drop the trailing slash we
                # already emitted so the tail can match zero segments
                parts[-1] = parts[-1][:-1]
                parts.append("(?:/.*)?")
                i += 2
                continue
            # bare trailing `**` -> any chars including /
            parts.append(".*")
            i += 2
            continue
        if ch == "*":
            parts.append("[^/]*")
            i += 1
            continue
        if ch == "?":
            parts.append("[^/]")
            i += 1
            continue
        if ch == "[":
            j = i + 1
            if j < n and core[j] == "!":
                j += 1
            if j < n and core[j] == "]":
                j += 1
            while j < n and core[j] != "]":
                j += 1
            if j >= n:
                parts.append(re.escape(ch))
                i += 1
                continue
            body = core[i + 1 : j]
            if body.startswith("!"):
                body = "^" + body[1:]
            parts.append("(?![/])[" + body + "]")
            i = j + 1
            continue
        parts.append(re.escape(ch))
        i += 1
    return "".join(parts)


def _compile_pattern(pattern: str) -> CompiledPattern:
    """Translate a gitignore-lite pattern into a CompiledPattern.

    Wildcards: `*`, `?`, `**`, `**/`, bracket classes `[abc]`,
    `[a-z]`, `[!xyz]`. Leading `!` marks negation; `\\!` escapes it.
    Leading `/` or any internal `/` anchors the pattern to repo root.
    Bare names match at any depth. Trailing `/` = directory-only
    (requires at least one char after the matched segment since our
    file list is files-only).
    """
    raw = pattern
    if not pattern:
        raise RlmReplError("empty pattern")

    # Negation
    is_negation = False
    if pattern.startswith("!"):
        is_negation = True
        pattern = pattern[1:]
    elif pattern.startswith("\\!"):
        # Escaped bang: strip the backslash so the `!` is literal
        pattern = pattern[1:]

    if not pattern:
        raise RlmReplError(f"empty pattern after negation marker: {raw!r}")

    # Directory-only (trailing /)
    dir_only = False
    if pattern.endswith("/") and not pattern.endswith("\\/"):
        dir_only = True
        pattern = pattern[:-1]
        if not pattern:
            raise RlmReplError(f"pattern is only a slash: {raw!r}")

    # Anchoring
    #
    # Rules (per task 016 spec, matcher tests):
    #   - leading `/` -> strip, anchored to root
    #   - internal `/` -> anchored to root (no cross-depth)
    #   - no `/`, no wildcards -> bare literal name, matches at any depth
    #   - no `/`, contains wildcards (`*`/`?`/`[`) -> root-anchored, single segment
    #   - dir_only (trailing `/`) -> directory segment matches at any depth
    anchored = False
    if pattern.startswith("/"):
        anchored = True
        pattern = pattern[1:]
    elif "/" in pattern:
        anchored = True

    has_wildcards = any(c in pattern for c in "*?[")

    core = _translate_core(pattern)

    if dir_only:
        # Directory name at any depth; our file list is files-only so
        # require at least one char after the segment (`.+` not `.*`).
        if anchored:
            regex_src = f"{core}/.+"
        else:
            regex_src = f"(?:^|.*/){core}/.+"
    else:
        if anchored:
            regex_src = core
        elif has_wildcards:
            # Bare pattern with wildcards -> root-only, single segment.
            regex_src = core
        else:
            # Literal bare name -> matches as a segment at any depth.
            regex_src = f"(?:^|.*/){core}(?:/.*)?"

    return CompiledPattern(
        raw=raw,
        is_negation=is_negation,
        anchored=anchored,
        dir_only=dir_only,
        regex=re.compile(regex_src),
    )


def _match_gitignore(rel_path: str, pattern: str) -> bool:
    """Return True if `rel_path` matches gitignore-lite `pattern`.

    Negation markers are a property of the pattern text; this helper
    reports raw "did the body match" and callers interpret negation.
    """
    return _compile_pattern(pattern).regex.fullmatch(rel_path) is not None


def _find_rlmignore(cwd: Path, repo_root: Path) -> Optional[Path]:
    """Locate a `.rlmignore` file starting at cwd.

    Walks upward from `cwd` through each parent; returns the first
    `.rlmignore` found. If none found during the walk, falls back to
    `repo_root/.rlmignore` if it exists. Returns `None` otherwise.
    """
    cwd = Path(cwd).resolve()
    repo_root = Path(repo_root).resolve()
    # Walk upward from cwd until the filesystem root
    current = cwd
    seen: Set[Path] = set()
    while current not in seen:
        seen.add(current)
        candidate = current / ".rlmignore"
        if candidate.is_file():
            return candidate
        parent = current.parent
        if parent == current:
            break
        current = parent
    # Fallback: repo_root/.rlmignore (handles "cwd outside repo" case)
    fallback = repo_root / ".rlmignore"
    if fallback.is_file():
        return fallback
    return None


def _parse_pattern_file(path: Path) -> List[Tuple[int, str]]:
    """Parse a `.rlmignore`-style file.

    Returns `[(lineno, raw_pattern), ...]` in input order. Skips blank
    lines and `#`-prefixed comments. Raises `RlmReplError` with the
    file path on read failure.
    """
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, PermissionError) as e:
        raise RlmReplError(f"cannot read pattern file {path}: {e}")

    out: List[Tuple[int, str]] = []
    for idx, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            continue
        out.append((idx, stripped))
    return out


def _compile_from_source(raw: str, source: str) -> CompiledPattern:
    """Compile a raw pattern and stamp a source label."""
    cp = _compile_pattern(raw)
    return cp._replace(source=source)


def _load_filter_spec(
    args: Any,
    repo_root: Path,
    cwd: Optional[Path] = None,
) -> Dict[str, Any]:
    """Build the FilterSpec from CLI args, `--exclude-from`, and `.rlmignore`.

    Precedence for excludes (in order appended):
      1. `--exclude` flags (CLI, repeatable)
      2. If `--exclude-from FILE` is given: patterns from FILE (explicit
         exclude-from overrides auto-discovered `.rlmignore`).
      3. Else, unless `--no-rlmignore` is set: patterns from an
         auto-discovered `.rlmignore`.

    Includes come only from `--include` (CLI). FilterSpec is a plain
    dict with keys `excludes` and `includes`, each a list of
    `CompiledPattern`.
    """
    if cwd is None:
        cwd = Path.cwd()
    cwd = Path(cwd)
    repo_root = Path(repo_root)

    excludes: List[CompiledPattern] = []
    includes: List[CompiledPattern] = []

    # 1. CLI excludes
    for raw in getattr(args, "exclude", []) or []:
        excludes.append(_compile_from_source(raw, "cli"))

    # 2. --exclude-from (explicit) or auto-discovered .rlmignore
    exclude_from = getattr(args, "exclude_from", None)
    no_rlmignore = getattr(args, "no_rlmignore", False)

    if exclude_from:
        exf = Path(exclude_from)
        if not exf.is_file():
            raise RlmReplError(f"exclude-from file not found: {exf}")
        source = f"exclude-from:{exf}"
        for lineno, raw in _parse_pattern_file(exf):
            try:
                excludes.append(_compile_from_source(raw, source))
            except RlmReplError as e:
                raise RlmReplError(
                    f"invalid pattern in {source} line {lineno}: {raw!r}: {e}"
                )
    elif not no_rlmignore:
        found = _find_rlmignore(cwd, repo_root)
        if found is not None:
            source = f"rlmignore:{found}"
            for lineno, raw in _parse_pattern_file(found):
                try:
                    excludes.append(_compile_from_source(raw, source))
                except RlmReplError as e:
                    raise RlmReplError(
                        f"invalid pattern in {source} line {lineno}: {raw!r}: {e}"
                    )

    # 3. CLI includes
    for raw in getattr(args, "include", []) or []:
        includes.append(_compile_from_source(raw, "cli"))

    return {"excludes": excludes, "includes": includes}


def _apply_filters(
    files: List[Path],
    repo_root: Path,
    spec: Dict[str, Any],
) -> Tuple[List[Path], Dict[str, Any]]:
    """Filter `files` according to `spec` and return (kept, stats).

    Semantics:
      - Walk `spec['excludes']` in order. For each file:
        * if a non-negation pattern matches: excluded = True
        * if a negation pattern matches later: excluded = False
        (last-match-wins, scoped to excludes only)
      - If `spec['includes']` is non-empty, a file must match at least
        one include to be kept. Excludes still win (exclude beats
        include). Negation in includes is not interpreted — a literal
        `!` at the front of an include would already have been stripped
        by `_compile_pattern` setting `is_negation=True`; during include
        scanning we simply skip negated include patterns.
      - Per-pattern counts recorded in stats.
    """
    excludes: List[CompiledPattern] = spec.get("excludes", []) or []
    includes: List[CompiledPattern] = spec.get("includes", []) or []

    per_exclude_counts: Dict[int, int] = {idx: 0 for idx in range(len(excludes))}
    per_include_counts: Dict[int, int] = {idx: 0 for idx in range(len(includes))}

    kept: List[Path] = []
    excluded_total = 0
    included_total = 0

    repo_root = Path(repo_root)
    # Pre-resolve once to avoid per-iteration cost
    repo_root_resolved = repo_root.resolve()

    for f in files:
        try:
            rel = Path(f).resolve().relative_to(repo_root_resolved).as_posix()
        except ValueError:
            # Path not under repo_root -> keep as-is by posix of path
            rel = Path(f).as_posix()

        # Resolve exclusion with last-match-wins over all excludes
        excluded = False
        matched_exclude_indices: List[int] = []
        for idx, cp in enumerate(excludes):
            if cp.regex.fullmatch(rel) is not None:
                matched_exclude_indices.append(idx)
                excluded = not cp.is_negation

        # Apply include allowlist if any non-negation include patterns exist
        positive_includes = [cp for cp in includes if not cp.is_negation]
        if positive_includes:
            include_hit = False
            for idx, cp in enumerate(includes):
                if cp.is_negation:
                    continue
                if cp.regex.fullmatch(rel) is not None:
                    include_hit = True
                    per_include_counts[idx] += 1
            if not include_hit:
                # Fails allowlist: drop silently (not an exclude match)
                continue

        if excluded:
            excluded_total += 1
            for idx in matched_exclude_indices:
                per_exclude_counts[idx] += 1
            continue

        # Kept: still record include counts (already recorded above) and
        # tally included_total only if an include was active
        if positive_includes:
            included_total += 1
        kept.append(f)

    stats: Dict[str, Any] = {
        "excluded_total": excluded_total,
        "included_total": included_total,
        "per_exclude": [
            (excludes[idx].raw, excludes[idx].source, per_exclude_counts[idx])
            for idx in range(len(excludes))
        ],
        "per_include": [
            (includes[idx].raw, includes[idx].source, per_include_counts[idx])
            for idx in range(len(includes))
        ],
    }
    return kept, stats


def _format_filter_stats(stats: Optional[Dict[str, Any]]) -> List[str]:
    """Render filter stats for inclusion in the init-repo summary.

    Returns an empty list when no filters were active — this preserves
    byte-identical stdout for the backward-compat path (no flags + no
    `.rlmignore`). Otherwise emits one overall line per section plus an
    indented breakdown per pattern (with source tag).
    """
    if not stats:
        return []

    lines: List[str] = []
    per_exclude = stats.get("per_exclude") or []
    per_include = stats.get("per_include") or []
    excluded_total = stats.get("excluded_total", 0) or 0
    included_total = stats.get("included_total", 0) or 0

    if per_exclude:
        n_patterns = len(per_exclude)
        lines.append(
            f"  - Excluded: {excluded_total} files via {n_patterns} pattern(s):"
        )
        for raw, source, count in per_exclude:
            lines.append(f"    • {count} via '{raw}' [{source}]")

    if per_include:
        n_patterns = len(per_include)
        lines.append(
            f"  - Allowlist kept: {included_total} files via {n_patterns} pattern(s):"
        )
        for raw, source, count in per_include:
            lines.append(f"    • {count} via '{raw}' [{source}]")

    return lines


def _discover_git_files(repo_root: Path) -> List[Path]:
    """Use git to discover all tracked and untracked files (respects .gitignore)."""
    try:
        # Get tracked files
        result = subprocess.run(
            ['git', 'ls-files'],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True
        )
        tracked = set(result.stdout.strip().split('\n')) if result.stdout.strip() else set()

        # Get untracked files (excluding ignored)
        result = subprocess.run(
            ['git', 'ls-files', '--others', '--exclude-standard'],
            cwd=repo_root,
            capture_output=True,
            text=True,
            check=True
        )
        untracked = set(result.stdout.strip().split('\n')) if result.stdout.strip() else set()

        all_files = tracked | untracked
        return [repo_root / f for f in sorted(all_files) if f]

    except (subprocess.CalledProcessError, FileNotFoundError):
        # Git not available or not a git repo, fall back to walking directory
        return _discover_files_fallback(repo_root)


def _discover_files_fallback(repo_root: Path) -> List[Path]:
    """Fallback file discovery when git is not available."""
    files = []
    # Common directories to skip
    skip_dirs = {
        '.git', '.svn', '.hg', '__pycache__', 'node_modules',
        'venv', 'env', '.env', 'build', 'dist', '.idea',
        '.vscode', 'target', 'bin', 'obj'
    }

    for item in repo_root.rglob('*'):
        # Skip if any parent is in skip_dirs
        if any(part in skip_dirs for part in item.parts):
            continue
        if item.is_file():
            files.append(item)

    return sorted(files)


def _build_repo_index(
    repo_root: Path,
    max_file_size_mb: int = 10,
    files: Optional[List[Path]] = None,
) -> Dict[str, Any]:
    """Build an index of all files in the repository.

    If `files` is provided, skip internal discovery and use the given
    list directly (enables the `init-repo` filter pipeline to feed a
    pre-filtered list). When `files` is `None`, behaviour is unchanged
    from the original implementation (backward-compat).
    """
    repo_root = repo_root.resolve()
    if files is None:
        files = _discover_git_files(repo_root)

    index = {
        'repo_root': str(repo_root),
        'indexed_at': time.time(),
        'total_files': 0,
        'total_size': 0,
        'files': {},
        'languages': {},
    }

    max_size_bytes = max_file_size_mb * 1024 * 1024

    for file_path in files:
        if not file_path.exists():
            continue

        try:
            rel_path = str(file_path.relative_to(repo_root))
            size = file_path.stat().st_size
            is_binary = _is_binary_file(file_path)
            language = _detect_language(file_path)

            # Store file metadata
            index['files'][rel_path] = {
                'size': size,
                'is_binary': is_binary,
                'lang': language,
                'too_large': size > max_size_bytes,
                'abs_path': str(file_path),
            }

            # Update statistics
            index['total_files'] += 1
            index['total_size'] += size

            # Track language counts
            if language not in index['languages']:
                index['languages'][language] = {'count': 0, 'size': 0}
            index['languages'][language]['count'] += 1
            index['languages'][language]['size'] += size

        except (OSError, PermissionError) as e:
            # Skip files we can't access
            continue

    return index


def _make_helpers(context_ref: Dict[str, Any], buffers_ref: List[str]):
    # These close over context_ref/buffers_ref so changes persist.
    def peek(start: int = 0, end: int = 1000) -> str:
        content = context_ref.get("content", "")
        return content[start:end]

    def grep(
        pattern: str,
        max_matches: int = 20,
        window: int = 120,
        flags: int = 0,
    ) -> List[Dict[str, Any]]:
        content = context_ref.get("content", "")
        out: List[Dict[str, Any]] = []
        for m in re.finditer(pattern, content, flags):
            start, end = m.span()
            snippet_start = max(0, start - window)
            snippet_end = min(len(content), end + window)
            out.append(
                {
                    "match": m.group(0),
                    "span": (start, end),
                    "snippet": content[snippet_start:snippet_end],
                }
            )
            if len(out) >= max_matches:
                break
        return out

    def chunk_indices(size: int = 200_000, overlap: int = 0) -> List[Tuple[int, int]]:
        if size <= 0:
            raise ValueError("size must be > 0")
        if overlap < 0:
            raise ValueError("overlap must be >= 0")
        if overlap >= size:
            raise ValueError("overlap must be < size")

        content = context_ref.get("content", "")
        n = len(content)
        spans: List[Tuple[int, int]] = []
        step = size - overlap
        for start in range(0, n, step):
            end = min(n, start + size)
            spans.append((start, end))
            if end >= n:
                break
        return spans

    def write_chunks(
        out_dir: str | os.PathLike,
        size: int = 200_000,
        overlap: int = 0,
        prefix: str = "chunk",
        encoding: str = "utf-8",
    ) -> List[str]:
        content = context_ref.get("content", "")
        spans = chunk_indices(size=size, overlap=overlap)
        out_path = Path(out_dir)
        out_path.mkdir(parents=True, exist_ok=True)
        paths: List[str] = []
        for i, (s, e) in enumerate(spans):
            p = out_path / f"{prefix}_{i:04d}.txt"
            p.write_text(content[s:e], encoding=encoding)
            paths.append(str(p))
        return paths

    def add_buffer(text: str) -> None:
        buffers_ref.append(str(text))

    return {
        "peek": peek,
        "grep": grep,
        "chunk_indices": chunk_indices,
        "write_chunks": write_chunks,
        "add_buffer": add_buffer,
    }


def cmd_init(args: argparse.Namespace) -> int:
    state_path = Path(args.state)
    ctx_path = Path(args.context)

    content = _read_text_file(ctx_path, max_bytes=args.max_bytes)
    state: Dict[str, Any] = {
        "version": 1,
        "context": {
            "path": str(ctx_path),
            "loaded_at": time.time(),
            "content": content,
        },
        "buffers": [],
        "globals": {},
        "repo_index": None,
    }
    _save_state(state, state_path)

    print(f"Initialised RLM REPL state at: {state_path}")
    print(f"Loaded context: {ctx_path} ({len(content):,} chars)")
    return 0


def cmd_init_repo(args: argparse.Namespace) -> int:
    """Initialize state for a code repository."""
    state_path = Path(args.state)
    repo_path = Path(args.repo_path).resolve()

    if not repo_path.exists():
        raise RlmReplError(f"Repository path does not exist: {repo_path}")
    if not repo_path.is_dir():
        raise RlmReplError(f"Repository path is not a directory: {repo_path}")

    print(f"Indexing repository: {repo_path}")
    print("This may take a moment for large repositories...")

    # Load filter spec; if no flags and no .rlmignore, spec is empty and
    # downstream behaviour is identical to the pre-change path.
    filter_spec = _load_filter_spec(args, repo_path)
    active_filters = bool(filter_spec.get("excludes") or filter_spec.get("includes"))

    filter_stats: Optional[Dict[str, Any]] = None
    if active_filters:
        discovered = _discover_git_files(repo_path)
        kept, filter_stats = _apply_filters(discovered, repo_path, filter_spec)
        repo_index = _build_repo_index(
            repo_path, max_file_size_mb=args.max_file_size_mb, files=kept
        )
    else:
        # Backward-compat path: no filter work, no extra discovery.
        repo_index = _build_repo_index(
            repo_path, max_file_size_mb=args.max_file_size_mb
        )

    # Create state
    state: Dict[str, Any] = {
        "version": 1,
        "context": {
            "path": str(repo_path),
            "loaded_at": time.time(),
            "content": "",  # Empty for repo mode
        },
        "buffers": [],
        "globals": {},
        "repo_index": repo_index,
    }
    _save_state(state, state_path)

    # Print summary
    total_files = repo_index['total_files']
    total_size_mb = repo_index['total_size'] / (1024 * 1024)

    print(f"\n✓ RLM initialized for repository: {repo_path}")
    print(f"  - {total_files:,} files indexed")
    print(f"  - Size: {total_size_mb:.1f} MB")

    # Show top languages
    langs = sorted(
        repo_index['languages'].items(),
        key=lambda x: x[1]['count'],
        reverse=True
    )
    if langs:
        print(f"  - Primary languages:")
        for lang, stats in langs[:5]:
            count = stats['count']
            pct = (count / total_files * 100) if total_files > 0 else 0
            print(f"    • {lang}: {count} files ({pct:.1f}%)")

    for line in _format_filter_stats(filter_stats):
        print(line)

    print(f"  - State saved to: {state_path}")
    print(f"\nNext steps:")
    print(f"  python3 {sys.argv[0]} status  # View index status")
    print(f"  python3 {sys.argv[0]} exec -c 'print(repo_index)' # Explore index")

    return 0


def cmd_status(args: argparse.Namespace) -> int:
    state = _load_state(Path(args.state))
    ctx = state.get("context", {})
    content = ctx.get("content", "")
    buffers = state.get("buffers", [])
    g = state.get("globals", {})
    repo_index = state.get("repo_index")

    print("RLM REPL status")
    print(f"  State file: {args.state}")
    print(f"  Context path: {ctx.get('path')}")

    if repo_index:
        # Repository mode
        print(f"  Mode: Repository")
        print(f"  Total files: {repo_index['total_files']:,}")
        print(f"  Total size: {repo_index['total_size'] / (1024 * 1024):.1f} MB")
        print(f"  Languages: {len(repo_index['languages'])}")
        if args.show_vars:
            langs = sorted(
                repo_index['languages'].items(),
                key=lambda x: x[1]['count'],
                reverse=True
            )
            for lang, stats in langs[:10]:
                print(f"    - {lang}: {stats['count']} files")
    else:
        # Single file mode
        print(f"  Mode: Single file")
        print(f"  Context chars: {len(content):,}")

    print(f"  Buffers: {len(buffers)}")
    print(f"  Persisted vars: {len(g)}")
    if args.show_vars and g:
        print(f"  Variables:")
        for k in sorted(g.keys()):
            print(f"    - {k}")
    return 0


def cmd_reset(args: argparse.Namespace) -> int:
    state_path = Path(args.state)
    if state_path.exists():
        state_path.unlink()
        print(f"Deleted state: {state_path}")
    else:
        print(f"No state to delete at: {state_path}")
    return 0


def cmd_export_buffers(args: argparse.Namespace) -> int:
    state = _load_state(Path(args.state))
    buffers = state.get("buffers", [])
    out_path = Path(args.out)
    _ensure_parent_dir(out_path)
    out_path.write_text("\n\n".join(str(b) for b in buffers), encoding="utf-8")
    print(f"Wrote {len(buffers)} buffers to: {out_path}")
    return 0


def cmd_exec(args: argparse.Namespace) -> int:
    state_path = Path(args.state)
    state = _load_state(state_path)

    ctx = state.get("context")
    if not isinstance(ctx, dict):
        raise RlmReplError("State is missing a valid 'context'. Re-run init or init-repo.")

    buffers = state.setdefault("buffers", [])
    if not isinstance(buffers, list):
        buffers = []
        state["buffers"] = buffers

    persisted = state.setdefault("globals", {})
    if not isinstance(persisted, dict):
        persisted = {}
        state["globals"] = persisted

    repo_index = state.get("repo_index")

    code = args.code
    if code is None:
        code = sys.stdin.read()

    # Build execution environment.
    # Start from persisted variables, then inject context, buffers and helpers.
    env: Dict[str, Any] = dict(persisted)
    env["context"] = ctx
    env["content"] = ctx.get("content", "")
    env["buffers"] = buffers
    if repo_index:
        env["repo_index"] = repo_index

    helpers = _make_helpers(ctx, buffers)
    env.update(helpers)

    # Capture output.
    stdout_buf = io.StringIO()
    stderr_buf = io.StringIO()

    try:
        with redirect_stdout(stdout_buf), redirect_stderr(stderr_buf):
            exec(code, env, env)
    except Exception:
        traceback.print_exc(file=stderr_buf)

    # Pull back possibly mutated context/buffers.
    maybe_ctx = env.get("context")
    if isinstance(maybe_ctx, dict) and "content" in maybe_ctx:
        state["context"] = maybe_ctx
        ctx = maybe_ctx

    maybe_buffers = env.get("buffers")
    if isinstance(maybe_buffers, list):
        state["buffers"] = maybe_buffers
        buffers = maybe_buffers

    # Persist any new variables, excluding injected keys.
    injected_keys = {
        "__builtins__",
        "context",
        "content",
        "buffers",
        "repo_index",
        *helpers.keys(),
    }
    to_persist = {k: v for k, v in env.items() if k not in injected_keys}
    filtered, dropped = _filter_pickleable(to_persist)
    state["globals"] = filtered

    _save_state(state, state_path)

    out = stdout_buf.getvalue()
    err = stderr_buf.getvalue()

    if dropped and args.warn_unpickleable:
        msg = "Dropped unpickleable variables: " + ", ".join(dropped)
        err = (err + ("\n" if err else "") + msg + "\n")

    if out:
        sys.stdout.write(_truncate(out, args.max_output_chars))

    if err:
        sys.stderr.write(_truncate(err, args.max_output_chars))

    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="rlm_repl",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=textwrap.dedent(
            """\
            Persistent mini-REPL for RLM-style workflows.

            Examples:
              python rlm_repl.py init context.txt
              python rlm_repl.py status
              python rlm_repl.py exec -c "print(len(content))"
              python rlm_repl.py exec <<'PY'
              print(peek(0, 2000))
              PY
            """
        ),
    )
    p.add_argument(
        "--state",
        default=str(DEFAULT_STATE_PATH),
        help=f"Path to state pickle (default: {DEFAULT_STATE_PATH})",
    )

    sub = p.add_subparsers(dest="cmd", required=True)

    p_init = sub.add_parser("init", help="Initialise state from a context file")
    p_init.add_argument("context", help="Path to the context file")
    p_init.add_argument(
        "--max-bytes",
        type=int,
        default=None,
        help="Optional cap on bytes read from the context file",
    )
    p_init.set_defaults(func=cmd_init)

    p_init_repo = sub.add_parser(
        "init-repo",
        help="Initialise state from a code repository (indexes all files)"
    )
    p_init_repo.add_argument(
        "repo_path",
        help="Path to the repository root directory"
    )
    p_init_repo.add_argument(
        "--max-file-size-mb",
        type=int,
        default=10,
        help="Mark files larger than this as 'too_large' (default: 10 MB)",
    )
    p_init_repo.add_argument(
        "--exclude",
        action="append",
        default=[],
        metavar="PATTERN",
        help=(
            "Gitignore-style pattern to exclude (repeatable). "
            "Example: --exclude 'html/**' --exclude 'vendor/**'"
        ),
    )
    p_init_repo.add_argument(
        "--include",
        action="append",
        default=[],
        metavar="PATTERN",
        help=(
            "Gitignore-style allowlist pattern (repeatable). "
            "When given, only files matching at least one --include are kept. "
            "Example: --include 'src/**' --include 'tests/**'"
        ),
    )
    p_init_repo.add_argument(
        "--exclude-from",
        metavar="FILE",
        help=(
            "Read exclude patterns from FILE (one pattern per line, "
            "# for comments, .rlmignore format). "
            "Overrides any auto-discovered .rlmignore."
        ),
    )
    p_init_repo.add_argument(
        "--no-rlmignore",
        action="store_true",
        help="Disable automatic discovery of .rlmignore in cwd/ancestors/repo-root.",
    )
    p_init_repo.set_defaults(func=cmd_init_repo)

    p_status = sub.add_parser("status", help="Show current state summary")
    p_status.add_argument(
        "--show-vars", action="store_true", help="List persisted variable names"
    )
    p_status.set_defaults(func=cmd_status)

    p_reset = sub.add_parser("reset", help="Delete the current state file")
    p_reset.set_defaults(func=cmd_reset)

    p_export = sub.add_parser(
        "export-buffers", help="Export buffers list to a text file"
    )
    p_export.add_argument("out", help="Output file path")
    p_export.set_defaults(func=cmd_export_buffers)

    p_exec = sub.add_parser("exec", help="Execute Python code with persisted state")
    p_exec.add_argument(
        "-c",
        "--code",
        default=None,
        help="Inline code string. If omitted, reads code from stdin.",
    )
    p_exec.add_argument(
        "--max-output-chars",
        type=int,
        default=DEFAULT_MAX_OUTPUT_CHARS,
        help=f"Truncate stdout/stderr to this many characters (default: {DEFAULT_MAX_OUTPUT_CHARS})",
    )
    p_exec.add_argument(
        "--warn-unpickleable",
        action="store_true",
        help="Warn on stderr when variables could not be persisted",
    )
    p_exec.set_defaults(func=cmd_exec)

    return p


def main(argv: List[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        return int(args.func(args))
    except RlmReplError as e:
        sys.stderr.write(f"ERROR: {e}\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
