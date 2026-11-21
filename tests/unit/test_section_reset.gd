extends GdUnitTestSuite
## Логика сброса секции SectionReset: ACTIVE → ALARM → ACTIVE, одно срабатывание — один сброс.

var rules: SectionReset


func before_test() -> void:
	rules = SectionReset.new()


func test_starts_active() -> void:
	assert_int(rules.state).is_equal(SectionReset.State.ACTIVE)
	assert_bool(rules.is_alarm()).is_false()


func test_begin_starts_alarm_and_remembers_cause() -> void:
	assert_bool(rules.begin(SectionReset.Cause.DIAMOND_TOUCHED, 0)).is_true()
	assert_int(rules.state).is_equal(SectionReset.State.ALARM)
	assert_bool(rules.is_alarm()).is_true()
	assert_int(rules.cause).is_equal(SectionReset.Cause.DIAMOND_TOUCHED)
	assert_int(rules.actor_id).is_equal(0)


func test_begin_remembers_culprit() -> void:
	rules.begin(SectionReset.Cause.PLAYER_CAUGHT, 2)
	assert_int(rules.cause).is_equal(SectionReset.Cause.PLAYER_CAUGHT)
	assert_int(rules.actor_id).is_equal(2)


func test_second_begin_during_alarm_is_rejected() -> void:
	rules.begin(SectionReset.Cause.PLAYER_CAUGHT, 1)
	assert_bool(rules.begin(SectionReset.Cause.DIAMOND_DESTROYED, 0)) \
		.override_failure_message("вторая причина во время тревоги отбрасывается (К12)").is_false()
	assert_bool(rules.is_alarm()).is_true()
	assert_int(rules.cause).override_failure_message("причина остаётся первой").is_equal(SectionReset.Cause.PLAYER_CAUGHT)
	assert_int(rules.actor_id).override_failure_message("виновник остаётся первым").is_equal(1)


func test_finish_returns_to_active() -> void:
	rules.begin(SectionReset.Cause.PLAYER_CAUGHT, 1)
	assert_bool(rules.finish()).is_true()
	assert_int(rules.state).is_equal(SectionReset.State.ACTIVE)
	assert_bool(rules.is_alarm()).is_false()


func test_finish_when_active_is_rejected() -> void:
	assert_bool(rules.finish()).is_false()
	assert_int(rules.state).is_equal(SectionReset.State.ACTIVE)


func test_begin_works_again_after_finish() -> void:
	rules.begin(SectionReset.Cause.PLAYER_CAUGHT, 1)
	rules.finish()
	assert_bool(rules.begin(SectionReset.Cause.DIAMOND_DESTROYED, 0)).is_true()
	assert_int(rules.cause).is_equal(SectionReset.Cause.DIAMOND_DESTROYED)
	assert_int(rules.actor_id).is_equal(0)


func test_cause_for_touch() -> void:
	assert_int(SectionReset.cause_for_touch(Obstacle.Target.PLAYER)).is_equal(SectionReset.Cause.PLAYER_CAUGHT)
	assert_int(SectionReset.cause_for_touch(Obstacle.Target.DIAMOND)).is_equal(SectionReset.Cause.DIAMOND_TOUCHED)


func test_consequence_resets() -> void:
	assert_bool(SectionReset.consequence_resets(Obstacle.Consequence.SECTION_RESET)).is_true()
	assert_bool(SectionReset.consequence_resets(Obstacle.Consequence.NONE)).is_false()
