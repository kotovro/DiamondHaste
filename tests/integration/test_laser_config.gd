extends GdUnitTestSuite
## Содержимое data/laser_config.tres: решения карточки и размеры луча относительно персонажа.
## Высота прыжка — из movement_config.tres и гравитации проекта, рост — из сцены персонажа.

const CONFIG_PATH := "res://data/laser_config.tres"
const MOVEMENT := preload("res://data/movement_config.tres")
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## Запас между верхом луча и высотой прыжка без алмаза, м (plan.md, опора К5).
const JUMP_CLEARANCE := 0.3

var config: LaserConfig


func before_test() -> void:
	config = load(CONFIG_PATH) as LaserConfig


func test_config_is_laser_config() -> void:
	assert_object(config).override_failure_message("%s — ресурс LaserConfig" % CONFIG_PATH).is_not_null()


func test_reacts_to_diamond_by_default() -> void:
	assert_bool(config.reacts_to_diamond).override_failure_message("decision-03 C: по умолчанию луч реагирует на алмаз").is_true()


func test_touch_means_section_reset() -> void:
	assert_int(config.consequence).override_failure_message("decision-02 A: касание — поимка и сброс секции") \
		.is_equal(Obstacle.Consequence.SECTION_RESET)


func test_beam_has_size() -> void:
	assert_float(config.beam_thickness).is_greater(0.0)
	assert_float(config.beam_height - config.beam_thickness / 2.0) \
		.override_failure_message("низ луча над полом").is_greater(0.0)


func test_beam_top_is_below_jump_height_with_margin() -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var jump_height := MOVEMENT.jump_velocity * MOVEMENT.jump_velocity / (2.0 * gravity)
	var beam_top := config.beam_height + config.beam_thickness / 2.0
	assert_float(jump_height - beam_top) \
		.override_failure_message("игрок без алмаза перепрыгивает луч с запасом %.2f м: прыжок %.2f м, верх луча %.2f м" \
			% [JUMP_CLEARANCE, jump_height, beam_top]) \
		.is_greater_equal(JUMP_CLEARANCE)


func test_player_cannot_pass_under_beam() -> void:
	var beam_bottom := config.beam_height - config.beam_thickness / 2.0
	var player_height := _player_height()
	assert_float(player_height).override_failure_message("рост персонажа читается из сцены").is_greater(0.0)
	assert_float(beam_bottom) \
		.override_failure_message("низ луча %.2f м ниже роста персонажа %.2f м: под лучом не пройти" % [beam_bottom, player_height]) \
		.is_less(player_height)


## Верх капсулы персонажа над его ступнями, м.
func _player_height() -> float:
	var player: Node3D = PLAYER_SCENE.instantiate()
	var shape_node := player.get_node("CollisionShape3D") as CollisionShape3D
	var capsule := shape_node.shape as CapsuleShape3D
	var height: float = shape_node.position.y + capsule.height / 2.0 if capsule else 0.0
	player.free()
	return height
