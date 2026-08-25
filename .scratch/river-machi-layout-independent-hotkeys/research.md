# Раскладко-независимые глобальные горячие клавиши в River/Machi

Дата исследования: 2026-08-25.

## Краткий вывод

Для исследованного baseline до commit `93db688` рекомендуемым уровнем решения был **Machi + штатный `river-xkb-bindings-v1.set_layout_override(0)`**, а не `channel` и не переписывание всей XKB-карты.

River 0.4.8 уже умеет сопоставлять keysym с физическим событием так, как если бы была активна указанная группа XKB. В текущей карте `layout us,ru` группа `0` — `us`, поэтому binding `super+j` с override `0` будет срабатывать от физической `<AC07>` и при `us` (`j`), и при `ru` (`Cyrillic_o`). Это меняет только проверку глобального binding: обычный ввод и сочетания, переданные приложениям, остаются в активной раскладке.

Закреплённый в репозитории Machi использует keysym bindings и версию 2 протокола, но **не вызывает** `set_layout_override`; keycode bindings и собственного latin fallback в нём нет. Минимальная рекомендуемая доработка репозитория — локальный patch для Machi, вызывающий `setLayoutOverride(0)` для создаваемых bindings, и подключение patch в `nixos/pkgs/machi.nix`.

`channel` технически может загрузить специально сконструированную XKB-карту, которая выдаёт латинские keysyms при Ctrl/Alt/Super, но сам `channel` не перехватывает и не транслирует события. Такое решение глобально меняет то, что видят все Wayland/Xwayland-клиенты, требует сложных XKB types с корректным `preserve` для Control/Mod1/Mod4 и значительно опаснее. Для задачи Machi bindings его применять не следует.

## Конфигурация на момент исследования

Ниже зафиксировано состояние репозитория непосредственно до commit `93db688`. Этот commit реализовал другой из рассмотренных вариантов — custom XKB positional Latin shortcuts — поэтому текущий `river.nix` уже отличается от исследованного baseline.

Изучены:

- [`nixos/home/river.nix`](../../nixos/home/river.nix) в исследованном baseline: запускает Machi и `channel`; Machi bindings записаны как `super+j`, `super+k`, `super+shift+j` и т. п.; `channel` получает `layout us,ru` и `options ctrl:nocaps,grp:ctrl_space_toggle`.
- [`nixos/pkgs/channel.nix`](../../nixos/pkgs/channel.nix): `channel` 0.4.1, commit `4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446`; локальный patch касается только `tap-button-map`.
- [`nixos/pkgs/machi.nix`](../../nixos/pkgs/machi.nix): Machi commit `65a0fc12f2796f41f4c9cbb7e034aaa137009b01`.
- Точные исходники, полученные derivations: Channel `4c4f95c…`, Machi `65a0fc1…`, River 0.4.8.

Проверка с `xkbcli compile-keymap --layout us,ru --options ctrl:nocaps,grp:ctrl_space_toggle` подтверждает:

```text
key <AC07> {
    symbols[1]= [ j, J ],
    symbols[2]= [ Cyrillic_o, Cyrillic_O ]
};
```

Следовательно, нынешний `super+j` — binding к keysym `j`, а не к `<AC07>`/evdev keycode. В русской группе без layout override физическая J имеет другой keysym.

## 1. Wayland и River: keycode против keysym

### Wayland core

`wl_keyboard.keymap` передаёт клиенту XKB keymap, а `wl_keyboard.key` — платформенный числовой код клавиши, который нужно интерпретировать этой картой. То есть core Wayland переносит низкоуровневое событие и состояние modifiers/layout, но не определяет политику глобальных shortcuts. Политику реализует compositor и, в River 0.4+, его window-manager client.

Термины XKB:

- **keycode** идентифицирует физическую клавишу;
- **keysym** — символ/функция, назначенная этому keycode выбранной группой и уровнем;
- **layout/group** — одно из отображений keycode → keysyms.

River получает evdev/libinput keycode и явно преобразует его в XKB keycode прибавлением 8 (`KeyboardGroup.zig`). Затем он проверяет bindings до отправки события focused client. Сработавшее событие по умолчанию поглощается compositor и клиенту не отправляется.

### River 0.4.8

