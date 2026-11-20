extends GdUnitTestSuite
## Звук лазерного луча — компонент LaserAudio в laser_beam.tscn (plan.md F-001, «Звук»;
## docs/audio/SOUND.md). Гудение — петля у луча, пока он не сработал; по tripped гудение
## замолкает и звучит треск касания в точке касания; по calmed гудение возвращается.
## Звук — подписчик сигналов, без сети: у компонента нет RPC.
## Без сети: локальный пир (id 1) — хост; персонаж «1» — свой.
##
## «Играет» — это playing у плеера. Под --headless драйвер звука Dummy, но воспроизведение
## идёт: петля остаётся playing, короткий звук через свою длину перестаёт быть playing.
## Поэтому короткий треск проверяется снимком в момент сигнала (_on_tripped_snapshot),
## а не через кадры. Какой плеер чей, определяется по поведению: гудение — то, что играет
## после ready; треск — то, что заиграло по tripped. Имена узлов-плееров тест не знает.

const LASER_SCENE := preload("res://scenes/props/laser_beam.tscn")
const LASER_AUDIO_CONFIG := preload("res://data/laser_audio_config.tres")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## Шина звуков мира (plan.md, «Звук»; SOUND.md, «Шины»).
const SFX_BUS := &"SFX"
## Где персонаж ждёт вдали от луча (луч — у начала координат).
const OWN_AWAY := Vector3(-3.0, 0.0, 6.0)
## Сколько кадров физики ждать касания.
const TOUCH_FRAMES := 5
## Насколько гудение может отстоять от отрезка луча, м («3D, у луча»).
const HUM_NEAR_BEAM := 0.05

var beam: LaserBeam
var audio: LaserAudio
var beam_signals: SignalLog
var own: Player
## Плееры компонента, игравшие в момент обработки tripped, и точка касания из сигнала.
var _at_trip: Array[Node] = []
var _trip_point: Variant = null


func before_test() -> void:
	_at_trip = []
	_trip_point = null
	add_child(auto_free(TestWorld.make_floor(60.0)))
	own = auto_free(PLAYER_SCENE.instantiate())
	own.name = "1"
	own.position = OWN_AWAY
	add_child(own)
	await TestWorld.physics_frames(self, 5)


func after_test() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_hums_after_ready() -> void:
	await _add_beam()
	assert_bool(audio.is_humming()).override_failure_message("после ready взведённый луч гудит").is_true()
	var playing := _playing(audio)
	assert_int(playing.size()).override_failure_message("после ready играет ровно один звук — гудение").is_equal(1)
	if playing.size() != 1:
		return
	var hum := playing[0]
	assert_bool(hum is AudioStreamPlayer3D).override_failure_message("гудение — позиционное, AudioStreamPlayer3D (3D, у луча)").is_true()
	assert_bool(_is_looping(hum.get("stream"))).override_failure_message("гудение — петля").is_true()
	if hum is AudioStreamPlayer3D:
		var segment := beam.get_beam_segment()
		var at := (hum as AudioStreamPlayer3D).global_position
		var distance := Geometry3D.get_closest_point_to_segment(at, segment[0], segment[1]).distance_to(at)
		assert_float(distance).override_failure_message("гудение звучит у луча (%.2f м от его оси)" % distance).is_less(HUM_NEAR_BEAM)
	await TestWorld.physics_frames(self, 30)
	assert_bool(audio.is_humming()).override_failure_message("гудение не обрывается само").is_true()


func test_trip_stops_hum_and_zaps_at_touch_point() -> void:
	await _add_beam()
	var hum := _single_playing("подготовка: после ready играет одно гудение")
	await _enter_beam()
	assert_int(beam_signals.count("tripped")).override_failure_message("подготовка: персонаж «1» задел луч").is_equal(1)
	assert_bool(audio.is_humming()).override_failure_message("по tripped гудение замолкает").is_false()
	if hum:
		assert_bool(hum.get("playing")).override_failure_message("плеер гудения остановлен").is_false()

	assert_int(_at_trip.size()).override_failure_message("в момент tripped играет ровно один звук — треск касания").is_equal(1)
	if _at_trip.size() != 1:
		return
	var zap := _at_trip[0]
	assert_bool(zap != hum).override_failure_message("треск касания — свой звук, не гудение").is_true()
	assert_bool(zap is AudioStreamPlayer3D).override_failure_message("треск касания — позиционный, AudioStreamPlayer3D").is_true()
	assert_int(typeof(_trip_point)).override_failure_message("tripped передаёт точку касания").is_equal(TYPE_VECTOR3)
	if zap is AudioStreamPlayer3D and typeof(_trip_point) == TYPE_VECTOR3:
		assert_vector((zap as AudioStreamPlayer3D).global_position).override_failure_message("треск звучит в точке касания %s" % _trip_point) \
			.is_equal_approx(_trip_point, Vector3.ONE * 0.001)


func test_calm_resumes_hum() -> void:
	await _add_beam()
	var hum := _single_playing("подготовка: после ready играет одно гудение")
	await _enter_beam()
	assert_bool(audio.is_humming()).override_failure_message("подготовка: сработавший луч не гудит").is_false()
	own.global_position = OWN_AWAY
	await TestWorld.physics_frames(self, TOUCH_FRAMES)

	beam.set_armed(true)
	assert_int(beam_signals.count("calmed")).override_failure_message("подготовка: луч успокоился").is_equal(1)
	assert_bool(audio.is_humming()).override_failure_message("по calmed гудение снова идёт").is_true()
	if hum:
		assert_bool(hum.get("playing")).override_failure_message("снова играет тот же плеер гудения").is_true()


