# DIA-5 — Архитектурные столпы (F-004): технический план

Статус: утверждён 2026-11-21 (H2), вместе с допущениями А1–А6
игрока, формат сохранения, `project.godot` (локализация, предупреждения GDScript), замена
временного решения T-18 и места T-17
Автор: architect
Карточка: `card.md` (утверждена 2026-11-21: 1A 2B 3B 4A 5A 6A, 7.1A 7.2B 7.3A, 8A, 9A)
Техзадание: `docs/tech/game-flow.md`, `saves.md`, `components.md`, `latency.md`,
`obstacles.md` §6; журнал T-22…T-41

## Решение в двух абзацах

Фича архитектурная: её результат — четыре файла техзадания, по которым подзадачи DIA-6…DIA-15
реализуются отдельно, каждая со своим циклом «тесты → код → ревью». Три машины состояний
разведены по ответственности: **сессия** (`SessionFlow` в узле `Main/Session`; у каждой
машины своя, события — от своего ввода и от хоста), **уровень** (`LevelFlow` в `LevelRoot`
на корне сцены уровня — текущий чекпоинт, тревога, финал; ведёт хост) и **секция**
(`SectionRoot` — своё `Content`, препятствия, часы). Новой автозагрузки нет: возврат в меню
— перезагрузка `Main`, а единственное, что должно её пережить, — причина конца сессии —
факт соединения и хранится в `Network` (`ARCHITECTURE.md`, «Связи»). Тревога и сброс
переезжают из `SectionRoot` в `LevelRoot`, потому что с несколькими секциями поимка в
пройденной секции сбрасывает к новому чекпоинту (Д6); правило T-17 не меняется.

Снимок чекпоинта — **только ID дальнего чекпоинта и «пройдено»**: всё остальное выводится
из сцены (пересоздание `Content`, алмаз на `DiamondPoint`, полная прочность). Каждая машина
пишет свой файл по событию хоста, прогресс по сети не передаётся, кроме номера при
подключении (decision-02 B, 7.1 A / 7.2 B / 7.3 A). Компоненты — по правилу «интерфейс =
таблица контракта + контрактный тест» (в 4.4.1 нет `@abstract`): прочность —
`DurabilityComponent` со стадиями, на него переходит алмаз; движение — `PathMover` от часов
секции, детерминированно, без синхронизатора; общего предка `Movable` нет, потому что
подвижные объекты наследуют разные встроенные типы. Имитация задержки — сменные стратегии
в `Network`, включая обёртку `LagPeer extends MultiplayerPeerExtension` (проверено по
справочнику 4.4.1), пинг меряется RPC на уровне игры.

## Слои

| Слой | Класс / файл | Ответственность |
|---|---|---|
| Данные | `SessionConfig`, `CheckpointConfig`, `DurabilityConfig`, `DurabilityLookConfig`, `PathMoverConfig`, `CaughtFeedbackConfig` → `data/*.tres`; поля `LaserConfig.rearm_delay`, `report_tolerance` | числа ниже |
| Логика | `SessionFlow`, `JoinRules`, `LevelFlow` (+ `SectionReset` как есть), `SectionClock`, `CheckpointRoute`, `ProgressRecord`, `SaveFormat`, `SaveLoadResult`, `ProgressRules`, `Durability` (+ стадии), `PathMotion`, `DelayQueue`, `Obstacle.report_plausible` | правила без узлов, сети, `Input`, физики |
| Узлы | `Session`, `LevelRoot`, `Checkpoint`, `SectionRoot` (упрощается), `ProgressStore`, `SaveFile`, `DurabilityComponent`, `DurabilityLook`, `PathMover`, `PathRails`, `Network` (+ авторизация, конец сессии, пинг, задержка), `LagPeer`, стратегии задержки, экраны UI, `NetOverlay` | адаптер: ввод, физика, RPC, файлы, сигналы |

## Контракты

Полные сигнатуры — в файлах техзадания (раздел указан). Здесь — сводка для H2.

**Поля конфигов** (тип, единицы, заглушка — подбирает владелец):
- `SessionConfig`: `connect_timeout: float` — с — `10.0`; `notice_seconds: float` — с —
  `3.0`; `quit_confirm_for_host: bool` — `true` (`game-flow.md` §5)
