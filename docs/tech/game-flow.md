# Состояния игры: сессия, уровень, секция — техзадание

Статус: принято (H2 2026-11-21, DIA-5). Журнал: T-22…T-28, T-34 в `00-index.md`.
Карточка: `docs/work/DIA-5-architecture-pillars/card.md` (decision-01 A, 05 A, 07, 08 A, 09 A).
Правила кода — `ARCHITECTURE.md`; препятствия и касание — `obstacles.md`; сохранения —
`saves.md`.

## 1. Три машины состояний и где они живут

| Машина | Логика (`RefCounted`) | Узел-адаптер | Где узел | Кто ведёт |
|---|---|---|---|---|
| Сессия: меню → игра → итог | `SessionFlow` (`scripts/flow/session_flow.gd`) | `Session` (`scripts/flow/session.gd`) | `main.tscn`: `Main/Session` | каждая машина своя; переходы по своему вводу и по событиям хоста |
| Уровень: текущий чекпоинт, тревога, финал | `LevelFlow` (`scripts/level/level_flow.gd`), внутри — существующий `SectionReset` | `LevelRoot` (`scripts/level/level_root.gd`) — скрипт корня сцены уровня | `Main/Level` (уже в `main.tscn`) | хост; остальные повторяют по событиям |
| Секция: своё `Content`, свои препятствия, свои часы | `SectionClock` (`scripts/level/section_clock.gd`) | `SectionRoot` (есть) | `Main/Level/Sections/<id>` | каждая машина по событиям `LevelRoot` |

**Новой автозагрузки нет** (`ARCHITECTURE.md`, «Связи»). Состояние сессии не переживает
возврат в меню — он делается перезагрузкой сцены `Main` (как сейчас при отключении), — значит,
хранить его глобально незачем. Единственное, что должно пережить перезагрузку, — причина
конца сессии для сообщения в меню; это факт соединения, его хранит `Network`
(`last_end_reason`, раздел 5). Прогресс читается с диска заново (`saves.md`).

`Main` остаётся точкой сборки: создаёт связи `Session` ↔ экраны UI, `LevelRoot`,
`ProgressStore`, HUD методами `bind_*`. Уровень, как и сейчас, лежит в `main.tscn` с
запуска — пути RPC совпадают у всех пиров без гонок; пока игрок в меню, `Main/Level`
выключен через `process_mode = PROCESS_MODE_DISABLED`.

**Когда уровень включается** (`process_mode = PROCESS_MODE_INHERIT`, делает `Session` по
своему переходу): у хоста — при `hosted` (вход в `IN_GAME`); у второго игрока — при `joined`
(вход в `START_WAIT`), то есть **до** выбора и до прихода полного состояния. За экраном
выбора мир у клиента живой: синхронизаторы (алмаз, персонаж хоста) и таймеры работают, часы
секций идут от полного состояния, подвижный луч едет — к `session_started` клиент уже видит
тот же мир, что хост, без рывка. Своего персонажа у него ещё нет (спавн после выбора), ввод
в мир не идёт — экран выбора модальный, звук мира приглушён (допущение А3). Выключается
уровень только перезагрузкой `Main` (возврат в меню). Проверка — `test_session_flow_net`:
после `joined` уровень у клиента включён, `LevelRoot.full_state_applied` пришёл до
`session_started`.

## 2. Сессия (`SessionFlow`)

```
                      ┌─ host_pressed ─► SLOT_SELECT ─ slot_chosen ─► STARTING ─ hosted ─────────┐
MAIN_MENU ◄─ back ────┤                      │ back                       │ host_failed           ▼
   ▲  ▲               │                      ▼                            └──► SLOT_SELECT       IN_GAME ─ finale ─► RESULT
   │  │               ├─ help_pressed ─► HELP ─ back ─► MAIN_MENU                                 ▲   │                │
   │  │               └─ join_pressed ─► CONNECTING ─ joined ─► START_WAIT ─ session_started ────┘   │                │
   │  │                                     │ failed(reason): остаётся CONNECTING с сообщением      │                │
   │  └──────── quit_to_menu / host_ended / connection_lost (кроме RESULT) ◄───────────────────────┘                │
   └──────────────────────────────── menu_pressed ◄─────────────────────────────────────────────────────────────────┘
```

