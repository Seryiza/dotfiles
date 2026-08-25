# Accept the River production pilot

Status: wontfix
Blocked by: 06

## Objective

Validate the candidate in a real UWSM-managed graphical session and through at least one working day of normal use.

## Scope

- Install the candidate as a new boot generation, reboot, and verify Mango before selecting River.
- Test UWSM environment finalization, `uwsm stop`, normal and abnormal compositor exit, and repeated login/logout.
- Verify exactly one matching Waybar and one Soteria agent in Mango, River, and Sway.
- Test keyboard, touchpad, xremap, output, DPMS, lock, suspend/resume, lock-before-suspend, and media idle inhibition.
- Test portals, privacy indication, screenshots, region capture, clipboard, Drawing, Mako, and audio/media/brightness controls with visible feedback.
- Smoke-test bindings, Alacritty, Emacs, browsers, work browser, Enpass, Telegram, Electron, tray applications, native Wayland, Xwayland, activation/focus behavior, and repeated decorated/transient/Picture-in-Picture/layer-shell clients.
- Verify AMD remains the primary renderer and `nvidia-offload vkcube` visibly uses the NVIDIA renderer.
- Verify configured and hotplug-discovered output coordinates remain nonnegative and within River's Xwayland coordinate bounds.
- Record all results and blockers in this ticket.

## Acceptance Criteria

- No stale River, Machi, Waybar, Soteria, or session environment remains after logout or compositor failure.
- Exactly one appropriate Waybar process and one graphical authentication agent run in each tested session.
- Graphical polkit prompting, portals, lock, input, output, critical applications, AMD rendering, and NVIDIA offload succeed.
- `eDP-1` returns in the expected mode and scale after DPMS and suspend/resume, and all observed output coordinates remain within River's Xwayland bounds.
- If output state does not survive, acceptance is blocked and a focused agent ticket must replace the one-shot policy with kanshi before this pilot is repeated.
- At least one complete working-day pilot succeeds.
- Missing compositor-state, workspace, layout, and language indicators are not treated as blockers.

## Comments

- 2026-08-25: Superseded by the Zelbar-based River status-panel rollout and its acceptance gates under `.scratch/river-machi-zelbar/`; this Waybar-specific pilot is no longer executable against the current tree.
