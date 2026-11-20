extends GdUnitTestSuite
## Кто судит касание препятствия: Obstacle.judges_here (docs/tech/obstacles.md, раздел 2).
## Своё тело судит его владелец — и на хосте, и на клиенте (опора К14);
## чужое тело не судит никто на этой машине; свободный алмаз — только хост.


func test_own_body_is_judged_on_host() -> void:
	assert_bool(Obstacle.judges_here(Obstacle.Target.PLAYER, true, true)).is_true()


func test_own_body_is_judged_on_client() -> void:
	assert_bool(Obstacle.judges_here(Obstacle.Target.PLAYER, true, false)) \
		.override_failure_message("клиент сам судит касание своего тела, без задержки (К14)").is_true()


func test_foreign_body_is_judged_nowhere() -> void:
	assert_bool(Obstacle.judges_here(Obstacle.Target.PLAYER, false, true)) \
		.override_failure_message("хост не судит чужого персонажа").is_false()
	assert_bool(Obstacle.judges_here(Obstacle.Target.PLAYER, false, false)) \
		.override_failure_message("клиент не судит чужого персонажа").is_false()


func test_diamond_is_judged_only_on_host() -> void:
	assert_bool(Obstacle.judges_here(Obstacle.Target.DIAMOND, false, true)).is_true()
	assert_bool(Obstacle.judges_here(Obstacle.Target.DIAMOND, false, false)) \
		.override_failure_message("клиент не судит касание алмаза").is_false()
	assert_bool(Obstacle.judges_here(Obstacle.Target.DIAMOND, true, false)) \
		.override_failure_message("для алмаза «своё тело» не важно: на клиенте — нет").is_false()
	assert_bool(Obstacle.judges_here(Obstacle.Target.DIAMOND, true, true)) \
		.override_failure_message("для алмаза «своё тело» не важно: на хосте — да").is_true()
