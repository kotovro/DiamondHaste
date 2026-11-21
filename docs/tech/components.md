# Компоненты и контракты — техзадание

Статус: предложено (DIA-5, ждёт H2). Журнал: T-31…T-33, T-37 в `00-index.md`.
Карточка: `docs/work/DIA-5-architecture-pillars/card.md` (decision-03 B, 04 A; Д10, Д11).
Правила — `ARCHITECTURE.md`, «Композиция»; T-02, T-16.

## 1. Правило: интерфейс = набор методов + контрактный тест

В GDScript 4.4.1 нет интерфейсов и `@abstract` (появился в 4.5). Поэтому «интерфейс» в
проекте — это:

1. **Таблица контракта в этом файле**: группа (как найти), сигналы, методы, поля — с
   типами.
2. **Контрактный тест**, который гоняет одни и те же проверки по всем реализациям из
   списка (`tests/integration/test_<контракт>_contract.gd`, массив сцен или классов в
   начале файла). Новая реализация считается готовой, когда добавлена в этот список и тест
   зелёный.
3. Вызов чужого метода — через типизированную ссылку, если тип один (`DurabilityComponent`),
   или через `call(&"метод")` / `connect(&"сигнал")` для утиного контракта с несколькими
   типами узлов (как препятствия, T-16). `has_method` в штатном коде не используется —
   соответствие доказывает тест, а не проверка на лету.

Общий базовый класс **узлов** не заводим: один скрипт — один встроенный тип, а реализации
наследуют разные встроенные типы (`Node3D`, `RigidBody3D`, `StaticBody3D`,
`CharacterBody3D`). Общий базовый класс **логики** (`RefCounted`) тоже не заводим для
стратегий — сменные стратегии с одинаковым набором методов (`ARCHITECTURE.md`).

## 2. Каталог

| Контракт / компонент | Узел, тип | Логика | Конфиг | Контрактный тест | Статус |
|---|---|---|---|---|---|
| Препятствие (утиный) | корень сцены препятствия: `LaserBeam` (`Node3D`) | `Obstacle`, `LaserTouch` | `LaserConfig` | `test_obstacle_contract.gd` | есть (T-16) |
| Несение | `PlayerCarry` (`Node`) у `Player` | `CarryRules`, `Stamina` | `CarryConfig` | — (одна реализация) | есть |
| Модель совместного несения A/B | стратегия в `PlayerCarry`/`Diamond` | `RigidCarry`, `BalanceCarry` | свои | `test_coop_carry_contract.gd` | шаг 3 плана, не DIA-5 |
| Поза поимки | `CaughtFeedback` (`Node`) у `Player` | — | `CaughtFeedbackConfig` (новый, № 7) | — | есть, конфиг — DIA-10 |
| **Прочность** | `DurabilityComponent` (`Node`) | `Durability` (+ стадии) | `DurabilityConfig` (новый) | `test_durability_contract.gd` (алмаз, учебный ящик) | новый, DIA-13 |
| **Движение по пути** | `PathMover` (`Node`) | `PathMotion` | `PathMoverConfig` (новый) | `test_path_mover.gd` | новый, DIA-14 |
| **Часы секции** | `SectionRoot` | `SectionClock` | — | `test_section_clock.gd` | новый, DIA-14 |
| Имитация задержки | стратегии в `Network` | — | — | `test_latency_contract.gd` | новый, DIA-9 (`latency.md`) |
| Звук объекта | `*Audio` (`Node`) | — | `*AudioConfig` | `test_*_audio.gd` | есть |

## 3. Прочность — `DurabilityComponent` (T-32, decision-03 B, 04 A)

Прочность — дочерний компонент любого объекта, который может разбиться: `Diamond/Durability`,
`TrainingCrate/Durability`. Состояние ведёт хост; изменения — событиями на всех пирах.

**Конфиг** `DurabilityConfig` (`scripts/durability/durability_config.gd`, `Resource`):
- `max_durability: float` — ед. — `100.0`;
- `min_impact_speed: float` — м/с — `3.5`;
- `damage_per_speed: float` — ед. за м/с сверх порога — `8.0`;
- `stage_thresholds: PackedFloat32Array` — доли прочности, по убыванию — `[0.667, 0.333]`
  (ниже первой — «повреждён», ниже второй — «вот-вот разрушится»; заглушки).

