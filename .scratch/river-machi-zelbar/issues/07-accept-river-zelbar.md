# Accept River Zelbar

Status: ready-for-human
Blocked by: 06

## Objective

Validate the renderer, Go status Module and River session behavior on the real `yuri-alpha` graphical session. This initial run failed its scale-2 renderer criterion; issue 08 owns the fix and mandatory repeated acceptance.

## Scope

- Activate through a new rollback-protected NixOS generation.
- Verify one top Zelbar surface on `eDP-1` at scale 2.
- Exercise Machi workspace/panel/mode/window/title changes and River `us`/`ru` switching.
- Check Org, WireGuard, audio, network, battery and minute clock text.
- Exercise long ASCII/Cyrillic/emoji/combining titles and raw `%{}` characters.
- Kill/restart Machi and the status Module; inspect restart latency, CPU and orphan processes.
- Test River logout/login and suspend/resume.
- Login to Mango and Sway and confirm their existing Waybar behavior.

## Acceptance Criteria

- Text is sharp, correctly positioned and not clipped at scale 2.
- Exactly one River bar process graph runs.
- No malformed text crashes Zelbar or injects markup.
- Essential-source failure yields a bounded clean graph restart without POLLHUP busy-loop.
- Optional-source failure degrades only that field and is diagnosable in the journal.
- Logout and next login contain no stale Zelbar/status processes.
- Mango and Sway Waybar sessions are unchanged.
- If a renderer defect requires changing Zelbar source, record the failure and reopen the specification before implementation. This gate fired: the specification now explicitly allows the single patch owned by issue 08.

## Comments

Human acceptance failed on `yuri-alpha`, output `eDP-1` (2560×1600, scale 2), with logical bar height 20. The running command used `-L 1`, which selects the layer-shell layer rather than output scale. Zelbar rendered an apparent 1× buffer that River stretched to 2×, producing visibly blurry text. `wlr-randr` confirmed `Scale: 2.000000`, and pinned upstream `src/Backend.zig` ignores `wl_output.scale` at `// TODO: scale`. Position/protocol acceptance is not sufficient: issue 08 must prove physical buffer scaling and repeat this visual gate.
