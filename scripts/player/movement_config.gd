class_name MovementConfig
extends Resource
## Настройки движения персонажа и камеры. Правятся в data/movement_config.tres.

@export var walk_speed := 5.0
@export var acceleration := 30.0
@export var jump_velocity := 4.8
## Скорость поворота модели к направлению движения.
@export var turn_speed := 12.0
@export var mouse_sensitivity := 0.003
