# Заголовки окон в River 0.4.8 + Machi

Дата исследования: 2026-08-25.

Исследованный baseline — parent commit перед `23194e9`. Результат исследования уже реализован в `23194e9`: текущий репозиторий собирает River через [`nixos/pkgs/river.nix`](../../nixos/pkgs/river.nix) с локальным `river-legacy-kde-decoration.patch`. Поэтому рассуждения ниже об отсутствующем legacy KDE global и необходимости будущего River override описывают upstream/pre-patch baseline, а не текущий tree.

## Краткий ответ

Наблюдаемая в проблемном окне строка с кнопкой закрытия и заголовком `Home` почти наверняка является **пикселями клиента** (CSD либо встроенным `GtkHeaderBar`), а не SSD River/Machi: закреплённый Machi просит `use_ssd()`, но рисует только рамку, а River не содержит реализации SSD-заголовка. По внешнему виду нельзя надёжно назвать приложение или toolkit.

Для клиентов, использующих стандартный `zxdg-decoration`, River+Machi уже делает практически то же, что Mango: сообщает `server_side`, после чего клиент обязан перестать рисовать CSD. Различие возникает прежде всего у:

1. Wayland-клиентов, которые вообще не создают `zxdg_toplevel_decoration_v1`; в частности, GTK 3.24.52 выбирает default CSD по legacy KDE `org_kde_kwin_server_decoration_manager`, а не по стандартному `xdg-decoration`;
2. GTK 3, старых Qt и прочих клиентов, использующих этот KDE-протокол, который Sway и Mango рекламируют с default `SERVER`, а River 0.4.8 — нет;
3. клиентов, где строка заголовка является частью собственного UI, а не договорной декорацией;
4. разных backend/environment: в сессии Sway этого репозитория дополнительно задано `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`, чего нет в River/Mango;
5. Xwayland-варианта той же программы, который может выглядеть иначе, чем нативный Wayland-вариант.

**Универсальная корректная политика “ни одного заголовка ни у одного приложения” недостижима стандартным `xdg-decoration`.** Стандарт имеет только `client_side` и `server_side`, не режим `none`, и действует лишь на клиентов, которые сами используют протокол. Универсальность возможна только как комбинация toolkit/app-настроек и несовместимых эвристик (обрезка клиентского содержимого), поэтому реалистичная цель — убрать заголовки у всех известных приложений, сохранив безопасный fallback для CSD-only клиентов.

## Зафиксированные версии и конфигурация baseline

Исследованы точные derivation/input версии до `23194e9`:

