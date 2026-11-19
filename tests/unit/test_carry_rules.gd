extends TestCase

const HOST := 1
const GUEST := 2

var rules: CarryRules


func before_each() -> void:
	rules = CarryRules.new(1.6, 2.5, 1.2)
	watch_signals(rules)


func test_starts_resting_with_nobody() -> void:
	assert_eq(rules.state, CarryRules.State.RESTING)
	assert_eq(rules.carrier_id, CarryRules.NOBODY)


func test_pick_up_within_radius() -> void:
	assert_true(rules.pick_up(HOST, 1.0))
	assert_eq(rules.state, CarryRules.State.CARRIED)
	assert_true(rules.is_carried_by(HOST))
	assert_signal_emit_count(rules, "changed", 1)


func test_pick_up_rejected_out_of_radius() -> void:
	assert_false(rules.pick_up(HOST, 1.7))
	assert_eq(rules.state, CarryRules.State.RESTING)
	assert_signal_not_emitted(rules, "changed")


func test_cannot_take_diamond_from_carrier() -> void:
	rules.pick_up(HOST, 0.5)
	assert_false(rules.pick_up(GUEST, 0.5))
	assert_true(rules.is_carried_by(HOST))


func test_only_carrier_can_put_down() -> void:
	rules.pick_up(HOST, 0.5)
	assert_false(rules.put_down(GUEST))
	assert_true(rules.put_down(HOST))
	assert_eq(rules.state, CarryRules.State.RESTING)
	assert_eq(rules.carrier_id, CarryRules.NOBODY)


func test_pass_to_partner_within_radius() -> void:
	rules.pick_up(HOST, 0.5)
	assert_true(rules.pass_to(HOST, GUEST, 2.0))
	assert_true(rules.is_carried_by(GUEST))


func test_pass_rejected_cases() -> void:
	rules.pick_up(HOST, 0.5)
	assert_false(rules.pass_to(HOST, GUEST, 3.0), "слишком далеко")
	assert_false(rules.pass_to(HOST, HOST, 0.0), "самому себе")
	assert_false(rules.pass_to(GUEST, HOST, 1.0), "передаёт не тот, кто несёт")
	assert_false(rules.pass_to(HOST, CarryRules.NOBODY, 1.0), "никому")
	assert_true(rules.is_carried_by(HOST))


func test_throw_puts_diamond_in_flight() -> void:
	rules.pick_up(HOST, 0.5)
	assert_false(rules.throw(GUEST), "бросает не тот, кто несёт")
	assert_true(rules.throw(HOST))
	assert_eq(rules.state, CarryRules.State.THROWN)
	assert_eq(rules.thrower_id, HOST)
	assert_eq(rules.carrier_id, CarryRules.NOBODY)


func test_thrower_cannot_catch_or_pick_up_own_throw() -> void:
	rules.pick_up(HOST, 0.5)
	rules.throw(HOST)
	assert_false(rules.try_catch(HOST, 0.1))
	assert_false(rules.pick_up(HOST, 0.1))
	assert_eq(rules.state, CarryRules.State.THROWN)


func test_partner_catches_within_radius() -> void:
	rules.pick_up(HOST, 0.5)
	rules.throw(HOST)
	assert_false(rules.try_catch(GUEST, 1.5), "слишком далеко")
	assert_true(rules.try_catch(GUEST, 1.0))
	assert_true(rules.is_carried_by(GUEST))
	assert_eq(rules.thrower_id, CarryRules.NOBODY)


func test_catch_only_while_thrown() -> void:
	assert_false(rules.try_catch(GUEST, 0.1), "лежащий алмаз не ловят, а поднимают")


func test_settle_ends_flight() -> void:
	rules.pick_up(HOST, 0.5)
	rules.throw(HOST)
	rules.settle()
	assert_eq(rules.state, CarryRules.State.RESTING)
	assert_true(rules.pick_up(HOST, 0.5), "после остановки бросивший может поднять")


func test_settle_does_nothing_when_carried() -> void:
	rules.pick_up(HOST, 0.5)
	rules.settle()
	assert_true(rules.is_carried_by(HOST))


func test_release_peer_drops_diamond_of_disconnected_carrier() -> void:
	rules.pick_up(GUEST, 0.5)
	rules.release_peer(HOST)
	assert_true(rules.is_carried_by(GUEST), "отключился не тот, кто несёт")
	rules.release_peer(GUEST)
	assert_eq(rules.state, CarryRules.State.RESTING)


func test_reset_returns_to_resting() -> void:
	rules.pick_up(HOST, 0.5)
	rules.throw(HOST)
	rules.reset()
	assert_eq(rules.state, CarryRules.State.RESTING)
	assert_eq(rules.thrower_id, CarryRules.NOBODY)
