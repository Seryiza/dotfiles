# Package River, Machi, and channel

Status: ready-for-agent
Blocked by: none

## Objective

Provide a reproducible, narrowly scoped River stack without changing the primary stable package set or enabling a login session.

## Scope

- Source River 0.4.8 only from the already pinned unstable package set; do not add a global unstable overlay.
- Package Machi from commit `65a0fc12f2796f41f4c9cbb7e034aaa137009b01` and source hash `sha256-StpGIGnIjtdEQ9fWdsei6n93IJOG6BG7gRKaOS9sI24=`.
- Package `channel` 0.4.1 from commit `4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446` and source hash `sha256-AIP5SO7p2Z8fYeLSoIliSya2fQALV1xkkYfIRdHY6TQ=`.
- Generate and fix the Zig dependency hashes; do not commit placeholder hashes.
- Expose package artifacts for direct builds and later module integration.
- Do not register River with the display manager or activate new session services.

## Acceptance Criteria

- River, Machi, and `channel` build in the Nix sandbox without network access.
- The expected executables exist and expose the intended versions or revisions.
- Evaluation shows stable nixpkgs remains primary and only River is narrowly sourced from unstable.
- `nix build .#nixosConfigurations.yuri-alpha.config.system.build.toplevel` succeeds.
- Every implementation commit leaves the complete `yuri-alpha` toplevel buildable.

## Comments