**Состояния и события** (`enum State`, `enum Event` в `SessionFlow`):

| Состояние | Что видит игрок | Допустимые события → куда |
|---|---|---|
| `MAIN_MENU` | главное меню; сообщение `Network.last_end_reason`, если есть | `host_pressed` → `SLOT_SELECT`; `join_pressed` → `CONNECTING`; `help_pressed` → `HELP`; `quit_game` → выход |
| `HELP` | справка о сохранениях (decision-06 A) | `back` → `MAIN_MENU` |
| `SLOT_SELECT` | слот: «продолжить» / «начать заново» (с подтверждением) | `slot_chosen(start_id)` → `STARTING`; `back` → `MAIN_MENU` |
| `STARTING` | короткий переход | `hosted` → `IN_GAME`; `host_failed(err)` → `SLOT_SELECT` с сообщением |
| `CONNECTING` | признак ожидания | `joined` → `START_WAIT`; `connect_failed(reason)` → `CONNECTING` (сообщение, ввод доступен); `back` → `MAIN_MENU` |
| `START_WAIT` | экран выбора чекпоинта, только просмотр (7.1 A) | `session_started(start_id)` → `IN_GAME`; `quit_to_menu`, `host_ended`, `connection_lost` → `MAIN_MENU` |
| `IN_GAME` | игра; игровое меню — оверлей, не состояние | `finale` → `RESULT`; `quit_to_menu`, `host_ended`, `connection_lost` → `MAIN_MENU` |
| `RESULT` | «ограбление удалось», без цифр (decision-01 A) | `menu_pressed` → `MAIN_MENU`; `host_ended`/`connection_lost` **игнорируются** (карточка: экран итога не меняется) |

Методы логики:
- `func handle(event: SessionFlow.Event) -> bool` — применяет переход, `false` — событие в
  этом состоянии не допустимо (ничего не меняется);
- `func can_quit_to_menu() -> bool` — `true` во всех состояниях, кроме `MAIN_MENU` (К1);
- `func needs_quit_confirm(is_host: bool, partner_present: bool) -> bool` — только хост в
  `IN_GAME`/`START_WAIT` с напарником (Д3);
- `var state: State`, сигнал `state_changed(state: int, previous: int)` — у узла `Session`.

**Хост и экран выбора.** У хоста состояние остаётся `IN_GAME`; экран выбора — оверлей
(Д2: мир идёт). Его открывает подсостояние напарника `Session.partner`:
`NONE → CHOOSING → PRESENT → NONE` (`enum PartnerState`). Переходы: `request_join` →
`CHOOSING`; `session_started` → `PRESENT`; `peer_left` → `NONE` из любого. Знак «напарник не
подключён» и адрес (Д23, `IP.get_local_addresses()`) показываются при `NONE`.

**Выход в меню из любого игрового состояния** (К1, К6). Игровое меню открывается по
`ui_cancel` (действие уже есть, `project.godot` не меняется) поверх любого состояния
уровня; «в меню» → `Session.quit_to_menu()`:
- второй игрок: `Network.close()` → перезагрузка `Main`;
- хост: подтверждение (если напарник есть) → `Network.end_session()` (раздел 5) →
  перезагрузка `Main`.
Ничего сохранять не нужно: прогресс записан на чекпоинтах (`saves.md`), тревога и
незаконченная секция теряются, как при сбросе (К11).

## 3. Уровень (`LevelFlow`) и секции

Уровень — линейная цепочка чекпоинтов (`DESIGN.md`, «Игровой цикл»). `LevelRoot`
содержит `Sections/<section_id>` (`SectionRoot`) в порядке прохождения; чекпоинт секции —
её начало. Порядок и ID — `CheckpointRoute` (`saves.md`, раздел 2), его строит
`LevelRoot._ready` из детей `Sections`.

