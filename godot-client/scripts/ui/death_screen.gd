## Game over / death screen with dramatic presentation.
##
## Displays death statistics and gold settlement, then offers retry or menu.
## Builds its entire UI tree programmatically so it has no .tscn dependency.
class_name DeathScreen
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal retry_requested
signal menu_requested

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color(0.02, 0.01, 0.03, 0.95)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_DEATH_RED := Color(0.85, 0.12, 0.12, 1.0)
const COLOR_STAT_LABEL := Color(0.6, 0.55, 0.75, 1.0)
const COLOR_STAT_VALUE := Color("#e6e1d1")
const COLOR_PANEL_BG := Color(0.06, 0.04, 0.08, 0.9)
const COLOR_PANEL_BORDER := Color(0.5, 0.1, 0.1, 0.6)
const COLOR_BUTTON_BG := Color(0.12, 0.1, 0.16, 0.9)
const COLOR_BUTTON_HOVER := Color(0.2, 0.16, 0.24, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.08, 0.06, 0.1, 1.0)
const COLOR_BUTTON_BORDER := Color(0.72, 0.58, 0.2, 0.6)
const COLOR_GOLD := Color("#FFD700")

# ── Constants ────────────────────────────────────────────────────────────────

const FADE_IN_DURATION: float = 1.5
const TITLE_DELAY: float = 0.5
const STATS_DELAY: float = 1.5
const BUTTONS_DELAY: float = 2.5

# ── UI Node References ───────────────────────────────────────────────────────

var _overlay: ColorRect
var _death_title: Label
var _stats_panel: PanelContainer
var _stat_labels: Dictionary = {}
var _settlement_label: Label
var _button_container: HBoxContainer
var _retry_btn: Button
var _menu_btn: Button
var _fade_tween: Tween

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()
	visible = false


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dark background.
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = COLOR_BG
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Main centered layout.
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 24)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(main_vbox)

	# Death title.
	_death_title = Label.new()
	_death_title.name = "DeathTitle"
	_death_title.text = "사 망"
	_death_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_title.add_theme_font_size_override("font_size", 64)
	_death_title.add_theme_color_override("font_color", COLOR_DEATH_RED)
	_death_title.modulate = Color(1, 1, 1, 0)
	_death_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_death_title)

	# Subtitle.
	var subtitle := Label.new()
	subtitle.name = "DeathSubtitle"
	subtitle.text = "심연이 당신을 삼켰습니다..."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", COLOR_STAT_LABEL)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(subtitle)

	# Stats panel.
	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsPanel"
	_stats_panel.custom_minimum_size = Vector2(380, 200)

	var stats_style := StyleBoxFlat.new()
	stats_style.bg_color = COLOR_PANEL_BG
	stats_style.border_color = COLOR_PANEL_BORDER
	stats_style.border_width_top = 1
	stats_style.border_width_bottom = 1
	stats_style.border_width_left = 1
	stats_style.border_width_right = 1
	_apply_corner_radius(stats_style, 6)
	stats_style.content_margin_top = 20.0
	stats_style.content_margin_bottom = 20.0
	stats_style.content_margin_left = 24.0
	stats_style.content_margin_right = 24.0
	_stats_panel.add_theme_stylebox_override("panel", stats_style)
	_stats_panel.modulate = Color(1, 1, 1, 0)
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(_stats_panel)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.name = "StatsVBox"
	stats_vbox.add_theme_constant_override("separation", 10)
	_stats_panel.add_child(stats_vbox)

	# Stats header.
	var stats_header := Label.new()
	stats_header.text = "── 탐험 기록 ──"
	stats_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_header.add_theme_font_size_override("font_size", 16)
	stats_header.add_theme_color_override("font_color", COLOR_ACCENT)
	stats_vbox.add_child(stats_header)

	# Individual stat rows.
	_add_stat_row(stats_vbox, "floor", "도달 층", "1층")
	_add_stat_row(stats_vbox, "monsters", "처치한 몬스터", "0마리")
	_add_stat_row(stats_vbox, "gold", "획득한 골드", "0G")
	_add_stat_row(stats_vbox, "time", "플레이 시간", "0분")
	_add_stat_row(stats_vbox, "quests", "완료한 퀘스트", "0개")

	# Gold settlement line.
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	stats_vbox.add_child(sep)

	_settlement_label = Label.new()
	_settlement_label.name = "SettlementLabel"
	_settlement_label.text = ""
	_settlement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settlement_label.add_theme_font_size_override("font_size", 13)
	_settlement_label.add_theme_color_override("font_color", COLOR_GOLD)
	stats_vbox.add_child(_settlement_label)

	# Button container.
	_button_container = HBoxContainer.new()
	_button_container.name = "ButtonContainer"
	_button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_button_container.add_theme_constant_override("separation", 24)
	_button_container.modulate = Color(1, 1, 1, 0)
	main_vbox.add_child(_button_container)

	_retry_btn = _create_button("다시 도전")
	_retry_btn.name = "RetryButton"
	_button_container.add_child(_retry_btn)

	_menu_btn = _create_button("메인 메뉴")
	_menu_btn.name = "MenuButton"
	_button_container.add_child(_menu_btn)


