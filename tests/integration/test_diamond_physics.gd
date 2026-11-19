extends TestCase
## Прочность алмаза в настоящей физике: удар об пол определяется по смене скорости.

const DIAMOND_SCENE := preload("res://scenes/props/diamond.tscn")
## Расстояние от центра алмаза до острия павильона, м.
const DIAMOND_BOTTOM := 0.222


func before_each() -> void:
	add_child_autofree(_make_floor())


func test_gentle_landing_deals_no_damage() -> void:
	var diamond := _spawn_diamond(DIAMOND_BOTTOM + 0.05)
	await wait_physics_frames(60)
	assert_almost_eq(diamond.durability_value, diamond.max_durability(), 0.001)


func test_high_fall_damages_diamond() -> void:
	var diamond := _spawn_diamond(4.0)
	watch_signals(diamond)
	await wait_physics_frames(90)
	assert_lt(diamond.durability_value, diamond.max_durability(), "падение с 4 м должно повредить алмаз")
	assert_gt(diamond.durability_value, 0.0, "но не разрушить")
	assert_signal_emitted(diamond, "damaged")
	assert_signal_emitted(diamond, "durability_changed")
	assert_signal_not_emitted(diamond, "destroyed")


func test_falling_out_of_level_destroys_diamond() -> void:
	var diamond := _spawn_diamond(1.0)
	watch_signals(diamond)
	diamond.global_position = Vector3(0.0, diamond.config.kill_height - 1.0, 0.0)
	await wait_physics_frames(3)
	assert_eq(diamond.durability_value, 0.0)
	assert_signal_emit_count(diamond, "destroyed", 1)


func test_reset_restores_position_and_durability() -> void:
	var diamond := _spawn_diamond(4.0)
	var start := diamond.global_position
	await wait_physics_frames(90)
	watch_signals(diamond)
	diamond.reset_to_start()
	assert_eq(diamond.global_position, start)
	assert_eq(diamond.durability_value, diamond.max_durability())
	assert_signal_emit_count(diamond, "restored", 1)


func _spawn_diamond(height: float) -> Diamond:
	var diamond: Diamond = DIAMOND_SCENE.instantiate()
	diamond.position = Vector3(0.0, height, 0.0)
	add_child_autofree(diamond)
	return diamond


static func _make_floor() -> StaticBody3D:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 1.0, 30.0)
	shape.shape = box
	floor.add_child(shape)
	floor.position = Vector3(0.0, -0.5, 0.0)
	return floor
