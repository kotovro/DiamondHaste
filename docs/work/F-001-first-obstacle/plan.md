# F-001 — Первое препятствие: лазерный луч в тестовой сцене: технический план

Статус: утверждён 2026-11-20 (H2). Было на утверждении: новые RPC, `Player.respawn` перестаёт быть RPC, меняется
поведение сброса (пауза и единый путь для разрушения алмаза), раскладка шин, временное
отступление от T-14 (без пересоздания `Content`). `project.godot` не меняется.
Автор: architect
Карточка: `card.md` (утверждена 2026-11-20; decision-01 A, 02 A, 03 C с умолчанием B, 04 A)
Техзадание: `docs/tech/obstacles.md` — разделы 1–5; журнал `docs/tech/00-index.md` — T-16…T-21

## Решение в двух абзацах

Лазер — самостоятельная сцена `scenes/props/laser_beam.tscn` (`LaserBeam`) с конфигом
`LaserConfig` и логикой `LaserTouch`. Касание судит машина, которая видит его без
задержки (`ARCHITECTURE.md`, «Сеть»; T-15): своё тело — владелец персонажа, он шлёт хосту
`request_report_player_touch`; свободный алмаз — хост, без RPC. Хост рассылает событие
`_apply_tripped`, и луч мигает и звучит у обоих. Что делать дальше, решает хост по полю
конфига `consequence` (`SECTION_RESET` = поимка, decision-02 A). Реакция на алмаз —
`LaserConfig.reacts_to_diamond`, по умолчанию `true` (decision-03 C/B). Фильтр — в логике,
а не в маске слоёв, поэтому оба значения проверяются одним тестом. Новых слоёв физики нет:
зона касания видит слои `players` (2) и `diamond` (3).

Все причины сброса — поимка лазером, касание лазера алмазом и разрушение алмаза — сходятся
в один узел `SectionRoot` с логикой `SectionReset` (`ACTIVE` → `ALARM` → `ACTIVE`). Так
выполняются К11 (один путь), К12 (повторные причины во время `ALARM` отбрасываются) и К15
(таймер паузы — на хосте, сброс трогает только своих персонажей). Сброс от разрушения
сейчас делает `Main` (T-12). Он уходит в `SectionRoot` и получает ту же паузу.
Тестовая сцена — одна секция `test_level` с нулевым чекпоинтом: точки появления и
постамент (decision-04 A, T-18). Пересоздания `Content` пока нет: у лазера из состояния
есть только взвод, его секция возвращает через `set_armed(true)`. Пересоздание
`Content` (T-14) появится с первым препятствием, у которого есть состояние, в шаге 4.
`Player.respawn` перестаёт быть RPC: каждая машина переносит своего персонажа по событию
`section_reset` (T-19).

## Слои

| Слой | Класс / файл | Ответственность |
|---|---|---|
| Данные | `LaserConfig` (`scripts/obstacles/laser_config.gd`) → `data/laser_config.tres` | размеры луча, реакция на алмаз, последствие, вид |
| Данные | `SectionConfig` (`scripts/level/section_config.gd`) → `data/section_config.tres` | пауза до сброса, блок управления, затемнение |
| Логика | `class_name Obstacle extends RefCounted` (`scripts/obstacles/obstacle.gd`) | общие перечисления препятствий; кто судит касание |
| Логика | `class_name LaserTouch extends RefCounted` (`scripts/obstacles/laser_touch.gd`) | взвод, «засчитывается ли касание», срабатывание |
| Логика | `class_name SectionReset extends RefCounted` (`scripts/level/section_reset.gd`) | состояние тревоги, одно срабатывание — один сброс, причина по касанию и последствию |
| Узлы | `LaserBeam` (`scripts/obstacles/laser_beam.gd`, `scenes/props/laser_beam.tscn`) | `Area3D` → логика → RPC; вид луча, мигание, искра |
| Узлы | `SectionRoot` (`scripts/level/section_root.gd`), узел `Section` в `test_level.tscn` | сбор причин, таймер паузы, события тревоги и сброса, вызовы вниз препятствиям и своим персонажам |
| Узлы | `CaughtFeedback` (`scripts/player/caught_feedback.gd`), узел в `player.tscn` | «нелепая поза» и мигание задевшего персонажа |
| Узлы | `Player`, `PlayerCarry`, `Hud`, `Main` — правки | блок управления, `respawn()` без RPC, затемнение, сборка связей |

