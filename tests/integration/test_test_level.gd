extends GdUnitTestSuite
## Тестовый уровень собран корректно.

const LEVEL_SCENE := preload("res://scenes/level/test_level.tscn")


func test_diamond_rests_on_pedestal_without_damage() -> void:
	var level: Node3D = auto_free(LEVEL_SCENE.instantiate())
	add_child(level)
	var diamond := level.get_node("Diamond") as Diamond
	var start := diamond.global_position
	await TestWorld.physics_frames(self, 120)
	assert_float(diamond.global_position.distance_to(start)).override_failure_message("алмаз не должен падать с постамента").is_less(0.03)
	assert_float(diamond.global_basis.y.dot(Vector3.UP)).override_failure_message("алмаз не должен опрокидываться").is_greater(0.99)
	assert_float(diamond.durability_value).is_equal(diamond.max_durability())


func test_has_two_spawn_points() -> void:
	add_child(auto_free(LEVEL_SCENE.instantiate()))
	assert_int(get_tree().get_nodes_in_group("spawn_points").size()).is_equal(2)
