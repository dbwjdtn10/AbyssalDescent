## Main gameplay HUD displaying player stats, floor info, and interaction prompts.
##
## Builds its entire UI tree programmatically so it has no .tscn dependency.
## Connects to EventBus for automatic updates of HP, gold, floor, and items.
class_name GameHUD
extends CanvasLayer

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color("#140f1a")
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_HP_BAR := Color(0.8, 0.13, 0.13, 1.0)        # #CC2222
const COLOR_HP_BAR_BG := Color(0.25, 0.08, 0.08, 0.8)
const COLOR_GOLD := Color("#FFD700")
const COLOR_FLOOR_TITLE := Color("#ebca42")
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.1, 0.75)
const COLOR_SLOT_BG := Color(0.1, 0.08, 0.12, 0.8)
const COLOR_SLOT_BORDER := Color(0.72, 0.58, 0.2, 0.4)
const COLOR_PROMPT_BG := Color(0.06, 0.04, 0.08, 0.85)
const COLOR_DAMAGE_FLASH := Color(0.85, 0.1, 0.1, 0.3)
const COLOR_PICKUP_BG := Color(0.08, 0.06, 0.1, 0.9)

# ── Rarity Colors ────────────────────────────────────────────────────────────

const RARITY_COLORS: Dictionary = {
	"common": Color("#c8c8c8"),
	"uncommon": Color("#4fc34f"),
	"rare": Color("#4f8fc3"),
	"epic": Color("#a64fc3"),
	"legendary": Color("#ebca42"),
}

# ── Constants ────────────────────────────────────────────────────────────────

const QUICK_SLOT_COUNT: int = 5
const FLOOR_TITLE_HOLD_TIME: float = 3.0
const FLOOR_TITLE_FADE_TIME: float = 0.8
const PROMPT_FADE_TIME: float = 0.2
const DAMAGE_FLASH_DURATION: float = 0.3
const PICKUP_HOLD_TIME: float = 2.5
const PICKUP_FADE_TIME: float = 0.4

# ── UI Node References ───────────────────────────────────────────────────────

var _top_left_panel: PanelContainer
var _hp_bar: ProgressBar
var _hp_label: Label
var _level_floor_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _gold_label: Label

var _floor_title_label: Label
var _floor_title_tween: Tween

var _prompt_panel: PanelContainer
var _prompt_label: Label
var _prompt_tween: Tween

var _quick_slots: Array[PanelContainer] = []

var _damage_overlay: ColorRect
var _damage_tween: Tween

var _pickup_panel: PanelContainer
var _pickup_label: Label
var _pickup_tween: Tween

# ── State ────────────────────────────────────────────────────────────────────

var _current_hp: float = 100.0
var _max_hp: float = 100.0
var _current_level: int = 1
var _current_floor: int = 1
var _current_gold: int = 0

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()
	visible = true


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	_build_top_left_panel()
	_build_floor_title()
	_build_quick_slots()
	_build_interaction_prompt()
	_build_damage_overlay()
	_build_controls_guide()
	_build_pickup_notification()


