# Emacs configuration

`~/.emacs.d` is a live symlink into this checkout. Configuration source stays
in the repository; generated package data, persistent state, and caches use XDG
directories instead.

## XDG layout

- `$XDG_DATA_HOME/emacs/` (default `~/.local/share/emacs/`) contains durable
  package data such as ELPA packages and the Elfeed database.
- `$XDG_STATE_HOME/emacs/` (default `~/.local/state/emacs/`) contains Custom,
  histories, project metadata, backups, auto-saves, Org state, and URL cookies.
- `$XDG_CACHE_HOME/emacs/` (default `~/.cache/emacs/`) contains native-compile,
  tree-sitter, URL, SVG, Org persistence, and package quickstart caches.

`early-init.el` validates the roots and prepares only package activation,
Custom, quickstart, and native-compile paths. Other paths belong to their
package's `use-package :init` form and fail before that package is consumed.
Nix manages the source link and declared packages; it does not migrate mutable
package or state trees. Existing user data is intentionally retained.

## Tests

From the repository root, run the permanent ERT suites with HOME, TMPDIR, and
every XDG root isolated:

```sh
tmp="$(mktemp -d)" || exit 1
repo="$PWD/dotfiles/emacs"; \
mkdir -p "$tmp/home" "$tmp/data" "$tmp/state" "$tmp/cache" "$tmp/runtime" "$tmp/tmp"; \
HOME="$tmp/home" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state" \
XDG_CACHE_HOME="$tmp/cache" XDG_RUNTIME_DIR="$tmp/runtime" TMPDIR="$tmp/tmp" \
EMACS_TEST_SOURCE="$repo" emacs -Q --batch \
--eval '(setq user-emacs-directory (file-name-as-directory (getenv "EMACS_TEST_SOURCE")))' \
--load "$repo/early-init.el" \
--load "$repo/tests/sz-state-test.el" \
--load "$repo/tests/sz-org-status-test.el" \
--funcall ert-run-tests-batch-and-exit; \
status=$?; rm -rf "$tmp"; exit $status
```

This harness exercises isolated state and module boundaries, not a full user
initialization with installed packages.
