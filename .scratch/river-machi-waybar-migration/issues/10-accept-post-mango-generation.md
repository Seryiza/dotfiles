# Accept the post-Mango generation

Status: wontfix
Blocked by: 09

## Objective

Confirm that the cleanup generation remains usable and retains both River and the independent Sway fallback.

## Scope

- Boot the cleanup generation.
- Perform focused River and Sway login/logout, Waybar, lock, portal, polkit, and critical-application smoke tests.
- Verify the previous Mango-bearing generation remains selectable as an emergency rollback.
- Record results and any rollback in this ticket.

## Acceptance Criteria

- River and Sway both start through UWSM and stop cleanly.
- Each session has exactly one generic Waybar process and one graphical authentication agent.
- No Mango entry appears in sysc-greet.
- The previous Mango-bearing generation remains bootable as emergency rollback.

## Comments

- 2026-08-25: Superseded with the original Mango retirement chain; a future cleanup generation needs a new acceptance ticket based on the current session architecture.
