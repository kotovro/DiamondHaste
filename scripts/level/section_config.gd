class_name SectionConfig
extends Resource
## Настройки сброса секции. Правятся в data/section_config.tres. Значения — заглушки, подбираются на плейтесте.

## Пауза от начала тревоги до сброса, с. Общая для всех причин.
@export var reset_delay: float = 1.5
## Блокировать движение, прыжок и действия с алмазом на время тревоги.
@export var lock_controls_during_alarm: bool = true
## Затемнение в конце паузы и проявление после сброса, с.
@export var reset_fade_seconds: float = 0.4