- `CheckpointConfig`: `zone_radius: float` — м — `1.5`; `report_tolerance: float` — м —
  `2.0`; `sign_seconds: float` — с — `2.0` (§3)
- `DurabilityConfig`: `max_durability: float` — `100.0`; `min_impact_speed: float` — м/с —
  `3.5`; `damage_per_speed: float` — `8.0`; `stage_thresholds: PackedFloat32Array` —
  доли — `[0.667, 0.333]` (`components.md` §3). У алмаза числа — как сейчас в
  `diamond_config.tres`
- `DurabilityLookConfig`: `stage_colors: PackedColorArray` — заглушки
- `PathMoverConfig`: `speed: float` — м/с — `1.0`; `dwell: float` — с — `0.5` (§4)
- `CaughtFeedbackConfig`: `tilt_degrees: float` — `28.0`; `blink_color: Color`;
  `blink_hz: float` — Гц — `5.0` (§5, значения из нынешних констант)
- `LaserConfig` (+): `report_tolerance: float` — м — `3.0`; `rearm_delay: float` — с —
  `2.0` (`obstacles.md` §6)

**Методы логики** — `game-flow.md` §2–3 (`SessionFlow`, `LevelFlow`, `JoinRules`),
`saves.md` §2–4 (`CheckpointRoute`, `SaveFormat`, `ProgressRules`), `components.md` §3–4
(`Durability`, `PathMotion`, `SectionClock`), `latency.md` §2 (`DelayQueue`, контракт
`LatencySimulator`).

**Сигналы** — `game-flow.md` §4, `components.md` §3, `saves.md` §4
(`ProgressStore.checkpoint_recorded`), `latency.md` §4 (`Network.ping_measured`).

**RPC** (все новые или перенесённые):

| Метод | Кто вызывает | На ком выполняется | Надёжность | Что проверяет хост |
|---|---|---|---|---|
| авторизация `SceneMultiplayer` (`send_auth`/`complete_auth`) | клиент ↔ хост | — | транспорт | `JoinRules.check`: версия, мест нет, игра закончена |
| `Session.request_join(farthest_id: String, finished: bool)` | второй игрок | хост | `any_peer`, `call_remote`, `reliable` | отправитель подключён, `partner == NONE` |
| `Session._apply_start_options(options: PackedStringArray, current_id: String, host_farthest: String, partner_farthest: String, selected_id: String)` | хост | все | `authority`, `call_local`, `reliable` | — |
| `Session._apply_session_started(start_id: String)` | хост | все | `authority`, `call_local`, `reliable` | `ProgressRules.is_valid_start` |
| `LevelRoot.request_report_checkpoint(index: int)` | носильщик | хост | `any_peer`, `call_local`, `reliable` | носильщик = отправитель, `can_reach`, допуск позиции |
| `LevelRoot._apply_alarm_started(cause: int, actor_id: int)` | хост | все | `authority`, `call_local`, `reliable` | перенос из `SectionRoot` |
| `LevelRoot._apply_section_reset(index: int)` | хост | все | `authority`, `call_local`, `reliable` | перенос, + индекс |
| `LevelRoot._apply_checkpoint_reached(index: int)` | хост | все | `authority`, `call_local`, `reliable` | — |
| `LevelRoot._apply_level_started(index: int)` | хост | все | `authority`, `call_local`, `reliable` | — |
| `LevelRoot._apply_full_state(state: Dictionary)` | хост | новый пир | `authority`, `call_remote`, `reliable` | перенос, + `index`, `alarm_remaining`, `clocks` |
| `LaserBeam._apply_full_state(tripped: bool, point: Vector3)` | хост | новый пир | `authority`, `call_remote`, `reliable` | — |
| `LaserBeam._apply_rearmed()` | хост | все | `authority`, `call_local`, `reliable` | только для `NONE`, с первым применением |
| `DurabilityComponent._apply_durability(current: float, damage: float)` | хост | все | `authority`, `call_local`, `reliable` | перенос из `Diamond` |
| `DurabilityComponent._apply_full_state(current: float)` | хост | новый пир | `authority`, `call_remote`, `reliable` | — |
| `Diamond._apply_full_state(new_carrier: int)` | хост | новый пир | как было | **сигнатура меняется**: прочность — у компонента |
| `Network._apply_host_ended()` | хост | клиент | `authority`, `call_remote`, `reliable` | — |
| `Network._ping(sent_usec: int)` / `_pong(sent_usec: int)` | любой | другой | `any_peer`, `call_remote`, `unreliable` | — |

