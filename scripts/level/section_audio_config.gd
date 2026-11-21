class_name SectionAudioConfig
extends Resource
## Звук секции: тревога и сброс. Правится в data/section_audio_config.tres. Значения — заглушки, подбираются на плейтесте.

## Громкость сирены тревоги, дБ.
@export var siren_volume_db: float = -4.0
## Громкость звука сброса, дБ.
@export var reset_volume_db: float = 0.0
