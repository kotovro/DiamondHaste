extends GdUnitTestSuite

var stamina: Stamina
var signals: SignalLog


func before_test() -> void:
	stamina = Stamina.new(100.0, 10.0, 20.0, 30.0)
	signals = SignalLog.watch(stamina)


func test_drains_while_carrying() -> void:
	stamina.tick(2.0, true)
	assert_float(stamina.current).is_equal_approx(80.0, 0.0001)
	assert_array(signals.args("changed")).is_equal([80.0, 100.0])


func test_no_changed_event_when_full_and_resting() -> void:
	stamina.tick(1.0, false)
	assert_int(signals.count("changed")).is_equal(0)


func test_regenerates_without_diamond_up_to_maximum() -> void:
	stamina.tick(5.0, true)
	stamina.tick(1.0, false)
	assert_float(stamina.current).is_equal_approx(70.0, 0.0001)
	stamina.tick(100.0, false)
	assert_float(stamina.current).is_equal(100.0)


func test_depleted_emitted_once_and_never_negative() -> void:
	stamina.tick(9.0, true)
	assert_int(signals.count("depleted")).is_equal(0)
	stamina.tick(5.0, true)
	assert_float(stamina.current).is_equal(0.0)
	assert_bool(stamina.is_depleted()).is_true()
	stamina.tick(5.0, true)
	assert_float(stamina.current).is_equal(0.0)
	assert_int(signals.count("depleted")).is_equal(1)


func test_pick_up_requires_minimum_stamina() -> void:
	assert_bool(stamina.can_pick_up()).is_true()
	stamina.tick(7.5, true)
	assert_bool(stamina.can_pick_up()).override_failure_message("25 < 30").is_false()
	stamina.tick(0.25, false)
	assert_bool(stamina.can_pick_up()).override_failure_message("ровно 30").is_true()


func test_from_config_uses_config_values() -> void:
	var config := CarryConfig.new()
	config.max_stamina = 50.0
	config.drain_per_second = 5.0
	var s := Stamina.from_config(config)
	s.tick(2.0, true)
	assert_float(s.current).is_equal_approx(40.0, 0.0001)
	assert_float(s.ratio()).is_equal_approx(0.8, 0.0001)