## Top-left: HP, level/floor, gold.
func _build_top_left_panel() -> void:
	_top_left_panel = PanelContainer.new()
	_top_left_panel.name = "TopLeftPanel"
	_top_left_panel.anchor_left = 0.0
	_top_left_panel.anchor_right = 0.0
	_top_left_panel.anchor_top = 0.0
	_top_left_panel.anchor_bottom = 0.0
	_top_left_panel.offset_left = 16.0
	_top_left_panel.offset_top = 16.0
	_top_left_panel.offset_right = 260.0
	_top_left_panel.offset_bottom = 150.0
	_top_left_panel.custom_minimum_size = Vector2(240, 130)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	_apply_corner_radius(panel_style, 6)
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	_top_left_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_top_left_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "StatsVBox"
	vbox.add_theme_constant_override("separation", 6)
	_top_left_panel.add_child(vbox)

	# HP bar.
	var hp_container := VBoxContainer.new()
	hp_container.add_theme_constant_override("separation", 2)
	vbox.add_child(hp_container)

	var hp_header := HBoxContainer.new()
	hp_header.add_theme_constant_override("separation", 4)
	hp_container.add_child(hp_header)

	var hp_icon := Label.new()
	hp_icon.text = "♥"
	hp_icon.add_theme_font_size_override("font_size", 14)
	hp_icon.add_theme_color_override("font_color", COLOR_HP_BAR)
	hp_header.add_child(hp_icon)

	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.text = "100 / 100"
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.add_theme_color_override("font_color", COLOR_TEXT)
	hp_header.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 100.0
	_hp_bar.value = 100.0
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 14)

	var hp_bg_style := StyleBoxFlat.new()
	hp_bg_style.bg_color = COLOR_HP_BAR_BG
	_apply_corner_radius(hp_bg_style, 3)
	_hp_bar.add_theme_stylebox_override("background", hp_bg_style)

	var hp_fill_style := StyleBoxFlat.new()
	hp_fill_style.bg_color = COLOR_HP_BAR
	_apply_corner_radius(hp_fill_style, 3)
	_hp_bar.add_theme_stylebox_override("fill", hp_fill_style)
	hp_container.add_child(_hp_bar)

	# Level + Floor display.
	_level_floor_label = Label.new()
	_level_floor_label.name = "LevelFloorLabel"
	_level_floor_label.text = "Lv.1 | 1층"
	_level_floor_label.add_theme_font_size_override("font_size", 14)
	_level_floor_label.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(_level_floor_label)

	# XP bar.
	var xp_container := VBoxContainer.new()
	xp_container.add_theme_constant_override("separation", 1)
	vbox.add_child(xp_container)

	_xp_label = Label.new()
	_xp_label.name = "XPLabel"
	_xp_label.text = "XP 0 / 80"
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	xp_container.add_child(_xp_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.name = "XPBar"
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = 80.0
	_xp_bar.value = 0.0
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0, 8)

	var xp_bg_style := StyleBoxFlat.new()
	xp_bg_style.bg_color = Color(0.1, 0.12, 0.2, 0.8)
	_apply_corner_radius(xp_bg_style, 2)
	_xp_bar.add_theme_stylebox_override("background", xp_bg_style)

	var xp_fill_style := StyleBoxFlat.new()
	xp_fill_style.bg_color = Color(0.3, 0.5, 1.0, 1.0)
	_apply_corner_radius(xp_fill_style, 2)
	_xp_bar.add_theme_stylebox_override("fill", xp_fill_style)
	xp_container.add_child(_xp_bar)

	# Gold display.
	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.text = "💰 0"
	_gold_label.add_theme_font_size_override("font_size", 14)
	_gold_label.add_theme_color_override("font_color", COLOR_GOLD)
	vbox.add_child(_gold_label)


## Top-center: cinematic floor name display.
func _build_floor_title() -> void:
	_floor_title_label = Label.new()
	_floor_title_label.name = "FloorTitleLabel"
	_floor_title_label.text = ""
	_floor_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_floor_title_label.add_theme_font_size_override("font_size", 32)
	_floor_title_label.add_theme_color_override("font_color", COLOR_FLOOR_TITLE)

	# Center horizontally at the top.
	_floor_title_label.anchor_left = 0.0
	_floor_title_label.anchor_right = 1.0
	_floor_title_label.anchor_top = 0.0
	_floor_title_label.anchor_bottom = 0.0
	_floor_title_label.offset_top = 60.0
	_floor_title_label.offset_bottom = 110.0

	_floor_title_label.modulate = Color(1, 1, 1, 0)
	_floor_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_floor_title_label)


