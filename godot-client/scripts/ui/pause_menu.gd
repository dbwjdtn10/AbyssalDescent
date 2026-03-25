## Pause menu overlay with dark fantasy styling.
##
## Pauses the game tree when shown and resumes on close.
## Builds its entire UI tree programmatically so it has no .tscn dependency.
class_name PauseMenu
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal resume_requested
signal menu_requested
signal settings_requested

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.75)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.1, 0.95)
const COLOR_PANEL_BORDER := Color(0.72, 0.58, 0.2, 1.0)
const COLOR_BUTTON_BG := Color(0.12, 0.1, 0.16, 0.9)
const COLOR_BUTTON_HOVER := Color(0.2, 0.16, 0.24, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.08, 0.06, 0.1, 1.0)
const COLOR_INFO_TEXT := Color(0.6, 0.55, 0.75, 1.0)
const COLOR_DANGER := Color(0.8, 0.25, 0.25, 1.0)

# ── UI Node References ───────────────────────────────────────────────────────

var _overlay: ColorRect
var _panel: PanelContainer
var _title_label: Label
var _floor_info_label: Label
var _difficulty_label: Label
var _resume_btn: Button
var _settings_btn: Button
var _save_btn: Button
var _return_menu_btn: Button
var _confirm_overlay: ColorRect
var _confirm_panel: PanelContainer

# ── State ────────────────────────────────────────────────────────────────────

var _confirm_visible: bool = false

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()
	visible = false


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dark overlay.
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = COLOR_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Center panel.
	_panel = PanelContainer.new()
	_panel.name = "PausePanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(360, 380)
	_panel.size = Vector2(360, 380)
	_panel.position = Vector2(-180, -190)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	_apply_corner_radius(panel_style, 8)
	panel_style.content_margin_top = 20.0
	panel_style.content_margin_bottom = 20.0
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_right = 24.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "PauseVBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	# Title.
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = "일시정지"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(_title_label)

	# Separator.
	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color(0.72, 0.58, 0.2, 0.3))
	vbox.add_child(separator)

	# Floor and difficulty info.
	_floor_info_label = Label.new()
	_floor_info_label.name = "FloorInfoLabel"
	_floor_info_label.text = "현재 층: 1층"
	_floor_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_info_label.add_theme_font_size_override("font_size", 14)
	_floor_info_label.add_theme_color_override("font_color", COLOR_INFO_TEXT)
	vbox.add_child(_floor_info_label)

	_difficulty_label = Label.new()
	_difficulty_label.name = "DifficultyLabel"
	_difficulty_label.text = "난이도: 보통"
	_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_label.add_theme_font_size_override("font_size", 13)
	_difficulty_label.add_theme_color_override("font_color", COLOR_INFO_TEXT)
	vbox.add_child(_difficulty_label)

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Buttons.
	_resume_btn = _create_button("계속하기")
	_resume_btn.name = "ResumeButton"
	vbox.add_child(_resume_btn)

	_settings_btn = _create_button("설정")
	_settings_btn.name = "SettingsButton"
	vbox.add_child(_settings_btn)

	_save_btn = _create_button("저장")
	_save_btn.name = "SaveButton"
	vbox.add_child(_save_btn)

	_return_menu_btn = _create_button("메인 메뉴로")
	_return_menu_btn.name = "ReturnMenuButton"
	_return_menu_btn.add_theme_color_override("font_color", COLOR_DANGER)
	_return_menu_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.35, 0.35, 1.0))
	vbox.add_child(_return_menu_btn)

	# Confirmation dialog (hidden by default).
	_build_confirm_dialog()


