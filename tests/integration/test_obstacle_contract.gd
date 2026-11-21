extends GdUnitTestSuite
## Общий контракт узла препятствия (docs/tech/obstacles.md, раздел 1). Одни и те же проверки
## гоняются по каждой сцене scenes/props/*.tscn, корень которой после _ready в группе obstacles:
## сигнал tripped(target, actor_id, point), методы set_armed / is_armed / get_consequence, config.

const PROPS_DIR := "res://scenes/props"


func test_props_contain_at_least_one_obstacle() -> void:
	var obstacles := await _instantiate_obstacles()
	assert_int(obstacles.size()) \
		.override_failure_message("в %s нет ни одной сцены-препятствия (ждём laser_beam.tscn)" % PROPS_DIR) \
		.is_greater(0)


func test_every_obstacle_has_tripped_signal_with_three_args() -> void:
	for node in await _instantiate_obstacles():
		var path := node.scene_file_path
		var tripped := _find_signal(node, "tripped")
		assert_bool(tripped.is_empty()).override_failure_message("%s: нет сигнала tripped" % path).is_false()
		if not tripped.is_empty():
			assert_int((tripped.args as Array).size()) \
				.override_failure_message("%s: tripped(target, actor_id, point) — три аргумента" % path).is_equal(3)


func test_every_obstacle_has_contract_methods() -> void:
	for node in await _instantiate_obstacles():
		for method: String in ["set_armed", "is_armed", "get_consequence"]:
			assert_bool(node.has_method(method)) \
				.override_failure_message("%s: нет метода %s" % [node.scene_file_path, method]).is_true()


func test_every_obstacle_has_config_after_ready() -> void:
	for node in await _instantiate_obstacles():
		assert_bool("config" in node).override_failure_message("%s: нет поля config" % node.scene_file_path).is_true()
		assert_object(node.get("config")).override_failure_message("%s: config == null после _ready" % node.scene_file_path).is_not_null()


func test_every_obstacle_arms_and_disarms() -> void:
	for node in await _instantiate_obstacles():
		var path := node.scene_file_path
		assert_bool(node.call("is_armed")).override_failure_message("%s: после _ready взведено" % path).is_true()
		node.call("set_armed", false)
		assert_bool(node.call("is_armed")).override_failure_message("%s: set_armed(false) снимает с взвода" % path).is_false()
		node.call("set_armed", true)
		assert_bool(node.call("is_armed")).override_failure_message("%s: set_armed(true) взводит" % path).is_true()


func test_every_obstacle_consequence_is_known() -> void:
	for node in await _instantiate_obstacles():
		var consequence: Variant = node.call("get_consequence")
		assert_int(typeof(consequence)).override_failure_message("%s: get_consequence() -> int" % node.scene_file_path).is_equal(TYPE_INT)
		assert_bool(Obstacle.Consequence.values().has(consequence)) \
			.override_failure_message("%s: последствие %s не из Obstacle.Consequence" % [node.scene_file_path, consequence]).is_true()


## Корни всех сцен scenes/props, которые после _ready в группе obstacles; остальные удаляются.
func _instantiate_obstacles() -> Array[Node]:
	var result: Array[Node] = []
	for path in TestWorld.list_files(PROPS_DIR, ".tscn"):
		var scene := load(path) as PackedScene
		if scene == null:
			continue  # битые сцены ловит test_project_loads
		var node: Node = auto_free(scene.instantiate())
		add_child(node)
		if node.is_in_group("obstacles"):
			result.append(node)
	await TestWorld.physics_frames(self, 1)
	return result


func _find_signal(obj: Object, signal_name: String) -> Dictionary:
	for sig: Dictionary in obj.get_signal_list():
		if sig.name == signal_name:
			return sig
	return {}
