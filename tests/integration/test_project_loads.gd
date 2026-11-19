extends TestCase
## Смоук-тест: все скрипты компилируются, сцены инстанцируются, ресурсы грузятся.


func test_all_scripts_compile() -> void:
	for path in TestCase.list_files("res://scripts", ".gd"):
		var script := load(path) as GDScript
		assert_true(script != null and script.can_instantiate(), "скрипт не компилируется: %s" % path)


func test_all_scenes_instantiate() -> void:
	for path in TestCase.list_files("res://scenes", ".tscn"):
		var scene := load(path) as PackedScene
		assert_not_null(scene, "сцена не загружается: %s" % path)
		if scene == null:
			continue
		var node := scene.instantiate()
		assert_not_null(node, "сцена не инстанцируется: %s" % path)
		if node:
			node.free()


func test_all_configs_load() -> void:
	for path in TestCase.list_files("res://data", ".tres"):
		assert_not_null(load(path), "ресурс не загружается: %s" % path)
