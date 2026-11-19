extends GdUnitTestSuite

var durability: Durability
var signals: SignalLog


func before_test() -> void:
	durability = Durability.new(100.0, 3.5, 8.0)
	signals = SignalLog.watch(durability)


func test_starts_full() -> void:
	assert_float(durability.current).is_equal(100.0)
	assert_bool(durability.is_broken()).is_false()
	assert_float(durability.ratio()).is_equal_approx(1.0, 0.0001)


func test_weak_impact_deals_no_damage() -> void:
	assert_float(durability.apply_impact(3.5)).override_failure_message("удар ровно на пороге").is_equal(0.0)
	assert_float(durability.apply_impact(1.0)).is_equal(0.0)
	assert_float(durability.current).is_equal(100.0)
	assert_int(signals.count("changed")).is_equal(0)


func test_damage_grows_with_speed_above_threshold() -> void:
	var damage := durability.apply_impact(6.0)
	assert_float(damage).is_equal_approx((6.0 - 3.5) * 8.0, 0.0001)
	assert_float(durability.current).is_equal_approx(80.0, 0.0001)
	assert_int(signals.count("changed")).is_equal(1)
	assert_array(signals.args("changed")).is_equal([80.0, 100.0])


func test_damage_is_clamped_and_breaks_once() -> void:
	var damage := durability.apply_impact(100.0)
	assert_float(damage).override_failure_message("урон не больше остатка").is_equal_approx(100.0, 0.001)
	assert_float(durability.current).is_equal(0.0)
	assert_bool(durability.is_broken()).is_true()
	assert_int(signals.count("broken")).is_equal(1)


func test_no_damage_after_broken() -> void:
	durability.apply_impact(100.0)
	assert_float(durability.apply_impact(50.0)).is_equal(0.0)
	assert_int(signals.count("broken")).is_equal(1)


func test_destroy_breaks_immediately() -> void:
	durability.destroy()
	assert_bool(durability.is_broken()).is_true()
	durability.destroy()
	assert_int(signals.count("broken")).override_failure_message("повторное разрушение не испускает сигнал").is_equal(1)


func test_reset_restores_full_durability() -> void:
	durability.apply_impact(10.0)
	durability.reset()
	assert_float(durability.current).is_equal(100.0)
	assert_bool(durability.is_broken()).is_false()


func test_from_config_uses_config_values() -> void:
	var config := DiamondConfig.new()
	config.max_durability = 40.0
	config.min_impact_speed = 1.0
	config.damage_per_speed = 2.0
	var d := Durability.from_config(config)
	assert_float(d.maximum).is_equal(40.0)
	assert_float(d.apply_impact(4.0)).is_equal_approx(6.0, 0.0001)
