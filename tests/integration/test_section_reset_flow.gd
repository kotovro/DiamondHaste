extends GdUnitTestSuite
## Сброс секции целиком (docs/tech/obstacles.md, раздел 4): причина (луч или разрушение алмаза)
## → SectionRoot.report_caught → тревога и пауза → сброс: персонажи на точках появления,
## алмаз на старте целым, луч снова взведён.
## Без сети: локальный пир (id 1) — хост; персонаж «1» — свой, «2» — чужой (стоит на своей точке).
## Состояние в момент сброса снимается обработчиком section_reset (_snapshot).

const LASER_SCENE := preload("res://scenes/props/laser_beam.tscn")
const LASER_CONFIG := preload("res://data/laser_config.tres")
const SECTION_CONFIG := preload("res://data/section_config.tres")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DIAMOND_SCENE := preload("res://scenes/props/diamond.tscn")

const SECTION_ID := "test_flow"
## Пауза до сброса в тестах, с: короче настоящей, но заметно дольше кадра.
const TEST_RESET_DELAY := 0.25
## Пауза для теста, который во время неё делает несколько касаний, с.
const LONG_RESET_DELAY := 0.8
## Сколько кадров физики ждать события, прежде чем считать, что его не будет.
const MAX_WAIT_FRAMES := 240
## Сколько кадров физики ждать касания.
const TOUCH_FRAMES := 5

const HOST_SPAWN := Vector3(-1.5, 0.1, 8.0)
const CLIENT_SPAWN := Vector3(1.5, 0.1, 8.0)
## Алмаз лежит перед персонажем «1» на его точке появления — в радиусе подбора.
const DIAMOND_START := Vector3(-1.5, 0.25, 7.25)
## Место в стороне от луча и от точек появления.
const ASIDE := Vector3(-6.0, 0.0, 3.0)

var section: SectionRoot
var beam: LaserBeam
var diamond: Diamond
var own: Player
var foreign: Player
var section_signals: SignalLog
var beam_signals: SignalLog
var diamond_signals: SignalLog
var _diamond_start: Vector3
var _snapshot: Dictionary


func after_test() -> void:
	Input.action_release("move_forward")
	Input.action_release("jump")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_player_caught_resets_section() -> void:
	await _build()
	await _enter_beam(own)
	assert_int(section_signals.count("alarm_started")).is_equal(1)
	assert_array(section_signals.args("alarm_started")).is_equal([SectionReset.Cause.PLAYER_CAUGHT, 1])
	assert_bool(section.is_alarm()).is_true()
	assert_bool(own.is_controls_locked()).override_failure_message("на паузе управление своим персонажем заблокировано (T-20)").is_true()
	assert_bool(beam.is_armed()).override_failure_message("на паузе препятствия сняты с взвода").is_false()
	assert_int(section_signals.count("section_reset")).override_failure_message("сброс — после паузы, а не сразу").is_equal(0)
	await _wait_for_reset()
	_assert_section_restored()


func test_caught_carrier_resets_diamond_to_pedestal() -> void:
	await _build()
	own.carry.pick_up()
	assert_int(diamond.carrier_id).override_failure_message("подготовка: персонаж «1» несёт алмаз").is_equal(1)
	await TestWorld.physics_frames(self, 3)
	await _enter_beam(own)
	assert_array(section_signals.args("alarm_started")).is_equal([SectionReset.Cause.PLAYER_CAUGHT, 1])
	await _wait_for_reset()
	_assert_section_restored()
	assert_bool(own.carry.is_carrying()).override_failure_message("после сброса алмаз никто не несёт").is_false()


func test_diamond_touch_resets_section() -> void:
	await _build()
	await _move(own, ASIDE)
	diamond.global_position = _beam_middle()
	await _wait_for_alarm()
	assert_array(beam_signals.args("tripped").slice(0, 2)).is_equal([Obstacle.Target.DIAMOND, 0])
	assert_int(section_signals.count("alarm_started")).is_equal(1)
	assert_array(section_signals.args("alarm_started")).is_equal([SectionReset.Cause.DIAMOND_TOUCHED, 0])
	assert_bool(own.is_controls_locked()).is_true()
	await _wait_for_reset()
	_assert_section_restored()