## Bottom-center: quick slot bar for consumable items.
## Slots are mapped to number keys 1-5 for quick use.
func _build_quick_slots() -> void:
	var slot_size: float = 48.0
	var slot_spacing: float = 6.0
	var total_width: float = slot_size * QUICK_SLOT_COUNT + slot_spacing * (QUICK_SLOT_COUNT - 1)

	var container := HBoxContainer.new()
	container.name = "QuickSlotBar"
	container.add_theme_constant_override("separation", int(slot_spacing))

	# Anchor to bottom-center.
	container.anchor_left = 0.5
	container.anchor_right = 0.5
	container.anchor_top = 1.0
	container.anchor_bottom = 1.0
	container.offset_left = -total_width * 0.5
	container.offset_right = total_width * 0.5
	container.offset_top = -70.0
	container.offset_bottom = -22.0
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	# Label above quick slots
	var hint_label := Label.new()
	hint_label.name = "QuickSlotHint"
	hint_label.text = "장비 슬롯 (I키로 인벤토리)"
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.add_theme_color_override("font_color", Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 0.5))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.anchor_left = 0.5
	hint_label.anchor_right = 0.5
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_left = -60.0
	hint_label.offset_right = 60.0
	hint_label.offset_top = -82.0
	hint_label.offset_bottom = -70.0
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint_label)

	for i in range(QUICK_SLOT_COUNT):
		var slot := PanelContainer.new()
		slot.name = "Slot_%d" % i
		slot.custom_minimum_size = Vector2(slot_size, slot_size)

		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = COLOR_SLOT_BG
		slot_style.border_color = COLOR_SLOT_BORDER
		slot_style.border_width_top = 1
		slot_style.border_width_bottom = 1
		slot_style.border_width_left = 1
		slot_style.border_width_right = 1
		_apply_corner_radius(slot_style, 4)
		slot.add_theme_stylebox_override("panel", slot_style)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Slot number label.
		var num_label := Label.new()
		num_label.text = str(i + 1)
		num_label.add_theme_font_size_override("font_size", 10)
		num_label.add_theme_color_override("font_color", Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 0.4))
		num_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(num_label)

		container.add_child(slot)
		_quick_slots.append(slot)


## Bottom-left: interaction prompt area.
func _build_interaction_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "PromptPanel"

	# Anchor to bottom-left.
	_prompt_panel.anchor_left = 0.0
	_prompt_panel.anchor_right = 0.0
	_prompt_panel.anchor_top = 1.0
	_prompt_panel.anchor_bottom = 1.0
	_prompt_panel.offset_left = 16.0
	_prompt_panel.offset_right = 280.0
	_prompt_panel.offset_top = -60.0
	_prompt_panel.offset_bottom = -22.0
	_prompt_panel.custom_minimum_size = Vector2(180, 36)

	var prompt_style := StyleBoxFlat.new()
	prompt_style.bg_color = COLOR_PROMPT_BG
	_apply_corner_radius(prompt_style, 4)
	prompt_style.content_margin_top = 6.0
	prompt_style.content_margin_bottom = 6.0
	prompt_style.content_margin_left = 12.0
	prompt_style.content_margin_right = 12.0
	prompt_style.border_color = COLOR_ACCENT
	prompt_style.border_width_left = 2
	_prompt_panel.add_theme_stylebox_override("panel", prompt_style)
	_prompt_panel.modulate = Color(1, 1, 1, 0)
	_prompt_panel.visible = false
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt_panel)

	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.text = ""
	_prompt_label.add_theme_font_size_override("font_size", 14)
	_prompt_label.add_theme_color_override("font_color", COLOR_TEXT)
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.add_child(_prompt_label)


## Full-screen damage flash overlay.
func _build_damage_overlay() -> void:
	_damage_overlay = ColorRect.new()
	_damage_overlay.name = "DamageOverlay"
	_damage_overlay.color = COLOR_DAMAGE_FLASH
	_damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_overlay.modulate = Color(1, 1, 1, 0)
	_damage_overlay.visible = false
	add_child(_damage_overlay)


