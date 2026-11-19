class_name Durability
extends RefCounted
## Запас прочности алмаза. Падения и удары уменьшают его; на нуле алмаз разрушен.
## Чистая логика: исполняется на хосте, покрыта tests/unit/test_durability.gd.

signal changed(current: float, maximum: float)
signal broken

var maximum: float
var current: float
## Удары со сменой скорости не больше порога не повреждают, м/с.
var min_impact_speed: float
## Урон за каждый м/с сверх порога.
var damage_per_speed: float


func _init(p_maximum: float = 100.0, p_min_impact_speed: float = 3.5, p_damage_per_speed: float = 8.0) -> void:
	maximum = p_maximum
	current = p_maximum
	min_impact_speed = p_min_impact_speed
	damage_per_speed = p_damage_per_speed


static func from_config(config: DiamondConfig) -> Durability:
	return Durability.new(config.max_durability, config.min_impact_speed, config.damage_per_speed)


func is_broken() -> bool:
	return current <= 0.0


func ratio() -> float:
	return current / maximum if maximum > 0.0 else 0.0


func damage_for_impact(impact_speed: float) -> float:
	if impact_speed <= min_impact_speed:
		return 0.0
	return (impact_speed - min_impact_speed) * damage_per_speed


## Применить удар; возвращает фактически нанесённый урон.
func apply_impact(impact_speed: float) -> float:
	if is_broken():
		return 0.0
	var damage := minf(damage_for_impact(impact_speed), current)
	if damage <= 0.0:
		return 0.0
	current -= damage
	changed.emit(current, maximum)
	if is_broken():
		broken.emit()
	return damage


## Мгновенное разрушение (например, алмаз упал за пределы уровня).
func destroy() -> void:
	if is_broken():
		return
	current = 0.0
	changed.emit(current, maximum)
	broken.emit()


func reset() -> void:
	current = maximum
	changed.emit(current, maximum)
