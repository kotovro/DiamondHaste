extends GdUnitTestSuite
## Подсказки HUD под полоской выносливости.


func test_carrying_explains_what_stamina_means() -> void:
	var text := Hud.stamina_hint_text(true, 0.8, 0.3)
	assert_str(text).contains("выносливость")
	assert_str(text).override_failure_message("игрок должен понимать, что будет на нуле: " + text).contains("положишь алмаз")


func test_low_stamina_warns_and_suggests_pass() -> void:
	var text := Hud.stamina_hint_text(true, 0.1, 0.3)
	assert_str(text).override_failure_message("подсказать передачу: " + text).contains("Q")


func test_resting_below_pick_up_threshold_shows_threshold() -> void:
	assert_str(Hud.stamina_hint_text(false, 0.1, 0.3)).contains("30%")


func test_resting_above_threshold_just_recovers() -> void:
	assert_str(Hud.stamina_hint_text(false, 0.6, 0.3)).is_equal("Выносливость восстанавливается")
