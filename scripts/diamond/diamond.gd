class_name Diamond
extends RigidBody3D
## Алмаз — узел-адаптер.
##
## Состояние (кто несёт, прочность) ведёт хост по правилам CarryRules и Durability.
## Клиенты присылают хосту запросы request_* через RPC.
##
## События. Каждое изменение — дискретное событие: хост применяет правило и рассылает его
## надёжным RPC всем пирам (себе тоже). На каждом пире событие обновляет состояние
## (carrier_id, durability_value) и испускает сигнал ниже — подписчики (HUD, компоненты,
## будущие звуки и эффекты) реагируют на сигнал, а не опрашивают состояние.
## Непрерывное — положение свободного алмаза — идёт через MultiplayerSynchronizer (net_transform).
##
## Пока алмаз несут, каждый пир сам ставит его в точку хвата несущего (позиция персонажа
## и так синхронизирована), поэтому у несущего алмаз не отстаёт на время пинга.

## Сменился несущий (0 — никто). Испускается на каждом пире.
signal carrier_changed(carrier_id: int)
signal picked_up(peer_id: int)
signal put_down(peer_id: int)
signal passed(from_id: int, to_id: int)
signal thrown(peer_id: int)
signal caught(peer_id: int, thrower_id: int)
## Брошенный алмаз остановился.
signal settled
signal damaged(amount: float, current: float, maximum: float)
signal durability_changed(current: float, maximum: float)
signal destroyed
## Алмаз возвращён на старт целым.
signal restored

enum CarryEvent { PICKED_UP, PUT_DOWN, PASSED, THROWN, CAUGHT, SETTLED, RESTORED }

const LAYER_DIAMOND := 4
const MASK_WORLD := 1
## Запас на задержку сети при проверке расстояний на хосте, м.
const DISTANCE_TOLERANCE := 0.5

@export var config: DiamondConfig

## Кто несёт алмаз (peer id) или 0. Меняется только событием от хоста.
var carrier_id := 0:
	set(value):
		if carrier_id == value:
			return
		carrier_id = value
		if is_inside_tree():
			_apply_physics_mode()
		carrier_changed.emit(value)

## Текущая прочность. Меняется только событием от хоста.
var durability_value := 100.0:
	set(value):
		if is_equal_approx(durability_value, value):
			return
		durability_value = value
		durability_changed.emit(value, max_durability())

## Реплицируется синхронизатором: положение свободного алмаза у хоста.
var net_transform := Transform3D.IDENTITY

## Только на хосте: правила и прочность.
var rules: CarryRules
var durability: Durability

var _start_transform: Transform3D
var _prev_velocity := Vector3.ZERO
var _settle_elapsed := 0.0


func _ready() -> void:
	add_to_group("diamond")
	if config == null:
		config = DiamondConfig.new()
	rules = CarryRules.from_config(config)
	durability = Durability.from_config(config)
	durability_value = durability.current
	_start_transform = global_transform
	net_transform = global_transform
	process_physics_priority = 10  # после персонажей: следуем за уже сдвинутой точкой хвата
	_use_model_collision()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_apply_physics_mode()


func is_carried() -> bool:
	return carrier_id != 0


func is_host() -> bool:
	return multiplayer.is_server()


func max_durability() -> float:
	return config.max_durability if config else 100.0


func _physics_process(delta: float) -> void:
	_apply_physics_mode()
	if is_carried():
		_follow_carrier()
	elif is_host():
		_simulate_on_host(delta)
	else:
		global_transform = global_transform.interpolate_with(net_transform, minf(1.0, delta * 15.0))


# --- Запросы клиентов (исполняются на хосте) ------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_pick_up() -> void:
	if not is_host():
		return
	var peer := _sender_id()
	var player := _find_player(peer)
	if player == null:
		return
	var distance := player.get_hold_transform().origin.distance_to(global_position)
	if rules.pick_up(peer, distance - DISTANCE_TOLERANCE):
		_broadcast(CarryEvent.PICKED_UP, peer)


@rpc("any_peer", "call_local", "reliable")
func request_put_down() -> void:
	if not is_host():
		return
	var peer := _sender_id()
	var player := _find_player(peer)
	if player == null or not rules.is_carried_by(peer):
		return
	global_transform = Transform3D(Basis(Vector3.UP, player.facing_yaw()), player.get_drop_position())
	rules.put_down(peer)
	_broadcast(CarryEvent.PUT_DOWN, peer)
	_set_velocity(Vector3.ZERO)


@rpc("any_peer", "call_local", "reliable")
func request_pass() -> void:
	if not is_host():
		return
	var peer := _sender_id()
	var from_player := _find_player(peer)
	var partner := _find_partner(peer)
	if from_player == null or partner == null:
		return
	var partner_id := partner.get_multiplayer_authority()
	var distance := from_player.global_position.distance_to(partner.global_position)
	if rules.pass_to(peer, partner_id, distance - DISTANCE_TOLERANCE):
		_broadcast(CarryEvent.PASSED, peer, partner_id)


@rpc("any_peer", "call_local", "reliable")
func request_throw(direction: Vector3) -> void:
	if not is_host():
		return
	var peer := _sender_id()
	var player := _find_player(peer)
	if player == null or not rules.throw(peer):
		return
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = player.facing_direction()
	direction = direction.normalized()
	_broadcast(CarryEvent.THROWN, peer)
	_set_velocity(direction * config.throw_speed + Vector3.UP * config.throw_lift)
	_settle_elapsed = 0.0


