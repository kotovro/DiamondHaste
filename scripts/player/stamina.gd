class_name Stamina
extends RefCounted
## Выносливость игрока, несущего алмаз в одиночку: расходуется с алмазом, восстанавливается без него.
## Чистая логика: исполняется у владельца персонажа, покрыта tests/unit/test_stamina.gd.

signal changed(current: float, maximum: float)
signal depleted

var maximum: float
var current: float
var drain_per_second: float
var regen_per_second: float
var min_to_pick_up: float


func _init(p_maximum: float = 100.0, p_drain: float = 12.0, p_regen: float = 25.0, p_min_to_pick_up: float = 30.0) -> void:
	maximum = p_maximum
	current = p_maximum
	drain_per_second = p_drain
	regen_per_second = p_regen
	min_to_pick_up = p_min_to_pick_up


static func from_config(config: CarryConfig) -> Stamina:
	return Stamina.new(config.max_stamina, config.drain_per_second, config.regen_per_second, config.min_stamina_to_pick_up)


func tick(delta: float, carrying: bool) -> void:
	var before := current
	if carrying:
		current = maxf(current - drain_per_second * delta, 0.0)
	else:
		current = minf(current + regen_per_second * delta, maximum)
	if current == before:
		return
	changed.emit(current, maximum)
	if is_depleted():
		depleted.emit()


func can_pick_up() -> bool:
	return current >= min_to_pick_up


func is_depleted() -> bool:
	return current <= 0.0


func ratio() -> float:
	return current / maximum if maximum > 0.0 else 0.0
