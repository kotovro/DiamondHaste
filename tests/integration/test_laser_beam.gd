extends GdUnitTestSuite
## Лазерный луч сам по себе: сцена луча на полу TestWorld, без тестового уровня (К1).
## Без сети: локальный пир (id 1) — хост; персонаж «1» — свой, персонаж «2» — чужой.
## Касание засчитывается по сигналу tripped(target, actor_id, point).

const LASER_SCENE := preload("res://scenes/props/laser_beam.tscn")
const LASER_CONFIG := preload("res://data/laser_config.tres")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DIAMOND_SCENE := preload("res://scenes/props/diamond.tscn")

const PLAYER := Obstacle.Target.PLAYER
const DIAMOND := Obstacle.Target.DIAMOND

## Где персонажи и алмаз ждут вдали от луча (луч — у начала координат).
const OWN_AWAY := Vector3(-3.0, 0.0, 6.0)
const FOREIGN_AWAY := Vector3(3.0, 0.0, 6.0)
## Алмаз лежит перед персонажем «1», в радиусе подбора.
const DIAMOND_AWAY := Vector3(-3.0, 0.25, 5.25)
## Сколько кадров физики ждать касания, прежде чем считать, что его нет.
const TOUCH_FRAMES := 5
## Расстояние от броска до луча по горизонтали, м: алмаз проходит луч уже на спуске.
const THROW_DISTANCE := 3.0
## Насколько центр брошенного алмаза должен подойти к оси луча, чтобы бросок считался «сквозь луч», м.
const THROUGH_BEAM := 0.1

var beam: LaserBeam
var beam_signals: SignalLog
var own: Player
var foreign: Player
var diamond: Diamond


func before_test() -> void:
	add_child(auto_free(TestWorld.make_floor(60.0)))
	own = _spawn_player(1, OWN_AWAY)
	foreign = _spawn_player(2, FOREIGN_AWAY)
	diamond = auto_free(DIAMOND_SCENE.instantiate())
	diamond.position = DIAMOND_AWAY
	add_child(diamond)
	own.carry.bind_diamond(diamond)
	foreign.carry.bind_diamond(diamond)
	await TestWorld.physics_frames(self, 10)


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_works_standalone() -> void:
	beam = auto_free(LASER_SCENE.instantiate())
	add_child(beam)
	beam_signals = SignalLog.watch(beam)
	assert_object(beam.config).override_failure_message("конфиг по умолчанию есть и без уровня").is_not_null()
	assert_bool(beam.is_in_group("obstacles")).is_true()
	assert_bool(beam.is_armed()).is_true()
	await TestWorld.physics_frames(self, 2)
	await _enter_beam(own)
	assert_int(beam_signals.count("tripped")).override_failure_message("луч без уровня срабатывает на персонажа (К1)").is_equal(1)


func test_touch_zone_matches_visible_beam() -> void:
	await _add_beam(true, Vector3(2.0, 0.0, -1.0), 3.5)
	var thickness := beam.config.beam_thickness
	var mesh_node := beam.get_node("%Beam") as MeshInstance3D
	var cylinder := mesh_node.mesh as CylinderMesh
	var shape_node := beam.get_node("%TouchShape") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D
	assert_object(cylinder).override_failure_message("%Beam — CylinderMesh").is_not_null()
	assert_object(box).override_failure_message("%TouchShape — BoxShape3D").is_not_null()

	assert_float(cylinder.height).override_failure_message("длина меша = length").is_equal_approx(beam.length, 0.001)
	assert_float(cylinder.top_radius * 2.0).override_failure_message("диаметр меша = beam_thickness").is_equal_approx(thickness, 0.001)
	assert_float(cylinder.bottom_radius * 2.0).is_equal_approx(thickness, 0.001)
	assert_vector(box.size).override_failure_message("зона касания (length, thickness, thickness)") \
		.is_equal_approx(Vector3(beam.length, thickness, thickness), Vector3.ONE * 0.001)

	var segment := beam.get_beam_segment()
	var axis := (segment[1] - segment[0]).normalized()
	var middle := _beam_middle()
	assert_float(absf(mesh_node.global_basis.y.normalized().dot(axis))) \
		.override_failure_message("ось цилиндра меша идёт вдоль луча").is_greater(0.999)
	assert_float(absf(shape_node.global_basis.x.normalized().dot(axis))) \
		.override_failure_message("длинная сторона зоны касания идёт вдоль луча").is_greater(0.999)
	assert_vector(mesh_node.global_position).override_failure_message("меш — посередине луча") \
		.is_equal_approx(middle, Vector3.ONE * 0.001)
	assert_vector(shape_node.global_position).override_failure_message("зона касания — там же, где меш") \
		.is_equal_approx(middle, Vector3.ONE * 0.001)


