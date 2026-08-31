---
name: commit-worktree
description: Commit all committable worktree changes as semantic commits.
disable-model-invocation: true
argument-hint: "[verify]"
---

# Commit worktree

Commit-only workflow. Preserve file contents: do not refactor, reformat, document, invoke subagents, run broad checks, or push. Reuse verification already reported. Stop if changes are unsafe, incomplete, or cannot be grouped reliably.

## Inspect

1. Run `git status --short --branch`.
2. Inspect every staged and unstaged patch and every non-excluded untracked file, grouped by subsystem.
3. Read the five most recent commit subjects for repository wording.

Use diff stats only when the change set is too large to classify directly. Read unchanged code only when needed to understand a diff.

## Group

Create one commit per independently revertible behavior.

Keep implementation with its tests, configuration with its lockfile, overrides with their patches, and renames with updated references. Separate unrelated features, fixes, refactors, docs, formatting, and generated state.

Exclude secrets, caches, logs, editor state, and build artifacts.

Preserve deliberate partial staging: never stage a whole file when that would include unrelated hunks. Stop if existing index boundaries prevent safe grouping.

## Verify and commit

For each group:

1. Stage only its files or hunks.
2. Confirm cached scope with `git diff --cached --name-status`; inspect the cached patch only when hunk boundaries are relevant.
3. Run `git diff --cached --check`.
4. With `verify`, run the smallest targeted check not already successful in the conversation; commit hooks count.
5. Commit using Conventional Commits: `<type>[scope][!]: <description>`.

Use `feat` for a new user-visible capability and `fix` for a defect; otherwise use the precise standard lowercase type. Scope is the lowercase module or program name; omit it for cross-module changes. Use `!` or a `BREAKING CHANGE:` footer for breaking changes. Add a body only when essential.

## Finish

Run `git status --short --branch` once after all commits. Report each created hash and subject plus every exclusion. Completion requires all committable changes committed and a clean status except reported exclusions.
