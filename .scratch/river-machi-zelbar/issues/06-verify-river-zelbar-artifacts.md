# Verify River Zelbar artifacts

Status: ready-for-agent
Blocked by: 05

## Objective

Add repository-level automated gates for packaging, generated Home Manager artifacts, transport and session ownership.

## Scope

- Add `nixos/tests/zelbar-runtime.nix` for package tests, Go tests and packet/lifecycle fixtures.
- Add `nixos/tests/zelbar-session.nix` for generated unit/link/profile assertions.
- Update `nixos/tests/waybar-session-profiles.nix` to expect only Mango/Sway Waybar identities.
- Update `nixos/tests/river-session-policy.nix` to assert exactly one River bar owner.
- Register checks in `flake.nix` using the existing `yuriArtifacts` pattern.
- Verify exact renderer revision and an exact one-file patch allowlist containing only `nixos/pkgs/zelbar-hidpi.patch`.
- Reject `postPatch`, substitutions, source forks, additional patches and arbitrary modified renderer sources.
- Add scale 1/2 regression coverage for `wl_surface` buffer scale, physical SHM dimensions and scale-change commit ordering; keep pixel sharpness as a human gate.
- Keep current staged River decoration/XKB tests intact.

## Acceptance Criteria

- `nix flake check` passes.
- Full `yuri-alpha` toplevel build passes.
- Checks reject a River Waybar link, duplicate bar owner, wrong Zelbar revision, any renderer patch outside the exact HiDPI allowlist, missing BindsTo, ordinary pipe transport and frames over 4096 bytes.
- Differential tests prove logical `W×20` maps to physical `W×20` at scale 1 and `2W×40` at scale 2, including a runtime scale transition.
- Checks retain Mango/Sway Waybar assertions.
- Generated unit graph passes `systemd-analyze --user verify`.
- Every implementation commit remains independently buildable.

## Comments

The original blanket renderer-patch prohibition is obsolete after failed scale-2 acceptance. Verification must now allow one named local patch while remaining strict enough to prevent substitutions, forks or unrelated renderer changes.