`river-xkb-bindings-v1` задаёт binding как `(keysym, modifiers)`, не как raw keycode. При этом версия 2 протокола содержит `river_xkb_binding_v1.set_layout_override(layout)`:

- без вызова используется активная группа клавиатуры;
- с override указанный 0-based layout используется **только для перевода события при проверке данного binding**, независимо от активной раскладки.

Реализация River хранит optional `layout` у каждого binding. В `XkbBinding.match()` она берёт либо override, либо активную layout клавиши, а затем получает keysyms для фактического keycode через `keyGetSymsByLevel()`. Поэтому это не raw-keycode binding, но практически даёт требуемую физическую стабильность относительно выбранной эталонной группы.

River делает две проверки:

1. base level без modifier translation — чтобы `Super+Shift+1` естественно оставался binding к `1`, а не к `!`;
2. translated level с удалением XKB-consumed modifiers — для случаев вроде keypad/NumLock.

При нескольких совпадениях River оставляет первое. Протокол прямо предупреждает, что layout overrides могут привести к совпадению нескольких bindings от одного физического события.

**Ответ на (1):** Wayland передаёт keycode и XKB state; River/Machi API объявляет глобальные bindings через keysyms. River сопоставляет фактический keycode с keysym, используя активную группу либо per-binding layout override. В River 0.4.8 нет публичного raw-keycode binding API, но layout override — штатный способ сделать bindings независимыми от активной раскладки.

## 2. Что поддерживает текущий Machi

Закреплённый Machi:

- парсит последний не-modifier token через `xkb.Keysym.fromName(..., case_insensitive)`;
- хранит только `keysym` и modifier mask;
- создаёт binding через `getXkbBinding(seat, keysym, modifiers)`;
- bind-ится к `river_xkb_bindings_v1` версии 2;
- содержит vendored protocol XML с `set_layout_override`;
- **не вызывает** `setLayoutOverride()`;
- не имеет полей `keycode`, `layout`, `layout-override`, `latin`, `fallback` и не делает параллельный binding к `Cyrillic_o`.

Следовательно:

- в исследованном baseline `super+j` зависел от активной группы;
- синтаксиса binding по `<AC07>`, evdev code или XKB keycode нет;
- «layout-inhibited»/latin fallback нет;
- инфраструктура для правильного решения уже согласована: Machi и River используют v2, не хватает одного protocol request (либо небольшого конфигурационного параметра вокруг него).

**Ответ на (2):** текущий Machi не поддерживает ни keycode bindings, ни layout override на уровне конфигурации, ни latin fallback. Однако используемая им версия River protocol поддерживает per-binding layout override, и текущий исходник Machi можно минимально пропатчить.

## 3. Можно ли сделать трансляцию через `channel`

### Что реально делает Channel

`channel` — input configuration manager, а не runtime key remapper. В закреплённом исходнике он:

1. читает RMLVO (`rules`, `model`, `layout`, `variant`, `options`);
2. вызывает `xkb_context_new()` с обычными default paths;
3. компилирует карту через `xkb_keymap_new_from_names2(..., TEXT_V2, ...)`;
4. сериализует её;
5. передаёт River через `river_xkb_keyboard_v1.set_keymap()`.

Listener Channel намеренно игнорирует текущие layout/state events: комментарий в исходнике — «we only configure it». Никакого чтения каждого key press и условной повторной отправки события нет.

Значит, один лишь patch `nixos/pkgs/channel.nix` не превращает Channel в прозрачный remapper. Возможны только два существенно разных подхода:

1. **Попросить Channel загрузить custom XKB configuration.** Это уже поддерживается косвенно: `xkb_context_new()` использует стандартные пути, включая `$XDG_CONFIG_HOME/xkb`; можно добавить custom rules/types/symbols и указать option в `river.nix`.
2. **Перепроектировать Channel как event interceptor/injector.** Текущие River input-config protocols для этого не предназначены. Это большой новый компонент, а не packaging patch; для настоящей injection/routing upstream River отдельно обсуждает новые protocol mechanisms.

### XKB latin-on-modifier: технически возможно, но рискованно

Документация xkbcommon приводит официальный пример custom key type, где при Control выбираются дополнительные уровни с латинскими keysyms, а `preserve[Control] = Control` оставляет modifier видимым shortcut matcher. Аналогично можно теоретически определить для русской группы уровни:

