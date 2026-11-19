extends GdUnitTestSuite
## Перенос алмаза целиком: действия компонента PlayerCarry (тот же путь, что от клавиш) →
## запросы Diamond.request_* → события. Настоящие персонажи и физика.
## Без сети: локальный пир (id 1) — хост; персонаж «2» стоит рядом как партнёр.

const DIAMOND_SCENE := preload("res://scenes/props/diamond.tscn")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var host_player: Player
var partner: Player
var diamond: Diamond
var diamond_signals: SignalLog
var host_signals: SignalLog
var partner_signals: SignalLog


func before_test() -> void:
	add_child(auto_free(TestWorld.make_floor(60.0)))
	host_player = _spawn_player(1, Vector3(0.0, 0.0, 0.0))
	partner = _spawn_player(2, Vector3(1.5, 0.0, 0.0))
	diamond = auto_free(DIAMOND_SCENE.instantiate())
	diamond.position = Vector3(0.0, 0.25, -0.75)
	add_child(diamond)
	host_player.carry.bind_diamond(diamond)
	partner.carry.bind_diamond(diamond)
	diamond_signals = SignalLog.watch(diamond)
	host_signals = SignalLog.watch(host_player.carry)
	partner_signals = SignalLog.watch(partner.carry)
	await TestWorld.physics_frames(self, 10)


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_pick_up_attaches_diamond_and_fires_events() -> void:
	host_player.carry.pick_up()
	assert_int(diamond.carrier_id).is_equal(1)
	assert_int(diamond_signals.count("picked_up")).is_equal(1)
	assert_array(diamond_signals.args("picked_up")).is_equal([1])
	assert_array(host_signals.args("carrying_changed")).is_equal([true])
	await TestWorld.physics_frames(self, 3)
	assert_float(diamond.global_position.distance_to(host_player.get_hold_transform().origin)).is_less(0.01)
	assert_bool(diamond.freeze).override_failure_message("несомый алмаз не симулируется").is_true()


func test_carrying_slows_down_and_blocks_jump() -> void:
	host_player.carry.pick_up()
	assert_float(host_player.carry.speed_multiplier()).is_equal_approx(host_player.carry.config.speed_multiplier, 0.0001)
	assert_bool(host_player.carry.can_jump()).is_false()
	assert_bool(host_player.carry.can_interact_with_objects()).is_false()


func test_pick_up_rejected_when_too_far() -> void:
	diamond.global_position = Vector3(0.0, 0.25, -6.0)
	await TestWorld.physics_frames(self, 2)
	host_player.carry.pick_up()
	assert_int(diamond.carrier_id).is_equal(0)
	assert_int(diamond_signals.count("picked_up")).is_equal(0)


func test_put_down_places_diamond_on_floor_without_damage() -> void:
	host_player.carry.pick_up()
	await TestWorld.physics_frames(self, 3)
	host_player.carry.put_down()
	assert_int(diamond.carrier_id).is_equal(0)
	assert_array(diamond_signals.args("put_down")).is_equal([1])
	assert_array(host_signals.args("carrying_changed")).is_equal([false])
	await TestWorld.physics_frames(self, 60)
	assert_float(diamond.global_position.y).override_failure_message("алмаз лежит у пола").is_less(0.4)
	assert_int(diamond_signals.count("damaged")).is_equal(0)


func test_stamina_depletion_puts_diamond_down() -> void:
	host_player.carry.pick_up()
	host_player.carry.stamina.tick(1000.0, true)
	assert_int(diamond.carrier_id).override_failure_message("кончилась выносливость — алмаз положен").is_equal(0)
	assert_int(diamond_signals.count("put_down")).is_equal(1)


func test_pass_to_partner() -> void:
	host_player.carry.pick_up()
	host_player.carry.pass_diamond()
	assert_int(diamond.carrier_id).is_equal(2)
	assert_array(diamond_signals.args("passed")).is_equal([1, 2])
	assert_bool(host_player.carry.is_carrying()).is_false()
	assert_bool(partner.carry.is_carrying()).is_true()
	assert_array(partner_signals.args("carrying_changed")).is_equal([true])


func test_throw_goes_where_player_faces() -> void:
	partner.global_position = Vector3(-20.0, 0.0, 0.0)  # убираем партнёра с линии броска
	host_player.body.rotation.y = -PI / 2.0  # персонаж смотрит в +X
	host_player.carry.pick_up()
	await TestWorld.physics_frames(self, 3)
	var start := diamond.global_position
	host_player.carry.throw_diamond()
	assert_array(diamond_signals.args("thrown")).is_equal([1])
	await TestWorld.physics_frames(self, 40)
	var moved := diamond.global_position - start
	assert_float(moved.x).override_failure_message("алмаз летит туда, куда повёрнут персонаж (+X)").is_greater(2.0)
	assert_float(absf(moved.z)).override_failure_message("а не вперёд по камере (-Z)").is_less(0.5)


func test_uncaught_throw_takes_damage_and_settles() -> void:
	partner.global_position = Vector3(20.0, 0.0, 0.0)
	host_player.carry.pick_up()
	await TestWorld.physics_frames(self, 3)
	host_player.carry.throw_diamond()
	assert_int(diamond.rules.state).is_equal(CarryRules.State.THROWN)
	await TestWorld.physics_frames(self, 180)
	assert_int(diamond_signals.count("damaged")).override_failure_message("непойманный алмаз повреждается").is_greater(0)
	assert_float(diamond.durability_value).is_less(diamond.max_durability())
	assert_int(diamond_signals.count("settled")).is_equal(1)
	assert_int(diamond.rules.state).is_equal(CarryRules.State.RESTING)


func test_partner_catches_throw() -> void:
	partner.global_position = Vector3(0.0, 0.0, -2.5)  # персонаж смотрит в -Z, партнёр на линии
	host_player.carry.pick_up()
	await TestWorld.physics_frames(self, 3)
	host_player.carry.throw_diamond()
	await TestWorld.physics_frames(self, 60)
	assert_int(diamond.carrier_id).override_failure_message("партнёр на линии броска ловит алмаз").is_equal(2)
	assert_array(diamond_signals.args("caught")).is_equal([2, 1])
	assert_int(diamond_signals.count("damaged")).is_equal(0)


func _spawn_player(peer_id: int, position: Vector3) -> Player:
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	player.name = str(peer_id)
	player.position = position
	add_child(player)
	return player
