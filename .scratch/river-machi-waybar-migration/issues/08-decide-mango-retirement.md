# Decide whether to retire Mango

Status: wontfix
Blocked by: 07

## Objective

Make an explicit go/no-go decision after reviewing the River pilot evidence.

## Scope

- Review the recorded working-day pilot, lifecycle tests, and unresolved regressions.
- Decide whether River is sufficient for daily use and whether rollback remains adequate.
- Authorize only Mango cleanup; Sway removal remains a separate future decision.
- Record the decision and rationale in this ticket without making implementation changes.

## Acceptance Criteria

- A recorded **GO** explicitly authorizes ticket 09.
- A recorded **NO-GO** retains Mango and leaves ticket 09 blocked or closed.
- The decision explicitly confirms that Sway remains available.
- No implementation commit is made as part of this ticket.

## Comments

- 2026-08-25: Superseded with the Waybar-specific pilot. Any future Mango retirement decision must be specified against the current Zelbar-based River session.