## Вернуть алмаз в исходное положение целым (только хост).
func reset_to_start() -> void:
	if not is_host():
		return
	rules.reset()
	global_transform = _start_transform
	net_transform = _start_transform
	durability.reset()
	_broadcast(CarryEvent.RESTORED)
	_broadcast_durability(0.0)
	_set_velocity(Vector3.ZERO)


# --- События (хост → все пиры) -------------------------------------------------

func _broadcast(event: CarryEvent, actor: int = 0, other: int = 0) -> void:
	_apply_carry_event.rpc(event, rules.carrier_id, actor, other)


@rpc("authority", "call_local", "reliable")
func _apply_carry_event(event: int, new_carrier: int, actor: int, other: int) -> void:
	carrier_id = new_carrier
	match event:
		CarryEvent.PICKED_UP:
			picked_up.emit(actor)
		CarryEvent.PUT_DOWN:
			put_down.emit(actor)
		CarryEvent.PASSED:
			passed.emit(actor, other)
		CarryEvent.THROWN:
			thrown.emit(actor)
		CarryEvent.CAUGHT:
			caught.emit(actor, other)
		CarryEvent.SETTLED:
			settled.emit()
		CarryEvent.RESTORED:
			restored.emit()


func _broadcast_durability(damage: float) -> void:
	_apply_durability.rpc(durability.current, damage)


@rpc("authority", "call_local", "reliable")
func _apply_durability(current: float, damage: float) -> void:
	var was_intact := durability_value > 0.0
	durability_value = current
	if damage > 0.0:
		damaged.emit(damage, current, max_durability())
		if was_intact and current <= 0.0:
			destroyed.emit()


## Подключившийся пир получает текущее состояние разом.
@rpc("authority", "call_remote", "reliable")
func _apply_full_state(new_carrier: int, current_durability: float) -> void:
	carrier_id = new_carrier
	durability_value = current_durability


# --- Внутреннее ----------------------------------------------------------------

func _simulate_on_host(delta: float) -> void:
	# Удар = резкая смена скорости за кадр; гравитация за кадр даёт ~0.16 м/с и порог не проходит.
	var impact := (linear_velocity - _prev_velocity).length()
	_prev_velocity = linear_velocity
	var damage := durability.apply_impact(impact)
	if damage > 0.0:
		_broadcast_durability(damage)

	if global_position.y < config.kill_height and not durability.is_broken():
		var remaining := durability.current
		durability.destroy()
		_broadcast_durability(remaining)

	if rules.state == CarryRules.State.THROWN:
		if _try_catch():
			return
		if linear_velocity.length() < config.settle_speed:
			_settle_elapsed += delta
			if _settle_elapsed >= config.settle_time:
				rules.settle()
				_broadcast(CarryEvent.SETTLED)
		else:
			_settle_elapsed = 0.0

	net_transform = global_transform


func _try_catch() -> bool:
	var thrower := rules.thrower_id
	for player in _players():
		var peer := player.get_multiplayer_authority()
		var distance := player.get_hold_transform().origin.distance_to(global_position)
		if rules.try_catch(peer, distance):
			_broadcast(CarryEvent.CAUGHT, peer, thrower)
			return true
	return false


func _follow_carrier() -> void:
	var carrier := _find_player(carrier_id)
	if carrier == null:
		return
	global_transform = carrier.get_hold_transform()
	net_transform = global_transform


## Форма столкновений — выпуклая оболочка модели: гранёный камень, в отличие от
## цилиндра-заглушки, не катится по полу колесом.
func _use_model_collision() -> void:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var meshes := find_children("*", "MeshInstance3D", true, false)
	if shape_node == null or meshes.is_empty():
		return
	var mesh := (meshes[0] as MeshInstance3D).mesh
	if mesh:
		shape_node.shape = mesh.create_convex_shape(true, true)


func _apply_physics_mode() -> void:
	var carried := is_carried()
	collision_layer = 0 if carried else LAYER_DIAMOND
	collision_mask = 0 if carried else MASK_WORLD
	var should_freeze := carried or not is_host()
	if freeze != should_freeze:
		freeze = should_freeze
		_prev_velocity = linear_velocity


func _set_velocity(velocity: Vector3) -> void:
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	_prev_velocity = velocity
	sleeping = false


func _on_peer_connected(peer_id: int) -> void:
	if is_host():
		_apply_full_state.rpc_id(peer_id, carrier_id, durability_value)


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	var was_carrier := rules.is_carried_by(peer_id)
	rules.release_peer(peer_id)
	if was_carrier:
		_broadcast(CarryEvent.PUT_DOWN, peer_id)


func _sender_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()


func _players() -> Array[Player]:
	var result: Array[Player] = []
	for node in get_tree().get_nodes_in_group("players"):
		if node is Player:
			result.append(node)
	return result


func _find_player(peer_id: int) -> Player:
	for player in _players():
		if player.get_multiplayer_authority() == peer_id:
			return player
	return null


func _find_partner(peer_id: int) -> Player:
	for player in _players():
		if player.get_multiplayer_authority() != peer_id:
			return player
	return null
