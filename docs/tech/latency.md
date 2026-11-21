# Имитация задержки сети и замер пинга — техзадание

Статус: принято (H2 2026-11-21, DIA-5; реализация — DIA-9). Журнал: T-38 в `00-index.md`.
Закрывает замечание ревью F-001 № 9 (`docs/work/F-001-first-obstacle/review.md`).
Нужна до H3 по совместному несению и К35 DIA-14 («150 мс в двух окнах»).

## 1. Зачем контракт

Ручные проверки «под задержкой 150 мс» не должны зависеть от того, как задержка
сделана: сейчас — внешний UDP-посредник, позже — внутри игры, к релизу — встроенная
имитация Steam. Код игры о задержке ничего не знает: он видит обычный `MultiplayerPeer`.
Выбор — только в `Network` (T-03), только в отладочной сборке (`OS.is_debug_build()`); в
релизе всегда «без задержки».

## 2. Контракт `LatencySimulator`

Сменные стратегии без общего базового класса (`components.md`, раздел 1), `RefCounted`,
`scripts/net/latency/`. Соответствие — `tests/integration/test_latency_contract.gd`.

| Метод | Смысл |
|---|---|
| `func get_kind() -> StringName` | `&"none"`, `&"peer"`, `&"proxy"`, `&"steam"` |
| `func get_one_way_ms() -> float` | заявленная односторонняя задержка (пинг ≈ 2×) |
| `func client_port(port: int) -> int` | куда клиенту подключаться (посредник меняет порт) |
| `func wrap(peer: MultiplayerPeer) -> MultiplayerPeer` | что поставить в `multiplayer.multiplayer_peer` |
| `func is_available() -> bool` | можно ли включить в этой сборке и окружении |

Задержка ставится **на стороне клиента** и действует в обе стороны — как у посредника
сейчас: пинг = 2 × `one_way_ms`. Хосту ничего не нужно.

| Реализация | Как работает | `wrap` | `client_port` | Когда |
|---|---|---|---|---|
| `NoLatency` | ничего | тот же peer | тот же | по умолчанию, релиз |
| `ProxyLatency` | `tools/lag_proxy.py` (UDP-посредник, есть; самопроверка `--self-test`) | тот же peer | `24681` | сейчас: `tools\run_local_coop.cmd 150` |
| `PeerLatency` | обёртка `LagPeer extends MultiplayerPeerExtension` вокруг настоящего peer | `LagPeer` | тот же | DIA-9: без Python, работает и с Steam-peer |
| `SteamLatency` | имитация задержки Steam Networking (параметры fake lag в конфигурации сокетов Steam) | тот же peer, параметры заданы | тот же | шаг 7 (Steam); API сверить с версией GodotSteam при подключении |

### `LagPeer` на GDScript — проверено по справочнику 4.4.1

`MultiplayerPeerExtension` (наследник `MultiplayerPeer`) в 4.4.1 даёт виртуальные методы для
скриптов: `_get_packet_script() -> PackedByteArray`, `_put_packet_script(p_buffer:
PackedByteArray) -> Error`, `_get_available_packet_count()`, `_get_packet_peer()`,
`_get_packet_mode()`, `_get_packet_channel()`, `_get_max_packet_size()`, `_poll()`,
`_close()`, `_disconnect_peer(p_peer, p_force)`, `_get_unique_id()`, `_is_server()`,
`_get_connection_status()`, `_set_target_peer()`, `_set_transfer_mode()`,
`_get_transfer_mode()`, `_set_transfer_channel()`, `_get_transfer_channel()`,
`_set_refuse_new_connections()`, `_is_refusing_new_connections()`,
`_is_server_relay_supported()`. Варианты с указателями (`_get_packet`, `_put_packet`) — для
GDExtension; скрипт реализует `*_script`. Значит, обёртка на GDScript возможна.
(Справочник сгенерирован без описаний — поведение уточняет тест, раздел 4.)

Устройство:
- `_put_packet_script(buf)` → в очередь «наружу» `(due_usec, buf, target_peer, mode,
  channel)`; `_poll()` отдаёт созревшее во внутренний peer (`set_target_peer`,
  `transfer_mode`, `transfer_channel`, `put_packet`), затем `inner.poll()`;
- входящие: после `inner.poll()` все пакеты внутреннего peer — в очередь «внутрь» с
  `due_usec`; `_get_available_packet_count()` — только созревшие; `_get_packet_*` — о
  текущем созревшем;
- `peer_connected`/`peer_disconnected` внутреннего peer кладутся в ту же очередь «внутрь»,
  чтобы не обогнать пакеты; при отключении несозревшие пакеты этого пира отбрасываются;
- порядок внутри очереди сохраняется (надёжные RPC приходят по порядку), `jitter` не
  нарушает порядок (сдвиг не меньше предыдущего);
- очередь — чистая логика `DelayQueue` (`RefCounted`: `push(now_usec, item)`,
  `pop_due(now_usec) -> Array`, `drop_where(peer_id)`), юнит-тест без сети.