func test_diamond_destroyed_gives_same_reset() -> void:
	await _build()
	await _move(own, ASIDE)
	diamond.global_position = Vector3(0.0, diamond.config.kill_height - 1.0, 20.0)
	await _wait_for_alarm()
	assert_int(diamond_signals.count("destroyed")).override_failure_message("подготовка: алмаз разрушен").is_equal(1)
	assert_int(section_signals.count("alarm_started")).override_failure_message("разрушение идёт тем же путём, что и луч (К11)").is_equal(1)
	assert_array(section_signals.args("alarm_started")).is_equal([SectionReset.Cause.DIAMOND_DESTROYED, 0])
	assert_bool(own.is_controls_locked()).is_true()
	assert_int(section_signals.count("section_reset")).override_failure_message("разрушение — тоже с паузой").is_equal(0)
	await _wait_for_reset()
	_assert_section_restored()


func test_one_alarm_one_reset() -> void:
	await _build(LONG_RESET_DELAY)
	await _enter_beam(own)
	assert_int(section_signals.count("alarm_started")).is_equal(1)

	# Во время паузы: повторный вход, касание алмазом, касание напарника, разрушение алмаза.
	await _move(own, ASIDE)
	await _enter_beam(own)
	diamond.global_position = _beam_middle()
	await TestWorld.physics_frames(self, TOUCH_FRAMES)
	section.report_caught(SectionReset.Cause.PLAYER_CAUGHT, 2)
	diamond.global_position = Vector3(0.0, diamond.config.kill_height - 1.0, 20.0)
	await TestWorld.physics_frames(self, TOUCH_FRAMES)
	assert_int(diamond_signals.count("destroyed")).override_failure_message("подготовка: алмаз разрушен во время паузы").is_equal(1)
	assert_int(section_signals.count("section_reset")).override_failure_message("подготовка: всё это случилось до сброса").is_equal(0)

	await _wait_for_reset()
	await TestWorld.physics_frames(self, ceili(LONG_RESET_DELAY * 2.0 * Engine.physics_ticks_per_second))
	assert_int(section_signals.count("alarm_started")).override_failure_message("одно срабатывание — одна тревога (К12)").is_equal(1)
	assert_int(section_signals.count("section_reset")).override_failure_message("одно срабатывание — один сброс (К12)").is_equal(1)
	assert_int(diamond_signals.count("restored")).override_failure_message("алмаз возвращается один раз").is_equal(1)
	assert_int(beam_signals.count("tripped")).is_equal(1)
	assert_array(section_signals.args("alarm_started")).override_failure_message("причина — первая").is_equal([SectionReset.Cause.PLAYER_CAUGHT, 1])
	_assert_section_restored()


func test_no_trip_right_after_reset() -> void:
	await _build()
	await _enter_beam(own)
	await _wait_for_reset()
	await TestWorld.physics_frames(self, 30)
	assert_int(section_signals.count("alarm_started")).override_failure_message("после сброса луч сам не срабатывает (К13)").is_equal(1)
	assert_int(beam_signals.count("tripped")).is_equal(1)
	assert_int(section_signals.count("section_reset")).is_equal(1)
	assert_bool(beam.is_armed()).is_true()
	assert_bool(section.is_alarm()).is_false()


func test_reset_survives_partner_disconnect() -> void:
	await _build()
	await _move(foreign, HOST_SPAWN + Vector3(1.5, 0.0, 0.0))
	own.carry.pick_up()
	own.carry.pass_diamond()
	assert_int(diamond.carrier_id).override_failure_message("подготовка: алмаз у персонажа «2»").is_equal(2)
	await TestWorld.physics_frames(self, 3)
	await _enter_beam(own)
	assert_int(section_signals.count("alarm_started")).is_equal(1)

	multiplayer.peer_disconnected.emit(2)
	foreign.queue_free()
	await _wait_for_reset()
	_assert_section_restored()


