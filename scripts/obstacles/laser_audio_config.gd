class_name LaserAudioConfig
extends Resource
## Звук лазерного луча. Правится в data/laser_audio_config.tres. Значения — заглушки, подбираются на плейтесте.

@export_group("Гудение")
## Громкость гудения луча, дБ.
@export var hum_volume_db: float = -12.0
## Дальше этого расстояния гудения не слышно, м (К17).
@export var hum_max_distance: float = 6.0
## Расстояние, на котором гудение звучит без ослабления, м (unit_size плеера).
@export var hum_unit_size: float = 2.0

@export_group("Касание")
## Громкость треска касания, дБ.
@export var zap_volume_db: float = 0.0
## Дальше этого расстояния треска касания не слышно, м.
@export var zap_max_distance: float = 40.0