Алмаз: `data/diamond_durability.tres` **с теми же числами**, что сейчас в
`data/diamond_config.tres` (100 / 3,5 / 8,0); поля прочности уходят из `DiamondConfig`
(`kill_height` остаётся). Контент-тест сторожит равенство (К28). Учебный ящик:
`data/training_crate_durability.tres` (заглушки по алмазу).

**Логика** `Durability` (есть, расширяется; старые методы и тесты не меняются):
- `enum Stage { INTACT, DAMAGED, CRITICAL, BROKEN }`;
- `static func stage_for(ratio: float, thresholds: PackedFloat32Array) -> Stage` — `BROKEN`
  только при `ratio <= 0`;
- `func stage() -> Stage`;
- `static func from_durability_config(config: DurabilityConfig) -> Durability`;
- `func restore() -> void` — синоним `reset()` для чекпоинта.

**Узел** `DurabilityComponent` (`scripts/durability/durability_component.gd`, `extends Node`):

| Что | Сигнатура | Где / кто |
|---|---|---|
| сигнал | `damaged(amount: float, current: float, maximum: float)` | все пиры, по событию |
| сигнал | `durability_changed(current: float, maximum: float)` | все пиры |
| сигнал | `stage_changed(stage: int, previous: int)` | все пиры; только `INTACT`/`DAMAGED`/`CRITICAL`; ровно раз на переходе порога (К30) |
| сигнал | `destroyed()` | все пиры; переход в `BROKEN` |
| сигнал | `restored()` | все пиры; возврат к полной (чекпоинт, сброс) |
| сигнал | `full_state_applied()` | новый пир (`game-flow.md`, раздел 6) |
| поле | `config: DurabilityConfig` | экспорт |
| поле | `current: float`, `stage: int` | все пиры, меняются только событием |
| метод | `apply_impact(impact_speed: float) -> float` | хост; урон или 0 |
| метод | `destroy() -> void`, `restore() -> void` | хост |
| метод | `ratio() -> float`, `is_broken() -> bool`, `get_maximum() -> float` | все |
| статика | `static func of(node: Node) -> DurabilityComponent` | первый ребёнок этого типа или `null` |

RPC: `_apply_durability(current: float, damage: float)` — `authority`, `call_local`,
`reliable` (переезжает из `Diamond`); `_apply_full_state(current: float)` — `authority`,
`call_remote`, `reliable`, по `peer_connected`. Стадия на каждом пире вычисляется из
`current` (`stage_for`) — одинаково у всех, без отдельного RPC.

**Алмаз переходит на компонент.** `Diamond` считает удары и `kill_height` как сейчас, но
вызывает `durability_component.apply_impact()`; свои сигналы `damaged`,
`durability_changed`, `destroyed` **оставляет и переиспускает** от компонента — подписчики
(`Hud`, `LevelRoot`) и тесты F-002/F-003 не меняются (К28). `durability_value`,
`max_durability()`, `reset_to_start()` остаются (чтение через компонент). Из
`Diamond._apply_full_state` уходит аргумент прочности (у компонента свой).

**Кто бьёт по ящику.** Удар считает хост по алмазу (смена скорости за кадр, как сейчас).
Если в этот кадр алмаз касается тела с компонентом (`contact_monitor = true`,
`max_contacts_reported = 4`, `get_colliding_bodies()`), хост вызывает
`DurabilityComponent.of(body).apply_impact(impact)`. Ящик — `StaticBody3D` на слое `world`,
сцена `scenes/props/training_crate.tscn`, живёт в `Content` тестовой секции: возвращается
целым пересозданием `Content` (Д11, К31). Разрушен — на всех пирах по `destroyed`: прячет
меш, коллизия на слой 0.

**Видимые стадии** — `DurabilityLook` (`Node`, рядом с компонентом): по `stage_changed` и
`full_state_applied` меняет материал меша (`DurabilityLookConfig`: `stage_colors:
PackedColorArray`, заглушки). Декалей нет (Compatibility).

## 4. Движение по пути — `PathMover` (T-33, Д10)

