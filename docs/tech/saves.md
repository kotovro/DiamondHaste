# Сохранения и прогресс — техзадание

Статус: предложено (DIA-5, ждёт H2). Журнал: T-29, T-30 в `00-index.md`.
Карточка: `docs/work/DIA-5-architecture-pillars/card.md` (decision-02 B, 06 A, 07: 7.1 A,
7.2 B, 7.3 A; Д8, Д13, Д15, Д16). Правила — `ARCHITECTURE.md`, «Данные игрока».

## 1. Что такое «снимок чекпоинта»

Прогресс — **только ID самого дальнего чекпоинта и отметка «пройдено»**. Всё остальное
состояние на чекпоинте выводится из сцены уровня: секция в исходном виде (её `Content`
пересоздаётся), алмаз на `DiamondPoint` с полной прочностью, персонажи на точках
чекпоинта (`game-flow.md`, раздел 3). Поэтому сериализовать мир не нужно, а сохранение не
ломается при правке содержимого секций. Числа на итоге не считаются (decision-01 A).

## 2. Порядок чекпоинтов (`CheckpointRoute`)

Логика `CheckpointRoute` (`scripts/save/checkpoint_route.gd`, `RefCounted`), строится из
порядка `LevelRoot/Sections`:
- `func _init(ids: PackedStringArray)` — первый ID — хранилище, последний — финал;
- `func index_of(id: String) -> int` — `-1`, если ID нет;
- `func farther(a: String, b: String) -> String` — неизвестный ID считается хранилищем;
- `func range_to(id: String) -> PackedStringArray` — от хранилища до `id` включительно;
- `func is_finale(id: String) -> bool`.

ID — `SectionRoot.section_id` (стабильная строка, T-14). Сравнение — только по порядку в
маршруте, не по строкам. Контент-тест: ID секций уровня уникальны и непусты.

## 3. Формат файла (этап 1 из `ARCHITECTURE.md`: один файл)

`user://progress.json` (UTF-8, `JSON.stringify` с отступом):

```json
{
  "format": 1,
  "farthest_checkpoint": "vault",
  "finished": false
}
```

| Поле | Тип | Смысл |
|---|---|---|
| `format` | int | версия формата; без поля или не int — файл повреждён |
| `farthest_checkpoint` | String | самый дальний чекпоинт, где угодно — хостом или вторым игроком (Д13) |
| `finished` | bool | финал достигнут (Д12) |

Логика (`scripts/save/`, всё `RefCounted`, юнит-тесты):
- `ProgressRecord` — данные: `farthest_checkpoint: String`, `finished: bool`;
  `static func fresh(route: CheckpointRoute) -> ProgressRecord`.
- `SaveFormat` — `const CURRENT := 1`; `static func to_text(record: ProgressRecord) -> String`;
  `static func parse(text: String) -> SaveLoadResult`; `static func migrate(data: Dictionary) -> Dictionary`
  (цепочка `_migrate_1_to_2`, … — по одной функции на шаг; сейчас пустая).
- `SaveLoadResult` — `status: int` (`OK | MISSING | CORRUPT | TOO_NEW`), `record: ProgressRecord`.
  `TOO_NEW` (файл новее игры) не перезаписывается — как повреждённый, но с другим
  сообщением; стирается только «начать заново».
- `ProgressRules` — правила прогресса (раздел 4).

Узлы и файлы:
- `SaveFile` (`scripts/save/save_file.gd`, `RefCounted`-адаптер файловой системы):
  `func read_text(path: String) -> String` (пусто, если нет), `func write_atomic(path: String, text: String) -> Error`.
- `ProgressStore` (`scripts/save/progress_store.gd`, `extends Node`, `Main/Progress`):
  читает файл в `_ready`, пишет по событиям, `@export var path: String`.

**Запись — через временный файл** (`ARCHITECTURE.md`): `FileAccess.open(path + ".tmp", WRITE)`
→ `store_string` → `close()` → `DirAccess.rename_absolute(tmp, path)`. На Windows Godot
удаляет старый файл перед переименованием, поэтому между этими шагами файла может не быть:
**при чтении, если основного файла нет или он повреждён, а `.tmp` читается — берём `.tmp`**
и сразу дописываем его как основной. Выбор между двумя текстами — чистая функция
`SaveFormat.pick(main_text: String, tmp_text: String) -> SaveLoadResult` (тест).

**Ошибки без ошибок в логе** (К26): нечитаемый JSON — `CORRUPT`, `push_warning`, слот
помечен «повреждён», «начать заново» его перезаписывает. `push_error` не используется
(`run_tests` считает `ERROR:` провалом).

**Два окна на одной машине.** Обе копии игры видят один `user://`. Аргумент командной строки
`--profile <имя>` меняет путь на `user://profiles/<имя>/progress.json`;
`tools\run_local_coop.cmd` передаёт `--profile host` и `--profile client`. Тесты пишут в
`user://test_progress_<suite>.json` и удаляют его в `after_test`.

### Следующие этапы (не в DIA-5)

1. **Настройки** — `user://settings.cfg` (`ConfigFile`), свой `format`.
2. **Три слота и миграции** — формат 2: `{"format": 2, "slots": [<запись v1>, null, null], "last_slot": 0}`;
   `_migrate_1_to_2` кладёт запись v1 в слот 0. Как прогресс из игры у напарника ложится на
   слоты (Д13) — решение фичи трёх слотов.
