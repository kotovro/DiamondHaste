class_name DiamondConfig
extends Resource
## Настройки алмаза. Значения подбираются на плейтестах: правятся в data/diamond_config.tres.

@export_group("Прочность")
@export var max_durability := 100.0
## Удары со сменой скорости не больше порога алмаз не повреждают, м/с.
@export var min_impact_speed := 3.5
## Урон за каждый м/с сверх порога.
@export var damage_per_speed := 8.0
## Ниже этой высоты алмаз считается потерянным и разрушается, м.
@export var kill_height := -10.0

@export_group("Перенос")
## Расстояние от точки хвата игрока до алмаза, на котором его можно поднять, м.
@export var pickup_radius := 1.6
## Максимальное расстояние между игроками для передачи, м.
@export var pass_radius := 2.5
## Расстояние от точки хвата до брошенного алмаза, на котором его ловят, м.
@export var catch_radius := 1.2

@export_group("Бросок")
@export var throw_speed := 7.0
@export var throw_lift := 3.0
## Брошенный алмаз считается упавшим, когда его скорость держится ниже порога заданное время.
@export var settle_speed := 0.3
@export var settle_time := 0.4
