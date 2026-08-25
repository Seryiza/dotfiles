# Package pinned Zelbar

Status: ready-for-agent
Blocked by: none

## Objective

Provide an exact, reproducible Zelbar v1.2.0 package pinned to commit `b1f1fe4a7f30332fbe6bffeaea77ef292c0f1932`. The initial package was unmodified; issue 08 now owns the sole allowlisted local HiDPI patch after scale-2 acceptance exposed an upstream renderer defect.

## Scope

- Add `nixos/pkgs/zelbar.nix` for commit `b1f1fe4a7f30332fbe6bffeaea77ef292c0f1932`.
- Use a fixed SourceHut source hash.
- Build with `zig_0_15`, Wayland, wayland-protocols, fcft, pixman and pkg-config.
- Materialize `zig-pixman`, `zig-wayland` and `zig-fcft` dependencies for offline sandbox builds.
- Set correct GPL-3.0-only metadata.
- Add package to the existing narrow overlay and `packages.x86_64-linux` without renaming or broadening unrelated package policy.
- Keep the upstream source pin unchanged.
- Permit only `nixos/pkgs/zelbar-hidpi.patch` via the explicit Nix `patches` attribute added by issue 08.
- Carry no `postPatch`, substitutions, source fork, additional patches or unrelated source edits.

## Acceptance Criteria

- `nix build .#zelbar` succeeds without build-time network access.
- `$out/bin/zelbar -version` reports 1.2.0.
- Evaluated derivation points at the exact commit and, after issue 08, contains exactly the allowlisted local HiDPI patch with no other patch phase customization.
- Source/build test records the exact source and dependency hashes rather than placeholders.
- Full `yuri-alpha` toplevel build succeeds.

## Comments

Initial human acceptance on `yuri-alpha` found blurry text at `eDP-1` scale 2 because upstream Zelbar rendered a 1× buffer and ignored `wl_output.scale`. The no-patch constraint is superseded only by the narrowly scoped work in issue 08; the upstream revision remains pinned.