3. **Steam Cloud** — тот же файл, синхронизация средствами Steam.

Каждый следующий этап — только когда предыдущий покрыт тестами.

## 4. Прогресс у обоих: правила (`ProgressRules`)

Все — чистые статические функции над `ProgressRecord` и `CheckpointRoute`:

| Функция | Правило | Критерии |
|---|---|---|
| `record_reached(record, id, route) -> bool` | запись растёт, только если `id` дальше; финальный ID не записывается (с финала не стартуют); `true` — изменилась | К19, К24, К37, К38, К53 |
| `mark_finished(record, route) -> void` | `finished = true`; `farthest` не меньше последнего чекпоинта перед финалом. «Продолжить» у пройденного слота стартует с него (допущение архитектора А1, H2) | К12 |
| `restart(route) -> ProgressRecord` | единственный способ уменьшить запись (Д15), вызывается после подтверждения | К40 |
| `start_options(host_farthest, partner_farthest, route) -> PackedStringArray` | 7.2 B: от хранилища до дальнего из двух | К49, К50 |
| `is_valid_start(id, host_farthest, partner_farthest, route) -> bool` | `id` в `start_options` | К50 |
| `compare(mine, theirs, route) -> int` | `-1/0/1`: чей прогресс дальше (decision-02 B, Д14) | К25 |
| `skips_sections(start_id, record, route) -> PackedStringArray` | секции между рекордом и стартом, которые игрок пропустит | К55 |

**Кто пишет.** Каждая машина пишет **свой** файл сама по событию хоста; по сети прогресс
не передаётся (кроме номера дальнего чекпоинта при подключении):
- `LevelRoot.checkpoint_reached(index, id)` → `record_reached` → запись файла, если изменилось
  → сигнал `ProgressStore.checkpoint_recorded(checkpoint_id: String, record_changed: bool)`.
  **Знак «чекпоинт достигнут» подписан на `checkpoint_recorded`, а не на
  `checkpoint_reached`** — так «знак появился» значит «запись сделана или не нужна» (Д9,
  К27). Знак одинаков у обоих, `record_changed` на него не влияет (решение владельца).
- `LevelRoot.finale_reached` → `mark_finished` → запись.
- `Session.session_started(start_id)` → `record_reached(start_id)` — **7.3 A: засчитывается
  сразу при старте** тому, кто стартовал дальше своего рекорда, и хосту тоже (при 7.2 B хост
  может стартовать дальше своего рекорда).
- Выход, отключение, вылет между чекпоинтами ничего не пишут (К22).

**Что знает хост о втором игроке.** Только `farthest_id` и `finished` из
`Session.request_join` — для диапазона (7.2 B) и сведений о разнице (2B). Хост этот прогресс
не хранит.

## 5. Выбор стартового чекпоинта (DIA-15; 7.1 A, 7.2 B, 7.3 A)

```
клиент: joined ─► request_join(farthest, finished) ─► хост
хост: partner = CHOOSING; options = start_options(мой, его); selected = текущий
      _apply_start_options(options, current, мой, его, selected) ─► оба: экран выбора
      указатель двигает только хост (7.1 A) ─► _apply_start_options(... selected) ─► оба
      сессия дошла до нового чекпоинта, пока выбор открыт (Д20) ─► _apply_start_options(обновлено)
      подтверждение ─► is_valid_start? ─► _apply_session_started(start_id) ─► оба
      start_id == текущий: только спавн (К51); иначе reset_to алмаза + _apply_level_started + спавн (К52)
оба:  session_started ─► record_reached(start_id) (7.3 A) ─► экран закрыт
```

Экран выбора показывает (данные — из `_apply_start_options`, тексты — ключи `tr()`):
- список `options`, отметки: дальний хоста, дальний второго, текущий сессии, выбранный;
- при `compare != 0` — чей прогресс дальше, что дальний сохранится, выбор его не изменит
  (К25; при 7.2 B подсказка «создайте игру сами» не нужна);
- для себя — `skips_sections(selected, мой рекорд)`, если не пусто: «вы пропустите секции …»
  и что прогресс засчитается сразу (К55).

## 6. Сообщения о разнице прогресса (decision-02 B) и справка (decision-06 A)

| Где | Откуда данные | Ключ (пример) |
|---|---|---|
| Главное меню, «продолжить» / выбор слота | `ProgressStore.record` | `ui.menu.continue_from` |
| Экран выбора чекпоинта | `_apply_start_options` + `ProgressRules.compare` | `ui.start.farther_host`, `ui.start.farther_partner`, `ui.start.kept` |
| Конец сессии у второго игрока | `Network.take_end_reason()` | `ui.notice.host_ended_progress_kept`, `ui.notice.connection_lost_progress_kept` |
| Справка | статический экран, пункты карточки «Что сказано в справке» | `ui.help.saves.*` |

Справка — одна сцена `scenes/ui/help.tscn` с текстом из ключей (Д17). Контент-тест: все
ключи `ui.help.saves.*` есть в `locale/ru.po`.

## 7. Расхождение с `DESIGN.md` (для владельца)

`DESIGN.md`, «Сложность и сохранения»: «Сохранение хранится у хоста… У хоста три слота».
По решениям 2026-11-21 прогресс есть у каждого игрока (decision-02 B), слот пока один (Д8),
и есть выбор стартового чекпоинта при подключении. Архитектура следует решениям; правку
`DESIGN.md` делает владелец.