Отчёт о касании `LaserBeam.request_report_player_touch` — тот же RPC, хост добавляет
допуск (`Obstacle.report_plausible`, ревью № 8).

**Кто чем управляет по сети:**

| Состояние | Владелец | Как доходит до остальных |
|---|---|---|
| Состояние сессии (экран) | каждая машина сама | своим вводом; `session_started`, `_apply_host_ended` от хоста |
| Выбор стартового чекпоинта | хост (7.1 A) | событие `_apply_start_options` / `_apply_session_started` |
| Спавн персонажа второго игрока | хост, **после выбора** (было — сразу при подключении) | `MultiplayerSpawner` |
| Текущий чекпоинт, тревога, финал | хост | события `LevelRoot`; новому — `_apply_full_state` |
| Факт «алмаз в руках вошёл в зону» | машина носильщика судит | `request_report_checkpoint`, решает хост |
| Часы секций | каждая машина сама | вычисляются от событий хоста; новому — в полном состоянии |
| Положение подвижного луча | каждая машина сама | функция часов секции, без синхронизатора |
| Прочность (алмаз, ящик) | хост | события компонента |
| Стадия повреждения | каждая машина сама | вычисляется из прочности |
| Прогресс игрока (файл) | каждая машина своя | пишет по событию хоста; хосту — только `farthest_id` при входе |
| Причина конца сессии | каждая машина сама (`Network`) | `HOST_ENDED` — от события хоста |
| Пинг | каждая машина сама | RPC `_ping/_pong` |
| Имитация задержки | клиент сам | аргумент запуска, не по сети |

## Звук (для звукового дизайнера)

| Сигнал | Звук | Шина | 2D/3D | Кто слышит | Параметры в конфиге |
|---|---|---|---|---|---|
| `Session.state_changed`, смена указателя выбора | интерфейс | UI | 2D | только сам | громкость |
| `Network.session_ended` (потеря связи, отказ) | ошибка интерфейса | UI | 2D | только сам | громкость |
| `Session.partner_changed` → пришёл / экран выбора | уведомление | UI | 2D | оба (экран), хост | громкость |
| `Session.partner_changed` → ушёл | другое уведомление | UI | 2D | хост | громкость |
| `ProgressStore.checkpoint_recorded` | победный сигнал | SFX | 2D | оба, в любой точке | громкость |
| `LevelRoot.level_started` | начало (не сирена) | SFX | 2D | оба | громкость |
| `LevelRoot.finale_reached` | джингл | Music | 2D | оба | громкость |
| `DurabilityComponent.damaged` | удар по материалу объекта | SFX | 3D | все | громкость, порог |
| `DurabilityComponent.stage_changed` | трещина, громче удара | SFX | 3D | все | по стадиям |
| `DurabilityComponent.destroyed` (ящик) | разрушение | SFX | 3D | все | громкость |
| подвижный луч (петля `LaserAudio`) | гудение едет с лучом | SFX | 3D | каждый у себя | затухание |

Сирена и сброс — `SectionAudio`, переподписка с `SectionRoot` на `LevelRoot`. Звук на
`full_state_applied` — только длящийся (петля сирены), разовые не играют. У второго
игрока на экране выбора шины SFX и Ambience приглушены (допущение А3).

## Файлы

