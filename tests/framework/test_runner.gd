extends Node
## Раннер тестов.
##
## Запуск: godot --headless --path . res://tests/run_tests.tscn [-- --filter <часть пути или имени теста>]
## Обычно через tools\run_tests.cmd — он ещё импортирует проект и ловит ошибки скриптов в логе.
## Код выхода: 0 — всё прошло, 1 — есть упавшие тесты или файлы, которые не загрузились.

const TEST_ROOTS := ["res://tests/unit", "res://tests/integration"]

var _passed := 0
var _failed := 0
var _broken_files := 0


func _ready() -> void:
	await get_tree().process_frame
	var filter := _arg_value("--filter")

	var files: PackedStringArray = []
	for root in TEST_ROOTS:
		files.append_array(TestCase.list_files(root, ".gd", "test_"))
	files.sort()

	print("Diamond Heist — тесты (%d файлов)%s" % [files.size(), "" if filter.is_empty() else ", фильтр «%s»" % filter])
	for path in files:
		await _run_file(path, filter)

	var ok := _failed == 0 and _broken_files == 0 and _passed > 0
	print("")
	print("ИТОГ: пройдено %d, упало %d, не загрузилось файлов %d" % [_passed, _failed, _broken_files])
	print("TEST_RESULT %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _run_file(path: String, filter: String) -> void:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		_broken_files += 1
		print("✘ %s — файл не загружается (ошибка компиляции?)" % path)
		return

	var instance: Variant = script.new()
	if not instance is TestCase:
		print("… %s пропущен: не наследует TestCase" % path)
		return
	var case: TestCase = instance
	case.tree = get_tree()

	var methods: PackedStringArray = []
	for method in script.get_script_method_list():
		var method_name: String = method.name
		if method_name.begins_with("test_") and not methods.has(method_name):
			if filter.is_empty() or path.contains(filter) or method_name.contains(filter):
				methods.append(method_name)
	if methods.is_empty():
		return

	print("▶ %s" % path.trim_prefix("res://"))
	await case.call("before_all")
	for method_name in methods:
		case._begin_test(method_name)
		await case.call("before_each")
		await case.call(method_name)
		await case.call("after_each")
		case._end_test()
		await get_tree().process_frame

		if case._failures.is_empty():
			_passed += 1
			print("  ✔ %s" % method_name)
		else:
			_failed += 1
			print("  ✘ %s" % method_name)
			for failure in case._failures:
				print("      %s" % failure)
	await case.call("after_all")


func _arg_value(flag: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find(flag)
	if index != -1 and index + 1 < args.size():
		return args[index + 1]
	return ""