## Controls guide shown at game start, fades out after a few seconds.
func _build_controls_guide() -> void:
	var guide := PanelContainer.new()
	guide.name = "ControlsGuide"
	guide.anchor_left = 0.5
	guide.anchor_right = 0.5
	guide.anchor_top = 1.0
	guide.anchor_bottom = 1.0
	guide.offset_left = -160.0
	guide.offset_right = 160.0
	guide.offset_top = -130.0
	guide.offset_bottom = -14.0
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.08, 0.85)
	_apply_corner_radius(style, 6)
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.border_color = COLOR_ACCENT
	style.border_width_bottom = 2
	guide.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	guide.add_child(vbox)

	var lines: Array[String] = [
		"[WASD]  이동",
		"[마우스]  시점 회전",
		"[E]  상호작용 / 전투 시작",
		"[I]  인벤토리",
		"[Tab]  퀘스트 로그",
		"[Esc]  일시정지",
	]
	for line in lines:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", COLOR_TEXT)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lbl)

	add_child(guide)

	# Fade out after 8 seconds.
	var fade_tween := create_tween()
	fade_tween.tween_interval(8.0)
	fade_tween.tween_property(guide, "modulate", Color(1, 1, 1, 0), 1.5)
	fade_tween.tween_callback(guide.queue_free)


## Pickup notification popup (appears near bottom-right).
func _build_pickup_notification() -> void:
	_pickup_panel = PanelContainer.new()
	_pickup_panel.name = "PickupPanel"

	# Anchor to bottom-right.
	_pickup_panel.anchor_left = 1.0
	_pickup_panel.anchor_right = 1.0
	_pickup_panel.anchor_top = 1.0
	_pickup_panel.anchor_bottom = 1.0
	_pickup_panel.offset_left = -300.0
	_pickup_panel.offset_right = -16.0
	_pickup_panel.offset_top = -60.0
	_pickup_panel.offset_bottom = -22.0
	_pickup_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pickup_panel.custom_minimum_size = Vector2(180, 36)

	var pickup_style := StyleBoxFlat.new()
	pickup_style.bg_color = COLOR_PICKUP_BG
	_apply_corner_radius(pickup_style, 4)
	pickup_style.content_margin_top = 6.0
	pickup_style.content_margin_bottom = 6.0
	pickup_style.content_margin_left = 12.0
	pickup_style.content_margin_right = 12.0
	pickup_style.border_color = COLOR_ACCENT
	pickup_style.border_width_top = 1
	pickup_style.border_width_bottom = 1
	pickup_style.border_width_left = 1
	pickup_style.border_width_right = 1
	_pickup_panel.add_theme_stylebox_override("panel", pickup_style)
	_pickup_panel.modulate = Color(1, 1, 1, 0)
	_pickup_panel.visible = false
	_pickup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pickup_panel)

	_pickup_label = Label.new()
	_pickup_label.name = "PickupLabel"
	_pickup_label.text = ""
	_pickup_label.add_theme_font_size_override("font_size", 14)
	_pickup_label.add_theme_color_override("font_color", COLOR_TEXT)
	_pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pickup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_panel.add_child(_pickup_label)


# ── Signal Wiring ────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	call_deferred("_deferred_connect_signals")


func _deferred_connect_signals() -> void:
	var event_bus := _get_autoload("EventBus")
	if event_bus == null:
		push_warning("GameHUD: EventBus not available – HUD will not auto-update.")
		return

	if event_bus.has_signal("player_damaged"):
		event_bus.player_damaged.connect(_on_player_damaged)
	if event_bus.has_signal("player_healed"):
		event_bus.player_healed.connect(_on_player_healed)
	# Sync HUD HP when combat starts/ends.
	if event_bus.has_signal("combat_started"):
		event_bus.combat_started.connect(func(_enemies: Variant) -> void: _sync_hp_from_game_manager())
	if event_bus.has_signal("combat_ended"):
		event_bus.combat_ended.connect(func(_summary: Variant) -> void: _sync_hp_from_game_manager())
	if event_bus.has_signal("gold_changed"):
		event_bus.gold_changed.connect(_on_gold_changed)
	if event_bus.has_signal("floor_started"):
		event_bus.floor_started.connect(_on_floor_started)
	if event_bus.has_signal("item_picked_up"):
		event_bus.item_picked_up.connect(_on_item_picked_up)
	if event_bus.has_signal("player_leveled_up"):
		event_bus.player_leveled_up.connect(_on_player_leveled_up)
	if event_bus.has_signal("monster_killed"):
		event_bus.monster_killed.connect(_on_monster_killed_xp)


# ── Public API ───────────────────────────────────────────────────────────────