## Контракты

### Поля конфигов (тип, единицы, заглушка)

`class_name LaserConfig extends Resource`:
- `@export var beam_height: float = 0.4` — м, ось луча над началом узла (пол) — подобрать на плейтесте (К5/К6)
- `@export var beam_thickness: float = 0.05` — м, диаметр видимого луча = сторона сечения зоны касания
- `@export var reacts_to_diamond: bool = true` — decision-03 C, по умолчанию B
- `@export var consequence: Obstacle.Consequence = Obstacle.Consequence.SECTION_RESET` — decision-02 A
- `@export var beam_color: Color = Color(1.0, 0.12, 0.1)` — спокойный луч
- `@export var alarm_color: Color = Color(1.0, 0.85, 0.2)` — второй цвет мигания в тревоге
- `@export var alarm_blink_hz: float = 6.0` — Гц, мигание луча и света
- `@export var light_energy_calm: float = 0.4` — подсветка вокруг луча (К16, полутёмный тоннель)
- `@export var light_energy_alarm: float = 3.0`
- `@export var light_range: float = 4.0` — м

Экспорт узла (не баланс, а расстановка): `LaserBeam.length: float = 2.2` — м, от
излучателя до излучателя, вдоль локальной X; ставит левел-дизайнер по ширине прохода.

`class_name SectionConfig extends Resource`:
- `@export var reset_delay: float = 1.5` — с, пауза от тревоги до сброса (общая для всех причин)
- `@export var lock_controls_during_alarm: bool = true` — блок движения, прыжка и действий с алмазом на паузе (ощущение — H3)
- `@export var reset_fade_seconds: float = 0.4` — с, затемнение в конце паузы и проявление после сброса

### Методы логики

`class_name Obstacle extends RefCounted` (только перечисления и статика):
- `enum Target { PLAYER, DIAMOND }`
- `enum Consequence { NONE, SECTION_RESET }`
- `static func judges_here(target: Target, is_own_body: bool, is_host: bool) -> bool` —
  `PLAYER` → `is_own_body`; `DIAMOND` → `is_host`

`class_name LaserTouch extends RefCounted`:
- `var reacts_to_diamond: bool`
- `var armed: bool = true`
- `var tripped: bool = false`
- `func _init(p_reacts_to_diamond: bool = true) -> void`
- `static func from_config(config: LaserConfig) -> LaserTouch`
- `func counts(target: Obstacle.Target) -> bool` — `armed and (target == PLAYER or reacts_to_diamond)`
- `func trip() -> void` — `armed = false`, `tripped = true` (повторно — без изменений)
- `func disarm() -> void` — `armed = false`, `tripped` не меняет
- `func arm() -> bool` — `armed = true`, `tripped = false`; возвращает, был ли `tripped`

`class_name SectionReset extends RefCounted`:
- `enum State { ACTIVE, ALARM }`
- `enum Cause { PLAYER_CAUGHT, DIAMOND_TOUCHED, DIAMOND_DESTROYED }`
- `var state: State = State.ACTIVE`, `var cause: Cause = Cause.PLAYER_CAUGHT`, `var actor_id: int = 0`
- `func is_alarm() -> bool`
- `func begin(p_cause: Cause, p_actor_id: int) -> bool` — из `ACTIVE`: `ALARM`, запомнить причину, `true`; из `ALARM`: `false`, ничего не менять
- `func finish() -> bool` — из `ALARM`: `ACTIVE`, `true`; иначе `false`
- `static func cause_for_touch(target: Obstacle.Target) -> Cause` — `PLAYER` → `PLAYER_CAUGHT`, `DIAMOND` → `DIAMOND_TOUCHED`
- `static func consequence_resets(consequence: Obstacle.Consequence) -> bool` — `true` только для `SECTION_RESET`

