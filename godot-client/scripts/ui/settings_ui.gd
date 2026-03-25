## Settings overlay for AI server configuration.
##
## Allows players to enter a custom AI server URL and Claude API key.
## Settings are saved to disk and loaded automatically on startup.
class_name SettingsUI
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal settings_closed

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.75)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.1, 0.95)
const COLOR_PANEL_BORDER := Color(0.72, 0.58, 0.2, 1.0)
const COLOR_BUTTON_BG := Color(0.12, 0.1, 0.16, 0.9)
const COLOR_BUTTON_HOVER := Color(0.2, 0.16, 0.24, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.08, 0.06, 0.1, 1.0)
const COLOR_INPUT_BG := Color(0.06, 0.04, 0.08, 1.0)
const COLOR_INFO := Color(0.6, 0.55, 0.75, 1.0)
const COLOR_SUCCESS := Color(0.3, 0.75, 0.35, 1.0)

# ── UI Node References ──────────────────────────────────────────────────────

var _overlay: ColorRect
var _server_url_input: LineEdit
var _api_key_input: LineEdit
var _status_label: Label
var _save_btn: Button

# ── State ────────────────────────────────────────────────────────────────────

var is_open: bool = false

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "SettingsOverlay"
	_overlay.color = COLOR_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var panel := PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(480, 400)
	panel.size = Vector2(480, 400)
	panel.position = Vector2(-240, -200)

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
	panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Title.
	var title := Label.new()
	title.text = "AI 서버 설정"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.72, 0.58, 0.2, 0.3))
	vbox.add_child(sep)

	# Info text.
	var info := Label.new()
	info.text = "AI 기능을 사용하려면 서버 URL과 Claude API 키를 입력하세요.\n비워두면 오프라인 모드(폴백 데이터)로 플레이합니다."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", COLOR_INFO)
	vbox.add_child(info)

	# Server URL.
	var url_label := Label.new()
	url_label.text = "서버 URL"
	url_label.add_theme_font_size_override("font_size", 14)
	url_label.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(url_label)

	_server_url_input = LineEdit.new()
	_server_url_input.name = "ServerURLInput"
	_server_url_input.placeholder_text = "http://localhost:8000"
	_server_url_input.custom_minimum_size = Vector2(0, 36)
	_server_url_input.add_theme_font_size_override("font_size", 14)
	_server_url_input.add_theme_color_override("font_color", COLOR_TEXT)

	var input_style := StyleBoxFlat.new()
	input_style.bg_color = COLOR_INPUT_BG
	input_style.border_color = Color(0.3, 0.25, 0.35, 0.6)
	input_style.border_width_top = 1
	input_style.border_width_bottom = 1
	input_style.border_width_left = 1
	input_style.border_width_right = 1
	_apply_corner_radius(input_style, 4)
	input_style.content_margin_left = 8.0
	input_style.content_margin_right = 8.0
	_server_url_input.add_theme_stylebox_override("normal", input_style)
	vbox.add_child(_server_url_input)

	# API Key.
	var key_label := Label.new()
	key_label.text = "Claude API Key"
	key_label.add_theme_font_size_override("font_size", 14)
	key_label.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(key_label)

	_api_key_input = LineEdit.new()
	_api_key_input.name = "APIKeyInput"
	_api_key_input.placeholder_text = "sk-ant-... (선택사항)"
	_api_key_input.secret = true
	_api_key_input.custom_minimum_size = Vector2(0, 36)
	_api_key_input.add_theme_font_size_override("font_size", 14)
	_api_key_input.add_theme_color_override("font_color", COLOR_TEXT)
	_api_key_input.add_theme_stylebox_override("normal", input_style.duplicate())
	vbox.add_child(_api_key_input)

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	# Status label.
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 13)
	_status_label.add_theme_color_override("font_color", COLOR_INFO)
	vbox.add_child(_status_label)

	# Button row.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_save_btn = _create_button("저장 및 연결")
	_save_btn.pressed.connect(_on_save_pressed)
	btn_row.add_child(_save_btn)

	var close_btn := _create_button("닫기")
	close_btn.pressed.connect(_on_close_pressed)
	btn_row.add_child(close_btn)


# ── Public API ───────────────────────────────────────────────────────────────

func show_settings() -> void:
	# Load current values from AIClient config.
	var ai_client := _get_autoload("AIClient")
	if ai_client != null and ai_client.get("config") != null:
		var cfg: Resource = ai_client.config
		_server_url_input.text = cfg.server_url
		_api_key_input.text = cfg.api_key
	_status_label.text = ""
	is_open = true
	visible = true


func hide_settings() -> void:
	is_open = false
	visible = false
	settings_closed.emit()


# ── Button Handlers ──────────────────────────────────────────────────────────

func _on_save_pressed() -> void:
	var ai_client := _get_autoload("AIClient")
	if ai_client == null or ai_client.get("config") == null:
		_status_label.text = "AIClient를 찾을 수 없습니다."
		_status_label.add_theme_color_override("font_color", Color(0.8, 0.25, 0.25))
		return

	var cfg: Resource = ai_client.config
	var new_url: String = _server_url_input.text.strip_edges()
	var new_key: String = _api_key_input.text.strip_edges()

	if new_url.is_empty():
		new_url = "http://localhost:8000"
		_server_url_input.text = new_url

	cfg.server_url = new_url
	cfg.api_key = new_key
	cfg.save_settings()

	_status_label.text = "설정 저장 완료! 서버 확인 중..."
	_status_label.add_theme_color_override("font_color", COLOR_ACCENT)

	# Trigger a health check with the new URL.
	if ai_client.has_method("check_health"):
		if ai_client.has_signal("server_health_checked"):
			# One-shot connection for this check.
			var _on_result := func(is_healthy: bool) -> void:
				if is_healthy:
					_status_label.text = "서버 연결 성공!"
					_status_label.add_theme_color_override("font_color", COLOR_SUCCESS)
				else:
					_status_label.text = "서버 연결 실패 — 오프라인 모드로 플레이합니다."
					_status_label.add_theme_color_override("font_color", Color(0.8, 0.25, 0.25))
			ai_client.server_health_checked.connect(_on_result, CONNECT_ONE_SHOT)
		ai_client.check_health()


func _on_close_pressed() -> void:
	hide_settings()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _create_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(160, 40)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BUTTON_BG
	style.border_color = Color(0.72, 0.58, 0.2, 0.4)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	_apply_corner_radius(style, 4)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = COLOR_BUTTON_HOVER
	hover.border_color = COLOR_ACCENT
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = COLOR_BUTTON_PRESSED
	btn.add_theme_stylebox_override("pressed", pressed)

	return btn


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
