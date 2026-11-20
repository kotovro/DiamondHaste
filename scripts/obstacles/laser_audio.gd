class_name LaserAudio
extends Node3D
## Звуковой компонент лазерного луча (дочерний узел LaserBeam, docs/audio/SOUND.md).
##
## Гудение — петля у середины луча, позиционно и только вблизи (К17): играет, пока луч
## не сработал; останавливается по tripped, снова звучит по calmed. Треск касания —
## позиционно в точке касания по tripped. Сигналы испускаются на каждом пире, поэтому
## каждая машина играет звук сама, без сети. Состояние игры компонент не меняет.

@export var config: LaserAudioConfig

var _laser: LaserBeam

@onready var _hum: AudioStreamPlayer3D = $Hum
@onready var _zap: AudioStreamPlayer3D = $Zap


func _ready() -> void:
	if config == null:
		config = LaserAudioConfig.new()
	_hum.volume_db = config.hum_volume_db
	_hum.max_distance = config.hum_max_distance
	_hum.unit_size = config.hum_unit_size
	_zap.volume_db = config.zap_volume_db
	_zap.max_distance = config.zap_max_distance
	var laser := get_parent() as LaserBeam
	if laser == null:
		return
	# Дочерний _ready идёт раньше родительского: конфиг луча и взвод готовы после ready.
	if laser.is_node_ready():
		bind_laser(laser)
	else:
		laser.ready.connect(bind_laser.bind(laser), CONNECT_ONE_SHOT)


func bind_laser(laser: LaserBeam) -> void:
	if _laser == laser:
		return
	if is_instance_valid(_laser):
		_laser.tripped.disconnect(_on_tripped)
		_laser.calmed.disconnect(_on_calmed)
	_laser = laser
	if _laser == null:
		_hum.stop()
		return
	_laser.tripped.connect(_on_tripped)
	_laser.calmed.connect(_on_calmed)
	var segment := _laser.get_beam_segment()
	_hum.global_position = (segment[0] + segment[1]) / 2.0
	if _laser.is_tripped():
		_hum.stop()
	else:
		_hum.play()


func is_humming() -> bool:
	return _hum.playing


func _on_tripped(_target: int, _actor_id: int, point: Vector3) -> void:
	_hum.stop()
	_zap.global_position = point
	_zap.play()


func _on_calmed() -> void:
	_hum.play()
