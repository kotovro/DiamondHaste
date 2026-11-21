class_name LaserTouch
extends RefCounted
## Логика лазерного луча: взвод, засчитывается ли касание, срабатывание.
## Чистая логика, покрыта tests/unit/test_laser_touch.gd.

var reacts_to_diamond: bool
## Луч взведён: касания засчитываются.
var armed: bool = true
## Луч сработал и ждёт сброса секции.
var tripped: bool = false


func _init(p_reacts_to_diamond: bool = true) -> void:
	reacts_to_diamond = p_reacts_to_diamond


static func from_config(config: LaserConfig) -> LaserTouch:
	return LaserTouch.new(config.reacts_to_diamond)


## Засчитывается ли касание цели прямо сейчас.
func counts(target: Obstacle.Target) -> bool:
	return armed and (target == Obstacle.Target.PLAYER or reacts_to_diamond)


## Срабатывание: луч снимается с взвода и помнит, что сработал. Повторно — без изменений.
func trip() -> void:
	armed = false
	tripped = true


## Снять с взвода (тревога секции); срабатывание не меняется.
func disarm() -> void:
	armed = false


## Взвести снова. Возвращает, срабатывал ли луч до этого.
func arm() -> bool:
	var was_tripped := tripped
	armed = true
	tripped = false
	return was_tripped
