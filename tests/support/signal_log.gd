class_name SignalLog
extends RefCounted
## Журнал сигналов объекта для тестов: сколько раз испущен сигнал и с какими аргументами.
## Синхронный, без ожиданий: события игры испускаются сразу, ждать кадры не нужно.
## (assert_signal из GdUnit4 ждёт кадр и не умеет считать испускания, поэтому свой журнал.)
##
## var signals := SignalLog.watch(stamina)
## stamina.tick(2.0, true)
## assert_int(signals.count("changed")).is_equal(1)
## assert_array(signals.args("changed")).is_equal([80.0, 100.0])

var _calls := {}


static func watch(obj: Object) -> SignalLog:
	var result := SignalLog.new()
	result.add(obj)
	return result


## Начать запись всех сигналов объекта (до 4 аргументов).
func add(obj: Object) -> void:
	for sig: Dictionary in obj.get_signal_list():
		var signal_name: String = sig.name
		if _calls.has(signal_name):
			continue
		var recorder: Callable
		match (sig.args as Array).size():
			0: recorder = _record_0.bind(signal_name)
			1: recorder = _record_1.bind(signal_name)
			2: recorder = _record_2.bind(signal_name)
			3: recorder = _record_3.bind(signal_name)
			4: recorder = _record_4.bind(signal_name)
			_: continue
		_calls[signal_name] = []
		obj.connect(signal_name, recorder)


## Сколько раз сигнал испущен с начала записи.
func count(signal_name: String) -> int:
	assert(_calls.has(signal_name), "сигнал «%s» не записывается" % signal_name)
	return (_calls.get(signal_name, []) as Array).size()


## Аргументы испускания; index -1 — последнее. Пустой массив, если сигнала не было.
func args(signal_name: String, index: int = -1) -> Array:
	var calls: Array = _calls.get(signal_name, [])
	if calls.is_empty():
		return []
	return calls[index]


func clear() -> void:
	for signal_name: String in _calls:
		(_calls[signal_name] as Array).clear()


func _record_0(signal_name: String) -> void:
	_calls[signal_name].append([])


func _record_1(a: Variant, signal_name: String) -> void:
	_calls[signal_name].append([a])


func _record_2(a: Variant, b: Variant, signal_name: String) -> void:
	_calls[signal_name].append([a, b])


func _record_3(a: Variant, b: Variant, c: Variant, signal_name: String) -> void:
	_calls[signal_name].append([a, b, c])


func _record_4(a: Variant, b: Variant, c: Variant, d: Variant, signal_name: String) -> void:
	_calls[signal_name].append([a, b, c, d])