func _add_stat_row(parent: VBoxContainer, key: String, label_text: String, default_value: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", COLOR_STAT_LABEL)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)

	var value := Label.new()
	value.name = "StatValue_%s" % key
	value.text = default_value
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", COLOR_STAT_VALUE)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value)

	_stat_labels[key] = value
	parent.add_child(hbox)


# ── Signal Wiring ────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_retry_btn.pressed.connect(_on_retry)
	_menu_btn.pressed.connect(_on_menu)


# ── Public API ───────────────────────────────────────────────────────────────

## Display the death screen with game stats from a Dictionary.
## Expected keys: floor, monsters_killed, gold_earned, play_time_seconds,
##   quests_completed, gold_retained, item_gold.
func show_death(stats: Dictionary) -> void:
	visible = true

	# Populate stat values.
	var floor_num: int = int(stats.get("floor", 1))
	var monsters: int = int(stats.get("monsters_killed", 0))
	var gold: int = int(stats.get("gold_earned", 0))
	var time_secs: float = float(stats.get("play_time_seconds", 0.0))
	var quests: int = int(stats.get("quests_completed", 0))

	_stat_labels["floor"].text = "%d층" % floor_num
	_stat_labels["monsters"].text = "%d마리" % monsters
	_stat_labels["gold"].text = "%dG" % gold
	_stat_labels["time"].text = _format_play_time(time_secs)
	_stat_labels["quests"].text = "%d개" % quests

	# Gold settlement summary.
	var item_gold: int = int(stats.get("item_gold", 0))
	var gold_retained: int = int(stats.get("gold_retained", 0))
	if gold_retained > 0:
		if item_gold > 0:
			_settlement_label.text = "골드 %dG + 아이템 매각 %dG → 영구 골드 %dG 획득" % [gold, item_gold, gold_retained]
		else:
			_settlement_label.text = "골드 %dG → 영구 골드 %dG 획득" % [gold, gold_retained]
	else:
		_settlement_label.text = ""

	# Reset element visibility for animation.
	_overlay.modulate = Color(1, 1, 1, 0)
	_death_title.modulate = Color(1, 1, 1, 0)
	_stats_panel.modulate = Color(1, 1, 1, 0)
	_button_container.modulate = Color(1, 1, 1, 0)

	# Dramatic fade-in sequence.
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.set_ease(Tween.EASE_OUT)
	_fade_tween.set_trans(Tween.TRANS_CUBIC)

	# Background fade in.
	_fade_tween.tween_property(_overlay, "modulate", Color(1, 1, 1, 1), FADE_IN_DURATION)

	# Title appears after delay.
	_fade_tween.tween_interval(TITLE_DELAY)
	_fade_tween.tween_property(_death_title, "modulate", Color(1, 1, 1, 1), 0.8)

	# Stats slide in.
	_fade_tween.tween_interval(STATS_DELAY - TITLE_DELAY - 0.8)
	_fade_tween.tween_property(_stats_panel, "modulate", Color(1, 1, 1, 1), 0.6)

	# Buttons appear last.
	_fade_tween.tween_interval(BUTTONS_DELAY - STATS_DELAY - 0.6)
	_fade_tween.tween_property(_button_container, "modulate", Color(1, 1, 1, 1), 0.4)


# ── Button Handlers ──────────────────────────────────────────────────────────

func _on_retry() -> void:
	visible = false
	retry_requested.emit()


func _on_menu() -> void:
	visible = false
	menu_requested.emit()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _format_play_time(seconds: float) -> String:
	var total_minutes: int = int(seconds / 60.0)
	if total_minutes < 60:
		return "%d분" % total_minutes
	var hours: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	return "%d시간 %d분" % [hours, minutes]


func _create_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(180, 48)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = COLOR_BUTTON_BG
	normal_style.border_color = COLOR_BUTTON_BORDER
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	_apply_corner_radius(normal_style, 6)
	normal_style.content_margin_top = 8.0
	normal_style.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = COLOR_BUTTON_HOVER
	hover_style.border_color = COLOR_ACCENT
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = COLOR_BUTTON_PRESSED
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn


func _apply_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