Создать (по подзадачам ниже):
`scripts/flow/{session_flow,session,session_config,join_rules}.gd`,
`scripts/level/{level_root,level_flow,checkpoint,checkpoint_config,section_clock}.gd`,
`scripts/save/{checkpoint_route,progress_record,save_format,save_load_result,progress_rules,save_file,progress_store}.gd`,
`scripts/durability/{durability_component,durability_config,durability_look,durability_look_config}.gd`,
`scripts/motion/{path_motion,path_mover,path_mover_config,path_rails}.gd`,
`scripts/net/latency/{no_latency,proxy_latency,peer_latency,lag_peer,delay_queue}.gd`,
`scripts/player/caught_feedback_config.gd`, `scripts/ui/{slot_select,start_select,game_menu,result_screen,help,partner_sign,net_overlay}.gd`;
сцены `scenes/ui/*.tscn` к ним, `scenes/props/{moving_laser_beam,training_crate}.tscn`,
`scenes/sections/<id>_content.tscn`; `data/{session,checkpoint,diamond_durability,training_crate_durability,path_mover,caught_feedback}_config.tres`;
`locale/ru.po`.

Изменить: `scripts/main.gd`, `scripts/net/network.gd`, `scripts/level/section_root.gd`,
`scripts/diamond/{diamond,diamond_config,durability}.gd`, `scripts/obstacles/{obstacle,laser_beam,laser_config}.gd`,
`scripts/player/{player,caught_feedback}.gd`, `scripts/ui/{hud,main_menu}.gd`,
`scripts/level/section_audio.gd`, `scenes/main.tscn`, `scenes/props/diamond.tscn`,
`scenes/level/test_level.tscn` (левел-дизайнер), `data/diamond_config.tres` (только перенос
полей прочности, числа те же), `tools/run_local_coop.cmd`, `project.godot` (архитектор,
после H2).

Не трогать: `DESIGN.md`, `ARCHITECTURE.md` (правка — после H2, если владелец примет T-22…T-41),
`data/*.tres` с числами баланса, `addons/`, `tools/lag_proxy.py` (остаётся как есть).

## Тесты (для тест-инженера)

Пишутся в своих подзадачах до кода. Общая обвязка: `tests/support/net_pair.gd` — два
`SceneMultiplayer` в одном процессе на ENet `127.0.0.1` (`latency.md` §4).

- `tests/unit/test_session_flow.gd`: каждое состояние имеет путь в `MAIN_MENU`; недопустимые
  события ничего не меняют; `RESULT` игнорирует `host_ended`/`connection_lost`; подтверждение
  выхода только у хоста с напарником
- `tests/unit/test_join_rules.gd`: третий → `FULL`; другая версия → `VERSION`; финал → `FINISHED`
- `tests/unit/test_level_flow.gd`: чекпоинт только следующий и только в `ACTIVE`; в `ALARM`
  не засчитывается; `start` снимает тревогу; финальный → `FINISHED`
- `tests/unit/test_checkpoint_route.gd`, `test_save_format.gd` (круг запись→чтение, повреждён,
  `TOO_NEW`, нет поля, `pick` с `.tmp`), `test_progress_rules.gd` (монотонность, финал не
  записывается, `start_options` 7.2 B, засчёт 7.3 A, `compare`, `skips_sections`, сценарий
  владельца 5/2 → 4/5)
- `tests/unit/test_durability.gd` (+ стадии, пороги, ровно один переход), `test_path_motion.gd`,
  `test_section_clock.gd`, `test_delay_queue.gd`, `test_obstacle.gd` (+ `report_plausible`)
- `tests/integration/test_session_flow_net.gd` (NetPair): вход, отказ третьему, выход хоста →
  `HOST_ENDED` у клиента, обрыв → `CONNECTION_LOST`, повторный вход без двойного персонажа
- `tests/integration/test_level_checkpoint.gd`: отчёт носильщика засчитан, чужой/брошенный/в
  тревоге — нет; прочность полная; сброс после чекпоинта — к новому; порядок «событие →
  запись → знак»
- `tests/integration/test_section_content.gd`: после сброса `Content` новый, пути те же,
  ящик целый, подвижный луч в начале; подключение во время паузы догоняет вид (№ 4)
- `tests/integration/test_progress_store.gd`: запись на чекпоинте, `--profile`, повреждённый
  файл без `ERROR:` в логе
- `tests/integration/test_start_select.gd`: текущий — без сброса; другой — один переход, в том
  числе в тревоге; диапазон; засчёт сразу; обновление списка при новом чекпоинте (Д20)
- `tests/integration/test_durability_contract.gd` (алмаз, ящик), `test_training_crate.gd`,
  `test_moving_laser.gd` (`test_moving_beam_trips_standing_player`, замирание в тревоге)