```
          request_report_checkpoint (следующий, алмаз в руках)
 IDLE ─start(index)─► ACTIVE ───────────────────────────────► ACTIVE (index+1) ─ если чекпоинт финальный ─► FINISHED
                       │  ▲                                     
     report_caught     │  │ reset_timer (хост, reset_delay ≥ 0)
     (поимка, касание, ▼  │                                     
      алмаз разрушен)  ALARM ── start(index) при выборе чекпоинта: один переход, тревога снимается ──► ACTIVE (index)
```

| Состояние | События, которые принимает | Что делает каждая машина |
|---|---|---|
| `IDLE` | `start(index)` | — (меню; уровень выключен) |
| `ACTIVE` | `report_caught` → `ALARM`; чекпоинт следующего индекса → `ACTIVE` (или `FINISHED`); `start(index)` | препятствия взведены, часы секций идут |
| `ALARM` | `reset` → `ACTIVE` (тот же индекс); `start(index)` → `ACTIVE`; **чекпоинт не принимается** (Д5, К15); новые причины отбрасываются (T-17) | препятствия сняты с взвода, часы секций стоят, своё управление заблокировано (T-20) |
| `FINISHED` | ничего | итог; препятствия сняты с взвода |

Методы `LevelFlow` (чистые, юнит-тест `test_level_flow.gd`):
- `func start(index: int) -> void` — из любого состояния, кроме `FINISHED`; снимает тревогу;
- `func begin_alarm(cause: SectionReset.Cause, actor_id: int) -> bool`;
- `func finish_alarm() -> bool`;
- `func can_reach(index: int) -> bool` — `ACTIVE` и `index == current + 1`;
- `func reach(index: int) -> bool`; `func is_finished() -> bool`;
- `var current: int`, `var finale_index: int`.

**Состояние секции** — производное от уровня: секция с индексом `current` «текущая»
(её `Content` пересоздаётся при сбросе), пройденные и будущие живут дальше (Д6: поимка в
пройденной секции сбрасывает к новому чекпоинту). Секций мало, выключать дальние не нужно;
когда уровень вырастет — дальние секции выключаются `process_mode` (оптимизация, не
контракт).

### Как это ложится на существующее

- **Тревога и сброс переезжают из `SectionRoot` в `LevelRoot`** (T-23): все причины со всех
  секций сходятся в `LevelRoot.report_caught(cause, actor_id)` — то же правило T-17 («один
  вход, одно срабатывание — один сброс»), новое место. `SectionRoot` перестаёт держать
  `SectionReset`, таймер и RPC; он находит свои препятствия и движители и пересоздаёт
  `Content`. Логика `SectionReset` и её тесты не меняются — ей владеет `LevelFlow`.
- **Сброс к текущему чекпоинту:** хост в конце паузы → `Diamond.reset_to(checkpoint.diamond_point)`
  → `_apply_section_reset(index)`; каждая машина: `SectionRoot.recreate_content()` текущей
  секции, остальные секции `set_armed(true)`, свои персонажи — `Player.respawn_at(...)` на
  точках чекпоинта, разблокировка, сигнал `section_reset(section_id)`.
- **`Content` пересоздаётся** (T-25, заменяет временный T-18): `remove_child` старого,
  `queue_free`, `instantiate()` из `SectionRoot.content_scene` с именем `Content` — путь
  RPC тот же. Пока секция без `content_scene` (тестовая сцена до DIA-12) — откат на
  `set_armed(true)`, как сейчас.
- **Старт с чекпоинта** (начало игры хоста, выбор при подключении): `_apply_level_started(index)` —
  пересоздаются `Content` **всех** секций, часы всех секций с нуля, свои персонажи на
  точках чекпоинта. Если шла тревога — она снимается этим же событием, сброса по таймеру не
  будет (хост останавливает таймер): переход ровно один (Д19, К52).
