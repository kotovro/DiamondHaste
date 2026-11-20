class_name LaserConfig
extends Resource
## Настройки лазерного луча. Правятся в data/laser_config.tres. Значения — заглушки, подбираются на плейтесте.

@export_group("Луч")
## Высота оси луча над началом узла (полом), м.
@export var beam_height: float = 0.4
## Диаметр видимого луча и сторона сечения зоны касания, м.
@export var beam_thickness: float = 0.05

@export_group("Правила")
## Засчитывается ли касание свободным алмазом (decision-03 C, по умолчанию B).
@export var reacts_to_diamond: bool = true
## Что происходит при срабатывании (decision-02 A: поимка — сброс секции).
@export var consequence: Obstacle.Consequence = Obstacle.Consequence.SECTION_RESET

@export_group("Вид")
## Цвет спокойного луча.
@export var beam_color: Color = Color(1.0, 0.12, 0.1)
## Второй цвет мигания в тревоге.
@export var alarm_color: Color = Color(1.0, 0.85, 0.2)
## Частота мигания луча и света в тревоге, Гц.
@export var alarm_blink_hz: float = 6.0
## Энергия подсветки вокруг луча в покое.
@export var light_energy_calm: float = 0.4
## Энергия подсветки в тревоге (пик мигания).
@export var light_energy_alarm: float = 3.0
## Радиус подсветки, м.
@export var light_range: float = 4.0
