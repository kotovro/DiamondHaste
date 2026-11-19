class_name CarryRules
extends RefCounted
## Правила владения алмазом: кто его несёт, передача, бросок, ловля.
## Исполняется только на хосте; узел Diamond переводит сетевые запросы в вызовы этих правил.
## Покрыта tests/unit/test_carry_rules.gd.
##
## Расстояния передаются уже измеренными: правила не знают о сцене.

enum State { RESTING, CARRIED, THROWN }

const NOBODY := 0

signal changed(state: State, carrier_id: int)

var state := State.RESTING
## Кто несёт алмаз (peer id) или NOBODY.
var carrier_id := NOBODY
## Кто бросил алмаз, пока он в полёте; бросивший не может его поймать.
var thrower_id := NOBODY

var pickup_radius: float
var pass_radius: float
var catch_radius: float


func _init(p_pickup_radius: float = 1.6, p_pass_radius: float = 2.5, p_catch_radius: float = 1.2) -> void:
	pickup_radius = p_pickup_radius
	pass_radius = p_pass_radius
	catch_radius = p_catch_radius


static func from_config(config: DiamondConfig) -> CarryRules:
	return CarryRules.new(config.pickup_radius, config.pass_radius, config.catch_radius)


func is_carried_by(peer_id: int) -> bool:
	return state == State.CARRIED and carrier_id == peer_id and peer_id != NOBODY


## Поднять лежащий алмаз. Брошенный может поднять любой, кроме бросившего.
func pick_up(peer_id: int, distance: float) -> bool:
	if peer_id == NOBODY or distance > pickup_radius:
		return false
	match state:
		State.CARRIED:
			return false
		State.THROWN:
			if peer_id == thrower_id:
				return false
	_set_state(State.CARRIED, peer_id, NOBODY)
	return true


func put_down(peer_id: int) -> bool:
	if not is_carried_by(peer_id):
		return false
	_set_state(State.RESTING, NOBODY, NOBODY)
	return true


func pass_to(from_id: int, to_id: int, distance: float) -> bool:
	if not is_carried_by(from_id) or to_id == NOBODY or to_id == from_id or distance > pass_radius:
		return false
	_set_state(State.CARRIED, to_id, NOBODY)
	return true


func throw(peer_id: int) -> bool:
	if not is_carried_by(peer_id):
		return false
	_set_state(State.THROWN, NOBODY, peer_id)
	return true


## Поймать брошенный алмаз на лету.
func try_catch(peer_id: int, distance: float) -> bool:
	if state != State.THROWN or peer_id == NOBODY or peer_id == thrower_id or distance > catch_radius:
		return false
	_set_state(State.CARRIED, peer_id, NOBODY)
	return true


## Брошенный алмаз остановился.
func settle() -> void:
	if state == State.THROWN:
		_set_state(State.RESTING, NOBODY, NOBODY)


## Игрок отключился: если он нёс алмаз, алмаз остаётся лежать.
func release_peer(peer_id: int) -> void:
	if is_carried_by(peer_id):
		_set_state(State.RESTING, NOBODY, NOBODY)
	elif state == State.THROWN and thrower_id == peer_id:
		thrower_id = NOBODY


func reset() -> void:
	_set_state(State.RESTING, NOBODY, NOBODY)


func _set_state(new_state: State, new_carrier: int, new_thrower: int) -> void:
	var differs := new_state != state or new_carrier != carrier_id or new_thrower != thrower_id
	state = new_state
	carrier_id = new_carrier
	thrower_id = new_thrower
	if differs:
		changed.emit(state, carrier_id)