- `tests/integration/test_latency_contract.gd`, `test_latency_peer.gd` (150 ± 40 мс, порядок)
- Контент-тесты: ключи `tr()` есть в `locale/ru.po`; в сценах и скриптах нет кириллицы в
  строках для игрока; `NONE` не используется; числа `diamond_durability.tres` = прежним;
  ID секций уникальны
- Меняются из-за переноса API (не ослабляются): `test_durability::from_config`,
  `test_section_reset_flow` (на `LevelRoot`), `test_test_level` (точки появления чекпоинта)
- Критерии → тесты: К1, К6 → `test_session_flow`; К2, К21 → `test_progress_store`; К3,
  К5, К8–К10, К44–К46, К63 → `test_session_flow_net`; К11, К22 → `test_progress_rules`; К12
  → `test_level_checkpoint` + H3; К13–К17 → `test_level_flow`, `test_level_checkpoint`;
  К19–К27, К37–К40 → сохранения; К49–К57 → `test_start_select`; К28–К31 → прочность; К32–К34
  → `test_moving_laser`; К58–К60 → `test_session_flow_net`; К4, К7, К18, К35, К36, К41, К43,
  К57 (понятность), К62 → H3

## DIA-10: замечания ревью F-001 и расхождения журнала

| Что | Решение | Где описано |
|---|---|---|
| № 4 подключившийся во время паузы не видит и не слышит тревогу | полное состояние догоняет и вид: `full_state_applied`, `LaserBeam._apply_full_state`, `alarm_remaining` (T-34) | `game-flow.md` §6, `obstacles.md` §6 |
| № 5 `Consequence.NONE` без перевзвода | контракт: самоперевзвод через `rearm_delay` (`_apply_rearmed`); до первого применения запрещён контент-тестом (T-35) | `obstacles.md` §6 |
| № 7 константы позы поимки | `CaughtFeedbackConfig` с нынешними значениями (T-37) | `components.md` §5 |
| № 8 хост не проверяет, где сообщивший | допуск `report_tolerance = 3 м` до отрезка луча (T-36) | `obstacles.md` §6 |
| № 9 задержка 150 мс не описана | `latency.md` (T-38) | `latency.md` |
| `untyped_declaration` не поднят до ошибки | `project.godot`: `debug/gdscript/warnings/untyped_declaration=2` (в 4.4.1: `int`, по умолчанию `0`), `exclude_addons` остаётся `true`. Порядок: сначала `=1` и типизация всего, что выдаст предупреждение (`scripts/` — программист, `tests/` — тест-инженер), затем `=2` (T-40) | здесь |
| Строки HUD без `tr()`, нет `locale/` | `locale/ru.po` (исходный язык `ru`), ключи `ui.*`, `hud.*`; `project.godot`: `internationalization/locale/translations=PackedStringArray("res://locale/ru.po")` (ключ пишет вкладка «Локализация» редактора; в справочнике `ProjectSettings` 4.4.1 его нет — архитектор ставит через редактор и сверяет файл), `internationalization/locale/fallback="ru"` (по умолчанию `"en"`). Отладочные `print` с русским текстом — не текст для игрока, остаются. Контент-тест: каждый ключ `tr("…")` в `scripts/` есть в `ru.po` (T-39) | здесь |
| SSAO в тестовом уровне | убрать `ssao_enabled` из `WorldEnvironment` `test_level.tscn` — в Compatibility не работает (T-41) | здесь |

Правки `project.godot` (T-39, T-40) — после H2, отдельным коммитом архитектора, вместе с
подзадачей, которая приносит `ru.po` и типизацию (иначе тесты упадут).

## Задачи для трекера

Каждая — свой цикл «тесты → код → ревью», вливается отдельным шагом. Роль «тест-инженер →
программист» значит: тесты по этому плану, затем код.

