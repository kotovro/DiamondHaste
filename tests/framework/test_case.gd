class_name TestCase
extends RefCounted
## Базовый класс тестов.
##
## Тестовый файл: tests/unit/test_*.gd или tests/integration/test_*.gd, `extends TestCase`.
## Методы с префиксом test_ запускаются в порядке объявления. Любой метод может быть
## корутиной (await), например чтобы дождаться кадров физики.
##
## Хуки: before_all / after_all — один раз на файл, before_each / after_each — вокруг каждого теста.

## Дерево сцены раннера; узлы для теста добавляйте через add_child_autofree().
var tree: SceneTree

var _failures: PackedStringArray = []
var _autofree: Array[Node] = []
var _signal_log := {}
var _current_test := ""


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- Утверждения -------------------------------------------------------------

func fail(message: String) -> void:
	_failures.append("%s  [%s]" % [message, _caller_location()])


func assert_true(value: bool, message: String = "") -> void:
	if not value:
		fail(_msg(message, "ожидалось true"))


func assert_false(value: bool, message: String = "") -> void:
	if value:
		fail(_msg(message, "ожидалось false"))


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _same(actual, expected):
		fail(_msg(message, "ожидалось %s, получено %s" % [_fmt(expected), _fmt(actual)]))


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _same(actual, unexpected):
		fail(_msg(message, "значение не должно быть %s" % _fmt(unexpected)))


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.001, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		fail(_msg(message, "ожидалось %s ± %s, получено %s" % [expected, tolerance, actual]))


func assert_gt(actual: float, threshold: float, message: String = "") -> void:
	if not actual > threshold:
		fail(_msg(message, "ожидалось > %s, получено %s" % [threshold, actual]))


func assert_lt(actual: float, threshold: float, message: String = "") -> void:
	if not actual < threshold:
		fail(_msg(message, "ожидалось < %s, получено %s" % [threshold, actual]))


func assert_null(value: Variant, message: String = "") -> void:
	if value != null:
		fail(_msg(message, "ожидалось null, получено %s" % _fmt(value)))


func assert_not_null(value: Variant, message: String = "") -> void:
	if value == null:
		fail(_msg(message, "ожидалось не null"))


# --- Сигналы -----------------------------------------------------------------

## Начать запись всех сигналов объекта (до 4 аргументов).
func watch_signals(obj: Object) -> void:
	for sig in obj.get_signal_list():
		var signal_name: String = sig.name
		var key := _signal_key(obj, signal_name)
		if _signal_log.has(key):
			continue
		var recorder: Callable
		match sig.args.size():
			0: recorder = _record_0.bind(key)
			1: recorder = _record_1.bind(key)
			2: recorder = _record_2.bind(key)
			3: recorder = _record_3.bind(key)
			4: recorder = _record_4.bind(key)
			_: continue
		_signal_log[key] = []
		obj.connect(signal_name, recorder)


func signal_emit_count(obj: Object, signal_name: String) -> int:
	var key := _signal_key(obj, signal_name)
	if not _signal_log.has(key):
		fail("сигнал «%s» не отслеживается: вызовите watch_signals()" % signal_name)
		return 0
	return _signal_log[key].size()


## Аргументы испускания сигнала; index -1 — последнее испускание.
func get_signal_args(obj: Object, signal_name: String, index: int = -1) -> Array:
	var key := _signal_key(obj, signal_name)
	var log: Array = _signal_log.get(key, [])
	if log.is_empty():
		return []
	return log[index]


func assert_signal_emitted(obj: Object, signal_name: String, message: String = "") -> void:
	if signal_emit_count(obj, signal_name) == 0:
		fail(_msg(message, "сигнал «%s» не был испущен" % signal_name))


func assert_signal_not_emitted(obj: Object, signal_name: String, message: String = "") -> void:
	var count := signal_emit_count(obj, signal_name)
	if count > 0:
		fail(_msg(message, "сигнал «%s» испущен %d раз(а), ожидалось 0" % [signal_name, count]))


func assert_signal_emit_count(obj: Object, signal_name: String, expected: int, message: String = "") -> void:
	var count := signal_emit_count(obj, signal_name)
	if count != expected:
		fail(_msg(message, "сигнал «%s» испущен %d раз(а), ожидалось %d" % [signal_name, count, expected]))


# --- Дерево сцены ------------------------------------------------------------

## Добавить узел в дерево; после теста он будет удалён.
func add_child_autofree(node: Node) -> Node:
	tree.root.add_child(node)
	_autofree.append(node)
	return node


func wait_physics_frames(count: int) -> void:
	for i in count:
		await tree.physics_frame


func wait_frames(count: int) -> void:
	for i in count:
		await tree.process_frame


# --- Утилиты -----------------------------------------------------------------

## Все файлы с расширением ext в папке root (рекурсивно).
static func list_files(root: String, ext: String, prefix: String = "") -> PackedStringArray:
	var result: PackedStringArray = []
	if not DirAccess.dir_exists_absolute(root):
		return result
	for file in DirAccess.get_files_at(root):
		if file.ends_with(ext) and file.begins_with(prefix):
			result.append(root.path_join(file))
	for dir in DirAccess.get_directories_at(root):
		result.append_array(list_files(root.path_join(dir), ext, prefix))
	return result


# --- Для раннера -------------------------------------------------------------

func _begin_test(test_name: String) -> void:
	_current_test = test_name
	_failures.clear()
	_signal_log.clear()


func _end_test() -> void:
	for node in _autofree:
		if is_instance_valid(node):
			node.queue_free()
	_autofree.clear()


func _record_0(key: String) -> void:
	_signal_log[key].append([])


func _record_1(a: Variant, key: String) -> void:
	_signal_log[key].append([a])


func _record_2(a: Variant, b: Variant, key: String) -> void:
	_signal_log[key].append([a, b])


func _record_3(a: Variant, b: Variant, c: Variant, key: String) -> void:
	_signal_log[key].append([a, b, c])


func _record_4(a: Variant, b: Variant, c: Variant, d: Variant, key: String) -> void:
	_signal_log[key].append([a, b, c, d])


static func _signal_key(obj: Object, signal_name: String) -> String:
	return "%d:%s" % [obj.get_instance_id(), signal_name]


static func _same(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	var numeric := [TYPE_INT, TYPE_FLOAT]
	if ta != tb and not (ta in numeric and tb in numeric):
		return false
	return a == b


static func _fmt(value: Variant) -> String:
	if value is Object:
		return str(value)
	return var_to_str(value)


static func _msg(custom: String, default: String) -> String:
	return default if custom.is_empty() else "%s: %s" % [custom, default]


func _caller_location() -> String:
	# get_stack() заполнен только при подключённом отладчике (запуск из редактора).
	for frame in get_stack():
		var source: String = frame.source
		if not source.ends_with("test_case.gd"):
			return "%s:%d" % [source.get_file(), frame.line]
	return "%s::%s" % [get_script().resource_path.get_file(), _current_test]
