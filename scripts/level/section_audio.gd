class_name SectionAudio
extends Node
## Звуковой компонент секции (дочерний узел SectionRoot, вне Content; docs/audio/SOUND.md).
##
## Сирена — петля без позиции: её слышно обоим в любой точке (К17). Начинается по
## alarm_started, обрывается по section_reset, и тогда же звучит сброс («перемотка»).
## Сигналы испускаются на каждом пире, поэтому каждая машина играет звук сама, без сети.
## Состояние игры компонент не меняет.

@export var config: SectionAudioConfig

var _section: SectionRoot

@onready var _siren: AudioStreamPlayer = $Siren
@onready var _reset: AudioStreamPlayer = $Reset


func _ready() -> void:
	if config == null:
		config = SectionAudioConfig.new()
	_siren.volume_db = config.siren_volume_db
	_reset.volume_db = config.reset_volume_db
	var section := get_parent() as SectionRoot
	if section:
		bind_section(section)


func bind_section(section: SectionRoot) -> void:
	if _section == section:
		return
	if is_instance_valid(_section):
		_section.alarm_started.disconnect(_on_alarm_started)
		_section.section_reset.disconnect(_on_section_reset)
	_section = section
	if _section:
		_section.alarm_started.connect(_on_alarm_started)
		_section.section_reset.connect(_on_section_reset)


func is_siren_playing() -> bool:
	return _siren.playing


func _on_alarm_started(_cause: int, _actor_id: int) -> void:
	_siren.play()


func _on_section_reset(_section_id: String) -> void:
	_siren.stop()
	_reset.play()
