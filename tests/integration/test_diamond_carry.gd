extends TestCase
## Перенос алмаза целиком: действия компонента PlayerCarry (тот же путь, что от клавиш) →
## запросы Diamond.request_* → события. Настоящие персонажи и физика.
## Без сети: локальный пир (id 1) — хост; персонаж «2» стоит рядом как партнёр.

const DIAMOND_SCENE := preload("res://scenes/props/diamond.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var host_player: Player
var partner: Player
var diamond: Diamond


func before_each() -> void:
	add_child_autofree(_make_floor())
	host_player = _spawn_player(1, Vector3(0.0, 0.0, 0.0))
	partner = _spawn_player(2, Vector3(1.5, 0.0, 0.0))
	diamond = DIAMOND_SCENE.instantiate()
	diamond.position = Vector3(0.0, 0.25, -0.75)
	add_child_autofree(diamond)
	host_player.carry.bind_diamond(diamond)
	partner.carry.bind_diamond(diamond)
	watch_signals(diamond)
	watch_signals(host_player.carry)
	watch_signals(partner.carry)
	await wait_physics_frames(10)


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_pick_up_attaches_diamond_and_fires_events() -> void:
	host_player.carry.pick_up()
	assert_eq(diamond.carrier_id, 1)
	assert_signal_emit_count(diamond, "picked_up", 1)
	assert_eq(get_signal_args(diamond, "picked_up"), [1])
	assert_eq(get_signal_args(host_player.carry, "carrying_changed"), [true])
	await wait_physics_frames(3)
	assert_lt(diamond.global_position.distance_to(host_player.get_hold_transform().origin), 0.01)
	assert_true(diamond.freeze, "несомый алмаз не симулируется")


func test_carrying_slows_down_and_blocks_jump() -> void:
	host_player.carry.pick_up()
	assert_almost_eq(host_player.carry.speed_multiplier(), host_player.carry.config.speed_multiplier)
	assert_false(host_player.carry.can_jump())
	assert_false(host_player.carry.can_interact_with_objects())


func test_pick_up_rejected_when_too_far() -> void:
	diamond.global_position = Vector3(0.0, 0.25, -6.0)
	await wait_physics_frames(2)
	host_player.carry.pick_up()
	assert_eq(diamond.carrier_id, 0)
	assert_signal_not_emitted(diamond, "picked_up")


func test_put_down_places_diamond_on_floor_without_damage() -> void:
	host_player.carry.pick_up()
	await wait_physics_frames(3)
	host_player.carry.put_down()
	assert_eq(diamond.carrier_id, 0)
	assert_eq(get_signal_args(diamond, "put_down"), [1])
	assert_eq(get_signal_args(host_player.carry, "carrying_changed"), [false])
	await wait_physics_frames(60)
	assert_lt(diamond.global_position.y, 0.4, "алмаз лежит у пола")
	assert_signal_not_emitted(diamond, "damaged")


func test_stamina_depletion_puts_diamond_down() -> void:
	host_player.carry.pick_up()
	host_player.carry.stamina.tick(1000.0, true)
	assert_eq(diamond.carrier_id, 0, "кончилась выносливость — алмаз положен")
	assert_signal_emit_count(diamond, "put_down", 1)


func test_pass_to_partner() -> void:
	host_player.carry.pick_up()
	host_player.carry.pass_diamond()
	assert_eq(diamond.carrier_id, 2)
	assert_eq(get_signal_args(diamond, "passed"), [1, 2])
	assert_false(host_player.carry.is_carrying())
	assert_true(partner.carry.is_carrying())
	assert_eq(get_signal_args(partner.carry, "carrying_changed"), [true])


func test_throw_goes_where_player_faces() -> void:
	partner.global_position = Vector3(-20.0, 0.0, 0.0)  # убираем партнёра с линии броска
	host_player.body.rotation.y = -PI / 2.0  # персонаж смотрит в +X
	host_player.carry.pick_up()
	await wait_physics_frames(3)
	var start := diamond.global_position
	host_player.carry.throw_diamond()
	assert_eq(get_signal_args(diamond, "thrown"), [1])
	await wait_physics_frames(40)
	var moved := diamond.global_position - start
	assert_gt(moved.x, 2.0, "алмаз летит туда, куда повёрнут персонаж (+X)")
	assert_lt(absf(moved.z), 0.5, "а не вперёд по камере (-Z)")


func test_uncaught_throw_takes_damage_and_settles() -> void:
	partner.global_position = Vector3(20.0, 0.0, 0.0)
	host_player.carry.pick_up()
	await wait_physics_frames(3)
	host_player.carry.throw_diamond()
	assert_eq(diamond.rules.state, CarryRules.State.THROWN)
	await wait_physics_frames(180)
	assert_signal_emitted(diamond, "damaged", "непойманный алмаз повреждается")
	assert_lt(diamond.durability_value, diamond.max_durability())
	assert_signal_emit_count(diamond, "settled", 1)
	assert_eq(diamond.rules.state, CarryRules.State.RESTING)


func test_partner_catches_throw() -> void:
	partner.global_position = Vector3(0.0, 0.0, -2.5)  # персонаж смотрит в -Z, партнёр на линии
	host_player.carry.pick_up()
	await wait_physics_frames(3)
	host_player.carry.throw_diamond()
	await wait_physics_frames(60)
	assert_eq(diamond.carrier_id, 2, "партнёр на линии броска ловит алмаз")
	assert_eq(get_signal_args(diamond, "caught"), [2, 1])
	assert_signal_not_emitted(diamond, "damaged")


func _spawn_player(peer_id: int, position: Vector3) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.position = position
	add_child_autofree(player)
	return player


static func _make_floor() -> StaticBody3D:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor.add_child(shape)
	floor.position = Vector3(0.0, -0.5, 0.0)
	return floor