func test_beam_segment_follows_length_and_height() -> void:
	await _add_beam(true, Vector3(2.0, 0.0, -1.0), 3.5)
	var segment := beam.get_beam_segment()
	assert_int(segment.size()).is_equal(2)
	assert_float(segment[0].distance_to(segment[1])).is_equal_approx(3.5, 0.001)
	for point in segment:
		assert_float(point.y).override_failure_message("ось луча на beam_height над началом узла") \
			.is_equal_approx(beam.global_position.y + beam.config.beam_height, 0.001)
	assert_float(absf((segment[1] - segment[0]).normalized().dot(beam.global_basis.x))) \
		.override_failure_message("луч идёт вдоль локальной X").is_greater(0.999)


func test_touch_area_sees_players_and_diamond_only() -> void:
	await _add_beam()
	var area := beam.get_node("%TouchArea") as Area3D
	assert_int(area.collision_layer).override_failure_message("зону касания никто не видит").is_equal(0)
	assert_int(area.collision_mask).override_failure_message("слои players (2) и diamond (3)").is_equal(6)
	assert_bool(area.monitorable).is_false()


func test_player_without_diamond_trips() -> void:
	await _add_beam()
	await _enter_beam(own)
	assert_int(beam_signals.count("tripped")).is_equal(1)
	var args := beam_signals.args("tripped")
	assert_int(args[0]).override_failure_message("задел игрок").is_equal(PLAYER)
	assert_int(args[1]).override_failure_message("виновник — персонаж «1»").is_equal(1)
	_assert_on_beam(args[2])
	assert_bool(beam.is_tripped()).is_true()
	assert_bool(beam.is_armed()).override_failure_message("сработавший луч снят с взвода").is_false()


func test_carrier_trips() -> void:
	await _add_beam()
	own.carry.pick_up()
	assert_int(diamond.carrier_id).override_failure_message("подготовка: персонаж «1» несёт алмаз").is_equal(1)
	await TestWorld.physics_frames(self, 3)
	await _enter_beam(own)
	assert_int(beam_signals.count("tripped")).override_failure_message("носильщик в луче — срабатывание (К4)").is_equal(1)
	var args := beam_signals.args("tripped")
	assert_int(args[0]).override_failure_message("засчитывается тело носильщика, а не несомый алмаз").is_equal(PLAYER)
	assert_int(args[1]).is_equal(1)


func test_thrown_diamond_trips_when_reacting() -> void:
	await _throw_through_beam(true)
	assert_int(beam_signals.count("tripped")).override_failure_message("брошенный алмаз задел луч (К7, decision-03 B)").is_equal(1)
	var args := beam_signals.args("tripped")
	assert_int(args[0]).is_equal(DIAMOND)
	assert_int(args[1]).override_failure_message("у алмаза нет виновника-пира").is_equal(0)
	_assert_on_beam(args[2])


func test_thrown_diamond_ignored_when_not_reacting() -> void:
	await _throw_through_beam(false)
	assert_int(beam_signals.count("tripped")).override_failure_message("reacts_to_diamond = false: алмаз не засчитывается (К7)").is_equal(0)
	assert_bool(beam.is_armed()).is_true()


func test_resting_diamond_trips_when_reacting() -> void:
	await _rest_diamond_in_beam(true)
	assert_int(beam_signals.count("tripped")).override_failure_message("лежащий в луче алмаз — срабатывание (К7)").is_equal(1)
	var args := beam_signals.args("tripped")
	assert_int(args[0]).is_equal(DIAMOND)
	assert_int(args[1]).is_equal(0)


func test_resting_diamond_ignored_when_not_reacting() -> void:
	await _rest_diamond_in_beam(false)
	assert_int(beam_signals.count("tripped")).override_failure_message("reacts_to_diamond = false: лежащий алмаз не засчитывается (К7)").is_equal(0)


func test_foreign_player_ignored() -> void:
	await _add_beam()
	await _enter_beam(foreign)
	assert_int(beam_signals.count("tripped")).override_failure_message("чужого персонажа судит его владелец, не эта машина").is_equal(0)
	assert_bool(beam.is_armed()).is_true()


func test_trips_once_until_rearmed() -> void:
	await _add_beam(true)
	await _enter_beam(own)
	assert_int(beam_signals.count("tripped")).is_equal(1)

	await _leave_beam(own)
	await _enter_beam(own)
	assert_int(beam_signals.count("tripped")).override_failure_message("повторный вход до сброса не засчитывается (К12)").is_equal(1)
	await _put_diamond_in_beam()
	assert_int(beam_signals.count("tripped")).override_failure_message("второе тело до сброса не засчитывается (К12)").is_equal(1)

	await _leave_beam(own)
	diamond.global_position = DIAMOND_AWAY
	await TestWorld.physics_frames(self, TOUCH_FRAMES)
	beam.set_armed(true)
	assert_int(beam_signals.count("calmed")).override_failure_message("сработавший луч, взведённый снова, успокаивается").is_equal(1)
	assert_bool(beam.is_armed()).is_true()
	assert_bool(beam.is_tripped()).is_false()

	await _enter_beam(own)
	assert_int(beam_signals.count("tripped")).override_failure_message("после взвода луч снова срабатывает").is_equal(2)