Поля `PeerLatency`/`LagPeer`: `one_way_ms: float`, `jitter_ms: float = 0.0`,
`loss_percent: float = 0.0` (потеря — только для ненадёжных пакетов: надёжные ENet
повторяет сам, их потеря внутри обёртки сломала бы гарантию).

## 3. Выбор в `Network`

Аргументы командной строки (после `--`), как `--host`/`--join`:
- `--lag <пинг_мс>` — включить задержку, односторонняя = пинг / 2;
- `--lag-mode peer|proxy` — реализация (по умолчанию `peer`, когда готова; до этого `proxy`);
- `--lag-jitter <мс>`, `--lag-loss <%>`.

`Network`: `var latency: RefCounted` (стратегия), `func set_latency(simulator: RefCounted) -> void`;
`join()` берёт `latency.client_port(port)` и ставит `latency.wrap(peer)`. Хост вызывает
`wrap` тоже — `NoLatency` у хоста по умолчанию. Остальной код `latency` не видит.
`tools\run_local_coop.cmd <пинг>` передаёт `--lag <пинг>` клиенту (и запускает посредник
только при `--lag-mode proxy`).

## 4. Замер пинга

Пинг меряется **на уровне игры**, а не статистикой транспорта: `ENetPacketPeer.get_statistic(PEER_ROUND_TRIP_TIME)`
не видит задержку, добавленную `LagPeer`, и не существует у Steam-peer.

- `Network._ping(sent_usec: int)` — `any_peer`, `call_remote`, `unreliable`; получатель сразу
  отвечает `Network._pong(sent_usec: int)` — `any_peer`, `call_remote`, `unreliable`.
  Пути совпадают у всех (`/root/Network`, автозагрузка; в обвязке `NetPair` — `Network`
  под каждым корнем, ниже).
- Раз в `PING_INTERVAL` (1 с, `Timer`, только когда онлайн) клиент шлёт `_ping`; по `_pong`
  — `ping_measured(rtt_ms: float)`, скользящее среднее `get_ping_ms() -> float`.
- **Оверлей** `NetOverlay` (`scenes/ui/net_overlay.tscn`, только отладочная сборка): пинг,
  вид имитации и заявленная задержка. Включается аргументом `--net-overlay`, а не клавишей:
  новое действие ввода потребовало бы правки `project.godot`. Подписан на
  `ping_measured`, не опрашивает.
- **Автопроверка** `tests/integration/test_latency_peer.gd`: в одном процессе два
  `SceneMultiplayer` (`SceneTree.set_multiplayer(api, root_path)`) на ENet `127.0.0.1`,
  клиент обёрнут `LagPeer(75 мс)`; надёжный RPC туда-обратно — 150 ± 40 мс; без обёртки —
  < 40 мс; порядок 100 надёжных RPC сохранён; отключение не теряет `peer_disconnected`.
  Та же обвязка (`tests/support/net_pair.gd`) нужна для тестов входа (`game-flow.md`,
  раздел 5). `lag_proxy.py --self-test` остаётся проверкой посредника.

**Обвязка `NetPair` и автозагрузка `Network`.** `set_multiplayer(api, root_path)` отдаёт
свой `SceneMultiplayer` только поддереву `root_path`. Автозагрузка `/root/Network` лежит вне
обоих корней и работает на общем API дерева, поэтому через неё RPC `_ping/_pong`, авторизация
и конец сессии двух пиров в одном процессе не пойдут. Правило:
- `NetPair` (`tests/support/net_pair.gd`) создаёт два корня `/root/NetPairHost` и
  `/root/NetPairClient`, вызывает `set_multiplayer(api, корень)` для каждого и **после
  этого** кладёт под каждый корень свой экземпляр `scripts/net/network.gd` с именем
  `Network`. Пути RPC считаются от `root_path`, поэтому у обоих пиров это `Network` — они
  совпадают. Автозагрузка в таких тестах не трогается и остаётся offline.
- `Network` берёт API только через свойство узла `multiplayer` (так сейчас: подписки в
  `_ready`, `multiplayer.multiplayer_peer` в `host/join/close`), не через
  `get_tree().get_multiplayer()` без пути и не по абсолютному пути `/root/Network`.
- Узлы игры не обращаются к глобальному имени `Network`: его знает только точка сборки
  `Main` (`var network: Node`, если не задан — автозагрузка) и передаёт остальным
  (`Session`, `NetOverlay`) через `bind_network(network: Node) -> void`. Тест под `NetPair`
  собирает то же сам: свой `Network` своего корня → `bind_network`.
- Тесты, которым сеть не нужна (`test_delay_queue`; в `test_latency_contract` — методы
  стратегий `client_port`/`wrap` без соединения), `NetPair` и `Network` не используют.

## 5. Как пользоваться (для `qa-manual.md`)

- Сейчас: `tools\run_local_coop.cmd 150` — клиент через посредник, пинг ≈ 150 мс.
- После DIA-9: то же, но без Python (`--lag-mode peer`); `--net-overlay` показывает пинг.
- Steam: `SteamLatency` с теми же аргументами.
