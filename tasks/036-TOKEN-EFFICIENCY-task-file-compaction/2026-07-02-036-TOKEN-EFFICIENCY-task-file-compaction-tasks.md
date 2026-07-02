# 036: Token Efficiency in embo Task Files — Task List

## Relevant Files

- [tasks/036-TOKEN-EFFICIENCY-task-file-compaction/2026-07-02-036-TOKEN-EFFICIENCY-task-file-compaction-tech-design.md](2026-07-02-036-TOKEN-EFFICIENCY-task-file-compaction-tech-design.md)
  :: Technical Design — validated compaction rule + component specs
- [tasks/036-TOKEN-EFFICIENCY-task-file-compaction/2026-07-02-036-TOKEN-EFFICIENCY-task-file-compaction-prd.md](2026-07-02-036-TOKEN-EFFICIENCY-task-file-compaction-prd.md)
  :: PRD — problem statement + scope + constraints
- [plugin/commands/impl.md](../../../plugin/commands/impl.md)
  :: Evidence note format block to extend (lines 147–160)
- [plugin/commands/start.md](../../../plugin/commands/start.md)
  :: Task file reading instruction to replace (lines 439–441)
- [plugin/commands/wrapup.md](../../../plugin/commands/wrapup.md)
  :: New command file (to be created)
- [plugin/.claude-plugin/plugin.json](../../../plugin/.claude-plugin/plugin.json)
  :: Version bump 0.1.2 → 0.1.3
- [README.md](../../../README.md)
  :: Command table update (add /embo:wrapup)

## Notes

- All changes are to Markdown command files — no runtime code, no shell
  scripts, no Python.
- TDD does not apply to Markdown prompt files. All subtasks use
  `code-only` or `manual-run-claude` verification.
- Verification of command behaviour changes requires running the actual
  command in a real session, not a simulated check.
- `/embo:wrapup` compaction must never touch `[ ]` or `[~]` subtasks —
  only `[X]` subtask bodies and their evidence notes.
- The validated compaction rule lives in the tech-design and must be
  copied verbatim into both `impl.md` and `wrapup.md`.

## Tasks

- [ ] 1.0 **User Story:** As a developer running `/embo:impl`, I want
  evidence notes to be compact from the moment they are written, so
  that task files do not accumulate process narration during
  implementation. [0/2]
  - [X] 1.1 Insert compact summary rule block into `impl.md` after
    line 151 (after the closing ` ``` ` of the evidence format block),
    using the exact text from tech-design §Component 1
    [verify: code-only]
  - [X] 1.2 Verify the inserted block reads correctly in context —
    confirm the bad/good examples are adjacent to the format they
    constrain and no formatting is broken [verify: manual-run-claude]
      → compact summary rule at impl.md:153–167, adjacent to format
        template; examples block unaffected; sanitization section follows
        cleanly [live] (2026-07-02)

- [X] 1.0 **User Story:** As a developer running `/embo:impl`, I want
  evidence notes to be compact from the moment they are written, so
  that task files do not accumulate process narration during
  implementation. [2/2]

- [ ] 2.0 **User Story:** As a developer starting a session, I want
  `/embo:start` to skip completed subtask bodies for mostly-done task
  files, so that startup context cost scales with remaining work. [0/2]
  - [X] 2.1 Replace `start.md` lines 439–441 (unconditional task file
    read) with the two-path completeness-gated instruction from
    tech-design §Component 2 [verify: code-only]
  - [X] 2.2 Run `/embo:start` with task 032's tasks file in place
    (≥80% complete); confirm the session summary omits completed
    subtask bodies and evidence notes [verify: manual-run-claude]
      → 032 shown as "complete" with no subtask bodies; 036 shown
        with open stories only [live] (2026-07-02)

- [X] 2.0 **User Story:** As a developer starting a session, I want
  `/embo:start` to skip completed subtask bodies for mostly-done task
  files, so that startup context cost scales with remaining work. [2/2]

- [ ] 3.0 **User Story:** As a developer ending a session, I want
  `/embo:wrapup` to compact task files, surface uncommitted work, and
  optionally save a session observation, so that the next session
  starts lean. [0/5]
  - [ ] 3.1 Create `plugin/commands/wrapup.md` with YAML frontmatter
    and the four-step process from tech-design §Component 3 (identify
    touched files, compact with confirmation, surface uncommitted work,
    optional claude-mem observation) [verify: code-only]
  - [ ] 3.2 Verify the compaction step in `wrapup.md`: run
    `/embo:wrapup` on a task file that has verbose `[X]` evidence;
    confirm the diff summary is shown and the file is only written
    after confirmation [verify: manual-run-claude]
  - [ ] 3.3 Verify the uncommitted-work step: run `/embo:wrapup` with
    a dirty working tree (a modified file); confirm modified files are
    listed and the commit/skip choice is presented
    [verify: manual-run-claude]
  - [ ] 3.4 Verify the safety constraint: run `/embo:wrapup` and
    confirm it does not offer to compact `[ ]` or `[~]` subtasks, and
    does not touch PRD/tech-design files [verify: manual-run-claude]
  - [ ] 3.5 Verify the no-modified-files path: run `/embo:wrapup` in
    a session where no task files were touched; confirm it reports
    "no task files modified" and skips to the uncommitted-work step
    [verify: manual-run-claude]

- [X] 5.0 **User Story:** As a developer using `/embo:impl`, I want RLM
  discovery to use functions that actually exist, so that context
  discovery works instead of silently failing. [2/2]
  - [X] 5.1 Replace broken exec blocks in `impl.md` Step 3a and 3c
    (`find_files_by_pattern`, `find_symbol`, `write_file_chunks`,
    `get_related_files`) with Glob tool + working `grep` exec calls;
    document available helpers explicitly [verify: code-only]
  - [X] 5.2 Deploy fixed `impl.md` to plugin cache for immediate effect
    [verify: code-only]

- [ ] 4.0 **User Story:** As an embo plugin user, I want the version
  bump and README update to be in place so that `/plugin update`
  delivers this feature. [0/2]
  - [ ] 4.1 Bump `plugin/.claude-plugin/plugin.json` version from
    `0.1.2` to `0.1.3` [verify: code-only]
  - [ ] 4.2 Add `/embo:wrapup` row to the command table in `README.md`
    with a one-line description consistent with the other entries
    [verify: code-only]
