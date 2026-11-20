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
| `docs/tech/obstacles.md` | препятствия, касание, сброс секции (минимум F-001) |

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
| T-12 | Сброс при разрушении алмаза: `Main._on_diamond_destroyed` на хосте → `Diamond.reset_to_start()` + `Player.respawn.rpc()` каждому персонажу, без паузы | заменено T-17 (после H2 F-001) | `scripts/main.gd` | до журнала |
| T-13 | Модели — в объектном хранилище, в git только `assets.lock.json` | принято | `tools/upload_assets.cmd`, `tools/fetch_assets.cmd` | до журнала |
| T-14 | Секция = `SectionRoot` (стабильный ID) → `Checkpoint` + `Content`; сброс пересоздаёт `Content` из сцены | заявлено; в F-001 — временно без `Content`, см. T-18 | `ARCHITECTURE.md` «Секции и препятствия» | до журнала |
| T-15 | Касание препятствия судит машина, которая видит без задержки; факт — `request_report_*`, последствие выбирает хост по конфигу; чужие персонажи игнорируются | заявлено → реализуется в F-001 (T-16) | `ARCHITECTURE.md` «Сеть» | до журнала |
| T-16 | Препятствие = сцена `scenes/props/` + `*Config` + логика; общий утиный контракт узла (группа `obstacles`, `tripped`, `set_armed`, `get_consequence`) с контрактным тестом; `Obstacle.judges_here()` — кто судит касание; RPC `LaserBeam.request_report_player_touch`, `LaserBeam._apply_tripped` | предложено | `docs/tech/obstacles.md`; `docs/work/F-001-first-obstacle/plan.md` | F-001 |
| T-17 | Единый сброс секции: все причины (поимка, касание алмазом, разрушение алмаза) идут в `SectionRoot.report_caught`; хост держит паузу `reset_delay`, одно срабатывание = один сброс; RPC `_apply_alarm_started`, `_apply_section_reset`, `_apply_full_state`. Заменяет T-12 | предложено | `docs/tech/obstacles.md` «Сброс секции» | F-001 |
| T-18 | Пока нет секций: вся тестовая сцена — одна секция `test_level`, нулевой чекпоинт = точки появления + постамент; `Content` не пересоздаётся, препятствия перевооружаются `set_armed(true)`. Пересоздание `Content` — с первым препятствием, у которого есть состояние (шаг 4) | предложено (временное отступление от T-14) | `docs/tech/obstacles.md` | F-001, decision-04 A |
| T-19 | `Player.respawn` перестаёт быть RPC: каждая машина переносит своего персонажа по событию `section_reset` | предложено | `docs/tech/obstacles.md` | F-001 |
| T-20 | На время тревоги управление своим персонажем блокируется (`SectionConfig.lock_controls_during_alarm`, по умолчанию да; ощущение — H3) | предложено | `docs/tech/obstacles.md` | F-001 |
| T-21 | Раскладка шин `default_bus_layout.tres`: Master, Music, SFX, UI, Ambience (по `docs/audio/SOUND.md`); сейчас есть только Master | предложено | `docs/audio/SOUND.md` «Шины» | F-001 |

## Расхождения, найденные при заведении журнала

Не блокируют F-001, задачи владельцу на будущее:

- `ARCHITECTURE.md` («GDScript») говорит, что `untyped_declaration` поднято до ошибки, а в
  `project.godot` этой настройки нет.
- `ARCHITECTURE.md` («Тексты») требует ключи и `tr()`, а `hud.gd`, `player.gd`, `main.gd`,
  `main.tscn` содержат строки на русском; папки `locale/` нет.
- В `test_level.tscn` включён `ssao_enabled` — в Compatibility SSAO не работает (вреда
  нет, но настройка вводит в заблуждение).
