class_name Player
extends CharacterBody3D
## Персонаж игрока — узел-адаптер.
##
## Имя узла = peer id владельца. Владелец управляет персонажем локально,
## MultiplayerSynchronizer рассылает позицию и поворот модели остальным.
## Перенос алмаза — компонент Carry (PlayerCarry), «поимка» — CaughtFeedback.
## На время тревоги секции управление блокируется (set_controls_locked): ввод движения
## и прыжок не действуют, гравитация и камера работают.

const PITCH_MIN := deg_to_rad(-70.0)
const PITCH_MAX := deg_to_rad(25.0)
const START_PITCH := deg_to_rad(-15.0)
## Высота центра положенного алмаза над ступнями, м.
const DROP_HEIGHT := 0.25

const HOST_COLOR := Color(0.95, 0.55, 0.2)
const CLIENT_COLOR := Color(0.25, 0.55, 0.95)

@export var movement: MovementConfig

@onready var body: Node3D = $Body
## Визуальная поза модели: локальна на каждом пире, синхронизатор её не трогает.
@onready var pose: Node3D = $Body/Pose
@onready var body_mesh: MeshInstance3D = $Body/Pose/Mesh
@onready var hold_point: Marker3D = $Body/HoldPoint
@onready var name_label: Label3D = $NameLabel
@onready var camera_pivot: Node3D = $CameraPivot
@onready var spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var camera: Camera3D = $CameraPivot/SpringArm3D/Camera3D
@onready var carry: PlayerCarry = $Carry
@onready var caught_feedback: CaughtFeedback = $CaughtFeedback

var _controls_locked := false


func _enter_tree() -> void:
	# Делается до _ready, чтобы MultiplayerSynchronizer и компоненты сразу получили владельца.
	set_multiplayer_authority(str(name).to_int())


func _ready() -> void:
	add_to_group("players")
	if movement == null:
		movement = MovementConfig.new()

	var owner_id := get_multiplayer_authority()
	var is_host_player := owner_id == 1
	name_label.text = "Хост" if is_host_player else "Игрок 2"

	var mat := StandardMaterial3D.new()
	mat.albedo_color = HOST_COLOR if is_host_player else CLIENT_COLOR
	body_mesh.material_override = mat

	if is_multiplayer_authority():
		spring_arm.rotation.x = START_PITCH
		camera.make_current()
		name_label.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_move_to_spawn()
	else:
		camera.current = false

	print("[Player] %s готов: владелец=%d, локальный id=%d" % [name, owner_id, multiplayer.get_unique_id()])


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * movement.mouse_sensitivity)
		spring_arm.rotation.x = clampf(spring_arm.rotation.x - event.relative.y * movement.mouse_sensitivity, PITCH_MIN, PITCH_MAX)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif not _controls_locked and Input.is_action_just_pressed("jump") and carry.can_jump():
		velocity.y = movement.jump_velocity

	# Движение относительно камеры: CameraPivot вращается только по Y.
	var input := Vector2.ZERO
	if not _controls_locked:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := camera_pivot.global_basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	direction = direction.normalized()

	var target := direction * movement.walk_speed * carry.speed_multiplier()
	velocity.x = move_toward(velocity.x, target.x, movement.acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, movement.acceleration * delta)

	if direction != Vector3.ZERO:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-direction.x, -direction.z), movement.turn_speed * delta)

	move_and_slide()


## Где держится алмаз.
func get_hold_transform() -> Transform3D:
	return hold_point.global_transform


## Куда кладётся алмаз: под точкой хвата, у ног.
func get_drop_position() -> Vector3:
	var position := hold_point.global_position
	position.y = global_position.y + DROP_HEIGHT
	return position


func facing_yaw() -> float:
	return body.global_rotation.y


## Куда повёрнут персонаж (горизонтально).
func facing_direction() -> Vector3:
	var forward := -body.global_basis.z
	forward.y = 0.0
	return forward.normalized()


## Блок управления на время тревоги секции (вызывает SectionRoot у своих персонажей).
func set_controls_locked(locked: bool) -> void:
	_controls_locked = locked


func is_controls_locked() -> bool:
	return _controls_locked


## Вернуть персонажа на точку появления. Не RPC (T-19): каждая машина переносит своего
## персонажа по событию section_reset; чужого персонажа вызов не трогает.
func respawn() -> void:
	if not is_multiplayer_authority():
		return
	velocity = Vector3.ZERO
	_move_to_spawn()


func _move_to_spawn() -> void:
	var index := 0 if get_multiplayer_authority() == 1 else 1
	var points := get_tree().get_nodes_in_group("spawn_points")
	if points.is_empty():
		return
	var point := points[mini(index, points.size() - 1)] as Node3D
	global_position = point.global_position
