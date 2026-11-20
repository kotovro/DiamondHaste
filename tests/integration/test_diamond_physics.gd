extends GdUnitTestSuite
## Прочность алмаза в настоящей физике: удар об пол определяется по смене скорости.

const DIAMOND_SCENE := preload("res://scenes/props/diamond.tscn")
## Расстояние от центра алмаза до острия павильона, м.
const DIAMOND_BOTTOM := 0.222


func before_test() -> void:
	add_child(auto_free(TestWorld.make_floor(30.0)))


func test_gentle_landing_deals_no_damage() -> void:
	var diamond := _spawn_diamond(DIAMOND_BOTTOM + 0.05)
	await TestWorld.physics_frames(self, 60)
	assert_float(diamond.durability_value).is_equal_approx(diamond.max_durability(), 0.001)


func test_high_fall_damages_diamond() -> void:
	var diamond := _spawn_diamond(4.0)
	var signals := SignalLog.watch(diamond)
	await TestWorld.physics_frames(self, 90)
	assert_float(diamond.durability_value).override_failure_message("падение с 4 м должно повредить алмаз").is_less(diamond.max_durability())
	assert_float(diamond.durability_value).override_failure_message("но не разрушить").is_greater(0.0)
	assert_int(signals.count("damaged")).is_greater(0)
	assert_int(signals.count("durability_changed")).is_greater(0)
	assert_int(signals.count("destroyed")).is_equal(0)


func test_falling_out_of_level_destroys_diamond() -> void:
	var diamond := _spawn_diamond(1.0)
	var signals := SignalLog.watch(diamond)
	diamond.global_position = Vector3(0.0, diamond.config.kill_height - 1.0, 0.0)
	await TestWorld.physics_frames(self, 3)
	assert_float(diamond.durability_value).is_equal(0.0)
	assert_int(signals.count("destroyed")).is_equal(1)


func test_reset_restores_position_and_durability() -> void:
	var diamond := _spawn_diamond(4.0)
	var start := diamond.global_position
	await TestWorld.physics_frames(self, 90)
	var signals := SignalLog.watch(diamond)
	diamond.reset_to_start()
	assert_vector(diamond.global_position).is_equal(start)
	assert_float(diamond.durability_value).is_equal(diamond.max_durability())
	assert_int(signals.count("restored")).is_equal(1)


func _spawn_diamond(height: float) -> Diamond:
	var diamond: Diamond = auto_free(DIAMOND_SCENE.instantiate())
	diamond.position = Vector3(0.0, height, 0.0)
	add_child(diamond)
	return diamond
