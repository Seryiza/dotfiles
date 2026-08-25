# Add session-scoped Soteria

Status: ready-for-agent
Blocked by: 04

## Objective

Configure Soteria as the sole graphical polkit authentication agent and bind its lifecycle to the graphical session.

## Scope

- Enable `pkgs.soteria` through the NixOS Soteria option, not through Home Manager.
- Extend the generated Soteria user unit so it starts and stops with the graphical session.
- Inspect configured packages, user units, and autostart entries for competing graphical polkit agents.
- If a competitor exists, disable its activation declaratively rather than suppressing Soteria.

## Acceptance Criteria

- The built configuration enables exactly one intended graphical polkit authentication agent.
- Soteria's generated user unit is bound to graphical-session lifecycle, not merely ordered after it.
- Artifact inspection finds no competing configured activation path.
- Explicit `systemd-analyze verify` of the generated units succeeds.
- The complete `yuri-alpha` toplevel builds after every implementation commit.

## Comments
