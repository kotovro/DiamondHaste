class_name CaughtFeedback
extends Node
## Компонент персонажа: «поимка» — задевший луч персонаж замирает в нелепой позе и мигает,
## чтобы оба игрока видели, кто виноват (К9). Работает на каждом пире по сигналам секции.
## Секцию подключает точка сборки (Main) через bind_section().
##
## Числа — заглушки-константы: визуальный стиль не выбран (DESIGN.md, вопрос 7).

## Наклон модели в позе поимки, рад. Наклоняется player.pose — нереплицируемый узел
## (Body:rotation реплицирует синхронизатор), поэтому поза задаётся только событием.
const TILT := deg_to_rad(28.0)
## Цвет мигания задевшего персонажа.
const BLINK_COLOR := Color(1.0, 0.9, 0.2)
## Частота мигания, Гц.
const BLINK_HZ := 5.0

var _section: SectionRoot
var _showing := false
var _blink: Tween
var _pose_rotation_z := 0.0
var _color := Color.WHITE

@onready var player: Player = get_parent()


func bind_section(section: SectionRoot) -> void:
	if _section == section:
		return
	if is_instance_valid(_section):
		if _section.alarm_started.is_connected(_on_alarm_started):
			_section.alarm_started.disconnect(_on_alarm_started)
		if _section.section_reset.is_connected(_on_section_reset):
			_section.section_reset.disconnect(_on_section_reset)
	_section = section
	if _section:
		_section.alarm_started.connect(_on_alarm_started)
		_section.section_reset.connect(_on_section_reset)


func is_showing() -> bool:
	return _showing


func _on_alarm_started(cause: int, actor_id: int) -> void:
	if cause != SectionReset.Cause.PLAYER_CAUGHT or actor_id != player.get_multiplayer_authority():
		return
	if _showing:
		return
	_showing = true
	_pose_rotation_z = player.pose.rotation.z
	player.pose.rotation.z = _pose_rotation_z + TILT
	var material := player.body_mesh.material_override as StandardMaterial3D
	if material:
		_color = material.albedo_color
		var half_period := 0.5 / BLINK_HZ
		_blink = create_tween().set_loops()
		_blink.tween_property(material, "albedo_color", BLINK_COLOR, half_period)
		_blink.tween_property(material, "albedo_color", _color, half_period)


func _on_section_reset(_section_id: String) -> void:
	if not _showing:
		return
	_showing = false
	if _blink:
		_blink.kill()
		_blink = null
	player.pose.rotation.z = _pose_rotation_z
	var material := player.body_mesh.material_override as StandardMaterial3D
	if material:
		material.albedo_color = _color