### Узлы

`class_name LaserBeam extends Node3D` (корень `laser_beam.tscn`, группа `obstacles`):
- `@export var config: LaserConfig` (по умолчанию `data/laser_config.tres`; `null` → `LaserConfig.new()`)
- `@export var length: float = 2.2`
- `var touch: LaserTouch`
- Дети (уникальные имена): `%Beam` (`MeshInstance3D`, `CylinderMesh`, материал `UNSHADED`),
  `%EmitterA`, `%EmitterB` (`MeshInstance3D`), `%TouchArea` (`Area3D`: `collision_layer = 0`,
  `collision_mask = 6`, `monitorable = false`) с `%TouchShape` (`CollisionShape3D`, `BoxShape3D`),
  `%AlarmLight` (`OmniLight3D`, без теней), `%Spark` (`MeshInstance3D`, сфера `UNSHADED`, скрыта)
- `func _ready() -> void` — группа, конфиг, `touch = LaserTouch.from_config(config)`, построить
  меш и зону из `length`, `beam_height`, `beam_thickness`; `%TouchArea.body_entered` → `_on_body_entered`
- `func set_armed(armed: bool) -> void` — все пиры; `true`: `touch.arm()`, если был `tripped` —
  погасить тревогу и `calmed.emit()`; `false`: `touch.disarm()`
- `func is_armed() -> bool`, `func is_tripped() -> bool`
- `func get_consequence() -> int` — `config.consequence`
- `func get_beam_segment() -> PackedVector3Array` — `[начало, конец]` оси луча в глобальных координатах (для проверок уровня, К13)
- `func _on_body_entered(body: Node3D) -> void` — `Player`: если `Obstacle.judges_here(PLAYER, body.is_multiplayer_authority(), is_host)` и `touch.counts(PLAYER)` → `request_report_player_touch.rpc_id(1, точка_на_оси)`; `Diamond`: если `judges_here(DIAMOND, false, is_host)` → `_host_trip(DIAMOND, 0, body.global_position)`; прочее — игнор
- `func _host_trip(target: Obstacle.Target, actor_id: int, point: Vector3) -> void` — хост: `if touch.counts(target): _apply_tripped.rpc(target, actor_id, point)`
- Мигание — `Tween` с `set_loops()`, гасится в `set_armed(true)`; без `_process`

`class_name SectionRoot extends Node3D` (группа `sections`):
- `@export var section_id: String = ""` — стабильный ID; в `test_level` — `"test_level"`
- `@export var config: SectionConfig` (`null` → `SectionConfig.new()`)
- `var rules: SectionReset` — на всех пирах; на клиентах повторяет хост по событиям
- `func _ready() -> void` — группа; `rules = SectionReset.new()`; `Timer` `ResetTimer` (`one_shot`) создаётся в коде; `bind_obstacle()` для каждого потомка в группе `obstacles` (`find_children("*", "", true, false)`); `multiplayer.peer_connected` → `_on_peer_connected`
- `func bind_diamond(diamond: Diamond) -> void` — `destroyed` → `_on_diamond_destroyed`; хранит ссылку для сброса
- `func bind_obstacle(obstacle: Node) -> void` — `tripped` → `_on_obstacle_tripped.bind(obstacle)`
- `func is_alarm() -> bool`
- `func report_caught(cause: SectionReset.Cause, actor_id: int) -> void` — **единственный вход для всех причин**, только хост: `if rules.is_alarm(): return`; `_apply_alarm_started.rpc(cause, actor_id)`; `ResetTimer.start(config.reset_delay)`
- `func _on_obstacle_tripped(target: int, actor_id: int, _point: Vector3, obstacle: Node) -> void` — хост: `if SectionReset.consequence_resets(obstacle.get_consequence()): report_caught(SectionReset.cause_for_touch(target), actor_id)`
- `func _on_diamond_destroyed() -> void` — хост: `report_caught(DIAMOND_DESTROYED, 0)`
- `func _on_reset_timer_timeout() -> void` — хост: `diamond.reset_to_start()` (если привязан и валиден), затем `_apply_section_reset.rpc()`
- `func _local_players() -> Array[Player]` — группа `players`, `is_multiplayer_authority()`, `is_instance_valid`, не `is_queued_for_deletion()`

