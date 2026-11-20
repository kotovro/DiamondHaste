extends GdUnitTestSuite
## Смоук-тест: все скрипты компилируются, сцены инстанцируются, ресурсы грузятся.


func test_all_scripts_compile() -> void:
	for path in TestWorld.list_files("res://scripts", ".gd"):
		var script := load(path) as GDScript
		assert_bool(script != null and script.can_instantiate()) \
			.override_failure_message("скрипт не компилируется: %s" % path).is_true()


func test_all_scenes_instantiate() -> void:
	for path in TestWorld.list_files("res://scenes", ".tscn"):
		var scene := load(path) as PackedScene
		assert_object(scene).override_failure_message("сцена не загружается: %s" % path).is_not_null()
		if scene == null:
			continue
		var node := scene.instantiate()
		assert_object(node).override_failure_message("сцена не инстанцируется: %s" % path).is_not_null()
		if node:
			node.free()


func test_all_configs_load() -> void:
	for path in TestWorld.list_files("res://data", ".tres"):
		assert_object(load(path)).override_failure_message("ресурс не загружается: %s" % path).is_not_null()