func test_respawn_moves_only_own_player() -> void:
	await _build()
	await _move(own, ASIDE)
	await _move(foreign, ASIDE + Vector3(3.0, 0.0, 0.0))
	var foreign_before := foreign.global_position
	own.velocity = Vector3(3.0, 0.0, 0.0)
	own.respawn()
	foreign.respawn()
	assert_vector(own.global_position).override_failure_message("свой персонаж — на своей точке появления") \
		.is_equal_approx(HOST_SPAWN, Vector3.ONE * 0.001)
	assert_vector(own.velocity).is_equal(Vector3.ZERO)
	assert_vector(foreign.global_position).override_failure_message("чужого персонажа переносит его владелец") \
		.is_equal_approx(foreign_before, Vector3.ONE * 0.001)


func test_respawn_is_not_rpc() -> void:
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	var rpc_config: Variant = (player.get_script() as Script).get_rpc_config()
	assert_bool(rpc_config is Dictionary and (rpc_config as Dictionary).has("respawn")) \
		.override_failure_message("Player.respawn — обычный метод, не RPC (T-19)").is_false()


func test_caught_feedback_marks_only_culprit() -> void:
	await _build()
	assert_bool(own.caught_feedback.is_showing()).is_false()
	await _enter_beam(own)
	assert_bool(own.caught_feedback.is_showing()).override_failure_message("задевший персонаж показывает «поимку»").is_true()
	assert_bool(foreign.caught_feedback.is_showing()).override_failure_message("незадевший — нет").is_false()
	await _wait_for_reset()
	assert_bool(own.caught_feedback.is_showing()).override_failure_message("после сброса — как было").is_false()
	assert_bool(foreign.caught_feedback.is_showing()).is_false()


func test_obstacle_with_none_consequence_does_not_reset() -> void:
	await _build(TEST_RESET_DELAY, Obstacle.Consequence.NONE)
	await _enter_beam(own)
	assert_int(beam_signals.count("tripped")).override_failure_message("луч срабатывает").is_equal(1)
	assert_int(section_signals.count("alarm_started")).override_failure_message("последствие NONE — без тревоги секции").is_equal(0)
	assert_bool(section.is_alarm()).is_false()
	assert_bool(own.is_controls_locked()).is_false()
	await TestWorld.physics_frames(self, ceili(TEST_RESET_DELAY * 2.0 * Engine.physics_ticks_per_second))
	assert_int(section_signals.count("section_reset")).is_equal(0)


func test_controls_stay_free_when_config_disables_lock() -> void:
	await _build(TEST_RESET_DELAY, Obstacle.Consequence.SECTION_RESET, false)
	await _enter_beam(own)
	assert_int(section_signals.count("alarm_started")).is_equal(1)
	assert_bool(own.is_controls_locked()).override_failure_message("lock_controls_during_alarm = false").is_false()
	await _wait_for_reset()
	assert_int(section_signals.count("section_reset")).is_equal(1)


func test_locked_player_ignores_move_and_jump() -> void:
	await _build()
	own.set_controls_locked(true)
	assert_bool(own.is_controls_locked()).is_true()
	var start := own.global_position
	var highest := start.y
	Input.action_press("move_forward")
	Input.action_press("jump")
	for i in 20:
		await get_tree().physics_frame
		highest = maxf(highest, own.global_position.y)
	Input.action_release("move_forward")
	Input.action_release("jump")
	var moved := own.global_position - start
	assert_float(Vector2(moved.x, moved.z).length()).override_failure_message("при блоке персонаж не идёт").is_less(0.01)
	assert_float(highest - start.y).override_failure_message("при блоке персонаж не прыгает").is_less(0.01)

	# Тот же ввод без блока двигает персонажа — значит, ввод в тесте доходит.
	own.set_controls_locked(false)
	await TestWorld.physics_frames(self, 2)
	start = own.global_position
	highest = start.y
	Input.action_press("move_forward")
	Input.action_press("jump")
	for i in 20:
		await get_tree().physics_frame
		highest = maxf(highest, own.global_position.y)
	Input.action_release("move_forward")
	Input.action_release("jump")
	moved = own.global_position - start
	assert_float(Vector2(moved.x, moved.z).length()).override_failure_message("без блока персонаж идёт").is_greater(0.3)
	assert_float(highest - start.y).override_failure_message("без блока персонаж прыгает").is_greater(0.3)


