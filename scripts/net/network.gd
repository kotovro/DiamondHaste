extends Node
## Создание сетевого подключения.
##
## Единственное место, где выбирается транспорт. Сейчас ENet; для релиза здесь же
## подключается SteamMultiplayerPeer (GodotSteam), остальной код при этом не меняется:
## геймплей работает только через высокоуровневый API (multiplayer, RPC,
## MultiplayerSynchronizer, MultiplayerSpawner) и сигналы этого модуля.

signal hosted
signal joined
signal connection_failed
signal server_disconnected
signal peer_joined(id: int)
signal peer_left(id: int)

const DEFAULT_PORT := 24680
## Игра на двоих: хост + один клиент.
const MAX_CLIENTS := 1


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		push_warning("[Network] Не удалось создать сервер на порту %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	print("[Network] Хост запущен, порт %d" % port)
	hosted.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_warning("[Network] Не удалось подключиться к %s:%d: %s" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	print("[Network] Подключение к %s:%d..." % [address, port])
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _on_peer_connected(id: int) -> void:
	print("[Network] Пир подключился: %d" % id)
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[Network] Пир отключился: %d" % id)
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	print("[Network] Подключено, мой id: %d" % multiplayer.get_unique_id())
	joined.emit()


func _on_connection_failed() -> void:
	print("[Network] Подключение не удалось")
	close()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	print("[Network] Сервер закрыл соединение")
	close()
	server_disconnected.emit()
