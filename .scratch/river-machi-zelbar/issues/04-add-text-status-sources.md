# Add text status sources

Status: ready-for-agent
Blocked by: 02

## Objective

Port every in-scope visible generic Waybar text function into internal Go source Adapters.

## Scope

- Poll existing `waybar-org-timeblock` and `waybar-org-current-clock` every 15 seconds; consume first line, hide empty, limit to 60 grapheme clusters.
- Poll `waybar-wireguard short` every 15 seconds; parse JSON `.text`, hide empty and discard tooltip.
- Poll default sink/source through `wpctl` every 2 seconds; render sink percentage or `MUTED`, append `+MIC` when source is unmuted.
- Poll NetworkManager through `nmcli` every 15 seconds; hide healthy connectivity and preserve low/disconnected/linked/disabled visible semantics.
- Read battery sysfs every 60 seconds; hide full and missing battery, otherwise render integer capacity.
- Update `%d %b %H:%M` at startup and minute boundaries.
- Use absolute Nix-store command paths supplied by packaging.
- Keep all sources read-only; do not add click actions.

## Acceptance Criteria

- Fixtures cover valid, empty, malformed, timeout and nonzero-exit outputs for each command source.
- Org/WireGuard failures are hidden and journaled without stale unbounded state.
- Audio tests cover muted/unmuted sink, source mute and malformed output.
- Network tests cover healthy Wi-Fi/Ethernet, `<20%`, disconnected, linked-without-IP and disabled states.
- Battery tests cover full, charging/discharging, missing and malformed sysfs.
- Clock tests cover minute rollover and local timezone formatting.
- Render order matches the specification and empty fields leave no duplicate separators.
- Full `yuri-alpha` toplevel build succeeds.

## Comments