# --- Подключившийся во время паузы: _apply_full_state (plan.md, таблица RPC) -----
# Прямой вызов на этой машине — то, что выполняет подключившийся пир по rpc_id от хоста.

func test_full_state_alarm_puts_section_into_alarm_like_event() -> void:
	await _build()
	section._apply_full_state(true, SectionReset.Cause.PLAYER_CAUGHT, 2)
	# Те же наблюдаемые признаки, что после события тревоги (test_player_caught_resets_section).
	assert_bool(section.is_alarm()).override_failure_message("подключившийся видит секцию в тревоге").is_true()
	assert_int(section.rules.cause).override_failure_message("причина — как у хоста").is_equal(SectionReset.Cause.PLAYER_CAUGHT)
	assert_int(section.rules.actor_id).override_failure_message("виновник — как у хоста").is_equal(2)
	assert_bool(beam.is_armed()).override_failure_message("на паузе препятствия сняты с взвода").is_false()

	await _enter_beam(own)
	assert_int(beam_signals.count("tripped")).override_failure_message("во время переданной тревоги луч не срабатывает").is_equal(0)
	section.report_caught(SectionReset.Cause.DIAMOND_DESTROYED, 0)
	assert_int(section_signals.count("alarm_started")).override_failure_message("во время переданной тревоги новые причины отбрасываются (К12)").is_equal(0)
	assert_int(section.rules.cause).override_failure_message("причина не перезаписана").is_equal(SectionReset.Cause.PLAYER_CAUGHT)

	await TestWorld.physics_frames(self, ceili(TEST_RESET_DELAY * 2.0 * Engine.physics_ticks_per_second))
	assert_int(section_signals.count("section_reset")).override_failure_message("сброс подключившемуся присылает хост; сам он паузу не отсчитывает").is_equal(0)
	assert_bool(section.is_alarm()).is_true()

	section._apply_section_reset()
	assert_int(section_signals.count("section_reset")).is_equal(1)
	assert_array(section_signals.args("section_reset")).is_equal([SECTION_ID])
	assert_bool(section.is_alarm()).override_failure_message("после сброса от хоста секция снова ACTIVE").is_false()
	assert_bool(beam.is_armed()).override_failure_message("после сброса от хоста луч взведён").is_true()

	await TestWorld.physics_frames(self, TOUCH_FRAMES)  # сброс унёс персонажа из луча — пусть зона это увидит
	await _enter_beam(own)
	assert_int(section_signals.count("alarm_started")).override_failure_message("после сброса секция снова ловит").is_equal(1)
	assert_array(section_signals.args("alarm_started")).is_equal([SectionReset.Cause.PLAYER_CAUGHT, 1])


func test_full_state_keeps_diamond_cause_and_no_actor() -> void:
	await _build()
	section._apply_full_state(true, SectionReset.Cause.DIAMOND_DESTROYED, 0)
	assert_bool(section.is_alarm()).is_true()
	assert_int(section.rules.cause).is_equal(SectionReset.Cause.DIAMOND_DESTROYED)
	assert_int(section.rules.actor_id).is_equal(0)
	assert_bool(beam.is_armed()).is_false()


func test_full_state_without_alarm_changes_nothing() -> void:
	await _build()
	section._apply_full_state(false, SectionReset.Cause.PLAYER_CAUGHT, 0)
	assert_bool(section.is_alarm()).override_failure_message("без тревоги у хоста секция остаётся ACTIVE").is_false()
	assert_bool(beam.is_armed()).is_true()
	assert_int(section_signals.count("alarm_started")).is_equal(0)
	assert_int(section_signals.count("section_reset")).is_equal(0)
	await _enter_beam(own)
	assert_int(section_signals.count("alarm_started")).override_failure_message("секция ловит как обычно").is_equal(1)


