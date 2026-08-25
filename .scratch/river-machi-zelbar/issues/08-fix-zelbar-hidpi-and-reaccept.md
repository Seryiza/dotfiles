# Fix Zelbar HiDPI and repeat acceptance

Status: ready-for-human
Blocked by: 06

## Objective

Apply one minimal local HiDPI patch to the pinned Zelbar v1.2.0 source, prove the full logical-size-to-physical-rendering chain at scale 1 and scale 2, and repeat mandatory human acceptance on `yuri-alpha`.

## Scope

- Keep upstream commit `b1f1fe4a7f30332fbe6bffeaea77ef292c0f1932` and its fixed source/dependency hashes unchanged.
- Add only `nixos/pkgs/zelbar-hidpi.patch`; do not use `postPatch`, substitutions, a fork or unrelated renderer edits.
- Handle initial and subsequent `wl_output.scale` events.
- Call `wl_surface.set_buffer_scale` with the active positive integer scale before the matching surface commit.
- Preserve layer-shell geometry in logical units and keep `-g 0:20` at 20 logical pixels.
- Allocate SHM buffers at `logical_width * scale` × `logical_height * scale` physical pixels.
- Rasterize fonts, text and decorations at the same physical scale, with matching damage/attach/commit semantics.
- Recreate scale-dependent resources and redraw safely when output scale changes.
- Do not change stdin framing, status-module protocol or process ownership.
- Add a deterministic differential regression harness for scale 1, scale 2 and a live scale transition at the narrowest real renderer seam.
- Update package checks to allow exactly this patch and reject every other renderer source mutation.
- Do not contact or contribute to upstream.
- If correctness requires a broad renderer redesign, stop and present replacement-renderer options instead of growing a local fork.

## Acceptance Criteria

### Automated

- The pre-fix differential test fails because scale 2 still reports/uses a 1× physical buffer.
- Scale 1 maps logical `W×20` to buffer scale 1 and physical `W×20`.
- Scale 2 maps logical `W×20` to buffer scale 2 and physical `2W×40`.
- A scale 1→2 and 2→1 transition updates buffer scale, physical dimensions, font/decorations and commit ordering without retaining stale resources.
- Nix evaluation proves the exact upstream revision and exactly one patch path, and rejects `postPatch`, substitutions, forks and extra patches.
- Focused Zelbar checks, Go tests, relevant Nix checks, `nix flake check`, and `nix build .#nixosConfigurations.yuri-alpha.config.system.build.toplevel` pass.

### Human gate

- Activate through a rollback-protected generation on `yuri-alpha`.
- Compare scale 1 and scale 2: text is sharp at both scales, the bar remains at the top with 20 logical pixels, and text/decorations are neither clipped nor displaced.
- Confirm the normal `-g 0:20` launcher and status framing remain unchanged.
- Restart the service and exercise scale changes, suspend/resume, River logout/login and a fresh session; no blurry stale buffer, clipping, orphan or restart loop remains.
- Capture `wlr-randr`, the running Zelbar argv and a screenshot for the repeated acceptance record.
- After automated work, set this ticket to `ready-for-human`; do not mark the feature accepted until this visual gate passes.

## Comments

Created after issue 07 failed on `eDP-1` scale 2. The observed symptom is compositor upscaling of a 1× Zelbar buffer, not a font-family choice and not the `-L 1` layer selector.

Automated implementation is complete. The pre-fix headless River differential trace passed at scale 1 (`800×20` logical/physical) and failed deterministically at scale 2 (`400×20` logical incorrectly used as a `400×20` SHM buffer, with no `set_buffer_scale`; expected `800×40`). The local patch now passes initial scale 1, initial scale 2 and live 1→2→1 transitions. Traces prove matching buffer scale, physical SHM size, full-buffer damage, attach and commit ordering. Fontconfig verification proves `scale=2` doubles raster pixels, while headless screenshots prove border/background scaling and glyph-height transitions `10→19→10` across scale `1→2→1`. Go tests, focused Nix checks, `nix flake check` and the complete `yuri-alpha` toplevel build pass. The remaining gate is the real-panel procedure in `nixos/pkgs/river-zelbar-status/LIVE_ACCEPTANCE.md`.
