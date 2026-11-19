extends GdUnitTestSuite

const HOST := 1
const GUEST := 2

var rules: CarryRules
var signals: SignalLog


func before_test() -> void:
	rules = CarryRules.new(1.6, 2.5, 1.2)
	signals = SignalLog.watch(rules)


func test_starts_resting_with_nobody() -> void:
	assert_int(rules.state).is_equal(CarryRules.State.RESTING)
	assert_int(rules.carrier_id).is_equal(CarryRules.NOBODY)


func test_pick_up_within_radius() -> void:
	assert_bool(rules.pick_up(HOST, 1.0)).is_true()
	assert_int(rules.state).is_equal(CarryRules.State.CARRIED)
	assert_bool(rules.is_carried_by(HOST)).is_true()
	assert_int(signals.count("changed")).is_equal(1)


func test_pick_up_rejected_out_of_radius() -> void:
	assert_bool(rules.pick_up(HOST, 1.7)).is_false()
	assert_int(rules.state).is_equal(CarryRules.State.RESTING)
	assert_int(signals.count("changed")).is_equal(0)


func test_cannot_take_diamond_from_carrier() -> void:
	rules.pick_up(HOST, 0.5)
	assert_bool(rules.pick_up(GUEST, 0.5)).is_false()
	assert_bool(rules.is_carried_by(HOST)).is_true()


func test_only_carrier_can_put_down() -> void:
	rules.pick_up(HOST, 0.5)
	assert_bool(rules.put_down(GUEST)).is_false()
	assert_bool(rules.put_down(HOST)).is_true()
	assert_int(rules.state).is_equal(CarryRules.State.RESTING)
	assert_int(rules.carrier_id).is_equal(CarryRules.NOBODY)


func test_pass_to_partner_within_radius() -> void:
	rules.pick_up(HOST, 0.5)
	assert_bool(rules.pass_to(HOST, GUEST, 2.0)).is_true()
	assert_bool(rules.is_carried_by(GUEST)).is_true()


func test_pass_rejected_cases() -> void:
	rules.pick_up(HOST, 0.5)
	assert_bool(rules.pass_to(HOST, GUEST, 3.0)).override_failure_message("слишком далеко").is_false()
	assert_bool(rules.pass_to(HOST, HOST, 0.0)).override_failure_message("самому себе").is_false()
	assert_bool(rules.pass_to(GUEST, HOST, 1.0)).override_failure_message("передаёт не тот, кто несёт").is_false()
	assert_bool(rules.pass_to(HOST, CarryRules.NOBODY, 1.0)).override_failure_message("никому").is_false()
	assert_bool(rules.is_carried_by(HOST)).is_true()


func test_throw_puts_diamond_in_flight() -> void:
	rules.pick_up(HOST, 0.5)
	assert_bool(rules.throw(GUEST)).override_failure_message("бросает не тот, кто несёт").is_false()
	assert_bool(rules.throw(HOST)).is_true()
	assert_int(rules.state).is_equal(CarryRules.State.THROWN)
	assert_int(rules.thrower_id).is_equal(HOST)
	assert_int(rules.carrier_id).is_equal(CarryRules.NOBODY)


func test_thrower_cannot_catch_or_pick_up_own_throw() -> void:
	rules.pick_up(HOST, 0.5)
	rules.throw(HOST)
	assert_bool(rules.try_catch(HOST, 0.1)).is_false()
	assert_bool(rules.pick_up(HOST, 0.1)).is_false()
	assert_int(rules.state).is_equal(CarryRules.State.THROWN)


func test_partner_catches_within_radius() -> void:
	rules.pick_up(HOST, 0.5)
	rules.throw(HOST)
	assert_bool(rules.try_catch(GUEST, 1.5)).override_failure_message("слишком далеко").is_false()
	assert_bool(rules.try_catch(GUEST, 1.0)).is_true()
	assert_bool(rules.is_carried_by(GUEST)).is_true()
	assert_int(rules.thrower_id).is_equal(CarryRules.NOBODY)


func test_catch_only_while_thrown() -> void:
	assert_bool(rules.try_catch(GUEST, 0.1)).override_failure_message("лежащий алмаз не ловят, а поднимают").is_false()


func test_settle_ends_flight() -> void:
	rules.pick_up(HOST, 0.5)
	rules.throw(HOST)
	rules.settle()
	assert_int(rules.state).is_equal(CarryRules.State.RESTING)
	assert_bool(rules.pick_up(HOST, 0.5)).override_failure_message("после остановки бросивший может поднять").is_true()


func test_settle_does_nothing_when_carried() -> void:
	rules.pick_up(HOST, 0.5)
	rules.settle()
	assert_bool(rules.is_carried_by(HOST)).is_true()


func test_release_peer_drops_diamond_of_disconnected_carrier() -> void:
	rules.pick_up(GUEST, 0.5)
	rules.release_peer(HOST)
	assert_bool(rules.is_carried_by(GUEST)).override_failure_message("отключился не тот, кто несёт").is_true()
	rules.release_peer(GUEST)
	assert_int(rules.state).is_equal(CarryRules.State.RESTING)


func test_reset_returns_to_resting() -> void:
	rules.pick_up(HOST, 0.5)
	rules.throw(HOST)
	rules.reset()
	assert_int(rules.state).is_equal(CarryRules.State.RESTING)
	assert_int(rules.thrower_id).is_equal(CarryRules.NOBODY)