# --- Поза поимки (review №1): наклоняется нереплицируемый Body/Pose ----------------

func test_caught_pose_tilts_pose_not_replicated_body() -> void:
	await _build()
	var own_pose := own.pose.rotation
	var own_body := own.body.rotation
	var foreign_pose := foreign.pose.rotation
	section.report_caught(SectionReset.Cause.PLAYER_CAUGHT, 1)
	assert_int(section_signals.count("alarm_started")).override_failure_message("подготовка: тревога началась").is_equal(1)
	assert_bool(own.pose.rotation.is_equal_approx(own_pose)).override_failure_message("у задевшего наклонена поза (Body/Pose)").is_false()
	assert_vector(own.body.rotation).override_failure_message("Body:rotation (реплицируется синхронизатором) не трогается позой поимки") \
		.is_equal_approx(own_body, Vector3.ONE * 0.0001)
	assert_vector(foreign.pose.rotation).override_failure_message("у незадевшего поза прежняя") \
		.is_equal_approx(foreign_pose, Vector3.ONE * 0.0001)

	await _wait_for_reset()
	assert_int(section_signals.count("section_reset")).override_failure_message("подготовка: сброс случился").is_equal(1)
	assert_vector(own.pose.rotation).override_failure_message("на section_reset поза возвращается") \
		.is_equal_approx(own_pose, Vector3.ONE * 0.0001)


func test_caught_pose_of_foreign_culprit_shown_here() -> void:
	await _build()
	var foreign_pose := foreign.pose.rotation
	var foreign_body := foreign.body.rotation
	section.report_caught(SectionReset.Cause.PLAYER_CAUGHT, 2)
	assert_bool(foreign.pose.rotation.is_equal_approx(foreign_pose)) \
		.override_failure_message("позу чужого задевшего эта машина показывает сама, по событию").is_false()
	assert_vector(foreign.body.rotation).override_failure_message("Body:rotation чужого персонажа не трогается") \
		.is_equal_approx(foreign_body, Vector3.ONE * 0.0001)
	await _wait_for_reset()
	assert_vector(foreign.pose.rotation).is_equal_approx(foreign_pose, Vector3.ONE * 0.0001)


func test_caught_pose_node_not_replicated() -> void:
	var player := _spawn_player(1, ASIDE)
	var sync := player.find_children("*", "MultiplayerSynchronizer", true, false)
	assert_int(sync.size()).override_failure_message("подготовка: у персонажа один синхронизатор").is_equal(1)
	var pose_path := str(player.get_path_to(player.pose))
	for path: NodePath in (sync[0] as MultiplayerSynchronizer).replication_config.get_properties():
		assert_bool(str(path).begins_with(pose_path)) \
			.override_failure_message("%s реплицируется синхронизатором — поза поимки должна идти только событием" % path).is_false()


# --- Сборка сцены ----------------------------------------------------------------

## Пол, точки появления, секция с лучом у начала координат, алмаз, персонажи «1» и «2».
func _build(reset_delay: float = TEST_RESET_DELAY,
		consequence: Obstacle.Consequence = Obstacle.Consequence.SECTION_RESET,
		lock_controls: bool = true) -> void:
	add_child(auto_free(TestWorld.make_floor(60.0)))
	var spawns: Node3D = auto_free(Node3D.new())
	spawns.name = "SpawnPoints"
	for point in [HOST_SPAWN, CLIENT_SPAWN]:
		var marker := Marker3D.new()
		marker.position = point
		marker.add_to_group("spawn_points")
		spawns.add_child(marker)
	add_child(spawns)

	var section_config := SECTION_CONFIG.duplicate() as SectionConfig
	section_config.reset_delay = reset_delay
	section_config.lock_controls_during_alarm = lock_controls
	var laser_config := LASER_CONFIG.duplicate() as LaserConfig
	laser_config.reacts_to_diamond = true
	laser_config.consequence = consequence

	section = auto_free(SectionRoot.new())
	section.name = "Section"
	section.section_id = SECTION_ID
	section.config = section_config
	var obstacles := Node3D.new()
	obstacles.name = "Obstacles"
	section.add_child(obstacles)
	beam = LASER_SCENE.instantiate()
	beam.config = laser_config
	obstacles.add_child(beam)
	add_child(section)

	diamond = auto_free(DIAMOND_SCENE.instantiate())
	diamond.position = DIAMOND_START
	add_child(diamond)
	_diamond_start = diamond.global_position
	section.bind_diamond(diamond)

	own = _spawn_player(1, HOST_SPAWN)
	foreign = _spawn_player(2, CLIENT_SPAWN)
	for player: Player in [own, foreign]:
		player.carry.bind_diamond(diamond)
		player.caught_feedback.bind_section(section)

	section_signals = SignalLog.watch(section)
	beam_signals = SignalLog.watch(beam)
	diamond_signals = SignalLog.watch(diamond)
	_snapshot = {}
	section.section_reset.connect(_take_snapshot)
	await TestWorld.physics_frames(self, 10)


