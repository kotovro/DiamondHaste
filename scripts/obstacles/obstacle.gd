class_name Obstacle
extends RefCounted
## Общее для всех препятствий: перечисления и правило «кто судит касание»
## (docs/tech/obstacles.md, разделы 1–2). Только перечисления и статика, без состояния.

## Что коснулось препятствия.
enum Target { PLAYER, DIAMOND }

## Последствие срабатывания — поле конфига препятствия; разбирает его SectionRoot на хосте.
enum Consequence { NONE, SECTION_RESET }


## Судит ли касание эта машина. Своё тело судит его владелец (и на хосте, и на клиенте),
## чужое — никто здесь; свободный алмаз судит хост.
static func judges_here(target: Target, is_own_body: bool, is_host: bool) -> bool:
	if target == Target.PLAYER:
		return is_own_body
	return is_host