- `Player.respawn()` (группа `spawn_points`) заменяется на `Player.respawn_at(point: Transform3D)`;
  точку даёт `LevelRoot.spawn_point(peer_id: int) -> Transform3D` (хост — `SpawnHost`,
  второй — `SpawnClient` текущего чекпоинта). Старый `respawn()` остаётся обёрткой, пока
  тесты F-001 не переведены.

### Чекпоинт (T-24)

Узел `Checkpoint` (`scripts/level/checkpoint.gd`, `extends Node3D`) в каждой секции:
`Zone` (`Area3D`, маска `players`), `SpawnHost`, `SpawnClient`, `DiamondPoint`
(`Marker3D`), `@export var is_finale: bool`. Конфиг `CheckpointConfig`
(`data/checkpoint_config.tres`): `zone_radius: float` — м — `1.5`; `report_tolerance: float`
— м — `2.0`; `sign_seconds: float` — с — `2.0`.

Несомый алмаз без коллизий (T-06), поэтому зона ловит **тело носильщика**. Судит машина,
которая видит без задержки (T-15) — носильщик:
- на машине носильщика: `Zone.body_entered(свой Player)` при `diamond.carrier_id == свой id`
  или `Diamond.carrier_changed` на свой id, когда своё тело уже в зоне
  (`Zone.overlaps_body`) → `LevelRoot.request_report_checkpoint.rpc_id(1, index)`;
- хост проверяет: отправитель — носильщик (`CarryRules.is_carried_by`), `LevelFlow.can_reach(index)`,
  синхронизированная позиция отправителя ближе `zone_radius + report_tolerance` к центру
  зоны. Брошенный алмаз не засчитывает: в полёте носильщика нет (К14).
- Хост: `Diamond.durability_component.restore()` (событие прочности, алмаз остаётся в руках) →
  `_apply_checkpoint_reached(index)`. Каждая машина: `LevelFlow.reach`, сигнал
  `checkpoint_reached(index: int, checkpoint_id: String)`; если `is_finale` — ещё
  `finale_reached()`. Порядок «прочность → чекпоинт» держит один канал надёжных RPC.
- Запись прогресса — по этому событию; знак «чекпоинт достигнут» — после записи, по
  `ProgressStore.checkpoint_recorded` (с DIA-7; до этого в DIA-12 — прямо по
  `checkpoint_reached`); победный сигнал — по `checkpoint_reached` (`saves.md`, раздел 4;
  раздел 7 ниже).

## 4. Сигналы и RPC

**Сигналы** (прошедшее время, на каждом пире):
- `Session.state_changed(state: int, previous: int)`, `Session.partner_changed(state: int)`,
  `Session.start_options_changed(options: PackedStringArray, current_id: String, host_farthest: String, partner_farthest: String, selected_id: String)`,
  `Session.session_started(start_id: String)`;
- `LevelRoot.alarm_started(cause: int, actor_id: int)`, `LevelRoot.section_reset(section_id: String)`,
  `LevelRoot.level_started(checkpoint_id: String)`, `LevelRoot.checkpoint_reached(index: int, checkpoint_id: String)`,
  `LevelRoot.finale_reached()`, `LevelRoot.full_state_applied()`;
- `SectionRoot.content_recreated()`;
- `Network.session_ended(reason: int)`, `Network.ping_measured(rtt_ms: float)`.

Подписчики, которые сейчас слушают `SectionRoot.alarm_started/section_reset` (`Hud`,
`CaughtFeedback`, `SectionAudio`), переводятся на `LevelRoot` с теми же аргументами.

**RPC:**