func test_players_use_existing_sfx_bus() -> void:
	await _add_beam()
	assert_int(AudioServer.get_bus_index(SFX_BUS)).override_failure_message("шина SFX есть в AudioServer (default_bus_layout.tres)").is_not_equal(-1)
	var players := _players(audio)
	assert_int(players.size()).override_failure_message("у LaserAudio есть плееры").is_greater(0)
	for player in players:
		assert_str(str(player.get("bus"))).override_failure_message("плеер %s — на шине SFX (plan.md, «Звук»)" % player.name).is_equal(str(SFX_BUS))


func test_scene_uses_config_from_data() -> void:
	beam = auto_free(LASER_SCENE.instantiate())
	audio = _find_audio(beam)
	assert_object(audio).override_failure_message("в laser_beam.tscn есть узел LaserAudio").is_not_null()
	if audio == null:
		return
	assert_object(audio.config).override_failure_message("у LaserAudio в сцене задан конфиг").is_not_null()
	if audio.config:
		assert_str(audio.config.resource_path).override_failure_message("конфиг звука луча — data/laser_audio_config.tres") \
			.is_equal(LASER_AUDIO_CONFIG.resource_path)


func test_config_numbers_reach_players() -> void:
	# Копия конфига со сдвинутыми числами: так видно, что плееры берут значения из конфига.
	var config := LASER_AUDIO_CONFIG.duplicate() as LaserAudioConfig
	config.hum_volume_db += 1.5
	config.hum_max_distance += 1.0
	config.hum_unit_size += 0.5
	config.zap_volume_db -= 2.0
	config.zap_max_distance += 5.0
	await _add_beam(config)
	var hum := _single_playing("подготовка: после ready играет одно гудение") as AudioStreamPlayer3D
	assert_object(hum).override_failure_message("гудение — AudioStreamPlayer3D").is_not_null()
	if hum:
		assert_float(hum.volume_db).override_failure_message("гудение: volume_db = hum_volume_db").is_equal_approx(config.hum_volume_db, 0.001)
		assert_float(hum.max_distance).override_failure_message("гудение: max_distance = hum_max_distance").is_equal_approx(config.hum_max_distance, 0.001)
		assert_float(hum.unit_size).override_failure_message("гудение: unit_size = hum_unit_size").is_equal_approx(config.hum_unit_size, 0.001)

	await _enter_beam()
	assert_int(_at_trip.size()).override_failure_message("подготовка: по tripped играет один звук").is_equal(1)
	if _at_trip.size() != 1:
		return
	var zap := _at_trip[0] as AudioStreamPlayer3D
	assert_object(zap).override_failure_message("треск — AudioStreamPlayer3D").is_not_null()
	if zap:
		assert_float(zap.volume_db).override_failure_message("треск: volume_db = zap_volume_db").is_equal_approx(config.zap_volume_db, 0.001)
		assert_float(zap.max_distance).override_failure_message("треск: max_distance = zap_max_distance").is_equal_approx(config.zap_max_distance, 0.001)


func test_audio_has_no_rpc() -> void:
	await _add_beam()
	var rpc_config: Variant = (audio.get_script() as Script).get_rpc_config()
	assert_bool(rpc_config is Dictionary).override_failure_message("RPC-конфиг скрипта читается").is_true()
	if rpc_config is Dictionary:
		assert_array((rpc_config as Dictionary).keys()).override_failure_message("звук не идёт по сети: у LaserAudio нет @rpc-методов (SOUND.md)").is_empty()


# --- Помощники -----------------------------------------------------------------

## Луч на полу у начала координат; config — конфиг звука вместо того, что в сцене.
func _add_beam(config: LaserAudioConfig = null) -> void:
	beam = auto_free(LASER_SCENE.instantiate())
	audio = _find_audio(beam)
	assert_object(audio).override_failure_message("в laser_beam.tscn есть узел LaserAudio").is_not_null()
	if audio and config:
		audio.config = config
	add_child(beam)
	beam_signals = SignalLog.watch(beam)
	# Отложенно: снимок после того, как все подписчики (и LaserAudio) обработали сигнал.
	beam.tripped.connect(_on_tripped_snapshot, CONNECT_DEFERRED)
	await TestWorld.physics_frames(self, 2)


func _on_tripped_snapshot(_target: int, _actor_id: int, point: Vector3) -> void:
	_trip_point = point
	_at_trip = _playing(audio)


## Персонаж «1» встаёт на пол посередине луча.
func _enter_beam() -> void:
	var segment := beam.get_beam_segment()
	var middle := (segment[0] + segment[1]) / 2.0
	own.global_position = Vector3(middle.x, beam.global_position.y, middle.z)
	await TestWorld.physics_frames(self, TOUCH_FRAMES)


func _single_playing(message: String) -> Node:
	var playing := _playing(audio)
	assert_int(playing.size()).override_failure_message(message).is_equal(1)
	return playing[0] if playing.size() == 1 else null


func _find_audio(root: Node) -> LaserAudio:
	for node in root.find_children("*", "", true, false):
		if node is LaserAudio:
			return node
	return null


## Все аудиоплееры внутри узла (любого вида).
static func _players(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	if root == null:
		return result
	for node in root.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			result.append(node)
	return result


static func _playing(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	for player in _players(root):
		if player.get("playing"):
			result.append(player)
	return result


static func _is_looping(stream: Variant) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	if stream is AudioStreamMP3:
		return (stream as AudioStreamMP3).loop
	return false
