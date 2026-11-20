extends GdUnitTestSuite
## Звук секции — компонент SectionAudio, узел Section/SectionAudio в test_level.tscn
## (plan.md F-001, «Звук»; docs/audio/SOUND.md). По alarm_started играет сирена — петля
## без позиции; по section_reset сирена обрывается и звучит сброс («перемотка»).
## Звук — подписчик сигналов, без сети: у компонента нет RPC.
## Тревога и сброс идут настоящим путём: SectionRoot.report_caught на локальном пире (он же
## хост), пауза до сброса — копия конфига секции с короткой reset_delay.
##
## «Играет» — это playing у плеера (под --headless драйвер Dummy, воспроизведение идёт:
## петля остаётся playing, короткий звук через свою длину перестаёт). Короткий звук сброса
## проверяется снимком в момент сигнала (_on_reset_snapshot). Какой плеер чей, определяется
## по поведению: сирена — то, что заиграло по alarm_started; сброс — то, что заиграло по
## section_reset. Имена узлов-плееров тест не знает.

const LEVEL_SCENE := preload("res://scenes/level/test_level.tscn")
const SECTION_CONFIG := preload("res://data/section_config.tres")
const SECTION_AUDIO_CONFIG := preload("res://data/section_audio_config.tres")

## Шина звуков мира (plan.md, «Звук»; SOUND.md, «Шины»).
const SFX_BUS := &"SFX"
## Пауза до сброса в тестах, с: короче настоящей, но заметно дольше кадра.
const TEST_RESET_DELAY := 0.25
## Сколько кадров физики ждать сброса, прежде чем считать, что его не будет.
const MAX_WAIT_FRAMES := 240

var level: Node3D
var section: SectionRoot
var audio: SectionAudio
var section_signals: SignalLog
## Плееры компонента, игравшие в момент обработки section_reset.
var _at_reset: Array[Node] = []
var _siren_at_reset := true


func before_test() -> void:
	_at_reset = []
	_siren_at_reset = true


func test_quiet_before_alarm() -> void:
	await _build()
	assert_bool(audio.is_siren_playing()).override_failure_message("до тревоги сирены нет").is_false()
	assert_array(_playing(audio)).override_failure_message("до тревоги звук секции молчит").is_empty()


func test_alarm_starts_siren() -> void:
	await _build()
	section.report_caught(SectionReset.Cause.PLAYER_CAUGHT, 1)
	assert_int(section_signals.count("alarm_started")).override_failure_message("подготовка: началась тревога").is_equal(1)
	assert_bool(audio.is_siren_playing()).override_failure_message("по alarm_started играет сирена").is_true()
	var playing := _playing(audio)
	assert_int(playing.size()).override_failure_message("на тревоге играет ровно один звук — сирена").is_equal(1)
	if playing.size() != 1:
		return
	var siren := playing[0]
	assert_bool(siren is AudioStreamPlayer).override_failure_message("сирена без позиции — AudioStreamPlayer (слышно в любой точке, К17)").is_true()
	assert_bool(_is_looping(siren.get("stream"))).override_failure_message("сирена — петля").is_true()
	await TestWorld.physics_frames(self, 5)
	assert_bool(audio.is_siren_playing()).override_failure_message("сирена звучит всю паузу до сброса").is_true()


func test_reset_stops_siren_and_plays_reset_sound() -> void:
	await _build()
	section.report_caught(SectionReset.Cause.PLAYER_CAUGHT, 1)
	var siren := _single_playing("подготовка: на тревоге играет одна сирена")
	await _wait_for_reset()
	assert_int(section_signals.count("section_reset")).override_failure_message("подготовка: сброс случился").is_equal(1)
	assert_bool(_siren_at_reset).override_failure_message("по section_reset сирена обрывается").is_false()
	assert_bool(audio.is_siren_playing()).override_failure_message("после сброса сирены нет").is_false()

	assert_int(_at_reset.size()).override_failure_message("в момент section_reset играет ровно один звук — сброс").is_equal(1)
	if _at_reset.size() != 1:
		return
	var reset := _at_reset[0]
	assert_bool(reset != siren).override_failure_message("звук сброса — свой, не сирена").is_true()
	assert_bool(reset is AudioStreamPlayer).override_failure_message("звук сброса без позиции — AudioStreamPlayer (2D)").is_true()


func test_siren_again_on_next_alarm() -> void:
	await _build()
	section.report_caught(SectionReset.Cause.PLAYER_CAUGHT, 1)
	await _wait_for_reset()
	section.report_caught(SectionReset.Cause.DIAMOND_TOUCHED, 0)
	assert_int(section_signals.count("alarm_started")).override_failure_message("подготовка: вторая тревога").is_equal(2)
	assert_bool(audio.is_siren_playing()).override_failure_message("на следующей тревоге сирена снова играет").is_true()


