extends TestCase

var stamina: Stamina


func before_each() -> void:
	stamina = Stamina.new(100.0, 10.0, 20.0, 30.0)
	watch_signals(stamina)


func test_drains_while_carrying() -> void:
	stamina.tick(2.0, true)
	assert_almost_eq(stamina.current, 80.0)
	assert_eq(get_signal_args(stamina, "changed"), [80.0, 100.0])


func test_no_changed_event_when_full_and_resting() -> void:
	stamina.tick(1.0, false)
	assert_signal_not_emitted(stamina, "changed")


func test_regenerates_without_diamond_up_to_maximum() -> void:
	stamina.tick(5.0, true)
	stamina.tick(1.0, false)
	assert_almost_eq(stamina.current, 70.0)
	stamina.tick(100.0, false)
	assert_eq(stamina.current, 100.0)


func test_depleted_emitted_once_and_never_negative() -> void:
	stamina.tick(9.0, true)
	assert_signal_not_emitted(stamina, "depleted")
	stamina.tick(5.0, true)
	assert_eq(stamina.current, 0.0)
	assert_true(stamina.is_depleted())
	stamina.tick(5.0, true)
	assert_eq(stamina.current, 0.0)
	assert_signal_emit_count(stamina, "depleted", 1)


func test_pick_up_requires_minimum_stamina() -> void:
	assert_true(stamina.can_pick_up())
	stamina.tick(7.5, true)
	assert_false(stamina.can_pick_up(), "25 < 30")
	stamina.tick(0.25, false)
	assert_true(stamina.can_pick_up(), "ровно 30")


func test_from_config_uses_config_values() -> void:
	var config := CarryConfig.new()
	config.max_stamina = 50.0
	config.drain_per_second = 5.0
	var s := Stamina.from_config(config)
	s.tick(2.0, true)
	assert_almost_eq(s.current, 40.0)
	assert_almost_eq(s.ratio(), 0.8)