- без Ctrl/Alt/Super — `Cyrillic_o`/`Cyrillic_O`;
- с Control, Mod1 (обычно Alt) или Mod4 (обычно Super) — `j`/`J`;
- для всех комбинаций modifiers — с соответствующим `preserve`.

Это позволило бы translated-проходу River увидеть `j`, а focused приложениям — латинскую букву при модификаторе. Но цена высока:

- нужно описать все буквенные клавиши и комбинации Shift × Control × Mod1 × Mod4, иначе поведение будет неполным;
- без `preserve` River сам удаляет consumed modifier и binding `super+j`/`ctrl+c` не совпадёт;
- Mod1 и Mod4 — реальные XKB bits, а Alt/Super — обычные соглашения; нестандартные modifier maps ломают предположение;
- AltGr обычно LevelThree/Mod5 и **не равен** Alt/Mod1; ошибочное объединение сломает ввод символов третьего уровня;
- изменение keymap видят все Wayland-клиенты и Xwayland, не только Machi;
- несработавшее `Super+key` уйдёт focused client уже с латинским keysym;
- `Alt+key` изменит application mnemonics/menu shortcuts и может конфликтовать с Compose/IME/custom layouts;
- обновления xkeyboard-config/libxkbcommon могут выявить ошибки в custom types/rules;
- ошибочная карта способна сделать клавиатуру частично неработоспособной; upstream xkbcommon прямо рекомендует сначала проверять её через `xkbcli` вне default paths.

### Ctrl+C в русской раскладке

Без custom fallback физическая C в группе `ru` порождает русский keysym (не Latin `c`). Wayland не обещает автоматический Latin fallback: приложение получает keycode, активную карту и Control state, а toolkit/application решает, считать ли это Copy/interrupt. Некоторые toolkits делают физический или latin fallback, другие — нет; полагаться на это как на свойство Wayland нельзя.

Custom XKB type с Control → positional Latin и `preserve[Control]` может сделать `Ctrl+C`, `Ctrl+V` и другие ASCII control shortcuts единообразными во всех клиентах. Но это **отдельная пользовательская политика**, более широкая, чем глобальные Machi bindings. Её нужно тестировать минимум в терминалах (включая реальный SIGINT), Emacs, GTK, Qt, Electron/browser и Xwayland.

Особенно важно:

- `preserve[Control]` обязателен, иначе Control будет consumed переводом;
- текущий `grp:ctrl_space_toggle` должен остаться рабочим; custom symbols/types не должны менять Space или group action;
- в исследованном baseline Caps был преобразован в Control (`ctrl:nocaps`), поэтому fallback затронул бы и сочетания с физическим Caps;
- добавление Alt/Super в тот же механизм резко увеличивает область воздействия и не рекомендуется без отдельного acceptance test.

**Ответ на (3):** через Channel можно доставить custom XKB keymap, но нельзя получить узкую «прозрачную трансляцию только глобальных Machi shortcuts». Для Ctrl-only positional Latin это допустимый отдельный эксперимент; для Super/Alt и решения исходной задачи — неправильный и опасный уровень абстракции.

## Рекомендуемая реализация для этого репозитория

### Рекомендация

Добавить локальный patch **к Machi**, не к Channel:

1. Создать, например, `nixos/pkgs/machi-layout-override.patch`.
2. В `src/XkbBinding.zig`, сразу после `getXkbBinding(...)`, вызвать сгенерированный Zig request:

   ```zig
   rwm_xkb_binding.setLayoutOverride(0);
   ```

3. Подключить patch через `patches = [ ./machi-layout-override.patch ];` в `nixos/pkgs/machi.nix`.
4. Оставить `layout us,ru` в `river.nix`: индекс `0` является контрактом «эталонная US-группа для WM bindings».
5. Не менять значения `super+j`, `super+h` и т. п.: они остаются читаемыми keysym names эталонной US-раскладки.

Вызов должен выполняться при initial configuration/manage sequence до `enable()`, как требует protocol. Текущий lifecycle Machi создаёт bindings при initial setup, а reload выполняет `reset()` из обработки binding action; локальный patch следует проверить и на старте, и после `super+ctrl+shift+r`.

