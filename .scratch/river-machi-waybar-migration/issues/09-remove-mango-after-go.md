# Remove Mango after a go decision

Status: wontfix
Blocked by: 08 (requires recorded GO)

## Objective

Remove Mango in one independently reversible cleanup change without affecting River or Sway.

## Scope

- Remove Mango flake inputs, imports, packages, session registration, configuration, and Waybar profile/instance.
- Remove references that become unused solely because Mango is gone.
- Preserve River, Machi, `channel`, the generic Waybar profile, and the independent Sway fallback.
- Do not add deferred Machi/Waybar state integration or remove Sway.

## Acceptance Criteria

- The evaluated session set contains River and Sway but no Mango or plain River entry.
- Mango packages, units, profiles, and configuration are absent from the evaluated closure.
- River and Sway retain valid generic Waybar instances and compositor-bound lifecycle relationships.
- Stable nixpkgs remains primary and GPU and unrelated desktop-service policy is unchanged.
- The complete `yuri-alpha` toplevel builds.
- Mango removal is contained in a standalone, revertible commit.

## Comments

- 2026-08-25: Superseded with the original retirement decision chain. Do not remove Mango from this historical ticket.