## Состояние ровно в момент section_reset.
func _take_snapshot(_section_id: String) -> void:
	_snapshot = {
		"own_position": own.global_position,
		"own_locked": own.is_controls_locked(),
		"diamond_position": diamond.global_position,
		"durability": diamond.durability_value,
		"carrier_id": diamond.carrier_id,
		"beam_armed": beam.is_armed(),
		"beam_tripped": beam.is_tripped(),
		"alarm": section.is_alarm(),
	}


## Сброс выполнен: персонаж «1» на своей точке, алмаз на старте целым и ничей, луч взведён,
## управление свободно, section_reset — один раз.
func _assert_section_restored() -> void:
	assert_int(section_signals.count("section_reset")).override_failure_message("сброс случился один раз").is_equal(1)
	if _snapshot.is_empty():
		return
	assert_array(section_signals.args("section_reset")).is_equal([SECTION_ID])
	assert_vector(_snapshot.own_position).override_failure_message("персонаж «1» на своей точке появления") \
		.is_equal_approx(HOST_SPAWN, Vector3.ONE * 0.01)
	assert_bool(_snapshot.own_locked).override_failure_message("после сброса управление свободно").is_false()
	assert_vector(_snapshot.diamond_position).override_failure_message("алмаз на старте (постаменте)") \
		.is_equal_approx(_diamond_start, Vector3.ONE * 0.01)
	assert_float(_snapshot.durability).override_failure_message("прочность полная").is_equal(diamond.max_durability())
	assert_int(_snapshot.carrier_id).override_failure_message("алмаз никто не несёт").is_equal(0)
	assert_bool(_snapshot.beam_armed).override_failure_message("луч снова взведён").is_true()
	assert_bool(_snapshot.beam_tripped).override_failure_message("луч в исходном состоянии").is_false()
	assert_bool(_snapshot.alarm).override_failure_message("тревога закончилась").is_false()
	assert_bool(section.is_alarm()).is_false()


# --- Помощники -----------------------------------------------------------------

func _beam_middle() -> Vector3:
	var segment := beam.get_beam_segment()
	return (segment[0] + segment[1]) / 2.0


## Персонаж встаёт на пол посередине луча.
func _enter_beam(player: Player) -> void:
	var middle := _beam_middle()
	await _move(player, Vector3(middle.x, beam.global_position.y, middle.z))


func _move(player: Player, position: Vector3) -> void:
	player.global_position = position
	await TestWorld.physics_frames(self, TOUCH_FRAMES)


func _wait_for_alarm() -> void:
	for i in MAX_WAIT_FRAMES:
		if section_signals.count("alarm_started") > 0:
			return
		await get_tree().physics_frame


func _wait_for_reset() -> void:
	for i in MAX_WAIT_FRAMES:
		if section_signals.count("section_reset") > 0:
			return
		await get_tree().physics_frame


func _spawn_player(peer_id: int, position: Vector3) -> Player:
	var player: Player = auto_free(PLAYER_SCENE.instantiate())
	player.name = str(peer_id)
	player.position = position
	add_child(player)
	return player