func test_players_use_existing_sfx_bus() -> void:
	await _build()
	assert_int(AudioServer.get_bus_index(SFX_BUS)).override_failure_message("шина SFX есть в AudioServer (default_bus_layout.tres)").is_not_equal(-1)
	var players := _players(audio)
	assert_int(players.size()).override_failure_message("у SectionAudio есть плееры").is_greater(0)
	for player in players:
		assert_str(str(player.get("bus"))).override_failure_message("плеер %s — на шине SFX (plan.md, «Звук»)" % player.name).is_equal(str(SFX_BUS))


func test_level_section_uses_config_from_data() -> void:
	level = auto_free(LEVEL_SCENE.instantiate())
	section = _find_section(level)
	assert_object(section).override_failure_message("в test_level.tscn есть SectionRoot").is_not_null()
	if section == null:
		return
	audio = _find_audio(section)
	assert_object(audio).override_failure_message("у секции есть дочерний узел SectionAudio (вне Content, plan.md)").is_not_null()
	if audio == null:
		return
	assert_object(audio.config).override_failure_message("у SectionAudio в уровне задан конфиг").is_not_null()
	if audio.config:
		assert_str(audio.config.resource_path).override_failure_message("конфиг звука секции — data/section_audio_config.tres") \
			.is_equal(SECTION_AUDIO_CONFIG.resource_path)


func test_config_numbers_reach_players() -> void:
	# Копия конфига со сдвинутыми числами: так видно, что плееры берут значения из конфига.
	var config := SECTION_AUDIO_CONFIG.duplicate() as SectionAudioConfig
	config.siren_volume_db += 1.5
	config.reset_volume_db -= 2.0
	await _build(config)
	section.report_caught(SectionReset.Cause.PLAYER_CAUGHT, 1)
	var siren := _single_playing("подготовка: на тревоге играет одна сирена")
	if siren:
		assert_float(siren.get("volume_db")).override_failure_message("сирена: volume_db = siren_volume_db").is_equal_approx(config.siren_volume_db, 0.001)
	await _wait_for_reset()
	assert_int(_at_reset.size()).override_failure_message("подготовка: по section_reset играет один звук").is_equal(1)
	if _at_reset.size() == 1:
		assert_float(_at_reset[0].get("volume_db")).override_failure_message("сброс: volume_db = reset_volume_db").is_equal_approx(config.reset_volume_db, 0.001)


func test_audio_has_no_rpc() -> void:
	await _build()
	var rpc_config: Variant = (audio.get_script() as Script).get_rpc_config()
	assert_bool(rpc_config is Dictionary).override_failure_message("RPC-конфиг скрипта читается").is_true()
	if rpc_config is Dictionary:
		assert_array((rpc_config as Dictionary).keys()).override_failure_message("звук не идёт по сети: у SectionAudio нет @rpc-методов (SOUND.md)").is_empty()


# --- Помощники -----------------------------------------------------------------

## Тестовый уровень с короткой паузой до сброса; config — конфиг звука вместо того, что в сцене.
func _build(config: SectionAudioConfig = null) -> void:
	level = auto_free(LEVEL_SCENE.instantiate())
	section = _find_section(level)
	assert_object(section).override_failure_message("в test_level.tscn есть SectionRoot").is_not_null()
	audio = _find_audio(section)
	assert_object(audio).override_failure_message("у секции есть дочерний узел SectionAudio").is_not_null()
	if section == null or audio == null:
		return
	var section_config := SECTION_CONFIG.duplicate() as SectionConfig
	section_config.reset_delay = TEST_RESET_DELAY
	section.config = section_config
	if config:
		audio.config = config
	add_child(level)
	section_signals = SignalLog.watch(section)
	# Отложенно: снимок после того, как все подписчики (и SectionAudio) обработали сигнал.
	section.section_reset.connect(_on_reset_snapshot, CONNECT_DEFERRED)
	await TestWorld.physics_frames(self, 2)


func _on_reset_snapshot(_section_id: String) -> void:
	_siren_at_reset = audio.is_siren_playing()
	_at_reset = _playing(audio)


func _wait_for_reset() -> void:
	var before := section_signals.count("section_reset")
	for i in MAX_WAIT_FRAMES:
		if section_signals.count("section_reset") > before:
			break
		await get_tree().physics_frame
	# Отложенный снимок выполняется в конце того же кадра.
	await get_tree().process_frame


func _single_playing(message: String) -> Node:
	var playing := _playing(audio)
	assert_int(playing.size()).override_failure_message(message).is_equal(1)
	return playing[0] if playing.size() == 1 else null


func _find_section(root: Node) -> SectionRoot:
	for node in root.find_children("*", "", true, false):
		if node is SectionRoot:
			return node
	return null


## SectionAudio — прямой потомок секции (вне будущего Content: сирена переживает сброс).
func _find_audio(parent: Node) -> SectionAudio:
	if parent == null:
		return null
	for node in parent.get_children():
		if node is SectionAudio:
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
