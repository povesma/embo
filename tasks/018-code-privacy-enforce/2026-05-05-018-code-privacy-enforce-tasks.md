# 018-code-privacy-enforce: Tasks

**PRD**: [2026-05-05-018-code-privacy-enforce-prd.md](2026-05-05-018-code-privacy-enforce-prd.md)
**Status**: Complete
**Created**: 2026-05-05

---

## Relevant Files

- `.claude/commands/dev/prd.md` — added Step 5.6 Sanitization Pass
- `.claude/commands/dev/tech-design.md` — added Step 6.5 Sanitization Pass
- `.claude/commands/dev/impl.md` — added Evidence Note Sanitization subsection

---

## Tasks

- [X] 1.0 **User Story:** As a workflow author, I want PRD docs to be sanitized before save so private deployment data does not leak into committed PRDs [1/1]
  - [X] 1.1 Insert `### Step 5.6: Sanitization Pass (MANDATORY)` in `.claude/commands/dev/prd.md` between existing Step 5.5 and Step 6, body <= 6 lines per FR-6, with working-state exception and CLAUDE.md deferral [verify: code-only]
    → inserted at prd.md:265-270; 4 wrapped body lines + heading + blank, within budget; references CLAUDE.md "Documentation Sanitization" rule and Step 5.5 orthogonality (2026-05-05)

- [X] 2.0 **User Story:** As a workflow author, I want tech-design docs sanitized before save with the same rule, without restating the rule [1/1]
  - [X] 2.1 Insert `### Step 6.5: Sanitization Pass (MANDATORY)` in `.claude/commands/dev/tech-design.md` immediately before Step 7 (Save to File), body <= 4 lines per FR-6, refer back to `/dev:prd` Step 5.6 instead of restating [verify: code-only]
    → inserted at tech-design.md:342-346; 3 wrapped body lines + heading + blank, within budget; refers to /dev:prd Step 5.6 and notes orthogonality to Step 1.5 (2026-05-05)

- [X] 3.0 **User Story:** As a workflow author, I want evidence notes in impl sessions to be sanitized at write time so live command output does not leak into task records [1/1]
  - [X] 3.1 Insert `### Evidence Note Sanitization` subsection in `.claude/commands/dev/impl.md` after the Evidence note format examples block, body <= 6 lines per FR-6 including one Bad/Good example pair, no working-state exception (sanitize at write time per FR-2/FR-4) [verify: code-only]
    → inserted at impl.md:155-160; 5 body lines including one Bad/Good example pair, within budget; explicit "no working-state exception" wording (2026-05-05)
