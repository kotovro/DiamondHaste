extends GdUnitTestSuite
## Логика лазера LaserTouch: взвод, «засчитывается ли касание», срабатывание.

const PLAYER := Obstacle.Target.PLAYER
const DIAMOND := Obstacle.Target.DIAMOND


func test_starts_armed_and_not_tripped() -> void:
	var touch := LaserTouch.new()
	assert_bool(touch.armed).is_true()
	assert_bool(touch.tripped).is_false()
	assert_bool(touch.reacts_to_diamond).override_failure_message("по умолчанию луч реагирует на алмаз (decision-03)").is_true()


func test_player_counts_when_armed() -> void:
	assert_bool(LaserTouch.new(true).counts(PLAYER)).is_true()
	assert_bool(LaserTouch.new(false).counts(PLAYER)) \
		.override_failure_message("игрок засчитывается независимо от реакции на алмаз").is_true()


func test_diamond_counts_only_when_reacting() -> void:
	assert_bool(LaserTouch.new(true).counts(DIAMOND)).is_true()
	assert_bool(LaserTouch.new(false).counts(DIAMOND)).is_false()


func test_nothing_counts_after_trip() -> void:
	var touch := LaserTouch.new(true)
	touch.trip()
	assert_bool(touch.tripped).is_true()
	assert_bool(touch.armed).is_false()
	assert_bool(touch.counts(PLAYER)).override_failure_message("после срабатывания игрок не засчитывается").is_false()
	assert_bool(touch.counts(DIAMOND)).override_failure_message("после срабатывания алмаз не засчитывается").is_false()


func test_second_trip_changes_nothing() -> void:
	var touch := LaserTouch.new(true)
	touch.trip()
	touch.trip()
	assert_bool(touch.tripped).is_true()
	assert_bool(touch.armed).is_false()


func test_disarm_ignores_everything_and_keeps_tripped() -> void:
	var touch := LaserTouch.new(true)
	touch.disarm()
	assert_bool(touch.armed).is_false()
	assert_bool(touch.tripped).override_failure_message("снятие с взвода — не срабатывание").is_false()
	assert_bool(touch.counts(PLAYER)).is_false()
	assert_bool(touch.counts(DIAMOND)).is_false()

	var tripped_touch := LaserTouch.new(true)
	tripped_touch.trip()
	tripped_touch.disarm()
	assert_bool(tripped_touch.tripped).override_failure_message("disarm не сбрасывает tripped").is_true()


func test_arm_after_trip_returns_true_and_counts_again() -> void:
	var touch := LaserTouch.new(true)
	touch.trip()
	assert_bool(touch.arm()).override_failure_message("arm() сообщает, что луч сработал раньше").is_true()
	assert_bool(touch.armed).is_true()
	assert_bool(touch.tripped).is_false()
	assert_bool(touch.counts(PLAYER)).is_true()
	assert_bool(touch.counts(DIAMOND)).is_true()


func test_arm_without_trip_returns_false() -> void:
	var touch := LaserTouch.new(true)
	assert_bool(touch.arm()).override_failure_message("взведённый луч не срабатывал").is_false()
	touch.disarm()
	assert_bool(touch.arm()).override_failure_message("снятый с взвода луч не срабатывал").is_false()
	assert_bool(touch.armed).is_true()


func test_from_config_takes_reacts_to_diamond() -> void:
	var config := LaserConfig.new()
	config.reacts_to_diamond = false
	assert_bool(LaserTouch.from_config(config).reacts_to_diamond).is_false()
	config.reacts_to_diamond = true
	assert_bool(LaserTouch.from_config(config).reacts_to_diamond).is_true()
