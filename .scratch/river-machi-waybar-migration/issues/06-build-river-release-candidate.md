# Build the River release candidate

Status: ready-for-agent
Blocked by: 04, 05

## Objective

Complete the automated verification seam and hand a specific bootable candidate to the human pilot.

## Scope

- Re-run package, evaluated-session, Waybar-profile, and systemd-unit checks against one candidate revision.
- Build the complete NixOS toplevel and a bootable generation artifact.
- Record artifact paths, revision, package revisions, expected session identities, a runtime checklist, and rollback instructions.
- Separate checks the agent completed from physical acceptance that remains for the user.
- Do not activate the production session or claim physical runtime checks were performed.

## Acceptance Criteria

- River, Machi, `channel`, and the complete `yuri-alpha` toplevel build from the candidate revision.
- Session-set, package-provenance, Waybar-profile, and systemd-unit assertions pass.
- The handoff identifies an exact candidate generation and a tested previous-generation rollback path.
- No automated blocker remains unresolved.

## Comments

- 2026-08-23: Automated release-candidate verification completed for configuration revision `e613665623fd7ed0b246fef2d9084ed4da1d4d41`.
- Candidate toplevel / bootable artifact: `/nix/store/r1g8m7z5jhihh881z6r9q64lnv7385f1-nixos-system-yuri-alpha-26.05.20260817.0dd31db`.
- River, Machi, `channel`, all three flake checks, the complete `yuri-alpha` toplevel, boot metadata, kernel, initrd, and `nix flake check` passed.
- Generation 900 (`/nix/store/gfbas27xdpy4qam2g03bpgsc5isigjk5-nixos-system-yuri-alpha-26.05.20260817.0dd31db`) is the tested rollback baseline because it was the currently booted system at handoff time; its boot artifacts remain present.
- The exact installation commands, artifact paths, provenance, expected session identities, runtime checklist, rollback procedure, and automated/physical verification boundary are recorded in `nixos/river-release-candidate.md`.
- No production session was activated and no physical runtime acceptance was claimed. Issue 07 remains the human acceptance gate.
