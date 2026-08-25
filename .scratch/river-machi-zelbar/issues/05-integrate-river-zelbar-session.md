# Integrate the River Zelbar session

Status: ready-for-agent
Blocked by: 01, 03, 04

## Objective

Make the Go status Module and pinned Zelbar package the only automatic bar path in the River session while preserving Mango and Sway Waybar behavior. Issue 08 may add only the allowlisted local HiDPI patch to that package.

## Scope

- Add `nixos/home/zelbar.nix` and import it from `nixos/home.nix`.
- Install exact Zelbar, status Module and Noto Color Emoji/font fallback requirements.
- Generate `zelbar-river.service` with River target ordering/binding, WAYLAND_DISPLAY condition, restart policy and control-group killing.
- Bake absolute executable/script paths and fixed `eDP-1`/theme/layout policy into the launcher.
- Render a top full-width 20px white/black Iosevka panel.
- Remove `river` from `profileBySessionIdentity` in `nixos/home/waybar.nix`.
- Remove River Waybar launcher case and target link.
- Preserve Mango top+bottom profile/link and Sway generic profile/link unchanged.
- Do not modify `nixos/home/river.nix`, `nixos/home/mango.nix` or `nixos/home/waybar.css`.

## Acceptance Criteria

- Home generation contains one River Zelbar unit/link and no River Waybar link/case.
- Mango and Sway Waybar profiles, cases and links are unchanged.
- `systemd-analyze --user verify` passes for the River Zelbar unit and UWSM target graph.
- Normal River target stop does not trigger unwanted restart.
- Failure of the status main process kills remaining children before restart.
- No custom environment marker or socket-presence session detection is introduced.
- Full `yuri-alpha` toplevel build succeeds.

## Comments
