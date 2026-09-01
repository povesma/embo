# Idea: PRD-tree replay refactoring

Principle (documented in start.md RULE:FOLD-FIRST): replaying the docs
tree from scratch must rebuild the current product.

Idea: periodically refactor the PRD tree into a shorter, more optimal
set of PRDs that replays to the same outcome — merging amendments into
their features, dropping superseded branches, collapsing historical
detours. The test for any refactoring: replaying the refactored tree
produces a product equivalent to replaying the original tree.

Value: smaller docs tree → cheaper discovery (start/scout/init), less
double-specification, clearer per-feature state.

Open questions: equivalence check mechanics; what history must be
preserved elsewhere (claude-mem) before a detour is collapsed.
