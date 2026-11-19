extends TestCase
## Подсказки HUD под полоской выносливости.


func test_carrying_explains_what_stamina_means() -> void:
	var text := Hud.stamina_hint_text(true, 0.8, 0.3)
	assert_true(text.contains("выносливость"), text)
	assert_true(text.contains("положишь алмаз"), "игрок должен понимать, что будет на нуле: " + text)


func test_low_stamina_warns_and_suggests_pass() -> void:
	var text := Hud.stamina_hint_text(true, 0.1, 0.3)
	assert_true(text.contains("Q"), "подсказать передачу: " + text)


func test_resting_below_pick_up_threshold_shows_threshold() -> void:
	var text := Hud.stamina_hint_text(false, 0.1, 0.3)
	assert_true(text.contains("30%"), text)


func test_resting_above_threshold_just_recovers() -> void:
	assert_eq(Hud.stamina_hint_text(false, 0.6, 0.3), "Выносливость восстанавливается")