**Почему не общий предок `Movable`.** Подвижными будут луч (`Node3D`), охранник
(`CharacterBody3D`), платформа (`AnimatableBody3D`). Один скрипт расширяет один встроенный
тип, значит, общий предок пришлось бы ставить выше их всех — такого типа нет; цепочки
наследования запрещены (T-02). Компонент `PathMover` двигает любой `Node3D` и не знает, что
двигает.

**Логика** `PathMotion` (`scripts/motion/path_motion.gd`, `RefCounted`) — чистая функция
времени:
- `static func from_config(config: PathMoverConfig, travel: Vector3) -> PathMotion`;
- `func offset_at(t: float) -> Vector3` — туда-обратно по прямой от `0` до `travel` с
  постоянной скоростью и остановкой `dwell` на концах; `t < 0` → начало;
- `func period() -> float` — `2 * (|travel| / speed + dwell)`.

**Конфиг** `PathMoverConfig`: `speed: float` — м/с — `1.0`; `dwell: float` — с — `0.5`.
Длина и направление хода — `@export var travel: Vector3` у узла (ставит левел-дизайнер, как
`LaserBeam.length`).

**Узел** `PathMover` (`scripts/motion/path_mover.gd`, `extends Node`): `@export var target:
Node3D` (по умолчанию родитель), `@export var travel: Vector3`, `@export var config`;
`func bind_clock(clock: SectionClock) -> void`; в `_physics_process`:
`target.position = _origin + motion.offset_at(clock.elapsed_now())`. Без секции (сцена
сама по себе) — свои часы с `_ready`. Группа `path_movers`: `SectionRoot` после создания
`Content` вызывает `bind_clock` у каждого.

**Часы секции** `SectionClock` (`RefCounted`): `start(now_usec: int)`, `pause(now_usec: int)`,
`resume(now_usec: int)`, `elapsed(now_usec: int) -> float`, `set_elapsed(seconds: float,
now_usec: int)`; `elapsed_now()` — обёртка с `Time.get_ticks_usec()`. Время — параметр,
поэтому логика детерминирована и тестируется без кадров.

**Детерминизм без синхронизатора.** Положение — функция общего времени секции, а время
двигают только события хоста: `level_started` (все часы с нуля), `section_reset` (часы
текущей секции с нуля, остальные продолжают), `alarm_started` (все на паузе — луч замирает,
К34), `checkpoint_reached` (ничего). Клиент получает события на одностороннюю задержку
позже, поэтому весь его мир сдвинут на неё одинаково — у хоста и клиента луч в одном месте
«без учёта задержки» (К32). Подключившийся получает `clocks: {section_id: elapsed}` в
`LevelRoot._apply_full_state`.

**Как сочетается с «касание судит владелец»** (T-15, К35). Владелец персонажа судит касание
по своему экрану: свой персонаж без задержки, луч — по своим часам. Что видел игрок, то и
засчитано. Хост факт не перепроверяет по своему положению луча (там и тело, и луч сдвинуты
по-разному), только допуск правдоподобия (`obstacles.md`, раздел 6: `report_tolerance` ≫
`speed × задержка`). Свободный алмаз судит хост по своим часам. Касание движущейся
`Area3D` неподвижного тела ловится физикой (риск — проверяет интеграционный тест
`test_moving_beam_trips_standing_player`).

**Сцена** `scenes/props/moving_laser_beam.tscn`: `MovingLaser` (`Node3D`) → `LaserBeam`
(экземпляр) + `PathMover` (`target = ../LaserBeam`) + `Rails` (`PathRails`, `Node3D`:
строит тонкий меш направляющих по `travel` в `_ready`). Контракт препятствия — у `LaserBeam`
(группа `obstacles`), секция находит его как обычно. Гудение (`LaserAudio`, 3D) — ребёнок
луча, едет вместе с ним (К36).

## 5. Конфиги вместо констант (замечание ревью F-001 № 7, T-37)

Всё, что подбирают на плейтесте, — в `.tres` (`ARCHITECTURE.md`, «Почему не…»):
`CaughtFeedbackConfig` (`data/caught_feedback_config.tres`): `tilt_degrees: float = 28.0`,
`blink_color: Color = Color(1, 0.9, 0.2)`, `blink_hz: float = 5.0` — значения как сейчас в
константах `caught_feedback.gd`. Так же — `Hud.EVENT_SECONDS` и `LOW_STAMINA` при следующей
правке HUD (`HudConfig`).