`Player` (правки):
- `func respawn() -> void` — **без `@rpc`**; только для `is_multiplayer_authority()`: `velocity = Vector3.ZERO`, `_move_to_spawn()`
- `func set_controls_locked(locked: bool) -> void`, `func is_controls_locked() -> bool`
- `_physics_process`: при блоке ввод движения = ноль, прыжка нет; гравитация и `move_and_slide` работают; мышь (камера) — работает
- `@onready var caught_feedback: CaughtFeedback = $CaughtFeedback`

`PlayerCarry` (правка): `_unhandled_input` ничего не делает, если `player.is_controls_locked()`.
Выносливость тикает как прежде.

`class_name CaughtFeedback extends Node` (дочерний узел `Player`):
- `func bind_section(section: SectionRoot) -> void`
- `alarm_started(cause, actor_id)`: если `cause == PLAYER_CAUGHT` и `actor_id == player.get_multiplayer_authority()` — наклон `Body` и мигание цветом (константы-заглушки: стиль не выбран, вопрос 7); `section_reset` — вернуть как было
- `func is_showing() -> bool` — для теста

`Hud` (правка): `func bind_section(section: SectionRoot) -> void`. На `alarm_started` через
`reset_delay - reset_fade_seconds` начинается затемнение `%ResetFade` (`ColorRect`, чёрный,
`mouse_filter = IGNORE`). На `section_reset` экран проявляется за `reset_fade_seconds`.
Текста не добавляется: тексты для игрока вне рамок карточки.

`Main` (правка): удалить `_on_diamond_destroyed` и подписку на `destroyed`. Найти
`section := get_tree().get_first_node_in_group("sections") as SectionRoot`, затем
`section.bind_diamond(diamond)` и `hud.bind_section(section)`. В `_on_player_ready` —
`player.caught_feedback.bind_section(section)`.

`Diamond` — без изменений (`reset_to_start()` уже возвращает на постамент целым и рассылает
`RESTORED` и прочность).

### Сигналы (прошедшее время; все — на каждом пире, порождены событием хоста)

- `LaserBeam.tripped(target: int, actor_id: int, point: Vector3)` — луч сработал; `actor_id` — peer id или `0` для алмаза; `point` — где показать искру
- `LaserBeam.calmed()` — луч, сработавший раньше, снова спокоен (после сброса)
- `SectionRoot.alarm_started(cause: int, actor_id: int)` — началась тревога (пауза до сброса)
- `SectionRoot.section_reset(section_id: String)` — сброс выполнен: свои персонажи на точках появления, препятствия взведены

### RPC

| Метод | Аннотация | Кто вызывает | На ком выполняется | Надёжность | Что проверяет хост |
|---|---|---|---|---|---|
| `LaserBeam.request_report_player_touch(point: Vector3)` | `@rpc("any_peer", "call_local", "reliable")` | владелец задевшего персонажа, `rpc_id(1)` (хост — себе через `call_local`) | хост | надёжно | `is_host`; отправитель (`get_remote_sender_id()`, `0` → свой id) — владелец существующего персонажа; `touch.counts(PLAYER)`; `point` прижимается к отрезку луча. Расстояние до луча **не** проверяется (К14) |
| `LaserBeam._apply_tripped(target: int, actor_id: int, point: Vector3)` | `@rpc("authority", "call_local", "reliable")` | хост, `.rpc()` | все | надёжно | — (`touch.trip()`, мигание, искра, `tripped`) |
| `SectionRoot._apply_alarm_started(cause: int, actor_id: int)` | `@rpc("authority", "call_local", "reliable")` | хост, `.rpc()` | все | надёжно | — (`rules.begin`; все препятствия `set_armed(false)`; свои персонажи `set_controls_locked(config.lock_controls_during_alarm)`; `alarm_started`) |
| `SectionRoot._apply_section_reset()` | `@rpc("authority", "call_local", "reliable")` | хост, `.rpc()` | все | надёжно | — (`rules.finish()`; свои персонажи `respawn()` и `set_controls_locked(false)`; препятствия `set_armed(true)`; `section_reset`) |
| `SectionRoot._apply_full_state(alarm: bool, cause: int, actor_id: int)` | `@rpc("authority", "call_remote", "reliable")` | хост, `rpc_id(новый_пир)` из `peer_connected` | подключившийся | надёжно | — (если `alarm`: `rules.begin`, препятствия `set_armed(false)`) |
| ~~`Player.respawn()`~~ | **удаляется** аннотация `@rpc` | — | — | — | становится обычным методом (T-19) |

