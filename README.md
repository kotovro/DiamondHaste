# Diamond Heist

Кооперативная игра для двух игроков по сети: вынести алмаз из банка. Алмаз тяжёлый и
хрупкий, его несут, передают и бросают друг другу, а по пути — препятствия.
Godot 4.4.1, GDScript.

Замысел, механики и план разработки — [`DESIGN.md`](DESIGN.md).
Что уже сделано — [`CHANGELOG.md`](CHANGELOG.md).

## Состояние

Ранний прототип. Готовы сеть на двоих, несение, передача, бросок и ловля алмаза,
выносливость и прочность. Сейчас в работе — первое препятствие.

## Запуск

Нужно:
- [Godot 4.4.1](https://godotengine.org/download/archive/4.4.1-stable/);
- [AWS CLI](https://aws.amazon.com/cli/) (`winget install Amazon.AWSCLI`) и профиль
  `yc-storage` с ключом доступа к хранилищу моделей:
  `aws configure --profile yc-storage` (регион `ru-central1`).

```bat
git clone https://github.com/kotovro/DiamondHaste.git
cd DiamondHaste
tools\fetch_assets.cmd
```

Модели (`.glb`) и исходники Blender (`.blend`) не хранятся в git: они лежат в
Yandex Object Storage, а в репозитории — только список с хешами `assets.lock.json`.
`fetch_assets` скачивает их по этому списку.

Дальше — открыть проект в Godot или сразу запустить хост и клиент в двух окнах:

```bat
tools\run_local_coop.cmd
```

Если Godot лежит не по пути из скрипта, задайте переменную `GODOT_BIN`.

С задержкой сети (пинг в миллисекундах; нужен Python 3):

```bat
tools\run_local_coop.cmd 150
```

Клиент подключается через `tools\lag_proxy.py` (порт 24681), который придерживает пакеты
на половину пинга в каждую сторону. Окно посредника закрывается вручную. Свои параметры:
`python tools\lag_proxy.py --delay 75 --jitter 10 --loss 1`, проверка без игры —
`python tools\lag_proxy.py --self-test`.

Управление: WASD — ходьба, мышь — камера, пробел — прыжок, E — взять или положить алмаз,
Q — передать, F — бросить, Esc — отпустить курсор.

## Готовые сборки

Сборки для Windows и Linux — на странице [Releases](https://github.com/kotovro/DiamondHaste/releases).
Их собирает CI, когда в `main` ставится тег версии `vX.Y.Z`.

## Разработка

- Проверка перед любым слиянием: `tools\run_tests.cmd` должен закончиться `VALIDATION OK`.
  Один файл: `tools\run_tests.cmd res://tests/unit/test_stamina.gd`.
- Тесты — GdUnit4 (`addons/gdUnit4`), в `tests/unit` и `tests/integration`.
  CI гоняет их на каждый push и pull request (`.github/workflows/tests.yml`).
- Правила кода — [`ARCHITECTURE.md`](ARCHITECTURE.md).
- Справочник классов Godot именно нашей версии: `tools\gen_class_ref.cmd` выгружает его в
  `.godot\class_ref\` (XML по классу на файл, в git не попадает).
- Как идёт работа над фичами (роли агентов, артефакты, решения владельца) —
  [`AGENTS.md`](AGENTS.md) и [`docs/agents/TEAM.md`](docs/agents/TEAM.md).
  Артефакты фич — `docs/work/<ID>-<slug>/`.
- Ветки: `main` — только проверенные версии, `dev` — интеграция,
  `feature/<ID>-<slug>` — фичи.
- Коммиты начинаются с тега: `feature:`, `tests:`, `refactor:`, `merge:`.
- Изменения записываются в [`CHANGELOG.md`](CHANGELOG.md), раздел `[Unreleased]`.

### Модели

После экспорта новой или изменённой модели:

```bat
tools\upload_assets.cmd
```

Скрипт загрузит изменённые файлы в хранилище и обновит `assets.lock.json` —
его нужно закоммитить вместе с изменением.

### Выпуск версии

1. В `CHANGELOG.md` переименовать `[Unreleased]` в `[X.Y.Z] - ГГГГ-ММ-ДД` и завести новый
   пустой `[Unreleased]`.
2. Влить `dev` в `main` (тесты зелёные, фичи прошли ручную проверку владельца).
3. Поставить тег на `main` и отправить его: `git tag vX.Y.Z` и `git push origin vX.Y.Z`.

CI (`.github/workflows/release.yml`) прогонит тесты, соберёт Windows и Linux и опубликует
релиз с разделом из `CHANGELOG.md`. Без раздела для версии релиз не публикуется.
Версии `0.x` публикуются как предварительные.

## Структура

```
scripts/   код по фичам: diamond, player, net, ui
scenes/    сцены: уровень, персонаж, алмаз, интерфейс
data/      конфиги баланса (.tres)
assets/    материалы и модели (модели — из хранилища)
art/       исходники Blender (из хранилища)
tests/     тесты GdUnit4
tools/     запуск тестов, двух окон, загрузка моделей
docs/      регламент команды, арт и звук, артефакты фич
```
