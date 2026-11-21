# Журнал технических решений

Ведёт архитектор. Правила кода — `ARCHITECTURE.md`; здесь — решения с датой, статусом и
местом, где они описаны или реализованы. Статус «принято» ставит владелец на H2 (или
решение уже было в коде и `ARCHITECTURE.md` до заведения журнала).

Статусы:
- **принято** — действует, есть в коде;
- **заявлено** — записано в `ARCHITECTURE.md`, в коде ещё нет (реализуется, когда появится
  первая система, которой оно нужно);
- **предложено** — в плане фичи, ждёт H2;
- **заменено T-NN** — больше не действует.

## Файлы техзадания

| Файл | Система |
|---|---|
| `docs/tech/obstacles.md` | препятствия, касание, сброс секции (минимум F-001; уточнения DIA-5 — раздел 6) |
| `docs/tech/game-flow.md` | состояния сессии, уровня и секции; чекпоинт; подключение и отключение (DIA-5) |
| `docs/tech/saves.md` | формат сохранения, прогресс у обоих, выбор стартового чекпоинта (DIA-5) |
| `docs/tech/components.md` | правило контрактов, каталог компонентов: прочность, движение по пути (DIA-5) |
| `docs/tech/latency.md` | имитация задержки сети и замер пинга (DIA-5) |

Сеть, алмаз, персонаж пока описаны только в `ARCHITECTURE.md` и коде.

## Решения

