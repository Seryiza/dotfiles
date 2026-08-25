# Integrate the River session and desktop policy

Status: ready-for-agent
Blocked by: 03

## Objective

Add a complete parallel UWSM-managed River session while retaining Mango and Sway.

## Scope

- Integrate River without enabling the river-classic NixOS module.
- Wrap River so its plain desktop entry is absent and register exactly one UWSM-managed River session.
- Start Machi from River initialization and use `uwsm stop` for logout.
- Express application, lock, capture, hardware-control, and core window-management bindings in Machi semantics rather than copying Mango-only concepts.
- Configure `channel` as the sole River input manager with `us,ru`, `Ctrl+Space`, tap-to-click, natural scrolling, disable-while-typing, `lrm` mapping, and middle emulation; remove `ctrl:nocaps` from XKB options and do not install or start `kwim`.
- Keep xremap as the sole owner of Caps-to-Control and preserve the low-level ordering that makes Caps-based `Ctrl+[` produce Escape.
- Apply `eDP-1` automatically on every River login with `wlr-randr`: `2560x1600@240Hz`, position `(0,0)`, scale 2. Generate no external-output profiles.
- Preserve Xwayland, portals, Mako, swaylock, swayidle, wlopm, media idle inhibition, PipeWire/WirePlumber, existing desktop services, AMD primary rendering, and NVIDIA PRIME offload.
- Activate the generic River Waybar template instance.

## Acceptance Criteria

- The evaluated display-manager session set contains exactly one UWSM River entry, no plain River entry, and retains Mango and Sway.
- River is 0.4.8; Machi and `channel` use their specified commits.
- Generated startup assigns composition to River, window policy to Machi, and input policy to one `channel` instance.
- Generated input policy includes every specified setting, xremap remains the sole Caps-to-Control owner, and Caps-based `Ctrl+[` produces Escape.
- Generated output policy automatically configures only `eDP-1` as specified.
- Bindings preserve the required workflows without reintroducing Mango-only semantics.
- River's Waybar instance is bound to its compositor-specific UWSM target.
- The complete `yuri-alpha` toplevel builds after every implementation commit.

## Comments
