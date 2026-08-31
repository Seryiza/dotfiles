---
name: commit-worktree
description: Analyze current staged and unstaged changes and create semantic Git commits.
disable-model-invocation: true
argument-hint: "[verify]"
---

# Commit worktree

Package all committable staged and unstaged changes into semantic Git commits. This is a commit workflow, not an implementation or code-review workflow.

## Inspect

Run only the minimum discovery needed:

1. `git status --short --branch`
2. staged and unstaged diff stats
3. recent commit subjects to learn repository wording
4. every staged and unstaged diff, grouped by subsystem

Read unchanged code only when a diff cannot be understood without it.

## Classify

Partition changes into the smallest independent commits that remain understandable. Group by behavior, not file type.

Keep together:

- implementation and its tests;
- configuration and its generated lockfile;
- package override and its patch;
- a rename and its directly updated references.

Separate unrelated features, fixes, refactors, documentation, formatting, and generated state. Exclude secrets, runtime caches, logs, editor state, and build artifacts.

## Preserve

Default mode is commit-only:

- preserve worktree contents;
- do not refactor, reformat, or improve code;
- do not create documentation;
- do not invoke subagents;
- do not run project-wide tests or builds;
- reuse verification already reported in the conversation.

Stop and report only when changes are unsafe, incomplete, or cannot be grouped reliably.

## Verify

Always run `git diff --check`.

When invoked with `verify`, additionally run the smallest checks directly covering the changed behavior. Prefer targeted checks over full suites. Existing successful verification and commit hooks count as evidence.

## Commit messages

Follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

Use lowercase types consistently:

- `feat` for a new user-visible capability;
- `fix` for a bug fix;
- `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `style`, or `revert` when they accurately describe the change.

The optional scope MUST be the module name or the program whose configuration changes. Use the repository's established spelling, preferably lowercase. Examples:

- `fix(mako): retry frames after busy buffers`
- `feat(river): remap terminal shortcut`
- `chore(emacs): record installed packages`
- `chore(nixos): refresh workstation packages`

For a genuinely cross-module change, omit the scope instead of inventing a generic scope such as `config`, `misc`, or `repo`.

Mark breaking changes with `!` before the colon or a `BREAKING CHANGE:` footer. Keep the description concise and concrete. Add a body or footer only when the subject cannot preserve essential context.

## Commit

Before each commit, stage only its semantic group and ensure unrelated staged changes cannot leak into it. Preserve deliberate partial staging when present.

After committing, run `git status --short --branch` and print the created commit hashes and subjects. Completion requires:

- every committable change committed;
- every exclusion explained;
- a clean status except explicitly reported exclusions;
- no push.
