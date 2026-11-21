class_name SectionRoot
extends Node3D
## Секция — единица чекпоинта и сброса (docs/tech/obstacles.md, раздел 4).
##
## Все причины сброса (поимка лазером, касание лазера алмазом, разрушение алмаза) сходятся
## в report_caught на хосте. Хост рассылает тревогу, держит паузу config.reset_delay и
## рассылает сброс. Состояние ACTIVE/ALARM ведёт логика SectionReset; на клиентах она
## повторяет хост по событиям. Каждая машина блокирует и переносит только своих персонажей.
##
## Препятствия секции находятся среди потомков по группе obstacles (утиный контракт
## препятствия). Алмаз подключает точка сборки (Main) через bind_diamond().
##
## Пока Content не пересоздаётся (T-18): препятствия возвращаются в исходное состояние
## через set_armed(true), алмаз — через Diamond.reset_to_start().

## Началась тревога: cause — SectionReset.Cause, actor_id — peer id виновника или 0.
signal alarm_started(cause: int, actor_id: int)
## Сброс выполнен: свои персонажи на точках появления, препятствия взведены.
signal section_reset(section_id: String)

## Стабильный ID секции.
@export var section_id: String = ""
@export var config: SectionConfig

## Состояние секции; на всех пирах, меняется только событиями хоста.
var rules: SectionReset

var _diamond: Diamond
var _obstacles: Array[Node] = []
var _reset_timer: Timer


func _ready() -> void:
	add_to_group("sections")
	if config == null:
		config = SectionConfig.new()
	rules = SectionReset.new()
	_reset_timer = Timer.new()
	_reset_timer.name = "ResetTimer"
	_reset_timer.one_shot = true
	_reset_timer.timeout.connect(_on_reset_timer_timeout)
	add_child(_reset_timer)
	for node: Node in find_children("*", "", true, false):
		if node.is_in_group("obstacles"):
			bind_obstacle(node)
	multiplayer.peer_connected.connect(_on_peer_connected)


func bind_diamond(diamond: Diamond) -> void:
	if _diamond == diamond:
		return
	if is_instance_valid(_diamond) and _diamond.destroyed.is_connected(_on_diamond_destroyed):
		_diamond.destroyed.disconnect(_on_diamond_destroyed)
	_diamond = diamond
	if _diamond:
		_diamond.destroyed.connect(_on_diamond_destroyed)


func bind_obstacle(obstacle: Node) -> void:
	if _obstacles.has(obstacle):
		return
	_obstacles.append(obstacle)
	obstacle.connect(&"tripped", _on_obstacle_tripped.bind(obstacle))


func is_alarm() -> bool:
	return rules.is_alarm()


## Единственный вход для всех причин сброса. Только хост; во время тревоги — ничего.
func report_caught(cause: SectionReset.Cause, actor_id: int) -> void:
	if not multiplayer.is_server() or rules.is_alarm():
		return
	_apply_alarm_started.rpc(cause, actor_id)
	_reset_timer.start(config.reset_delay)


# --- События (хост → все пиры) -------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _apply_alarm_started(cause: int, actor_id: int) -> void:
	if not rules.begin(cause as SectionReset.Cause, actor_id):
		return
	_set_obstacles_armed(false)
	for player in _local_players():
		player.set_controls_locked(config.lock_controls_during_alarm)
	alarm_started.emit(cause, actor_id)


@rpc("authority", "call_local", "reliable")
func _apply_section_reset() -> void:
	rules.finish()
	for player in _local_players():
		player.respawn()
		player.set_controls_locked(false)
	_set_obstacles_armed(true)
	section_reset.emit(section_id)


## Подключившийся пир получает состояние секции разом.
@rpc("authority", "call_remote", "reliable")
func _apply_full_state(alarm: bool, cause: int, actor_id: int) -> void:
	if alarm and rules.begin(cause as SectionReset.Cause, actor_id):
		_set_obstacles_armed(false)


# --- Причины (только хост) -----------------------------------------------------

func _on_obstacle_tripped(target: int, actor_id: int, _point: Vector3, obstacle: Node) -> void:
	if not multiplayer.is_server() or not is_instance_valid(obstacle):
		return
	var consequence: int = obstacle.call(&"get_consequence")
	if SectionReset.consequence_resets(consequence as Obstacle.Consequence):
		report_caught(SectionReset.cause_for_touch(target as Obstacle.Target), actor_id)


func _on_diamond_destroyed() -> void:
	if multiplayer.is_server():
		report_caught(SectionReset.Cause.DIAMOND_DESTROYED, 0)


func _on_reset_timer_timeout() -> void:
	if not multiplayer.is_server():
		return
	if is_instance_valid(_diamond):
		_diamond.reset_to_start()
	_apply_section_reset.rpc()


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		_apply_full_state.rpc_id(peer_id, rules.is_alarm(), rules.cause, rules.actor_id)


# --- Внутреннее ----------------------------------------------------------------

func _set_obstacles_armed(armed: bool) -> void:
	for obstacle in _obstacles:
		if is_instance_valid(obstacle) and not obstacle.is_queued_for_deletion():
			obstacle.call(&"set_armed", armed)


## Персонажи, которыми управляет эта машина.
func _local_players() -> Array[Player]:
	var result: Array[Player] = []
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node is Player and is_instance_valid(node) and not node.is_queued_for_deletion() \
				and node.is_multiplayer_authority():
			result.append(node as Player)
	return result