| Подзадача | К задаче | Роль | Готово, когда |
|---|---|---|---|
| Локализация: `locale/ru.po`, `tr()` в HUD, меню, `Main`, `Player`; `project.godot` translations | DIA-10 | программист; архитектор (`project.godot`); тест-инженер (контент-тест) | контент-тест ключей зелёный, в строках для игрока нет кириллицы |
| Типизация и `untyped_declaration` = ошибка | DIA-10 | программист (`scripts`), тест-инженер (`tests`), архитектор (`project.godot`) | `run_tests` зелёный при настройке «ошибка» |
| Убрать SSAO из тестового уровня | DIA-10 | левел-дизайнер | `test_project_loads` зелёный, в `test_level.tscn` нет `ssao_enabled` |
| `CaughtFeedbackConfig` (№ 7) | DIA-10 | программист | тесты позы зелёные, констант в `caught_feedback.gd` нет |
| Допуск отчёта о касании (№ 8) | DIA-10 | тест-инженер → программист | `test_obstacle`, `test_laser_beam::test_host_report_*` с далёким отправителем |
| Контент-тест «`NONE` не используется» (№ 5) | DIA-10 | тест-инженер | тест зелёный |
| **Новая:** обвязка двух пиров `NetPair` | DIA-9 | тест-инженер | пример-тест: RPC от клиента доходит до хоста |
| Контракт задержки, `NoLatency`/`ProxyLatency`, выбор в `Network`, `run_local_coop` | DIA-9 | тест-инженер → программист | `test_latency_contract` зелёный; `run_local_coop.cmd 150` работает как раньше |
| `LagPeer` (`PeerLatency`) | DIA-9 | тест-инженер → программист | `test_delay_queue`, `test_latency_peer` (150 ± 40 мс, порядок) зелёные |
| Пинг и `NetOverlay` | DIA-9 | тест-инженер → программист | `ping_measured` в NetPair; H3: оверлей виден с `--net-overlay` |
| `LevelRoot`/`LevelFlow`: перенос тревоги и сброса из `SectionRoot`; догон вида (№ 4) | DIA-12 | тест-инженер → программист | тесты F-001 на новом месте и `test_level_flow` зелёные; подключение во время паузы догоняет вид |
| **Новая:** пересоздание `Content` секции при сбросе (T-25) | DIA-12 | тест-инженер → программист; левел-дизайнер (`content_scene` тестовой секции) | `test_section_content` зелёный |
| Чекпоинт: зона, отчёт носильщика, событие, восстановление прочности, знак | DIA-12 | тест-инженер → программист | `test_level_checkpoint` зелёный |
| Секции и финал в тестовой сцене (≥ 3 чекпоинта + выход) | DIA-12 | левел-дизайнер | `test_test_level`: маршрут, точки чекпоинтов вне лучей |
| Звуки чекпоинта, начала, финала | DIA-12 | звуковой дизайнер | `test_*_audio` зелёные; H3 К18 |
| `DurabilityComponent`, стадии, перенос алмаза | DIA-13 | тест-инженер → программист | `test_durability`, `test_durability_contract`, прежние тесты алмаза зелёные (К28) |
| Учебный ящик (сцена + расстановка в тестовой секции) | DIA-13 | программист; левел-дизайнер | `test_training_crate` зелёный (К29, К31) |
| Вид и звук стадий | DIA-13 | программист (`DurabilityLook`), звуковой дизайнер | тест смены материала; H3 К30 |
| `SectionClock`, `PathMotion`, `PathMover` | DIA-14 | тест-инженер → программист | `test_path_motion`, `test_section_clock` зелёные |
| Подвижный луч: сцена, направляющие, расстановка | DIA-14 | программист; левел-дизайнер | `test_moving_laser` зелёный (К32–К34); H3 К35–К36 |
| Логика сохранения (`CheckpointRoute`, `SaveFormat`, `ProgressRules`) | DIA-7 | тест-инженер → программист | юнит-тесты сохранения зелёные |
| `ProgressStore`, `SaveFile`, `--profile` | DIA-7 | тест-инженер → программист | `test_progress_store` зелёный (К19–К22, К26) |
| Справка и сообщения о прогрессе | DIA-7 | программист | переходы в тесте экранов; H3 К41–К43 |
| `SessionFlow`, `Session`, экраны (меню, слот, подключение, игровое меню, итог, знак напарника) | DIA-11 | тест-инженер → программист | `test_session_flow` зелёный; H3 К4, К7 |
| `Network`: авторизация, конец сессии, причина, спавн после выбора | DIA-11 | тест-инженер → программист | `test_join_rules`, `test_session_flow_net` зелёные |
| Выбор стартового чекпоинта: RPC, экран, старт с чекпоинта | DIA-15 | тест-инженер → программист | `test_start_select` зелёный (К49–К56); H3 К57 |
| Звуки интерфейса и уведомлений о напарнике | DIA-11 | звуковой дизайнер | тест подписки; H3 |
| `ARCHITECTURE.md` и журнал после H2 | DIA-5 | ведущий (ARCHITECTURE.md), архитектор (журнал) | статусы T-22…T-41 проставлены |

