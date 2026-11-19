extends TestCase

var durability: Durability


func before_each() -> void:
	durability = Durability.new(100.0, 3.5, 8.0)
	watch_signals(durability)


func test_starts_full() -> void:
	assert_eq(durability.current, 100.0)
	assert_false(durability.is_broken())
	assert_almost_eq(durability.ratio(), 1.0)


func test_weak_impact_deals_no_damage() -> void:
	assert_eq(durability.apply_impact(3.5), 0.0, "удар ровно на пороге")
	assert_eq(durability.apply_impact(1.0), 0.0)
	assert_eq(durability.current, 100.0)
	assert_signal_not_emitted(durability, "changed")


func test_damage_grows_with_speed_above_threshold() -> void:
	var damage := durability.apply_impact(6.0)
	assert_almost_eq(damage, (6.0 - 3.5) * 8.0)
	assert_almost_eq(durability.current, 80.0)
	assert_signal_emit_count(durability, "changed", 1)
	assert_eq(get_signal_args(durability, "changed"), [80.0, 100.0])


func test_damage_is_clamped_and_breaks_once() -> void:
	var damage := durability.apply_impact(100.0)
	assert_almost_eq(damage, 100.0, 0.001, "урон не больше остатка")
	assert_eq(durability.current, 0.0)
	assert_true(durability.is_broken())
	assert_signal_emit_count(durability, "broken", 1)


func test_no_damage_after_broken() -> void:
	durability.apply_impact(100.0)
	assert_eq(durability.apply_impact(50.0), 0.0)
	assert_signal_emit_count(durability, "broken", 1)


func test_destroy_breaks_immediately() -> void:
	durability.destroy()
	assert_true(durability.is_broken())
	durability.destroy()
	assert_signal_emit_count(durability, "broken", 1, "повторное разрушение не испускает сигнал")


func test_reset_restores_full_durability() -> void:
	durability.apply_impact(10.0)
	durability.reset()
	assert_eq(durability.current, 100.0)
	assert_false(durability.is_broken())


func test_from_config_uses_config_values() -> void:
	var config := DiamondConfig.new()
	config.max_durability = 40.0
	config.min_impact_speed = 1.0
	config.damage_per_speed = 2.0
	var d := Durability.from_config(config)
	assert_eq(d.maximum, 40.0)
	assert_almost_eq(d.apply_impact(4.0), 6.0)
