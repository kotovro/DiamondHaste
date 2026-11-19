extends TestCase
## Тестовый уровень собран корректно.

const LEVEL_SCENE := preload("res://scenes/level/test_level.tscn")


func test_diamond_rests_on_pedestal_without_damage() -> void:
	var level: Node3D = add_child_autofree(LEVEL_SCENE.instantiate())
	var diamond := level.get_node("Diamond") as Diamond
	var start := diamond.global_position
	await wait_physics_frames(120)
	assert_lt(diamond.global_position.distance_to(start), 0.03, "алмаз не должен падать с постамента")
	assert_gt(diamond.global_basis.y.dot(Vector3.UP), 0.99, "алмаз не должен опрокидываться")
	assert_eq(diamond.durability_value, diamond.max_durability())


func test_has_two_spawn_points() -> void:
	add_child_autofree(LEVEL_SCENE.instantiate())
	assert_eq(tree.get_nodes_in_group("spawn_points").size(), 2)