| Метод | Кто вызывает | На ком выполняется | Надёжность | Что проверяет хост |
|---|---|---|---|---|
| `Session.request_join(farthest_id: String, finished: bool)` | второй игрок после `joined` | хост | `any_peer`, `call_remote`, `reliable` | отправитель — подключённый пир, `partner == NONE`; неизвестный ID → как хранилище |
| `Session._apply_start_options(options, current_id, host_farthest, partner_farthest, selected_id)` | хост (открыл экран, сдвинул указатель, сессия дошла до нового чекпоинта — Д20) | все | `authority`, `call_local`, `reliable` | — |
| `Session._apply_session_started(start_id: String)` | хост по подтверждению | все | `authority`, `call_local`, `reliable` | `start_id` в диапазоне (7.2 B) |
| `LevelRoot.request_report_checkpoint(index: int)` | носильщик | хост | `any_peer`, `call_local`, `reliable` | см. «Чекпоинт» |
| `LevelRoot._apply_alarm_started(cause, actor_id)` | хост | все | `authority`, `call_local`, `reliable` | (переезд из `SectionRoot`) |
| `LevelRoot._apply_section_reset(index: int)` | хост по таймеру | все | `authority`, `call_local`, `reliable` | (переезд, + индекс) |
| `LevelRoot._apply_checkpoint_reached(index: int)` | хост | все | `authority`, `call_local`, `reliable` | — |
| `LevelRoot._apply_level_started(index: int)` | хост | все | `authority`, `call_local`, `reliable` | — |
| `LevelRoot._apply_full_state(state: Dictionary)` | хост при `peer_connected` | новый пир | `authority`, `call_remote`, `reliable` | — (`index`, `alarm`, `cause`, `actor_id`, `alarm_remaining`, `clocks`) |
| `Network._apply_host_ended()` | хост перед закрытием | клиент | `authority`, `call_remote`, `reliable` | — |

После `_apply_session_started` хост спавнит персонажа второго игрока (сейчас — сразу по
`peer_joined`; T-27 переносит спавн на выбор). Если выбран текущий чекпоинт — уровень не
трогается (К51); иначе хост сначала `reset_to` алмаза, затем `_apply_level_started(index)`,
затем спавн. Полное состояние алмаза и уровня приходит при подключении, до выбора, — экран
выбора закрывает мир, пока игрок ждёт; уровень у клиента к этому моменту уже включён (по
`joined`, раздел 1).

## 5. Подключение, отключение, конец сессии (decision-05 A, 09 A)

- **Вход** (T-27): `Network` ставит `SceneMultiplayer.auth_callback` (API 4.4.1:
  `auth_callback`, `send_auth`, `complete_auth`, `peer_authenticating`,
  `peer_authentication_failed`). Клиент шлёт JSON `{"protocol": Network.PROTOCOL_VERSION}`,
  хост отвечает `{"ok": bool, "refusal": int}` по логике `JoinRules.check(protocol: int,
  peers: int, session_open: bool) -> int` (`JoinRefusal.NONE | FULL | VERSION | FINISHED`).
  Отказ приходит до `peer_connected` — третий игрок не получает спавнов и полного
  состояния (К5). `ENetMultiplayerPeer.create_server(port, MAX_CLIENTS + 1)`, чтобы третий
  дошёл до ответа «заполнено», а не до немого отказа транспорта.
- **Как закрывается отклонённый** (К5). Хост после `send_auth(id, отказ)` **не** вызывает
  `complete_auth(id)` и **не** зовёт `disconnect_peer(id)` сразу — иначе ответ может не
  уйти, и третий увидит немой разрыв. Закрывает клиент сам: его `auth_callback` читает
  `{"ok": false, "refusal": r}` → `last_end_reason = REFUSED_*` → `Network.close()` →
  `connect_failed(reason)`. Если клиент молчит (старая сборка, завис), хост отпускает пира по
  `SceneMultiplayer.auth_timeout` — ставим явно `AUTH_TIMEOUT = 3.0` с (значение по
  умолчанию в 4.4.1); у хоста при этом `peer_authentication_failed(id)`, убирать нечего:
  пир не стал подключённым. Клиент, не получивший ответа за свой `auth_timeout`, — тоже
  `peer_authentication_failed` → `connect_failed(CONNECT_FAILED)`. Проверка —
  `test_session_flow_net`: третий получает `REFUSED_FULL` (не `CONNECT_FAILED`), у двоих нет
  `peer_connected`/`peer_disconnected` от него, после закрытия клиента список
  `get_authenticating_peers()` у хоста пуст.