- River `0.4.8`, source `/nix/store/vfjsqg82aa1hvgkrs57zcdw172454cjn-source`, wlroots `0.20.2` (`nixos-unstable` input `e5bdc4a…`); derivation — [`nixpkgs` `river/package.nix`](https://github.com/NixOS/nixpkgs/blob/e5bdc4a41d4c072fe1e3787eaa0320a384741d44/pkgs/by-name/ri/river/package.nix).
- Machi `65a0fc12f2796f41f4c9cbb7e034aaa137009b01`, source `/nix/store/frl8s248nss5slp9vxrqqm6zi5gacd07-source`, закреплён в [`nixos/pkgs/machi.nix`](../../nixos/pkgs/machi.nix).
- Sway `1.12`, source `/nix/store/2j7grygxd5da5r214vzz3y8b54rr739k-source`, wlroots `0.19.3`.
- Mango `0.16.1`, commit `6cf03353ab07cad4306c2cc10b9063161717a6f3`, source `/nix/store/ffr1qjars5n846izh06gs6ijii98f5nn-source`, wlroots `0.20.1`.
- wayland-protocols `1.49`, GTK 3 `3.24.52`, GTK 4 `4.22.4`, QtWayland 5 `5.15.19`, QtWayland 6 `6.11.1`, libdecor `0.2.5`.

Репозиторий:

- [`nixos/home/sway.nix`](../../nixos/home/sway.nix): `window.titlebar = false`, но также `QT_QPA_PLATFORM=wayland` и **`QT_WAYLAND_DISABLE_WINDOWDECORATION=1`** (строки 17–23). Последнее — клиентская Qt-политика, не возможность Sway.
- [`nixos/home/mango.nix`](../../nixos/home/mango.nix): нет `allow_csd` rules и нет Qt disable variable.
- [`nixos/home/river.nix`](../../nixos/home/river.nix): запускает точный Machi и не задаёт decoration-related env.
- [`nixos/configuration.nix`](../../nixos/configuration.nix): глобально `QT_QPA_PLATFORM=wayland` и `NIXOS_OZONE_WL=1` (строки 229–233), поэтому Chromium/Electron и Qt обычно выбирают Wayland, если wrapper не переопределяет backend.
- [`nixos/home.nix`](../../nixos/home.nix): Firefox policies не задают `browser.tabs.inTitlebar`; внешний вид titlebar остаётся на profile/default policy Firefox и не определяет поведение других приложений.

## Что именно делает `xdg-decoration`

Спецификация говорит:

- если клиент **не создаёт** decoration object, он должен сам рисовать CSD;
- клиент может запросить предпочтение, но compositor выбирает итоговый mode;
- при `server_side` клиент не рисует CSD, а compositor отвечает за декорации;
- mode содержит только `client_side=1` и `server_side=2`, режима `none` нет.

См. точный XML wayland-protocols 1.49: [`xdg-decoration-unstable-v1.xml`](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/1.49/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml), локально после распаковки derivation: `/tmp/river-titlebars-src/wayland-protocols/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml`.

wlroots лишь хранит request и планирует `configure`: `toplevel_decoration_handle_set_mode()` записывает `requested_mode`, а `wlr_xdg_toplevel_decoration_v1_set_mode()` записывает `scheduled_mode` и вызывает `wlr_xdg_surface_schedule_configure()`; mode отправляется в configure. Он не удаляет пиксели клиента и не рисует titlebar автоматически: [`types/wlr_xdg_decoration_v1.c`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/wlr_xdg_decoration_v1.c#L25-57), локально `/nix/store/r2zcb3d3dgmz09qjaqsy945inal2h41r-source/types/wlr_xdg_decoration_v1.c:25-57,93-145`.

Следовательно, “сообщить SSD, но не нарисовать SSD” даёт желаемое titleless-окно только для сотрудничающего клиента. Это полезная, но формально неполная реализация server-side decoration.

## Точный путь River + Machi

River создаёт и рекламирует `zxdg_decoration_manager_v1` в `river/Server.zig:159-160,238-239`: [`Server.zig`](https://codeberg.org/river/river/src/tag/v0.4.8/river/Server.zig).

Для клиента, создавшего decoration object:

1. `river/XdgDecoration.zig:21-31` связывает его с toplevel.
2. `handleRequestMode()` (`:54-68`) преобразует wlroots mode в `decoration_hint`: `none → no_preference`, `client_side → prefers_csd`, `server_side → prefers_ssd`: [`XdgDecoration.zig`](https://codeberg.org/river/river/src/tag/v0.4.8/river/XdgDecoration.zig#L54-L68).
3. River protocol прямо различает `only_supports_csd`, `prefers_csd`, `prefers_ssd`, `no_preference`; `use_ssd` “не имеет эффекта”, если клиент CSD-only: [`river-window-management-v1.xml`](https://codeberg.org/river/river/src/tag/v0.4.8/protocol/river-window-management-v1.xml#L552-L601), локально `protocol/river-window-management-v1.xml:552-601`.
4. Machi на новом окне безусловно вызывает `window.rwm_window.useSsd()`, затем выставляет все tiled edges и `informMaximized()`: [`src/Window.zig`](https://codeberg.org/machi/machi/src/commit/65a0fc12f2796f41f4c9cbb7e034aaa137009b01/src/Window.zig#L63-L77), локально `src/Window.zig:63-77`.
5. River применяет `use_ssd` как `wm_requested.ssd=true` (`river/Window.zig:627-633`) и в configure вызывает `setMode(.server_side)` (`river/XdgToplevel.zig:161-163`): [`Window.zig`](https://codeberg.org/river/river/src/tag/v0.4.8/river/Window.zig#L627-L633), [`XdgToplevel.zig`](https://codeberg.org/river/river/src/tag/v0.4.8/river/XdgToplevel.zig#L154-L163).

Machi получает `decoration_hint`, но только логирует его (`src/Window.zig:236-238`). Для нынешнего безусловного SSD это не мешает: даже `only_supports_csd` нельзя исправить повторным `use_ssd`. Однако hint полезен для диагностики и будущей per-class политики.

Upstream/pre-patch River **не создаёт** `wlr_server_decoration_manager`/`org_kde_kwin_server_decoration_manager`: в точном upstream source нет соответствующего symbol/global. Локальный patch из `23194e9` устраняет это отличие в текущем репозитории.

Для Xwayland River читает Motif-decoration hints wlroots: `no_border || no_title → prefers_csd`, иначе `prefers_ssd` (`river/XwaylandWindow.zig:304-311`). `use_ssd()` не может заставить X11-клиент удалить пиксели, которые тот сам нарисовал внутри X surface; River также не создаёт традиционную X11 WM titlebar.

## Точный путь Sway 1.12

Sway рекламирует **оба** протокола:

- legacy KDE manager с default `SERVER`: `sway/server.c:384-397`;
- `zxdg_decoration_manager_v1`: `sway/server.c:398-408`.

Источник: [`sway/server.c`](https://github.com/swaywm/sway/blob/1.12/sway/server.c#L384-L408).

Для `xdg-decoration` `set_xdg_decoration_mode()` начинает с SSD; для floating окна сохраняет явный client request, но для tiled окна остаётся SSD (`sway/xdg_decoration.c:64-92`): [`sway/xdg_decoration.c`](https://github.com/swaywm/sway/blob/1.12/sway/xdg_decoration.c#L64-L92). Клиент без xdg-decoration классифицируется как CSD, если не создал legacy KDE decoration (`sway/desktop/xdg_shell.c:483-500`): [`xdg_shell.c`](https://github.com/swaywm/sway/blob/1.12/sway/desktop/xdg_shell.c#L483-L500).

`titlebar=false` Home Manager приводит к Sway border policy, но не вырезает клиентскую строку. В Sway команда `border none` при `using_csd` вызывает `view_set_csd_from_server(false)`; этот вызов способен отправить SSD **только при наличии xdg-decoration object** (`sway/commands/border.c:15-30`, `sway/tree/view.c:515-524`). Для CSD-only клиента это всего лишь убирает рамку Sway.

Поэтому Sway имеет два преимущества над River:

1. legacy KDE global для GTK 3 (включая Nemo) и старых Qt-клиентов;
2. в этом репозитории — `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`.

Для обычного `GtkWindow` GTK 3 это первое отличие непосредственно предотвращает автоматическое создание default CSD: `gdk_wayland_display_prefers_ssd()` возвращает true, а `gtk_window_should_use_csd()` — false. Sway по-прежнему не может убрать `GtkHeaderBar`, который приложение явно установило как часть UI через `gtk_window_set_titlebar()`.

## Точный путь Mango в этом репозитории

Mango commit `6cf0335…`:

- создаёт legacy KDE manager с default `SERVER` и xdg-decoration manager (`src/mango.c:7109-7116`): [`mango.c`](https://github.com/mangowm/mango/blob/6cf03353ab07cad4306c2cc10b9063161717a6f3/src/mango.c#L7109-L7116);
- `allow_csd` по умолчанию равен `0` (`:5255-5258`);
- если `allow_csd == 0`, `requestdecorationmode()` независимо от client request выбирает `WLR_..._SERVER_SIDE` (`:6137-6152`): [`mango.c`](https://github.com/mangowm/mango/blob/6cf03353ab07cad4306c2cc10b9063161717a6f3/src/mango.c#L6137-L6152);
- по умолчанию `force_tiled_state=1`, и Mango сообщает все tiled edges (`:5258`, `:5463-5466`).

В [`nixos/home/mango.nix`](../../nixos/home/mango.nix) нет `windowrule=allow_csd:1`, значит точная effective policy — принудительный SSD для xdg-decoration и legacy-KDE клиентов. Mango сам titlebar не рисует.

Итак, Mango действительно охватывает **больше старых Qt-клиентов**, чем River, но для стандартного xdg-decoration его итоговая политика эквивалентна Machi `useSsd()`.

## Классы клиентов

| Класс | Sway | Mango | River+Machi |
|---|---|---|---|
| Native Wayland + `zxdg-decoration` | tiled: SSD; floating может уважить request | SSD по умолчанию | Machi безусловно SSD |
| Native Wayland без decoration protocol | compositor не может выключить CSD | то же | то же |
| Legacy KDE server-decoration (GTK 3, часть старого Qt) | advertised, default SSD | advertised, default SSD | **не advertised** |
| GTK header bar / app-owned chrome | protocol не отличает от app UI | то же | то же |
| libdecor | зависит от найденного global/configure; fallback рисует CSD | то же | то же |
| Xwayland | нет обычного WM titlebar; client/theme/Motif hints решают | то же | то же; hints только передаются Machi |

QtWayland 5 также имеет прямой аварийный выключатель decoration: exact source `/nix/store/1zpb9kr68cx7lv5k502yikpb4nv1rw60-qtwayland-605b8bc/src/client/qwaylandwindow.cpp` ищет `QT_WAYLAND_DISABLE_WINDOWDECORATION`; официальный source tree: [QtWayland 5.15 branch](https://code.qt.io/cgit/qt/qtwayland.git/tree/src/client/qwaylandwindow.cpp?h=5.15). Именно поэтому сравнение с Sway без выравнивания environment некорректно.

GTK позволяет приложению сделать title widget частью `GtkWindow`; такой header bar — не отдельный объект Wayland. GTK source — [`gtk/gtkwindow.c` 3.24.52](https://gitlab.gnome.org/GNOME/gtk/-/blob/3.24.52/gtk/gtkwindow.c) и [`gtk/gtkwindow.c` 4.22.4](https://gitlab.gnome.org/GNOME/gtk/-/blob/4.22.4/gtk/gtkwindow.c). Никакой compositor negotiation не может безопасно удалить произвольный widget.

libdecor предназначен именно для CSD fallback, когда compositor не обеспечивает подходящий SSD path; source `0.2.5`: [`src/libdecor.c`](https://gitlab.freedesktop.org/libdecor/libdecor/-/blob/0.2.5/src/libdecor.c), точный local source `/nix/store/f670s14b96k4m134g108zm079mxx3zly-source`.

## Почему наблюдение может меняться без изменения policy

Перед выводами нужно одинаково запустить один executable/profile с одинаковым environment и state:

- `QT_QPA_PLATFORM=wayland` против `xcb`;
- Sway-only `QT_WAYLAND_DISABLE_WINDOWDECORATION=1`;
- `GDK_BACKEND`, `MOZ_ENABLE_WAYLAND`, `NIXOS_OZONE_WL`/Chromium flags;
- tiled/maximized configure: некоторые toolkits упрощают chrome при `tiled_*`/`maximized`; Machi сообщает и all-edges tiled, и maximized, Mango обычно tiled, но снимает maximized (`mango.c:6460-6467`), Sway сообщает tiled;
- набор globals (`zxdg_decoration_manager_v1`, legacy KDE manager);
- Wayland против Xwayland;
- app preference: Firefox `browser.tabs.inTitlebar=1`, GTK app header-bar setting, Qt flags/theme.

## Как точно определить backend/protocol проблемного окна

### 1. Xwayland или Wayland

```bash
xlsclients -l
xprop WM_CLASS _NET_WM_NAME _MOTIF_WM_HINTS
```

Курсор `xprop` выбирает окно. Если оно найдено `xlsclients`/`xprop`, это Xwayland. Отсутствие не доказывает конкретный Wayland toolkit, только исключает X11-visible window.

Проверить environment уже запущенного процесса:

```bash
pid=$(pgrep -n -f 'ИМЯ_ПРОЦЕССА')
tr '\0' '\n' < /proc/$pid/environ | sort | grep -E \
  '^(WAYLAND_DISPLAY|DISPLAY|QT_QPA_PLATFORM|QT_WAYLAND_DISABLE_WINDOWDECORATION|GDK_BACKEND|MOZ_ENABLE_WAYLAND|NIXOS_OZONE_WL|XDG_CURRENT_DESKTOP)='
readlink -f /proc/$pid/exe
```

Наличие обоих `DISPLAY` и `WAYLAND_DISPLAY` не определяет backend; решающими являются protocol trace/X11 window.

### 2. Wayland protocol trace

Запустить **новый процесс**, не существующий single-instance daemon:

```bash
env WAYLAND_DEBUG=client app-command 2> /tmp/app.wayland.log
grep -E 'zxdg_decoration_manager_v1|zxdg_toplevel_decoration_v1|org_kde_kwin_server_decoration|xdg_toplevel.*(configure|app_id)' /tmp/app.wayland.log
```

Искомая последовательность для стандартного случая:

- bind `zxdg_decoration_manager_v1`;
- `get_toplevel_decoration`;
- optional client `set_mode(client_side)`;
- server `configure(server_side)`.

Если `get_toplevel_decoration` отсутствует, `useSsd()` принципиально не адресует этот клиент. Если есть configure `server_side`, но row остаётся, это либо client bug, либо app-owned/header-bar UI, а не договорная CSD.

Список compositor globals можно снять первичным инструментом Wayland:

```bash
wayland-info | grep -E 'zxdg_decoration|org_kde_kwin_server_decoration|xdg_wm_base'
```

Ожидание для upstream/pre-patch baseline: Sway/Mango покажут оба decoration manager, River — только `zxdg_decoration_manager_v1`. Текущий локально пропатченный River должен показывать оба; отсутствие legacy KDE manager теперь означает regression patch wiring.

### 3. app_id/title и River/Machi hint

Machi уже логирует `app_id` и `decoration hint` в `src/Window.zig:224-238`. Запустить Machi с debug logging/смотреть user session journal:

```bash
journalctl --user -b --grep='machi\|decoration hint\|app_id'
```

Для Sway:

```bash
swaymsg -t get_tree | jq '.. | objects | select(has("app_id") or has("window_properties")) | {name,app_id,window_properties}'
```

Для Mango использовать его IPC (если сборка/модуль предоставляет клиент) и сверить `appid`; иначе protocol trace остаётся переносимым способом.

## Позиция upstream River и состояние GTK

Upstream осознанно не реализует legacy KDE decoration protocol:

- [river#24](https://codeberg.org/river/river/issues/24) остаётся открытым с 2020 года. Isaac Freund объяснил, что GTK не поддерживает стандартный `xdg-decoration`, но предпочёл исправлять GTK, а не добавлять obsolete KDE protocol в River. В 2023 году он сообщил, что сам использует однострочный патч GTK 3 (`gtk_window_should_use_csd()` всегда возвращает `FALSE` для Wayland).
- [river#353](https://codeberg.org/river/river/issues/353) закрыт с прямым отказом (`nacking kde SSD protocol support`).
- [river#1134](https://codeberg.org/river/river/issues/1134) закрыт в 2024 году: участник проекта подтвердил, что это принципиальное решение River; merge request можно предложить, но гарантий принятия нет.
- [river#1231](https://codeberg.org/river/river/issues/1231) закрыт в 2025 году как проблема GTK, даже для GTK 4/Ghostty, который видел `zxdg_decoration_manager_v1`, но не создавал decoration object.
- GTK 3 [MR !6161](https://gitlab.gnome.org/GNOME/gtk/-/merge_requests/6161) и GTK 4 [MR !6398](https://gitlab.gnome.org/GNOME/gtk/-/merge_requests/6398), заменяющие KDE protocol на `xdg-decoration`, всё ещё открыты и имеют merge conflicts.

Следствие: локальный River patch технически мал, но противоречит устойчивой upstream-политике и почти наверняка останется downstream-only. Его главный maintenance risk — не размер diff, а ожидаемое удаление obsolete API из будущего wlroots. Однострочный GTK 3 patch соответствует личному workaround maintainer River, но требует собственной сборки GTK и не решает все GTK 4/app-owned header bars. CSS workaround из issue #24 хрупок: он уже ломал поле имени файла в GTK file chooser.

## Варианты для River+Machi, от лучших к худшим

### 1. Сохранить `useSsd()` — обязательно, малая сложность

Он уже присутствует в `machi/src/Window.zig:74`. Удаление вернёт default `use_csd` River и добавит заголовки у исправных xdg-decoration клиентов. Никаких изменений сейчас не требуется.

### 2. Диагностировать и настраивать конкретные app/toolkit — малая/средняя, самый надёжный практический путь

- Перенести `QT_WAYLAND_DISABLE_WINDOWDECORATION=1` из Sway-only session в общую session либо River session, если приемлемо для всех Qt Wayland приложений.
- Для приложения выбрать его официальный titlebar/header-bar preference.
- Firefox: при необходимости явно настроить `browser.tabs.inTitlebar=1` в нужном profile и подтвердить effective policy.
- При необходимости per-command wrappers вместо глобальных переменных.

Файлы репозитория при реализации: `nixos/home/river.nix` или общие `home.sessionVariables` в `nixos/home.nix`; app-specific wrapper/module. Побочные эффекты: у floating Qt окна могут исчезнуть drag/resize/close controls, потому что River/Machi даёт только keybindings и border.

### 3. Добавить River legacy KDE decoration manager — реализовано в `23194e9`

Технически wlroots 0.20.2 всё ещё предоставляет `wlr_server_decoration_manager_create()` и default modes: [`wlr_server_decoration.c`](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/wlr_server_decoration.c), особенно `:132-165,180-197`. Можно пропатчить River `river/Server.zig`/build bindings и создать manager с default `SERVER`, как Sway/Mango.

Предполагавшиеся файлы: River `build.zig`, `river/Server.zig`, возможно Zig wlroots bindings; packaging patch + `nixos/pkgs/river.nix`/overlay в `flake.nix`. Реализация `23194e9` добавила локальный package override и legacy-decoration patch; дальнейшие изменения здесь не нужны без нового runtime evidence.

Побочные эффекты: поддержка нестандартного legacy-протокола и дополнительная lifecycle поверхность. Это помогает только клиентам, которые используют legacy global, включая default-CSD путь GTK 3 и часть старого Qt ecosystem; app-owned `GtkHeaderBar` протокол убрать не может. Проверка `WAYLAND_DEBUG` должна подтверждать, какой path использует проблемный клиент.

### 4. Использовать `decoration_hint` в Machi — малая реализация, но не средство принуждения

Изменить `src/Window.zig` event handler и политику `manage()`, чтобы явно логировать/классифицировать `only_supports_csd`; SSD оставить для остальных. Это улучшит объяснимость и позволит per-app exceptions, но не уберёт CSD: protocol прямо говорит, что `use_ssd` не действует для CSD-only.

### 5. Принудительный Xwayland + app/X11 no-decoration — средняя, хрупкая

`QT_QPA_PLATFORM=xcb` уже применяется к Enpass в repo. Xwayland может дать иной toolkit path, а Motif hints/Qt flags — отключить decoration. Но compositor не может универсально заставить X11 client не рисовать собственный chrome; будут проблемы HiDPI, IME, clipboard и security isolation. Использовать только per-app после теста.

### 6. Изменить advertisement/negotiation River — средняя, ограниченная

Не рекламировать `zxdg_decoration_manager_v1` **ухудшит** ситуацию: спецификация велит клиентам fallback на CSD. Рекламировать его уже сделано. Можно изменить default/тайминг configure, но Machi уже вызывает SSD; это имеет смысл только если `WAYLAND_DEBUG` обнаружит sequencing bug.

### 7. Обрезать CSD в compositor — большая, небезопасная

Compositor видит surface/subsurfaces и `xdg_window_geometry`, но не получает семантический прямоугольник “titlebar”. Заголовок часто лежит в том же buffer, что меню/контент; обрезка фиксированных пикселей сломает ввод, coordinate transforms, popups, fractional scale, resize, shadows и приложения с нестандартным chrome. Sway не решает задачу такой обрезкой. Не рекомендуется.

### 8. Расширить протоколы — большая/очень большая

Собственный River protocol мог бы сообщать пожелание `undecorated`, но существующие GTK/Qt/libdecor клиенты его не понимают. Новый стандарт потребует изменений protocol spec и каждого toolkit; даже тогда app-owned header bar остаётся приложением. Для локальной задачи несоразмерно.

## Оценка и рекомендуемый путь

| Цель | Сложность | Вероятные изменения | Результат |
|---|---:|---|---|
| Сохранить SSD у compliant clients | малая/готово | нет (`useSsd` уже есть) | надёжно |
| Qt parity со Sway config | малая | env в `river.nix`/`home.nix` | высокий эффект для Qt |
| Qt parity с Mango globals | готово в `23194e9` | локальный River patch + Nix override | legacy KDE clients |
| Убрать header bar у известных GTK apps | малая–средняя на приложение | app prefs/wrappers/theme | практично, не универсально |
| Универсально вырезать любой title row | большая и небезопасная | scene/input clipping heuristics | нереалистично |
| Новый interoperable protocol | очень большая | protocol + River + toolkits/apps | долгосрочно, всё равно не app UI |

Рекомендация:

1. **Не менять Machi `useSsd()`.**
2. Снять `WAYLAND_DEBUG` одного проблемного приложения под River и Sway/Mango и сравнить executable, environment и globals.
3. Если отсутствует `get_toplevel_decoration`, определить: это legacy KDE (клиент ищет соответствующий global), GTK/header bar или иной fallback.
4. Для Qt сначала проверить уже установленный River legacy KDE patch; `QT_WAYLAND_DISABLE_WINDOWDECORATION=1` применять per-app/common только если runtime evidence показывает оставшийся toolkit-specific CSD.
5. Для GTK/app-owned chrome использовать официальные app preferences; не клиппировать buffer.
6. Считать policy завершённой как “titleless для поддерживаемого набора приложений”, а не универсальной для произвольного Wayland client.

**Итоговая оценка:** legacy KDE global уже добавлен локальным River patch; добиться практически titleless набора известных приложений остаётся задачей **средней** сложности; гарантировать titleless для любого приложения — **нереалистично без поломок**, то есть не достижимо корректно стандартными протоколами.

## Primary sources

- [River 0.4.8 source](https://codeberg.org/river/river/src/tag/v0.4.8)
- [River window-management protocol: decoration hint/use_csd/use_ssd](https://codeberg.org/river/river/src/tag/v0.4.8/protocol/river-window-management-v1.xml#L552-L601)
- [Machi exact commit](https://codeberg.org/machi/machi/src/commit/65a0fc12f2796f41f4c9cbb7e034aaa137009b01)
- [Sway 1.12 source](https://github.com/swaywm/sway/tree/1.12)
- [Mango exact commit](https://github.com/mangowm/mango/tree/6cf03353ab07cad4306c2cc10b9063161717a6f3)
- [wayland-protocols 1.49 xdg-decoration XML](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/1.49/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml)
- [wlroots 0.20.2 xdg-decoration implementation](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/wlr_xdg_decoration_v1.c)
- [wlroots 0.20.2 legacy KDE server-decoration implementation](https://gitlab.freedesktop.org/wlroots/wlroots/-/blob/0.20.2/types/wlr_server_decoration.c)
- [QtWayland official source](https://code.qt.io/cgit/qt/qtwayland.git/)
- [GTK 3.24.52 source](https://gitlab.gnome.org/GNOME/gtk/-/tree/3.24.52)
- [GTK 4.22.4 source](https://gitlab.gnome.org/GNOME/gtk/-/tree/4.22.4)
- [libdecor 0.2.5 source](https://gitlab.freedesktop.org/libdecor/libdecor/-/tree/0.2.5)
