class_name CarryConfig
extends Resource
## Настройки переноса алмаза одним игроком. Правятся в data/carry_config.tres.

## Множитель скорости ходьбы с алмазом.
@export var speed_multiplier := 0.55
@export var max_stamina := 100.0
## Расход выносливости с алмазом, ед/с (100 / 12 ≈ 8 с непрерывного переноса).
@export var drain_per_second := 12.0
## Восстановление без алмаза, ед/с.
@export var regen_per_second := 25.0
## Меньше этого запаса поднять алмаз нельзя — чтобы не поднимать и сразу ронять.
@export var min_stamina_to_pick_up := 30.0
