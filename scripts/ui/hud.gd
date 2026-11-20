class_name Hud
extends Control
## HUD: прочность алмаза, выносливость локального игрока и лента событий.
## Обновляется только по сигналам: Main подключает алмаз (bind_diamond), локального игрока
## (bind_player) и секцию (bind_section): в конце паузы тревоги экран затемняется, после
## сброса — проявляется.

## Ниже этой доли выносливости полоска краснеет и подсказка предупреждает.
const LOW_STAMINA := 0.25
const EVENT_SECONDS := 2.5
const NORMAL_COLOR := Color(1, 1, 1)
const LOW_COLOR := Color(1, 0.35, 0.3)

@onready var durability_label: Label = %DurabilityLabel
@onready var stamina_panel: Control = %StaminaPanel
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var stamina_hint: Label = %StaminaHint
@onready var event_label: Label = %EventLabel
@onready var reset_fade: ColorRect = %ResetFade

var _player: Player
var _event_tween: Tween
var _section: SectionRoot
var _fade_tween: Tween


func _ready() -> void:
	stamina_panel.hide()
	event_label.text = ""
	reset_fade.modulate.a = 0.0
	reset_fade.hide()


func bind_diamond(diamond: Diamond) -> void:
	diamond.durability_changed.connect(_on_durability_changed)
	diamond.picked_up.connect(func(id: int) -> void: _show_event("%s взял алмаз" % _who(id)))
	diamond.put_down.connect(func(id: int) -> void: _show_event("%s положил алмаз" % _who(id)))
	diamond.passed.connect(_on_passed)
	diamond.thrown.connect(func(id: int) -> void: _show_event("%s бросил алмаз" % _who(id)))
	diamond.caught.connect(func(id: int, _thrower: int) -> void: _show_event("%s поймал алмаз" % _who(id)))
	diamond.damaged.connect(_on_damaged)
	diamond.destroyed.connect(func() -> void: _show_event("Алмаз разбит! Секция начинается заново"))
	_on_durability_changed(diamond.durability_value, diamond.max_durability())


func bind_player(player: Player) -> void:
	_player = player
	player.carry.stamina.changed.connect(_on_stamina_changed)
	player.carry.carrying_changed.connect(_on_carrying_changed)
	_refresh_stamina()


func bind_section(section: SectionRoot) -> void:
	_section = section
	section.alarm_started.connect(_on_alarm_started)
	section.section_reset.connect(_on_section_reset)


## Подсказка под полоской выносливости. Чистая функция — покрыта tests/unit/test_hud.gd.
static func stamina_hint_text(carrying: bool, ratio: float, min_ratio_to_pick_up: float) -> String:
	if carrying:
		if ratio < LOW_STAMINA:
			return "Силы на исходе — сейчас положишь алмаз! Передай его напарнику (Q)"
		return "Алмаз тяжёлый: пока несёшь его один, тратится выносливость. Кончится — положишь алмаз"
	if ratio < min_ratio_to_pick_up:
		return "Отдышись: поднять алмаз можно, когда выносливость наберётся до %d%%" % roundi(min_ratio_to_pick_up * 100.0)
	return "Выносливость восстанавливается"


func _on_durability_changed(current: float, maximum: float) -> void:
	durability_label.text = "Алмаз: %d%%" % roundi(current / maximum * 100.0)


func _on_damaged(amount: float, current: float, maximum: float) -> void:
	if current > 0.0:
		_show_event("Удар! Алмаз −%d%%" % maxi(1, roundi(amount / maximum * 100.0)))


func _on_passed(from_id: int, to_id: int) -> void:
	var me := multiplayer.get_unique_id()
	if to_id == me:
		_show_event("%s передал тебе алмаз" % _who(from_id))
	elif from_id == me:
		_show_event("Ты передал алмаз напарнику")
	else:
		_show_event("%s передал алмаз: %s" % [_who(from_id), _who(to_id)])


func _on_stamina_changed(_current: float, _maximum: float) -> void:
	_refresh_stamina()


func _on_carrying_changed(_carrying: bool) -> void:
	_refresh_stamina()


func _refresh_stamina() -> void:
	if _player == null:
		return
	var carry := _player.carry
	var ratio := carry.stamina.ratio()
	var carrying := carry.is_carrying()
	stamina_panel.visible = carrying or ratio < 1.0
	stamina_bar.value = ratio * 100.0
	stamina_bar.modulate = LOW_COLOR if ratio < LOW_STAMINA else NORMAL_COLOR
	var min_ratio := carry.config.min_stamina_to_pick_up / carry.config.max_stamina
	stamina_hint.text = stamina_hint_text(carrying, ratio, min_ratio)


## Затемнение начинается так, чтобы закончиться к сбросу.
func _on_alarm_started(_cause: int, _actor_id: int) -> void:
	var fade_seconds := _section.config.reset_fade_seconds
	var wait := maxf(0.0, _section.config.reset_delay - fade_seconds)
	_start_fade()
	reset_fade.show()
	_fade_tween.tween_interval(wait)
	_fade_tween.tween_property(reset_fade, "modulate:a", 1.0, fade_seconds)


func _on_section_reset(_section_id: String) -> void:
	_start_fade()
	_fade_tween.tween_property(reset_fade, "modulate:a", 0.0, _section.config.reset_fade_seconds)
	_fade_tween.tween_callback(reset_fade.hide)


func _start_fade() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()


func _show_event(text: String) -> void:
	event_label.text = text
	event_label.modulate.a = 1.0
	if _event_tween:
		_event_tween.kill()
	_event_tween = create_tween()
	_event_tween.tween_interval(EVENT_SECONDS)
	_event_tween.tween_property(event_label, "modulate:a", 0.0, 0.5)


func _who(peer_id: int) -> String:
	if peer_id == multiplayer.get_unique_id():
		return "Ты"
	return "Хост" if peer_id == 1 else "Игрок 2"