- **Ушёл второй игрок:** хост: `peer_left` → `Diamond._on_peer_disconnected` кладёт алмаз
  (есть), персонаж удаляется (есть), `Session.partner = NONE`, уведомление. Таймер тревоги на
  хосте — сброс ровно один (К10, уже покрыто F-001).
- **Хост вышел сам:** `Network.end_session()` на хосте → `_apply_host_ended.rpc()` →
  через `SESSION_END_GRACE` (0,25 с, `Timer`) `close()`. Клиент по `_apply_host_ended`:
  `last_end_reason = HOST_ENDED`, `close()`, перезагрузка `Main`.
- **Связь пропала:** `server_disconnected` без предшествующего `_apply_host_ended` →
  `last_end_reason = CONNECTION_LOST`. Если `_apply_host_ended` потерялся — игрок увидит
  «связь потеряна»; прогресс от этого не меняется.
- `enum Network.EndReason { NONE, LEFT, HOST_ENDED, CONNECTION_LOST, CONNECT_FAILED, REFUSED_FULL, REFUSED_VERSION, REFUSED_FINISHED }`,
  `var last_end_reason: int`, `func take_end_reason() -> int` (читает и сбрасывает — меню
  показывает сообщение один раз).
- Тайм-аут подключения (К4): `Network.CONNECT_TIMEOUT` → `SessionConfig.connect_timeout: float`
  — с — `10.0` (`Timer`), затем `connect_failed(CONNECT_FAILED)`.

`SessionConfig` (`data/session_config.tres`): `connect_timeout: float = 10.0`,
`notice_seconds: float = 3.0` (уведомления о напарнике), `quit_confirm_for_host: bool = true`.

## 6. Подключившийся догоняет состояние (замечание ревью F-001 № 4, T-34)

Правило: **`_apply_full_state` восстанавливает и логику, и то, что видно и слышно.** Каждый
узел с полным состоянием после применения испускает `full_state_applied()`. Реакции делятся
на два рода:
- **длящиеся** (мигание сработавшего луча, сирена, затемнение, поза виновника, стадия
  повреждения) подписаны ещё и на `full_state_applied` и показывают текущее состояние «с
  середины»: затемнение — по `alarm_remaining`, сирена — с начала петли, без стартового
  удара;
- **разовые** (звук удара, трещины, искра) — только на события; при догоне не играют.

Полное состояние препятствия — его собственный RPC `LaserBeam._apply_full_state(tripped:
bool, point: Vector3)` (`obstacles.md`, раздел 6). Тест: подключение во время паузы →
у нового пира `is_tripped()`, `CaughtFeedback.is_showing()`, затемнение видимо.

## 7. Звук

| Сигнал | Звук | Шина | 2D/3D | Кто слышит |
|---|---|---|---|---|
| `Session.state_changed` (экраны), выбор указателя | звук интерфейса | UI | 2D | только сам |
| `Network.session_ended` (`CONNECTION_LOST`, отказ) | ошибка интерфейса | UI | 2D | только сам |
| `Session.partner_changed` → `CHOOSING`/`PRESENT` | уведомление «пришёл» | UI | 2D | оба (экран выбора), хост |
| `Session.partner_changed` → `NONE` | уведомление «ушёл» (другое) | UI | 2D | хост |
| `LevelRoot.checkpoint_reached` | победный сигнал | SFX | 2D | оба, где угодно |
| `LevelRoot.level_started` | звук начала (не сирена) | SFX | 2D | оба |
| `LevelRoot.finale_reached` | джингл | Music | 2D | оба |

Победный сигнал подписан на событие уровня, знак — на `ProgressStore.checkpoint_recorded`
(`saves.md`, раздел 4). Звук не обещает «прогресс записан» — это обещает знак (К27); запись
синхронна в обработчике того же события, поэтому звук и знак — в одном кадре. Звук
чекпоинта делается целиком в DIA-12 и в DIA-7 не переподписывается.

Сирена и звук сброса — `SectionAudio`, переподписка на `LevelRoot`.