Отдельного RPC на «сыграть звук» или «показать позу» нет: всё — подписчики сигналов.
Порядок «события алмаза (`RESTORED`, прочность) раньше `section_reset`» держится на одном
канале надёжных RPC (`SceneMultiplayer`, канал 0 по умолчанию).

### Кто чем управляет по сети

| Состояние | Владелец | Как доходит до остальных |
|---|---|---|
| Положение и поворот персонажа | владелец персонажа | синхронизатор (как сейчас) |
| Касание лучом своего тела (с алмазом или без) | владелец персонажа судит | `request_report_player_touch` → хост |
| Касание лучом чужого персонажа | никто на этой машине | игнорируется |
| Касание лучом свободного алмаза | хост судит | вызов логики на хосте без RPC |
| Несомый алмаз и луч | — | коллизий нет (T-06); засчитывается тело носильщика |
| Взвод и срабатывание луча | хост | событие `_apply_tripped`; взвод — внутри событий секции |
| Последствие срабатывания | хост, по `LaserConfig.consequence` | событие `_apply_alarm_started` |
| Состояние секции (`ACTIVE`/`ALARM`), причина, виновник | хост | события `_apply_alarm_started`, `_apply_section_reset`; подключившемуся — `_apply_full_state` |
| Таймер паузы | только хост | — |
| Алмаз при сбросе (позиция, прочность, несущий) | хост | существующие события алмаза `RESTORED` и прочности |
| Перенос персонажа на точку появления | каждая машина — своего, по `section_reset` | синхронизатор |
| Блок управления на паузе | каждая машина — своего, по `alarm_started` | — (локально) |
| Мигание, искра, поза, затемнение, звук | каждая машина сама по сигналам | — |

## Звук (для звукового дизайнера)

| Сигнал | Звук | Шина | 2D/3D | Кто слышит | Параметры в конфиге |
|---|---|---|---|---|---|
| луч взведён и не сработал (с `_ready`; останов — `LaserBeam.tripped`, возобновление — `LaserBeam.calmed`) | тихое гудение, петля | SFX | 3D, у луча | каждый у себя по расстоянию (К17) | `LaserAudioConfig.hum_volume_db = -12.0`, `hum_max_distance = 6.0` м, `hum_unit_size = 2.0` |
| `LaserBeam.tripped` | резкий треск касания в `point` | SFX | 3D | оба | `zap_volume_db = 0.0`, `zap_max_distance = 40.0` м |
| `SectionRoot.alarm_started` | сирена, петля | SFX | 2D (без позиции) | оба, в любой точке (К17) | `SectionAudioConfig.siren_volume_db = -4.0` |
| `SectionRoot.section_reset` | сирена обрывается; звук сброса («перемотка») | SFX | 2D | оба | `reset_volume_db = 0.0` |

- Компоненты: `LaserAudio` — дочерний узел `laser_beam.tscn`, в `_ready` подписывается на
  родителя, как `PlayerCarry`. `SectionAudio` — дочерний узел `Section` в `test_level.tscn`
  (вне будущего `Content`: сирена должна пережить сброс, `SOUND.md`). Конфиги
  `LaserAudioConfig`, `SectionAudioConfig` + `.tres`, файлы — `audio/sfx/laser/`,
  `audio/sfx/section/`, строки в `assets/LICENSES.md`.
- **Шины.** Сейчас есть только Master (`default_bus_layout.tres` нет). Раскладка Master,
  Music, SFX, UI, Ambience по `SOUND.md` — после H2 (T-21). `project.godot` для этого не
  меняется: Godot берёт `res://default_bus_layout.tres` по умолчанию. Если владелец
  отклонит T-21, всё идёт в Master.
