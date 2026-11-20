class_name LaserBeam
extends Node3D
## Лазерный луч — узел-адаптер препятствия (docs/tech/obstacles.md, раздел 3).
##
## Луч — отрезок вдоль локальной X длиной length на высоте config.beam_height над началом узла
## (начало — на полу посередине прохода). Видимый луч и зона касания строятся в _ready из одних
## и тех же чисел, поэтому совпадают.
##
## Касание судит машина, которая видит его без задержки (Obstacle.judges_here): своё тело —
## владелец персонажа, он сообщает хосту request_report_player_touch; свободный алмаз — хост.
## Хост рассылает событие _apply_tripped, и сигнал tripped испускается на каждом пире.
## Что делать дальше, решает секция по get_consequence(). Взвод меняет секция через set_armed().
## Звуки и прочие реакции подписываются на tripped и calmed.

## Луч сработал: target — Obstacle.Target, actor_id — peer id задевшего или 0 для алмаза,
## point — точка на оси луча, где показать искру. Испускается на каждом пире.
signal tripped(target: int, actor_id: int, point: Vector3)
## Сработавший раньше луч снова спокоен (после сброса секции).
signal calmed

@export var config: LaserConfig
## Длина луча от излучателя до излучателя, м. Ставит левел-дизайнер по ширине прохода.
@export var length: float = 2.2

var touch: LaserTouch

var _material: StandardMaterial3D
var _blink: Tween

@onready var _beam: MeshInstance3D = %Beam
@onready var _emitter_a: MeshInstance3D = %EmitterA
@onready var _emitter_b: MeshInstance3D = %EmitterB
@onready var _touch_area: Area3D = %TouchArea
@onready var _touch_shape: CollisionShape3D = %TouchShape
@onready var _alarm_light: OmniLight3D = %AlarmLight
@onready var _spark: MeshInstance3D = %Spark


func _ready() -> void:
	add_to_group("obstacles")
	if config == null:
		config = LaserConfig.new()
	touch = LaserTouch.from_config(config)
	_build()
	_touch_area.body_entered.connect(_on_body_entered)
	_show_calm()


# --- Контракт препятствия ------------------------------------------------------

## Взвести или снять с взвода (на всех пирах, вызывает секция).
func set_armed(armed: bool) -> void:
	if armed:
		if touch.arm():
			_show_calm()
			calmed.emit()
	else:
		touch.disarm()


func is_armed() -> bool:
	return touch.armed


func is_tripped() -> bool:
	return touch.tripped


## Последствие срабатывания — Obstacle.Consequence из конфига.
func get_consequence() -> int:
	return config.consequence


## Начало и конец оси луча в глобальных координатах.
func get_beam_segment() -> PackedVector3Array:
	var half := length / 2.0
	return PackedVector3Array([
		to_global(Vector3(-half, config.beam_height, 0.0)),
		to_global(Vector3(half, config.beam_height, 0.0)),
	])


# --- Касание -------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		var is_own := body.is_multiplayer_authority()
		if Obstacle.judges_here(Obstacle.Target.PLAYER, is_own, _is_host()) and touch.counts(Obstacle.Target.PLAYER):
			request_report_player_touch.rpc_id(1, _closest_on_beam(body.global_position))
	elif body is Diamond:
		if Obstacle.judges_here(Obstacle.Target.DIAMOND, false, _is_host()):
			_host_trip(Obstacle.Target.DIAMOND, 0, _closest_on_beam(body.global_position))


## Владелец персонажа сообщает, что его тело задело луч. Расстояние до луча хост
## не проверяет (К14): игрок может сообщить только о себе.
@rpc("any_peer", "call_local", "reliable")
func request_report_player_touch(point: Vector3) -> void:
	if not _is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if not _has_player(sender):
		return
	_host_trip(Obstacle.Target.PLAYER, sender, _closest_on_beam(point))


## Хост: засчитать касание и разослать событие.
func _host_trip(target: Obstacle.Target, actor_id: int, point: Vector3) -> void:
	if not _is_host() or not touch.counts(target):
		return
	_apply_tripped.rpc(target, actor_id, point)


@rpc("authority", "call_local", "reliable")
func _apply_tripped(target: int, actor_id: int, point: Vector3) -> void:
	touch.trip()
	_show_alarm(point)
	tripped.emit(target, actor_id, point)


# --- Вид -----------------------------------------------------------------------

func _build() -> void:
	var axis_center := Vector3(0.0, config.beam_height, 0.0)
	var half := length / 2.0
	var radius := config.beam_thickness / 2.0

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = config.beam_color

	var cylinder := CylinderMesh.new()
	cylinder.height = length
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.radial_segments = 12
	cylinder.rings = 1
	_beam.mesh = cylinder
	_beam.material_override = _material
	# Ось цилиндра (Y) — вдоль луча (X).
	_beam.transform = Transform3D(Basis(Vector3.BACK, PI / 2.0), axis_center)

	_emitter_a.position = Vector3(-half, config.beam_height, 0.0)
	_emitter_b.position = Vector3(half, config.beam_height, 0.0)
	_emitter_a.material_override = _material
	_emitter_b.material_override = _material

	var box := BoxShape3D.new()
	box.size = Vector3(length, config.beam_thickness, config.beam_thickness)
	_touch_shape.shape = box
	_touch_shape.transform = Transform3D(Basis.IDENTITY, axis_center)

	_alarm_light.position = axis_center
	_alarm_light.omni_range = config.light_range
	_alarm_light.shadow_enabled = false

	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.albedo_color = config.alarm_color
	_spark.material_override = spark_material


func _show_calm() -> void:
	if _blink:
		_blink.kill()
		_blink = null
	_material.albedo_color = config.beam_color
	_alarm_light.light_color = config.beam_color
	_alarm_light.light_energy = config.light_energy_calm
	_spark.hide()


## Тревога: луч и свет мигают, в точке касания — искра. Гасится в set_armed(true).
func _show_alarm(point: Vector3) -> void:
	_spark.global_position = point
	_spark.show()
	if _blink:
		_blink.kill()
	var half_period := 0.5 / maxf(config.alarm_blink_hz, 0.01)
	_blink = create_tween().set_loops()
	_blink.tween_property(_material, "albedo_color", config.alarm_color, half_period)
	_blink.parallel().tween_property(_alarm_light, "light_energy", config.light_energy_alarm, half_period)
	_blink.tween_property(_material, "albedo_color", config.beam_color, half_period)
	_blink.parallel().tween_property(_alarm_light, "light_energy", config.light_energy_calm, half_period)


# --- Внутреннее ----------------------------------------------------------------

func _is_host() -> bool:
	return multiplayer.is_server()


func _closest_on_beam(point: Vector3) -> Vector3:
	var segment := get_beam_segment()
	return Geometry3D.get_closest_point_to_segment(point, segment[0], segment[1])


func _has_player(peer_id: int) -> bool:
	for node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.get_multiplayer_authority() == peer_id:
			return true
	return false