func _build_confirm_dialog() -> void:
	_confirm_overlay = ColorRect.new()
	_confirm_overlay.name = "ConfirmOverlay"
	_confirm_overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	_confirm_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_overlay.visible = false
	add_child(_confirm_overlay)

	_confirm_panel = PanelContainer.new()
	_confirm_panel.name = "ConfirmPanel"
	_confirm_panel.set_anchors_preset(Control.PRESET_CENTER)
	_confirm_panel.custom_minimum_size = Vector2(320, 180)
	_confirm_panel.size = Vector2(320, 180)
	_confirm_panel.position = Vector2(-160, -90)

	var confirm_style := StyleBoxFlat.new()
	confirm_style.bg_color = COLOR_PANEL_BG
	confirm_style.border_color = COLOR_DANGER
	confirm_style.border_width_top = 2
	confirm_style.border_width_bottom = 2
	confirm_style.border_width_left = 2
	confirm_style.border_width_right = 2
	_apply_corner_radius(confirm_style, 8)
	confirm_style.content_margin_top = 16.0
	confirm_style.content_margin_bottom = 16.0
	confirm_style.content_margin_left = 20.0
	confirm_style.content_margin_right = 20.0
	_confirm_panel.add_theme_stylebox_override("panel", confirm_style)
	_confirm_overlay.add_child(_confirm_panel)

	var confirm_vbox := VBoxContainer.new()
	confirm_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	confirm_vbox.add_theme_constant_override("separation", 16)
	_confirm_panel.add_child(confirm_vbox)

	var confirm_text := Label.new()
	confirm_text.text = "메인 메뉴로 돌아가시겠습니까?\n저장하지 않은 진행 상황은 사라집니다."
	confirm_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_text.add_theme_font_size_override("font_size", 14)
	confirm_text.add_theme_color_override("font_color", COLOR_TEXT)
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_vbox.add_child(confirm_text)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	confirm_vbox.add_child(button_row)

	var cancel_btn := _create_button("취소")
	cancel_btn.custom_minimum_size = Vector2(120, 40)
	cancel_btn.pressed.connect(_on_confirm_cancel)
	button_row.add_child(cancel_btn)

	var confirm_btn := _create_button("확인")
	confirm_btn.custom_minimum_size = Vector2(120, 40)
	confirm_btn.add_theme_color_override("font_color", COLOR_DANGER)
	confirm_btn.pressed.connect(_on_confirm_return)
	button_row.add_child(confirm_btn)


# ── Signal Wiring ────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_resume_btn.pressed.connect(_on_resume)
	_settings_btn.pressed.connect(_on_settings)
	_save_btn.pressed.connect(_on_save)
	_return_menu_btn.pressed.connect(_on_return_to_menu)


# ── Public API ───────────────────────────────────────────────────────────────

## Pause the game tree and show the pause menu.
func show_pause() -> void:
	_update_info_display()
	get_tree().paused = true
	_confirm_overlay.visible = false
	_confirm_visible = false
	visible = true


## Unpause the game tree and hide the pause menu.
func hide_pause() -> void:
	get_tree().paused = false
	_confirm_overlay.visible = false
	_confirm_visible = false
	visible = false


# ── Button Handlers ──────────────────────────────────────────────────────────

func _on_resume() -> void:
	resume_requested.emit()


func _on_settings() -> void:
	settings_requested.emit()


func _on_save() -> void:
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null and game_mgr.has_method("save_game"):
		game_mgr.save_game()
		# Brief visual feedback.
		_save_btn.text = "저장 완료!"
		await get_tree().create_timer(1.0).timeout
		_save_btn.text = "저장"


func _on_return_to_menu() -> void:
	# Show confirmation dialog.
	_confirm_overlay.visible = true
	_confirm_visible = true


func _on_confirm_cancel() -> void:
	_confirm_overlay.visible = false
	_confirm_visible = false


func _on_confirm_return() -> void:
	_confirm_overlay.visible = false
	_confirm_visible = false
	hide_pause()
	menu_requested.emit()


# ── Info Display ─────────────────────────────────────────────────────────────

func _update_info_display() -> void:
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		var floor_num: int = game_mgr.get("current_floor") if "current_floor" in game_mgr else 1
		_floor_info_label.text = "현재 층: %d층" % floor_num

	var diff_mgr := _get_autoload("DifficultyManager")
	if diff_mgr != null and diff_mgr.has_method("get_difficulty_display_name"):
		var diff_name: String = diff_mgr.get_difficulty_display_name()
		var diff_color: Color = diff_mgr.get_difficulty_color() if diff_mgr.has_method("get_difficulty_color") else COLOR_TEXT
		_difficulty_label.text = "난이도: %s" % diff_name
		_difficulty_label.add_theme_color_override("font_color", diff_color)
	else:
		_difficulty_label.text = "난이도: 보통"


# ── Button Factory ───────────────────────────────────────────────────────────

func _create_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(260, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = COLOR_BUTTON_BG
	normal_style.border_color = Color(COLOR_PANEL_BORDER.r, COLOR_PANEL_BORDER.g, COLOR_PANEL_BORDER.b, 0.4)
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	_apply_corner_radius(normal_style, 4)
	normal_style.content_margin_top = 6.0
	normal_style.content_margin_bottom = 6.0
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = COLOR_BUTTON_HOVER
	hover_style.border_color = COLOR_ACCENT
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = COLOR_BUTTON_PRESSED
	btn.add_theme_stylebox_override("pressed", pressed_style)

	return btn


# ── Helpers ──────────────────────────────────────────────────────────────────

func _apply_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius


func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