- Звук разрушения алмаза — не в этой фиче (в карточке его нет; есть в общем списке `SOUND.md`).

## Файлы

Создать (программист):
- `scripts/obstacles/obstacle.gd`, `scripts/obstacles/laser_config.gd`, `scripts/obstacles/laser_touch.gd`, `scripts/obstacles/laser_beam.gd`
- `scenes/props/laser_beam.tscn`, `data/laser_config.tres`
- `scripts/level/section_config.gd`, `scripts/level/section_reset.gd`, `scripts/level/section_root.gd`, `data/section_config.tres`
- `scripts/player/caught_feedback.gd`
- `.uid` ко всем новым скриптам (после `tools\run_tests.cmd`)

Изменить (программист):
- `scripts/main.gd` — убрать `_on_diamond_destroyed`, связать секцию (см. «Узлы»)
- `scripts/player/player.gd` — `respawn()` без RPC, блок управления, ссылка на `CaughtFeedback`
- `scripts/player/player_carry.gd` — игнор ввода при блоке
- `scripts/ui/hud.gd`, `scenes/main.tscn` — `bind_section`, `%ResetFade`
- `scenes/player/player.tscn` — узел `CaughtFeedback`
- `CHANGELOG.md` — строка в `[Unreleased]`

Изменить (левел-дизайнер, после появления `laser_beam.tscn`):
- `scenes/level/test_level.tscn`:
  - узел `Section` (`Node3D`, скрипт `SectionRoot`, `section_id = "test_level"`, `config = data/section_config.tres`);
  - `Section/Obstacles/LaserBeam` в проходе тоннеля: начало на полу в `(-10, 0, -6)`, `length = 2.2`, ось X поперёк прохода;
  - перегородить зал, чтобы с юга (постамент z = 6, точки появления z = 12) на север вёл только тоннель (К2). За лучом свободно не меньше 4 м;
  - `Diamond` и `SpawnPoints` не переносить: тесты обращаются к `Diamond` по пути, а К13 проверяет, что они вне луча.

Создать (звуковой дизайнер, шаг 4з): `LaserAudio`, `SectionAudio`, их конфиги и `.tres`,
звуки, `default_bus_layout.tres` (после H2).

Не трогать: `project.godot`, `scripts/diamond/*`, `scripts/net/network.gd`,
существующие `data/*.tres`, `DESIGN.md`, `ARCHITECTURE.md`.

## Тесты (для тест-инженера)

Юнит:
- `tests/unit/test_obstacle.gd`: `judges_here` — своё тело судится и на хосте, и на клиенте; чужое — нигде; алмаз — только на хосте
- `tests/unit/test_laser_touch.gd`: игрок засчитывается во взведённом состоянии; алмаз засчитывается при `reacts_to_diamond = true` и не засчитывается при `false`; после `trip()` ничего не засчитывается; `disarm()` — ничего не засчитывается, `tripped` не меняется; `arm()` после `trip()` возвращает `true` и снова засчитывает; `arm()` без срабатывания возвращает `false`; `from_config` берёт `reacts_to_diamond`
- `tests/unit/test_section_reset.gd`: старт `ACTIVE`; `begin` → `ALARM`, причина и виновник запомнены; второй `begin` в `ALARM` → `false`, причина прежняя; `finish` → `ACTIVE`; `finish` в `ACTIVE` → `false`; после `finish` `begin` снова работает; `cause_for_touch` для обеих целей; `consequence_resets` для `NONE` и `SECTION_RESET`

