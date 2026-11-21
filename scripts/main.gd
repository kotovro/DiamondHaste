extends Node3D
## Корневая сцена прототипа.
##
## Уровень, спавнер игроков и меню живут в одной сцене, поэтому у хоста и клиента
## путь до MultiplayerSpawner существует с момента запуска, и спавн реплицируется
## без гонок при подключении.
##
## Быстрый запуск из командной строки (аргументы после «--»):
##   --host                 создать игру
##   --join [адрес]         подключиться (по умолчанию 127.0.0.1)
##   --port <порт>          порт (по умолчанию Network.DEFAULT_PORT)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

@onready var players: Node3D = $Players
@onready var overview_camera: Camera3D = $OverviewCamera
@onready var menu: Control = $UI/MainMenu
@onready var hud: Hud = $UI/HUD
@onready var status_label: Label = $UI/HUD/Status

var diamond: Diamond
var section: SectionRoot


func _ready() -> void:
	overview_camera.look_at(Vector3(0.0, 0.0, -2.0))
	hud.hide()

	Network.hosted.connect(_on_hosted)
	Network.joined.connect(_on_joined)
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_disconnected.connect(_on_server_disconnected)
	Network.peer_joined.connect(_on_peer_joined)
	Network.peer_left.connect(_on_peer_left)

	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)

	# Main — точка сборки: связывает алмаз, секцию, персонажей и HUD сигналами.
	# Сброс (в том числе от разрушения алмаза) ведёт секция (T-17).
	diamond = get_tree().get_first_node_in_group("diamond") as Diamond
	if diamond:
		hud.bind_diamond(diamond)
	section = get_tree().get_first_node_in_group("sections") as SectionRoot
	if section:
		if diamond:
			section.bind_diamond(diamond)
		hud.bind_section(section)
	players.child_entered_tree.connect(_on_player_entered)

	_handle_command_line.call_deferred()


## Персонаж появился (у хоста — сразу, у клиента — через спавнер); связываем после его _ready.
func _on_player_entered(node: Node) -> void:
	if node is Player:
		node.ready.connect(_on_player_ready.bind(node), CONNECT_ONE_SHOT)


func _on_player_ready(player: Player) -> void:
	if diamond:
		player.carry.bind_diamond(diamond)
	if section:
		player.caught_feedback.bind_section(section)
	if player.is_multiplayer_authority():
		hud.bind_player(player)


## Аргументы командной строки применяются один раз за запуск, а не при каждой перезагрузке сцены
## (иначе клиент после отключения хоста сам переподключался бы).
static var _command_line_handled := false


func _handle_command_line() -> void:
	if _command_line_handled:
		return
	_command_line_handled = true
	var args := OS.get_cmdline_user_args()
	var port := Network.DEFAULT_PORT
	var port_index := args.find("--port")
	if port_index != -1 and port_index + 1 < args.size():
		port = args[port_index + 1].to_int()

	if args.has("--host"):
		_on_host_requested(port)
	elif args.has("--join"):
		var address := "127.0.0.1"
		var join_index := args.find("--join")
		if join_index + 1 < args.size() and not args[join_index + 1].begins_with("--"):
			address = args[join_index + 1]
		_on_join_requested(address, port)


func _on_host_requested(port: int) -> void:
	var err := Network.host(port)
	if err != OK:
		menu.show_error("Не удалось создать игру: %s" % error_string(err))


func _on_join_requested(address: String, port: int) -> void:
	var err := Network.join(address, port)
	if err != OK:
		menu.show_error("Не удалось подключиться: %s" % error_string(err))


func _on_hosted() -> void:
	_enter_game()
	_spawn_player(1)


func _on_joined() -> void:
	_enter_game()


func _on_connection_failed() -> void:
	menu.show_error("Не удалось подключиться к хосту.")


func _on_server_disconnected() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(id)
	_update_status()


func _on_peer_left(id: int) -> void:
	if multiplayer.is_server():
		var player := players.get_node_or_null(str(id))
		if player:
			player.queue_free()
	_update_status()


func _enter_game() -> void:
	menu.hide()
	hud.show()
	_update_status()


func _spawn_player(id: int) -> void:
	if players.has_node(str(id)):
		return
	var player := PLAYER_SCENE.instantiate()
	player.name = str(id)
	players.add_child(player, true)
	print("[Main] Заспавнен игрок %d" % id)


func _update_status() -> void:
	var role := "Хост" if multiplayer.is_server() else "Клиент"
	var count := multiplayer.get_peers().size() + 1
	status_label.text = "%s · id %d · игроков: %d" % [role, multiplayer.get_unique_id(), count]