## Update the HP bar and label.
func update_hp(current: float, max_hp: float) -> void:
	_current_hp = current
	_max_hp = max_hp
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	_hp_label.text = "%d / %d" % [int(current), int(max_hp)]

	# Shift HP bar color based on remaining HP ratio.
	var ratio: float = current / maxf(max_hp, 1.0)
	var fill_color: Color
	if ratio > 0.5:
		fill_color = COLOR_HP_BAR
	elif ratio > 0.25:
		fill_color = Color(0.85, 0.55, 0.1, 1.0)  # Orange warning.
	else:
		fill_color = Color(0.9, 0.15, 0.15, 1.0)   # Critical red.

	var fill_style := _hp_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = fill_color
		_hp_bar.add_theme_stylebox_override("fill", fill_style)


## Update the player level display.
func update_level(level: int) -> void:
	_current_level = level
	_level_floor_label.text = "Lv.%d | %d층" % [_current_level, _current_floor]
	# Refresh XP display from GameManager.
	_sync_xp_from_game_manager()


## Update XP bar and label.
func update_xp(current_xp: int, xp_to_next: int) -> void:
	_xp_bar.max_value = xp_to_next
	_xp_bar.value = current_xp
	_xp_label.text = "XP %d / %d" % [current_xp, xp_to_next]


## Update floor display and optionally show the cinematic floor title.
func update_floor(floor_number: int, floor_name: String) -> void:
	_current_floor = floor_number
	_level_floor_label.text = "Lv.%d | %d층" % [_current_level, _current_floor]

	if not floor_name.is_empty():
		show_floor_title(floor_name)


## Update the gold amount display.
func update_gold(amount: int) -> void:
	_current_gold = amount
	_gold_label.text = "💰 %d" % amount


## Show a cinematic floor title that fades in, holds, and fades out.
func show_floor_title(floor_name: String) -> void:
	_floor_title_label.text = "— %s —" % floor_name

	if _floor_title_tween != null and _floor_title_tween.is_valid():
		_floor_title_tween.kill()

	_floor_title_tween = create_tween()
	_floor_title_tween.set_ease(Tween.EASE_OUT)
	_floor_title_tween.set_trans(Tween.TRANS_CUBIC)

	# Fade in.
	_floor_title_label.modulate = Color(1, 1, 1, 0)
	_floor_title_tween.tween_property(_floor_title_label, "modulate", Color(1, 1, 1, 1), FLOOR_TITLE_FADE_TIME)

	# Hold.
	_floor_title_tween.tween_interval(FLOOR_TITLE_HOLD_TIME)

	# Fade out.
	_floor_title_tween.tween_property(_floor_title_label, "modulate", Color(1, 1, 1, 0), FLOOR_TITLE_FADE_TIME)


## Show an interaction prompt (e.g., "[E] 대화하기").
func show_interaction_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_panel.visible = true

	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()

	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_panel, "modulate", Color(1, 1, 1, 1), PROMPT_FADE_TIME)


## Hide the interaction prompt.
func hide_interaction_prompt() -> void:
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()

	_prompt_tween = create_tween()
	_prompt_tween.tween_property(_prompt_panel, "modulate", Color(1, 1, 1, 0), PROMPT_FADE_TIME)
	_prompt_tween.finished.connect(func() -> void: _prompt_panel.visible = false, CONNECT_ONE_SHOT)


## Flash red on screen edges to indicate damage taken.
func show_damage_indicator(amount: float) -> void:
	_damage_overlay.visible = true

	# Scale flash intensity with damage amount (capped).
	var intensity: float = clampf(amount / 50.0, 0.15, 0.5)
	_damage_overlay.color = Color(COLOR_DAMAGE_FLASH.r, COLOR_DAMAGE_FLASH.g, COLOR_DAMAGE_FLASH.b, intensity)

	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()

	_damage_tween = create_tween()
	_damage_overlay.modulate = Color(1, 1, 1, 1)
	_damage_tween.tween_property(_damage_overlay, "modulate", Color(1, 1, 1, 0), DAMAGE_FLASH_DURATION)
	_damage_tween.finished.connect(func() -> void: _damage_overlay.visible = false, CONNECT_ONE_SHOT)