Интеграционные (локальный пир = хост, персонаж «2» — чужой):
- `tests/integration/test_laser_config.gd` (содержимое `data/laser_config.tres`): `reacts_to_diamond == true` (умолчание decision-03); `consequence == SECTION_RESET`; верх луча ниже высоты прыжка `jump_velocity² / 2g` из `movement_config.tres` с запасом ≥ 0,3 м (опора К5); низ луча ниже роста персонажа 1,8 м, под лучом не пройти (опора К6)
- `tests/integration/test_obstacle_contract.gd`: каждая сцена `scenes/props/*.tscn`, корень которой после `_ready` в группе `obstacles`, имеет сигнал `tripped` с 3 аргументами, методы `set_armed`, `is_armed`, `get_consequence`, не-`null` `config`
- `tests/integration/test_laser_beam.gd` — сцена луча на полу `TestWorld`, без уровня:
  - `test_works_standalone` — инстанцируется без уровня, персонаж «1» в луче → `tripped` (К1)
  - `test_touch_zone_matches_visible_beam` — размеры `BoxShape3D` = длина и диаметр меша (Д9)
  - `test_player_without_diamond_trips` — `tripped` один раз с `[PLAYER, 1, точка]` (К3)
  - `test_carrier_trips` — персонаж «1» с поднятым алмазом входит в луч → `tripped(PLAYER, 1, …)` (К4)
  - `test_thrown_diamond_trips_when_reacting` / `test_thrown_diamond_ignored_when_not_reacting` — бросок через луч низко; конфиг-копия с `reacts_to_diamond = true/false` (К7)
  - `test_resting_diamond_trips_when_reacting` / `..._ignored_when_not_reacting` — алмаз кладётся в луч (К7)
  - `test_foreign_player_ignored` — персонаж «2» в луче → нет `tripped`
  - `test_trips_once_until_rearmed` — повторный вход и вход второго тела → `tripped` один раз; после `set_armed(true)` → `calmed` и снова срабатывает (К12)
  - `test_disarmed_ignores_touches`
- `tests/integration/test_section_reset_flow.gd` — пол, 2 `Marker3D` в `spawn_points`, `SectionRoot` с конфигом-копией `reset_delay = 0.1`, луч внутри секции, алмаз, персонажи «1» и «2», `bind_diamond`. Общий помощник `_assert_section_restored()`: персонаж «1» на своей точке появления, алмаз на старте, прочность полная, `carrier_id == 0`, луч взведён, управление разблокировано, `section_reset` один раз
  - `test_player_caught_resets_section` — `alarm_started(PLAYER_CAUGHT, 1)`, на паузе управление заблокировано, через паузу `_assert_section_restored()` (К10)
  - `test_caught_carrier_resets_diamond_to_pedestal` — персонаж «1» несёт алмаз и входит в луч (К10)
  - `test_diamond_touch_resets_section` — свободный алмаз в луче → `alarm_started(DIAMOND_TOUCHED, 0)` и тот же сброс (К7, К10)
  - `test_diamond_destroyed_gives_same_reset` — разрушение (падение ниже `kill_height`) → `alarm_started(DIAMOND_DESTROYED, 0)`, тот же `_assert_section_restored()` (К11)
  - `test_one_alarm_one_reset` — во время паузы повторное касание, касание алмазом и разрушение → `alarm_started` 1, `section_reset` 1, `restored` 1 (К12)
  - `test_no_trip_right_after_reset` — после сброса 30 кадров физики → новых `alarm_started` нет (К13)
  - `test_reset_survives_partner_disconnect` — персонаж «1» поднимает алмаз и передаёт «2» (`pass_diamond()`, как в `test_diamond_carry::test_pass_to_partner`), тревога от персонажа «1» в луче, затем `multiplayer.peer_disconnected.emit(2)` и `queue_free` персонажа «2» → сброс случился, без `SCRIPT ERROR`, алмаз на постаменте (К15)
  - `test_respawn_moves_only_own_player` — `respawn()` двигает «1» и не двигает «2»
  - `test_caught_feedback_marks_only_culprit` — `CaughtFeedback` у «1» показывает, у «2» нет; после сброса — нет (опора К9)
  - `test_obstacle_with_none_consequence_does_not_reset` — конфиг-копия `consequence = NONE`: `tripped` есть, `alarm_started` нет
- `tests/integration/test_test_level.gd` (дописать): в уровне ровно один `SectionRoot` с непустым `section_id`, в нём есть хотя бы одно препятствие; точки появления и алмаз на постаменте дальше `beam_thickness/2 + 1,0 м` от каждого отрезка луча (К13); существующие тесты остаются зелёными

