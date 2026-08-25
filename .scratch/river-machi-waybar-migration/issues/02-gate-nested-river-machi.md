# Gate River and Machi in a nested session

Status: wontfix
Blocked by: 01

## Objective

Prove the River 0.4 + Machi architecture before registering a production login session.

## Scope

- Add or assemble a reusable River/Machi initialization path suitable for nested validation and later UWSM integration.
- Start Machi from River initialization without finalizing the parent UWSM session.
- Exercise Machi-native focus, navigation, close, fullscreen, single/split, panels/workspaces, spawn, and restart behavior.
- Exercise decorated, transient, Picture-in-Picture, layer-shell, and Xwayland clients.
- Keep Mango and Sway unchanged and do not add a display-manager session.

## Acceptance Criteria

- Nested River starts and exits cleanly with Machi owning window-management policy.
- Restart and repeated client lifecycle scenarios do not crash River or Machi.
- Nested startup does not call `uwsm finalize` or damage the parent session.
- Any architecture or configuration blockers discovered by the gate are resolved before ticket 04 starts.
- Any committed harness or configuration passes the complete `yuri-alpha` toplevel build.

## Comments

- Nested gate отменён по решению пользователя: допустимо обнаруживать и исправлять поломки непосредственно при интеграции River-сессии. Отдельный harness и его зависимости не добавляются.
