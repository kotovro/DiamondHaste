class_name SectionReset
extends RefCounted
## Логика сброса секции: ACTIVE → ALARM → ACTIVE. Одно срабатывание — один сброс:
## причины во время тревоги отбрасываются. Чистая логика, покрыта tests/unit/test_section_reset.gd.

enum State { ACTIVE, ALARM }
## Почему начинается сброс.
enum Cause { PLAYER_CAUGHT, DIAMOND_TOUCHED, DIAMOND_DESTROYED }

var state: State = State.ACTIVE
## Причина текущей (или последней) тревоги.
var cause: Cause = Cause.PLAYER_CAUGHT
## Виновник: peer id задевшего игрока или 0.
var actor_id: int = 0


func is_alarm() -> bool:
	return state == State.ALARM


## Начать тревогу. Во время тревоги — false, причина и виновник прежние.
func begin(p_cause: Cause, p_actor_id: int) -> bool:
	if state == State.ALARM:
		return false
	state = State.ALARM
	cause = p_cause
	actor_id = p_actor_id
	return true


## Закончить тревогу (сброс выполнен). Без тревоги — false.
func finish() -> bool:
	if state != State.ALARM:
		return false
	state = State.ACTIVE
	return true


static func cause_for_touch(target: Obstacle.Target) -> Cause:
	if target == Obstacle.Target.DIAMOND:
		return Cause.DIAMOND_TOUCHED
	return Cause.PLAYER_CAUGHT


## Ведёт ли последствие препятствия к сбросу секции.
static func consequence_resets(consequence: Obstacle.Consequence) -> bool:
	return consequence == Obstacle.Consequence.SECTION_RESET