## Show a brief item pickup notification popup.
func show_pickup_notification(item_name: String, rarity: String) -> void:
	var color: Color = RARITY_COLORS.get(rarity, RARITY_COLORS["common"])
	_pickup_label.text = "획득: %s" % item_name
	_pickup_label.add_theme_color_override("font_color", color)

	# Update border color to match rarity.
	var pickup_style := _pickup_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if pickup_style != null:
		pickup_style.border_color = color
		_pickup_panel.add_theme_stylebox_override("panel", pickup_style)

	_pickup_panel.visible = true

	if _pickup_tween != null and _pickup_tween.is_valid():
		_pickup_tween.kill()

	_pickup_tween = create_tween()
	_pickup_tween.set_ease(Tween.EASE_OUT)
	_pickup_tween.set_trans(Tween.TRANS_CUBIC)

	# Fade in.
	_pickup_panel.modulate = Color(1, 1, 1, 0)
	_pickup_tween.tween_property(_pickup_panel, "modulate", Color(1, 1, 1, 1), PICKUP_FADE_TIME)

	# Hold.
	_pickup_tween.tween_interval(PICKUP_HOLD_TIME)

	# Fade out.
	_pickup_tween.tween_property(_pickup_panel, "modulate", Color(1, 1, 1, 0), PICKUP_FADE_TIME)
	_pickup_tween.finished.connect(func() -> void: _pickup_panel.visible = false, CONNECT_ONE_SHOT)


# ── EventBus Handlers ────────────────────────────────────────────────────────

func _on_player_damaged(amount: float) -> void:
	# Always read authoritative HP from GameManager instead of local tracking.
	_sync_hp_from_game_manager()
	show_damage_indicator(amount)


func _on_player_healed(_amount: float) -> void:
	_sync_hp_from_game_manager()


func _on_gold_changed(new_amount: int, _change: int) -> void:
	update_gold(new_amount)


func _on_floor_started(floor_number: int) -> void:
	_current_floor = floor_number
	_level_floor_label.text = "Lv.%d | %d층" % [_current_level, _current_floor]


func _on_player_leveled_up(new_level: int) -> void:
	update_level(new_level)
	_sync_xp_from_game_manager()
	# Update max HP based on new level.
	_sync_hp_from_game_manager()
	# Brief gold-colored flash to celebrate level-up.
	show_floor_title("LEVEL UP!  Lv.%d" % new_level)


func _on_monster_killed_xp(_monster_data: Dictionary) -> void:
	# Refresh XP bar after each kill.
	_sync_xp_from_game_manager()


func _on_item_picked_up(item_data: Dictionary) -> void:
	var item_name: String = item_data.get("name", "알 수 없는 아이템")
	var rarity: String = item_data.get("rarity", "common")
	show_pickup_notification(item_name, rarity)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _apply_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius


func _sync_hp_from_game_manager() -> void:
	var game_mgr := _get_autoload("GameManager")
	if game_mgr == null:
		return
	var level: int = game_mgr.get("player_level") if "player_level" in game_mgr else 1
	var hp_per_level: float = 15.0  # Must match CombatSystem.HP_PER_LEVEL
	_max_hp = 100.0 + (level - 1) * hp_per_level
	# Include permanent upgrade HP bonus.
	var upgrade_hp: int = game_mgr.get("upgrade_hp") if "upgrade_hp" in game_mgr else 0
	_max_hp += upgrade_hp * 10.0
	var ratio: float = game_mgr.get("player_hp_ratio") if "player_hp_ratio" in game_mgr else 1.0
	_current_hp = _max_hp * ratio
	update_hp(_current_hp, _max_hp)


func _sync_xp_from_game_manager() -> void:
	var game_mgr := _get_autoload("GameManager")
	if game_mgr == null:
		return
	var xp: int = game_mgr.get("player_xp") if "player_xp" in game_mgr else 0
	var xp_next: int = game_mgr.get("player_xp_to_next") if "player_xp_to_next" in game_mgr else 80
	update_xp(xp, xp_next)


func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