| № | Решение | Статус | Где | Откуда |
|---|---|---|---|---|
| T-01 | Три слоя: данные (`*Config` + `data/*.tres`), логика (`RefCounted`, без узлов/сети/`Input`/физики), узлы-адаптеры | принято | `ARCHITECTURE.md` «Три слоя»; `DiamondConfig`/`Durability`/`CarryRules`/`Diamond`, `CarryConfig`/`Stamina`/`PlayerCarry` | до журнала |
| T-02 | Композиция: способность — дочерний компонент (`Player` → `Carry`); наследование только от встроенных типов, один уровень | принято | `ARCHITECTURE.md` «Композиция»; `scenes/player/player.tscn` | до журнала |
| T-03 | Сеть только на высокоуровневом API Godot; транспорт выбирается в одном месте (`Network`, ENet сейчас, Steam к релизу); `Network` — единственная автозагрузка | принято | `ARCHITECTURE.md` «Сеть»; `scripts/net/network.gd`, `project.godot [autoload]` | до журнала |
| T-04 | Персонажем управляет владелец: имя узла = peer id, авторитет ставится в `_enter_tree`; положение и поворот — `MultiplayerSynchronizer`; спавн — `MultiplayerSpawner` в `Main` | принято | `scripts/player/player.gd`, `scenes/main.tscn` | до журнала |
| T-05 | Состояние алмаза (кто несёт, режим, прочность, физика свободного алмаза) ведёт хост: `request_*` (`any_peer`, `call_local`, `reliable`) → правило логики → событие надёжным RPC `authority`+`call_local` → сигнал на каждом пире; подключившийся получает `_apply_full_state` | принято | `scripts/diamond/diamond.gd` | до журнала |
| T-06 | Несомый алмаз каждая машина ставит в точку хвата сама; физика несомого заморожена на всех, коллизии выключены (слой 0) | принято | `Diamond._follow_carrier`, `_apply_physics_mode` | до журнала |
| T-07 | Синхронизатор — только для непрерывного (`Diamond.net_transform`, `Player.position`); дискретное — только событием | принято | `ARCHITECTURE.md` «Сеть», «События» | до журнала |
| T-08 | События — сигналы в прошедшем времени; подписчики (HUD, звук) не опрашивают состояние; связи настраивает `Main` через `bind_*` | принято | `scripts/main.gd`, `scripts/ui/hud.gd` | до журнала |
| T-09 | Слои физики: 1 `world`, 2 `players`, 3 `diamond`; новые — через H2 | принято | `project.godot [layer_names]` | до журнала |
| T-10 | Рендерер Compatibility (`gl_compatibility`) | принято | `project.godot [rendering]` | до журнала |
| T-11 | Тесты: GdUnit4 5.1.1, `SignalLog`/`TestWorld`, `tools\run_tests.cmd`, CI `tests.yml` | принято | `ARCHITECTURE.md` «Тесты», `tests/` | до журнала |
| T-12 | Сброс при разрушении алмаза: `Main._on_diamond_destroyed` на хосте → `Diamond.reset_to_start()` + `Player.respawn.rpc()` каждому персонажу, без паузы | заменено T-17 (H2 2026-11-20) | `scripts/main.gd` | до журнала |
| T-13 | Модели — в объектном хранилище, в git только `assets.lock.json` | принято | `tools/upload_assets.cmd`, `tools/fetch_assets.cmd` | до журнала |
| T-14 | Секция = `SectionRoot` (стабильный ID) → `Checkpoint` + `Content`; сброс пересоздаёт `Content` из сцены | заявлено; в F-001 — временно без `Content`, см. T-18 | `ARCHITECTURE.md` «Секции и препятствия» | до журнала |
| T-15 | Касание препятствия судит машина, которая видит без задержки; факт — `request_report_*`, последствие выбирает хост по конфигу; чужие персонажи игнорируются | заявлено → реализуется в F-001 (T-16) | `ARCHITECTURE.md` «Сеть» | до журнала |
| T-16 | Препятствие = сцена `scenes/props/` + `*Config` + логика; общий утиный контракт узла (группа `obstacles`, `tripped`, `set_armed`, `get_consequence`) с контрактным тестом; `Obstacle.judges_here()` — кто судит касание; RPC `LaserBeam.request_report_player_touch`, `LaserBeam._apply_tripped` | принято (H2 2026-11-20) | `docs/tech/obstacles.md`; `docs/work/F-001-first-obstacle/plan.md` | F-001 |
| T-17 | Единый сброс секции: все причины (поимка, касание алмазом, разрушение алмаза) идут в `SectionRoot.report_caught`; хост держит паузу `reset_delay`, одно срабатывание = один сброс; RPC `_apply_alarm_started`, `_apply_section_reset`, `_apply_full_state`. Заменяет T-12 | принято (H2 2026-11-20) | `docs/tech/obstacles.md` «Сброс секции» | F-001 |
| T-18 | Пока нет секций: вся тестовая сцена — одна секция `test_level`, нулевой чекпоинт = точки появления + постамент; `Content` не пересоздаётся, препятствия перевооружаются `set_armed(true)`. Пересоздание `Content` — с первым препятствием, у которого есть состояние (шаг 4) | заменено T-25 (H2 2026-11-21) | `docs/tech/obstacles.md` | F-001, decision-04 A |
| T-19 | `Player.respawn` перестаёт быть RPC: каждая машина переносит своего персонажа по событию `section_reset` | принято (H2 2026-11-20) | `docs/tech/obstacles.md` | F-001 |
| T-20 | На время тревоги управление своим персонажем блокируется (`SectionConfig.lock_controls_during_alarm`, по умолчанию да; ощущение — H3) | принято (H2 2026-11-20) | `docs/tech/obstacles.md` | F-001 |
| T-21 | Раскладка шин `default_bus_layout.tres`: Master, Music, SFX, UI, Ambience (по `docs/audio/SOUND.md`); сейчас есть только Master | принято (H2 2026-11-20) | `docs/audio/SOUND.md` «Шины» | F-001 |
| T-22 | Сессия: логика `SessionFlow` + узел `Main/Session`, без автозагрузки; выход в меню из любого состояния = закрыть сеть и перезагрузить `Main`; экран выбора у хоста — оверлей, подсостояние напарника | принято (H2 2026-11-21) | `game-flow.md` §1–2 | DIA-5 |
| T-23 | Уровень: `LevelRoot` + логика `LevelFlow` (текущий чекпоинт, тревога, финал); вход сброса и RPC тревоги переезжают из `SectionRoot` в `LevelRoot` — правило T-17 то же, место новое | принято (H2 2026-11-21) | `game-flow.md` §3; `obstacles.md` §6 | DIA-5 |
| T-24 | Чекпоинт: зона ловит тело носильщика, судит машина носильщика (`request_report_checkpoint`), хост проверяет носильщика, порядок, тревогу, допуск; событие `_apply_checkpoint_reached`, финал — флаг чекпоинта | принято (H2 2026-11-21) | `game-flow.md` §3 | DIA-5 |
| T-25 | Сброс пересоздаёт `Content` текущей секции; старт с чекпоинта (`_apply_level_started`) — все секции. Заменяет временный T-18, реализует T-14 | принято (H2 2026-11-21) | `game-flow.md` §3; `obstacles.md` §6 | DIA-5 |
| T-26 | Часы секции `SectionClock`: идут в `ACTIVE`, стоят в тревоге, с нуля при пересоздании `Content`; подключившийся получает их в полном состоянии | принято (H2 2026-11-21) | `components.md` §4 | DIA-5 |
| T-27 | Вход в игру: авторизация `SceneMultiplayer` в `Network` (версия протокола, «заполнено», «закончилась»); `Session.request_join(farthest)`; персонаж второго игрока спавнится после выбора чекпоинта | принято (H2 2026-11-21) | `game-flow.md` §4–5 | DIA-5 |
| T-28 | Конец сессии без смены хоста (decision-05 A): `Network.end_session` → `_apply_host_ended` → закрытие; причина — `Network.last_end_reason`, переживает перезагрузку `Main` | принято (H2 2026-11-21) | `game-flow.md` §5 | DIA-5 |
| T-29 | Сохранение, этап 1: `user://progress.json`, JSON `{format: 1, farthest_checkpoint, finished}`; запись через `.tmp` + переименование, восстановление из `.tmp`; логика `ProgressRecord`/`SaveFormat`/`ProgressRules`/`CheckpointRoute`, узел `ProgressStore`; `--profile` для двух окон | принято (H2 2026-11-21) (меняет формат сохранения → H2) | `saves.md` §1–4 | DIA-5 |
| T-30 | Прогресс у обоих: каждая машина пишет свой файл по событию хоста; знак «чекпоинт достигнут» — после записи; выбор старта — хост (7.1 A), до дальнего из двух (7.2 B), засчёт сразу (7.3 A) | принято (H2 2026-11-21) | `saves.md` §4–5 | DIA-5 |
| T-31 | Интерфейс = таблица контракта + контрактный тест по всем реализациям; без общего предка узлов и стратегий; `has_method` в штатном коде не используется | принято (H2 2026-11-21) (обобщает T-16) | `components.md` §1–2 | DIA-5 |
| T-32 | Прочность — компонент `DurabilityComponent` + `DurabilityConfig`, стадии `INTACT/DAMAGED/CRITICAL/BROKEN` по порогам; RPC прочности переезжают из `Diamond`, сигналы алмаза остаются; учебный ящик в тестовой секции | принято (H2 2026-11-21) | `components.md` §3 | DIA-5 |
| T-33 | Движение — компонент `PathMover` + логика `PathMotion` от часов секции, без синхронизатора; общего предка `Movable` нет | принято (H2 2026-11-21) | `components.md` §4 | DIA-5 |
| T-34 | Полное состояние догоняет и вид: `full_state_applied`, длящиеся реакции читают состояние; `LaserBeam._apply_full_state` (ревью F-001 № 4) | принято (H2 2026-11-21) | `game-flow.md` §6; `obstacles.md` §6 | DIA-5 |
| T-35 | `Consequence.NONE`: препятствие перевзводит себя само через `rearm_delay` (`_apply_rearmed`); до первого применения `NONE` запрещён контент-тестом (ревью F-001 № 5) | принято (H2 2026-11-21) | `obstacles.md` §6 | DIA-5 |
| T-36 | Допуск правдоподобия отчётов о касании и чекпоинте: позиция отправителя не дальше `report_tolerance` (ревью F-001 № 8) | принято (H2 2026-11-21) | `obstacles.md` §6 | DIA-5 |
| T-37 | Подбираемые числа обратной связи — в конфигах: `CaughtFeedbackConfig` (ревью F-001 № 7) | принято (H2 2026-11-21) | `components.md` §5 | DIA-5 |
| T-38 | `LatencySimulator`: стратегии `NoLatency`/`ProxyLatency`/`PeerLatency` (`LagPeer extends MultiplayerPeerExtension`)/`SteamLatency`, выбор в `Network` аргументами, только отладочная сборка; пинг — RPC `Network._ping/_pong`; оверлей; автотест (ревью F-001 № 9) | принято (H2 2026-11-21) | `latency.md` | DIA-5 |
| T-39 | Локализация: ключи и `tr()`, `locale/ru.po`, `project.godot`: `internationalization/locale/translations` и `fallback = "ru"`; контент-тест ключей | принято (H2 2026-11-21) (меняет `project.godot` → H2) | `plan.md` DIA-5, «DIA-10» | DIA-5, расхождение журнала |
| T-40 | `debug/gdscript/warnings/untyped_declaration = 2` (ошибка), `exclude_addons` остаётся `true`; сначала типизация кода и тестов | принято (H2 2026-11-21) (меняет `project.godot` → H2) | `plan.md` DIA-5, «DIA-10» | DIA-5, расхождение журнала |
| T-41 | Убрать `ssao_enabled` из `test_level.tscn` (в Compatibility не работает) | принято (H2 2026-11-21) | `plan.md` DIA-5, «DIA-10» | DIA-5, расхождение журнала |

## Расхождения, найденные при заведении журнала

Не блокируют F-001, задачи владельцу на будущее. Решения предложены в DIA-5: первое — T-40,
второе — T-39, третье — T-41.

- `ARCHITECTURE.md` («GDScript») говорит, что `untyped_declaration` поднято до ошибки, а в
  `project.godot` этой настройки нет.
- `ARCHITECTURE.md` («Тексты») требует ключи и `tr()`, а `hud.gd`, `player.gd`, `main.gd`,
  `main.tscn` содержат строки на русском; папки `locale/` нет.
- В `test_level.tscn` включён `ssao_enabled` — в Compatibility SSAO не работает (вреда
  нет, но настройка вводит в заблуждение).