### Почему это лучше

- используется штатная семантика River v2;
- изменение локально только для Machi globals;
- focused приложения продолжают получать русские символы и прежние Ctrl/Alt semantics;
- не требуется вести таблицу `j ↔ Cyrillic_o`;
- работает для букв, цифр и punctuation согласно физическим позициям US group;
- patch мал, воспроизводим и соответствует уже применяемой локальной packaging-модели.

### Предпочтительное развитие

Если hardcode нежелателен, более чистый patch Machi должен добавить глобальный параметр конфигурации вроде `binding-layout=0`/`binding-layout=us` и передавать его во все `XkbBinding.create()`. Но для исследованного baseline с фиксированным `us,ru` hardcode `0` был минимален и однозначен. Не стоит добавлять два bindings (`j` и `Cyrillic_o`): это привязывает конфигурацию к конкретной паре layouts и создаёт дубли/конфликты.

### Ограничения и тесты

- Override — индекс группы, не аппаратный keycode. Он надёжен, пока `us` остаётся первой группой у всех клавиатур. При per-device картах этот контракт нужно пересмотреть.
- Проверить `Super+J/H/K/L`, Shift/Alt/Ctrl варианты, punctuation и spawn bindings в обеих группах.
- Проверить, что сработавшие globals не попадают в focused client.
- Проверить reload bindings.
- Проверить обычный русский ввод и `Ctrl+Space`.
- Отдельно зафиксировать фактическое поведение `Ctrl+C/V/X/Z` в terminal, GTK, Qt, Electron и Xwayland. Если оно неудовлетворительно, завести отдельную задачу на **Ctrl-only XKB latin fallback**, не расширяя её сразу на Alt/Super.
- Если тестируется custom XKB, сначала компилировать через `xkbcli compile-keymap` с отдельным `--include` path, затем проверять интерактивно; не активировать непроверенную карту при login.

## Sources

- [Wayland core protocol specification (`wl_keyboard`)](https://wayland.freedesktop.org/docs/html/apa.html)
- [libxkbcommon: Introduction to XKB](https://xkbcommon.org/doc/current/xkb-intro.html)
- [libxkbcommon: keymap text format; keycodes, keysyms, types, consumed modifiers and `preserve`](https://xkbcommon.org/doc/current/keymap-text-format-v1-v2.html)
- [libxkbcommon: Custom configuration and default lookup paths](https://xkbcommon.org/doc/current/custom-configuration.html)
- [River 0.4.8: `river-xkb-bindings-v1` protocol](https://codeberg.org/river/river/src/tag/v0.4.8/protocol/river-xkb-bindings-v1.xml)
- [River 0.4.8: `XkbBinding.match()` and layout override implementation](https://codeberg.org/river/river/src/tag/v0.4.8/river/XkbBinding.zig)
- [River 0.4.8: keycode processing and evdev → XKB offset](https://codeberg.org/river/river/src/tag/v0.4.8/river/KeyboardGroup.zig)
- [River 0.4.8: binding matching order](https://codeberg.org/river/river/src/tag/v0.4.8/river/Seat.zig)
- [Machi pinned source: keysym-only `XkbBinding`](https://codeberg.org/machi/machi/src/commit/65a0fc12f2796f41f4c9cbb7e034aaa137009b01/src/XkbBinding.zig)
- [Machi pinned source: keybinding parser](https://codeberg.org/machi/machi/src/commit/65a0fc12f2796f41f4c9cbb7e034aaa137009b01/src/Config.zig)
- [Machi pinned protocol copy with `set_layout_override`](https://codeberg.org/machi/machi/src/commit/65a0fc12f2796f41f4c9cbb7e034aaa137009b01/protocol/upstream/river-xkb-bindings-v1.xml)
- [Channel pinned source: RMLVO compilation and serialized keymap](https://codeberg.org/Sivecano/channel/src/commit/4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446/src/xkb_keymap.zig)
- [Channel pinned source: XKB state events are not handled](https://codeberg.org/Sivecano/channel/src/commit/4c4f95ccb8308fe8b0e1923e85845f6c4f2b3446/src/xkb_config.zig)
- [River issue #1388: current upstream discussion of routing/injection rather than input configuration](https://codeberg.org/river/river/issues/1388)