Порядок (общие сцены `main.tscn` и `test_level.tscn` — последовательно): DIA-10 (локализация
нужна всем новым экранам) → DIA-9 (`NetPair` нужен тестам сессии) → DIA-12 → DIA-13 → DIA-14
→ DIA-7 → DIA-11 → DIA-15.

В «Беклог» (предложение): `SteamLatency` — вместе с DIA-16 «Steam: приглашение друга»;
`HudConfig` (константы HUD в конфиг) — при следующей правке HUD; три слота (этап 3
сохранений) — отдельной фичей после DIA-7.

## Допущения архитектора (для H2)

- А1. «Продолжить» у пройденного слота стартует с последнего чекпоинта перед выходом.
- А2. К хосту, который на экране итога, подключиться нельзя: отказ «игра уже закончилась»
  (`REFUSED_FINISHED`).
- А3. Пока второй игрок на экране выбора, звук мира у него приглушён (шины SFX, Ambience).
- А4. Засчитывается только следующий по порядку чекпоинт; пропустить зону нельзя.
- А5. Сброс пересоздаёт `Content` только текущей секции; объекты пройденных секций (разбитый
  ящик) не возвращаются (согласуется с Д11).
- А6. Возврат в меню — перезагрузка `Main` (как сейчас при отключении), состояние сессии не
  переносится.

Новых `decision-NN.md` нет: пробелы закрыты допущениями выше, их принимает владелец на H2.

## Для владельца: расхождение с `DESIGN.md`

«Сложность и сохранения»: «Сохранение хранится у хоста… У хоста три слота». По решениям
2026-11-21 прогресс у каждого игрока (decision-02 B), слот пока один (Д8), есть выбор
стартового чекпоинта (decision-07). План следует решениям; `DESIGN.md` правит владелец.

## Риски и как узнаем рано

- `LagPeer` на GDScript ведёт себя иначе, чем ожидается (справочник без описаний) —
  `test_latency_peer` в NetPair, первая задача DIA-9; запасной путь — `ProxyLatency` уже есть.
- Движущаяся `Area3D` не ловит неподвижное тело — `test_moving_beam_trips_standing_player`
  первым тестом DIA-14.
- Пересоздание `Content` теряет RPC в полёте или ломает пути — `test_section_content`
  (пути те же, отчёт после сброса не срабатывает на новом луче в `ALARM`).
- `DirAccess.rename_absolute` на Windows неатомарен — восстановление из `.tmp`,
  `test_save_format::pick`.
- `_apply_host_ended` не успевает уйти до закрытия — пауза `SESSION_END_GRACE`; при потере
  игрок видит «связь потеряна» (прогресс тот же), NetPair-тест.
- `untyped_declaration` = ошибка ломает тесты или аддон — сначала прогон с «предупреждением»,
  `exclude_addons = true`.
- Перенос RPC прочности меняет `Diamond._apply_full_state` — прежние тесты алмаза и NetPair
  на подключение.

## Изменения техзадания

- Новые: `docs/tech/game-flow.md`, `saves.md`, `components.md`, `latency.md`.
- `docs/tech/obstacles.md`: статус разделов 1–5 приведён к журналу (приняты на H2
  2026-11-20); добавлен раздел 6 (предложено): перенос сброса в `LevelRoot`, пересоздание
  `Content`, полное состояние препятствия (№ 4), контракт `NONE` (№ 5), допуск отчёта (№ 8).
- `docs/tech/00-index.md`: четыре файла в таблицу, T-22…T-41 со статусом «предложено»;
  у расхождений — ссылки на T-39…T-41. Принятые записи не менялись.