Критерии карточки → тесты:
К1 → `test_laser_beam::test_works_standalone`;
К2 → H3;
К3 → `test_laser_beam::test_player_without_diamond_trips`;
К4 → `test_laser_beam::test_carrier_trips`;
К5 → H3 (опора: `test_laser_config`);
К6 → H3 (опора: `test_laser_config`, существующий запрет прыжка в `test_diamond_carry`);
К7 → `test_laser_beam::test_*diamond*`, `test_laser_touch`, `test_section_reset_flow::test_diamond_touch_resets_section`;
К8 → H3;
К9 → H3 (опора: `test_caught_feedback_marks_only_culprit`);
К10 → `test_section_reset_flow::test_player_caught_resets_section`, `test_caught_carrier_resets_diamond_to_pedestal`;
К11 → `test_section_reset_flow::test_diamond_destroyed_gives_same_reset`;
К12 → `test_section_reset_flow::test_one_alarm_one_reset`, `test_laser_beam::test_trips_once_until_rearmed`, `test_section_reset`;
К13 → `test_section_reset_flow::test_no_trip_right_after_reset`, `test_test_level`;
К14 → H3 (опора: `test_obstacle` — своё тело судит владелец);
К15 → `test_section_reset_flow::test_reset_survives_partner_disconnect`;
К16, К17 → H3.

Для `qa-manual.md` (H3): К2, К5, К6, К8, К9, К14 (`tools\run_local_coop.cmd` с задержкой
150 мс), К16, К17. Отдельно — ощущение блока управления на паузе
(`lock_controls_during_alarm`) и паузы 1,5 с при разрушении алмаза.

## Риски и как узнаем рано

- **Тонкая зона касания (5 см) и быстрые тела.** Пересечение зоны со стенкой засчитывается
  на шаге физики. Тела крупнее шага (персонаж 0,8 м при 5 м/с, алмаз ~0,6 м при 7 м/с),
  поэтому пролёт насквозь маловероятен. Покажут `test_thrown_diamond_trips_when_reacting`
  с настоящим броском и К7 на H3. Если пролетает — `ShapeCast3D` вдоль луча, без смены
  контракта.
- **Под задержкой клиент замирает с запозданием на круг сети** (касание засчитывается
  после отчёта и события хоста), а хост может увидеть, как клиент «прошёл сквозь» луч
  без тревоги. Это цена правила «судит владелец». Проверка — К14 и К9 на H3.
- **Порядок событий разных узлов** (алмаз раньше `section_reset`) держится на одном
  канале надёжных RPC. Локальный тест этого не покажет — H3 в двух окнах.
- **Отступление от T-14** (сброс без пересоздания `Content`). Риск — переделка в шаге 4.
  Объём маленький: у лазера взвод — единственное состояние.
- **Пауза при разрушении алмаза** — новое поведение (раньше сброс был сразу). Если
  мешает, `reset_delay` подбирается на H3. Отдельная пауза для разрушения — новым полем,
  после решения владельца.
- **Подключение во время паузы.** Новый персонаж не блокируется, сброс его не двигает: он
  и так появляется на точке. Не опасно, `_apply_full_state` только снимает взвод
  препятствий.
- **Левел-дизайн: луч можно обойти** (зал сейчас открыт). Проверяется на H3 (К2).
  Перегородка — в задаче левел-дизайнера выше.

## Изменения техзадания

- Создан `docs/tech/00-index.md` — журнал. Статус «принято» (T-01…T-11, T-13) — у того,
  что уже есть в коде и `ARCHITECTURE.md`; T-14, T-15 — «заявлено»; T-12 станет «заменено
  T-17» после H2. Новые T-16…T-21 — «предложено».
- Создан `docs/tech/obstacles.md` — препятствия, правило касания, лазер, сброс секции.
- Найдены расхождения `ARCHITECTURE.md` с кодом (`untyped_declaration`, строки без `tr()`,
  SSAO в Compatibility). Они записаны в журнал, F-001 не блокируют.
