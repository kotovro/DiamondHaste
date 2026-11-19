class_name PlayerCarry
extends Node
## Компонент персонажа: перенос алмаза одним игроком и выносливость.
##
## Несёт ли персонаж алмаз, решает хост; компонент узнаёт об этом из события
## Diamond.carrier_changed и испускает своё carrying_changed. Действия (взять, положить,
## передать, бросить) уходят хосту запросами Diamond.request_*.
## Алмаз подключается извне через bind_diamond() (в игре — Main).

## Персонаж взял алмаз или перестал его нести.
signal carrying_changed(carrying: bool)

@export var config: CarryConfig

var stamina: Stamina

var _diamond: Diamond
var _carrying := false

@onready var player: Player = get_parent()


func _ready() -> void:
	if config == null:
		config = CarryConfig.new()
	stamina = Stamina.from_config(config)
	stamina.depleted.connect(_on_stamina_depleted)


func bind_diamond(diamond: Diamond) -> void:
	if _diamond == diamond:
		return
	if _diamond and _diamond.carrier_changed.is_connected(_on_carrier_changed):
		_diamond.carrier_changed.disconnect(_on_carrier_changed)
	_diamond = diamond
	if _diamond:
		_diamond.carrier_changed.connect(_on_carrier_changed)
		_on_carrier_changed(_diamond.carrier_id)


func is_carrying() -> bool:
	return _carrying


func speed_multiplier() -> float:
	return config.speed_multiplier if _carrying else 1.0


func can_jump() -> bool:
	return not _carrying


## С алмазом нельзя взаимодействовать с объектами уровня (DESIGN.md, «Перенос алмаза»).
func can_interact_with_objects() -> bool:
	return not _carrying


# --- Действия (запросы к хосту) ------------------------------------------------

func pick_up() -> void:
	if _diamond and not _carrying and stamina.can_pick_up():
		_diamond.request_pick_up.rpc_id(1)


func put_down() -> void:
	if _carrying:
		_diamond.request_put_down.rpc_id(1)


func pass_diamond() -> void:
	if _carrying:
		_diamond.request_pass.rpc_id(1)


## Бросок — туда, куда повёрнут персонаж.
func throw_diamond() -> void:
	if _carrying:
		_diamond.request_throw.rpc_id(1, player.facing_direction())


# --- Внутреннее ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		stamina.tick(delta, _carrying)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("interact"):
		if _carrying:
			put_down()
		else:
			pick_up()
	elif event.is_action_pressed("pass_diamond"):
		pass_diamond()
	elif event.is_action_pressed("throw_diamond"):
		throw_diamond()


func _on_carrier_changed(carrier_id: int) -> void:
	var carrying := carrier_id != 0 and carrier_id == player.get_multiplayer_authority()
	if carrying != _carrying:
		_carrying = carrying
		carrying_changed.emit(carrying)


## Выносливость кончилась — персонаж кладёт алмаз на пол.
func _on_stamina_depleted() -> void:
	if is_multiplayer_authority():
		put_down()