func test_disarmed_ignores_touches() -> void:
	await _add_beam(true)
	beam.set_armed(false)
	assert_bool(beam.is_armed()).is_false()
	await _enter_beam(own)
	await _put_diamond_in_beam()
	assert_int(beam_signals.count("tripped")).override_failure_message("снятый с взвода луч не срабатывает").is_equal(0)
	assert_bool(beam.is_tripped()).is_false()
	beam.set_armed(true)
	assert_bool(beam.is_armed()).is_true()
	assert_int(beam_signals.count("calmed")).override_failure_message("calmed — только если луч срабатывал").is_equal(0)


# --- Помощники -----------------------------------------------------------------

## Луч на полу с копией конфига; узел и журнал сигналов — в beam / beam_signals.
func _add_beam(reacts_to_diamond: bool = true, at: Vector3 = Vector3.ZERO, length: float = -1.0) -> void:
	var config := LASER_CONFIG.duplicate() as LaserConfig
	config.reacts_to_diamond = reacts_to_diamond
	beam = auto_free(LASER_SCENE.instantiate())
	beam.config = config
	if length > 0.0:
		beam.length = length
	beam.position = at
	add_child(beam)
	beam_signals = SignalLog.watch(beam)
	await TestWorld.physics_frames(self, 2)


func _beam_middle() -> Vector3:
	var segment := beam.get_beam_segment()
	return (segment[0] + segment[1]) / 2.0


## Персонаж встаёт на пол посередине луча.
func _enter_beam(player: Player) -> void:
	var middle := _beam_middle()
	player.global_position = Vector3(middle.x, beam.global_position.y, middle.z)
	await TestWorld.physics_frames(self, TOUCH_FRAMES)


func _leave_beam(player: Player) -> void:
	player.global_position = OWN_AWAY if player == own else FOREIGN_AWAY
	await TestWorld.physics_frames(self, TOUCH_FRAMES)


## Свободный алмаз центром на оси луча.
func _put_diamond_in_beam() -> void:
	diamond.global_position = _beam_middle()
	await TestWorld.physics_frames(self, TOUCH_FRAMES)


## Персонаж «1» бросает алмаз; луч стоит поперёк полёта там, где алмаз проходит его ось
## на спуске (расчёт по throw_speed, throw_lift из конфига алмаза и гравитации проекта).
func _throw_through_beam(reacts_to_diamond: bool) -> void:
	own.carry.pick_up()
	assert_int(diamond.carrier_id).override_failure_message("подготовка: персонаж «1» несёт алмаз").is_equal(1)
	await TestWorld.physics_frames(self, 3)
	var start := diamond.global_position
	var forward := own.facing_direction()
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var t := THROW_DISTANCE / diamond.config.throw_speed
	var axis_height := start.y + diamond.config.throw_lift * t - gravity * t * t / 2.0
	var crossing := start + forward * THROW_DISTANCE
	crossing.y = axis_height
	await _add_beam(reacts_to_diamond)
	beam.global_basis = Basis(Vector3.UP, own.facing_yaw())  # луч поперёк направления броска
	beam.global_position += crossing - _beam_middle()
	await TestWorld.physics_frames(self, 2)
	assert_int(beam_signals.count("tripped")).override_failure_message("подготовка: до броска луч никого не задел").is_equal(0)

	own.carry.throw_diamond()
	var closest := INF
	for i in 90:
		await get_tree().physics_frame
		var segment := beam.get_beam_segment()
		closest = minf(closest, Geometry3D.get_closest_point_to_segment(diamond.global_position, segment[0], segment[1]).distance_to(diamond.global_position))
	assert_float(closest).override_failure_message("подготовка: брошенный алмаз прошёл сквозь луч (ближе всего %.2f м)" % closest) \
		.is_less(THROUGH_BEAM)


## Алмаз лежит на полу; луч ставится так, что его ось проходит через центр алмаза.
func _rest_diamond_in_beam(reacts_to_diamond: bool) -> void:
	own.global_position = Vector3(-10.0, 0.0, 10.0)
	await TestWorld.physics_frames(self, 60)
	assert_int(diamond.rules.state).override_failure_message("подготовка: алмаз лежит").is_equal(CarryRules.State.RESTING)
	var rest := diamond.global_position
	await _add_beam(reacts_to_diamond, Vector3(20.0, 0.0, 20.0))
	beam.global_position += rest - _beam_middle()
	await TestWorld.physics_frames(self, TOUCH_FRAMES)


func _assert_on_beam(point: Variant) -> void:
	assert_int(typeof(point)).override_failure_message("point — Vector3").is_equal(TYPE_VECTOR3)
	if typeof(point) != TYPE_VECTOR3:
		return
	var segment := beam.get_beam_segment()
	var on_axis := Geometry3D.get_closest_point_to_segment(point, segment[0], segment[1])
	assert_float(on_axis.distance_to(point)).override_failure_message("точка касания %s — на отрезке луча" % point).is_less(0.01)


func _spawn_player(peer_id: int, position: Vector3) -> Player:
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	player.name = str(peer_id)
	player.position = position
	add_child(player)
	return player
