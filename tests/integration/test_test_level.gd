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


## Вся тестовая сцена — одна секция с нулевым чекпоинтом (decision-04 A, T-18).
func test_has_one_section_with_obstacle() -> void:
	add_child(auto_free(LEVEL_SCENE.instantiate()))
	var sections := get_tree().get_nodes_in_group("sections")
	assert_int(sections.size()).override_failure_message("в уровне ровно одна секция").is_equal(1)
	if sections.size() != 1:
		return
	# Классы секции и луча — по имени, без ссылки на тип: файл разбирается и до их появления.
	var section: Node = sections[0]
	assert_str(_class_name_of(section)).override_failure_message("узел группы sections — SectionRoot").is_equal("SectionRoot")
	assert_str(str(section.get("section_id"))).override_failure_message("у секции стабильный section_id").is_not_empty()
	assert_int(_obstacles_in(section).size()).override_failure_message("в секции есть хотя бы одно препятствие").is_greater(0)


## Сразу после сброса луч не срабатывает сам: точки появления и алмаз на постаменте
## дальше beam_thickness/2 + 1 м от каждого луча (К13).
func test_spawn_points_and_pedestal_are_clear_of_beams() -> void:
	var level: Node3D = auto_free(LEVEL_SCENE.instantiate())
	add_child(level)
	var beams: Array[Node] = []
	for node in get_tree().get_nodes_in_group("obstacles"):
		if node.has_method("get_beam_segment"):
			beams.append(node)
	assert_int(beams.size()).override_failure_message("в уровне есть луч").is_greater(0)

	var places := {}
	for point in get_tree().get_nodes_in_group("spawn_points"):
		places[str(point.name)] = (point as Node3D).global_position
	places["Diamond"] = (level.get_node("Diamond") as Diamond).global_position

	for beam: Node in beams:
		var segment: PackedVector3Array = beam.call("get_beam_segment")
		var config: Resource = beam.get("config")
		var clearance: float = float(config.get("beam_thickness")) / 2.0 + 1.0
		for place_name: String in places:
			var place: Vector3 = places[place_name]
			var distance := Geometry3D.get_closest_point_to_segment(place, segment[0], segment[1]).distance_to(place)
			assert_float(distance) \
				.override_failure_message("%s в %.2f м от луча %s, нужно больше %.2f м" % [place_name, distance, beam.name, clearance]) \
				.is_greater(clearance)


func _class_name_of(node: Node) -> String:
	var script := node.get_script() as Script
	return str(script.get_global_name()) if script else ""


func _obstacles_in(section: Node) -> Array[Node]:
	var result: Array[Node] = []
	for node in get_tree().get_nodes_in_group("obstacles"):
		if section.is_ancestor_of(node):
			result.append(node)
	return result
