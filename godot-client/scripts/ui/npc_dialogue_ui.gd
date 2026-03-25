## Full-screen NPC dialogue overlay.
##
## Builds its entire UI tree programmatically so it has no .tscn dependency.
## Register as an autoload or add as a child of the main scene.
## Communicates with the AI server through the AIClient singleton.
class_name NPCDialogueUI
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal dialogue_opened(npc_id: String)
signal dialogue_closed(npc_id: String)
signal message_sent(npc_id: String, message: String)

# ── Public State ─────────────────────────────────────────────────────────────

var is_open: bool = false
var current_npc_id: String = ""
var current_npc_name: String = ""
var conversation_history: Array = []
var typing_speed: float = 0.03  # seconds per character for typewriter effect

# ── Private State ────────────────────────────────────────────────────────────

var _is_typing: bool = false
var _full_response_text: String = ""
var _current_char_index: int = 0
var _typewriter_timer: float = 0.0

# ── Emotion Mapping ─────────────────────────────────────────────────────────

const EMOTION_MAP: Dictionary = {
	"happy": "😊",
	"sad": "😢",
	"angry": "😠",
	"afraid": "😨",
	"curious": "🤔",
	"suspicious": "🧐",
	"grateful": "🙏",
	"melancholy": "😔",
	"excited": "✨",
	"disgusted": "😤",
	"mysterious": "🔮",
	"neutral": "😐",
	"friendly": "😊",
	"sorrowful": "😢",
	"gruff": "😠",
}

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG_OVERLAY := Color(0.0, 0.0, 0.0, 0.6)
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.1, 0.95)
const COLOR_PANEL_BORDER := Color(0.72, 0.58, 0.2, 1.0)  # Gold accent
const COLOR_NPC_AREA_BG := Color(0.06, 0.04, 0.08, 1.0)
const COLOR_CHAT_BG := Color(0.05, 0.03, 0.07, 1.0)
const COLOR_INPUT_BG := Color(0.1, 0.08, 0.12, 1.0)
const COLOR_TEXT := Color(0.9, 0.88, 0.82, 1.0)  # Warm parchment white
const COLOR_NPC_NAME := Color(0.92, 0.76, 0.26, 1.0)  # Gold
const COLOR_ACCENT := Color(0.72, 0.58, 0.2, 1.0)
const COLOR_BUTTON := Color(0.18, 0.14, 0.22, 1.0)
const COLOR_BUTTON_HOVER := Color(0.28, 0.22, 0.34, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.12, 0.1, 0.16, 1.0)
const COLOR_AFFINITY_LOW := Color(0.7, 0.2, 0.2, 1.0)
const COLOR_AFFINITY_MID := Color(0.7, 0.7, 0.2, 1.0)
const COLOR_AFFINITY_HIGH := Color(0.2, 0.7, 0.3, 1.0)
const COLOR_HINT := Color(0.6, 0.55, 0.75, 1.0)

# ── UI Node References ──────────────────────────────────────────────────────

var _overlay: ColorRect
var _panel: PanelContainer
var _npc_name_label: Label
var _npc_title_label: Label
var _emotion_label: Label
var _affinity_bar: ProgressBar
var _affinity_label: Label
var _response_label: RichTextLabel
var _hint_label: RichTextLabel
var _input_field: LineEdit
var _send_button: Button
var _close_button: Button
var _loading_label: Label

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()
	visible = false


func _process(delta: float) -> void:
	if _is_typing:
		_update_typewriter(delta)


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen overlay
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = COLOR_BG_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Centered dialogue panel
	_panel = PanelContainer.new()
	_panel.name = "DialoguePanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(800, 500)
	_panel.size = Vector2(800, 500)
	_panel.position = Vector2(-400, -250)  # Center offset

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_top = 12.0
	panel_style.content_margin_bottom = 12.0
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(_panel)

	# Main horizontal split: NPC info (left) | Chat area (right)
	var h_split := HBoxContainer.new()
	h_split.name = "HSplit"
	h_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	h_split.add_theme_constant_override("separation", 12)
	_panel.add_child(h_split)

	# ── Left Column: NPC portrait area ──────────────────────────────────
	var left_panel := PanelContainer.new()
	left_panel.name = "NPCInfoPanel"
	left_panel.custom_minimum_size = Vector2(200, 0)
	left_panel.size_flags_horizontal = Control.SIZE_FILL
	left_panel.size_flags_stretch_ratio = 0.35

	var left_style := StyleBoxFlat.new()
	left_style.bg_color = COLOR_NPC_AREA_BG
	left_style.corner_radius_top_left = 6
	left_style.corner_radius_bottom_left = 6
	left_style.content_margin_top = 16.0
	left_style.content_margin_bottom = 16.0
	left_style.content_margin_left = 12.0
	left_style.content_margin_right = 12.0
	left_panel.add_theme_stylebox_override("panel", left_style)
	h_split.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.name = "LeftVBox"
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)

	# Emotion icon (large, centered)
	_emotion_label = Label.new()
	_emotion_label.name = "EmotionLabel"
	_emotion_label.text = EMOTION_MAP["neutral"]
	_emotion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_emotion_label.add_theme_font_size_override("font_size", 64)
	left_vbox.add_child(_emotion_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	left_vbox.add_child(spacer)

	# NPC name
	_npc_name_label = Label.new()
	_npc_name_label.name = "NPCNameLabel"
	_npc_name_label.text = "NPC"
	_npc_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_name_label.add_theme_font_size_override("font_size", 20)
	_npc_name_label.add_theme_color_override("font_color", COLOR_NPC_NAME)
	left_vbox.add_child(_npc_name_label)

	# NPC title
	_npc_title_label = Label.new()
	_npc_title_label.name = "NPCTitleLabel"
	_npc_title_label.text = ""
	_npc_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_npc_title_label.add_theme_font_size_override("font_size", 13)
	_npc_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	left_vbox.add_child(_npc_title_label)

	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 12)
	left_vbox.add_child(spacer2)

	# Affinity label
	_affinity_label = Label.new()
	_affinity_label.name = "AffinityLabel"
	_affinity_label.text = "호감도"
	_affinity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_affinity_label.add_theme_font_size_override("font_size", 12)
	_affinity_label.add_theme_color_override("font_color", COLOR_TEXT)
	left_vbox.add_child(_affinity_label)

	# Affinity progress bar
	_affinity_bar = ProgressBar.new()
	_affinity_bar.name = "AffinityBar"
	_affinity_bar.min_value = -100.0
	_affinity_bar.max_value = 100.0
	_affinity_bar.value = 0.0
	_affinity_bar.show_percentage = false
	_affinity_bar.custom_minimum_size = Vector2(0, 16)

	var affinity_bg_style := StyleBoxFlat.new()
	affinity_bg_style.bg_color = Color(0.15, 0.12, 0.18, 1.0)
	affinity_bg_style.corner_radius_top_left = 4
	affinity_bg_style.corner_radius_top_right = 4
	affinity_bg_style.corner_radius_bottom_left = 4
	affinity_bg_style.corner_radius_bottom_right = 4
	_affinity_bar.add_theme_stylebox_override("background", affinity_bg_style)

	var affinity_fill_style := StyleBoxFlat.new()
	affinity_fill_style.bg_color = COLOR_AFFINITY_MID
	affinity_fill_style.corner_radius_top_left = 4
	affinity_fill_style.corner_radius_top_right = 4
	affinity_fill_style.corner_radius_bottom_left = 4
	affinity_fill_style.corner_radius_bottom_right = 4
	_affinity_bar.add_theme_stylebox_override("fill", affinity_fill_style)
	left_vbox.add_child(_affinity_bar)

	# Hint area (expandable, at the bottom of left column)
	_hint_label = RichTextLabel.new()
	_hint_label.name = "HintLabel"
	_hint_label.bbcode_enabled = true
	_hint_label.fit_content = true
	_hint_label.scroll_active = false
	_hint_label.custom_minimum_size = Vector2(0, 40)
	_hint_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hint_label.add_theme_font_size_override("normal_font_size", 11)
	_hint_label.add_theme_color_override("default_color", COLOR_HINT)
	left_vbox.add_child(_hint_label)

	# ── Right Column: Chat + Input ──────────────────────────────────────
	var right_vbox := VBoxContainer.new()
	right_vbox.name = "RightVBox"
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.65
	right_vbox.add_theme_constant_override("separation", 8)
	h_split.add_child(right_vbox)

	# Close button row (top-right)
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	right_vbox.add_child(top_bar)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(top_spacer)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "✕"
	_close_button.custom_minimum_size = Vector2(32, 32)
	_close_button.add_theme_font_size_override("font_size", 18)
	_close_button.add_theme_color_override("font_color", COLOR_TEXT)
	_close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.3, 0.3, 1.0))

	var close_style_normal := StyleBoxFlat.new()
	close_style_normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_close_button.add_theme_stylebox_override("normal", close_style_normal)

	var close_style_hover := StyleBoxFlat.new()
	close_style_hover.bg_color = Color(0.3, 0.1, 0.1, 0.5)
	close_style_hover.corner_radius_top_left = 4
	close_style_hover.corner_radius_top_right = 4
	close_style_hover.corner_radius_bottom_left = 4
	close_style_hover.corner_radius_bottom_right = 4
	_close_button.add_theme_stylebox_override("hover", close_style_hover)

	var close_style_pressed := StyleBoxFlat.new()
	close_style_pressed.bg_color = Color(0.4, 0.1, 0.1, 0.7)
	close_style_pressed.corner_radius_top_left = 4
	close_style_pressed.corner_radius_top_right = 4
	close_style_pressed.corner_radius_bottom_left = 4
	close_style_pressed.corner_radius_bottom_right = 4
	_close_button.add_theme_stylebox_override("pressed", close_style_pressed)
	top_bar.add_child(_close_button)

	# Chat display area (scrollable RichTextLabel)
	var chat_panel := PanelContainer.new()
	chat_panel.name = "ChatPanel"
	chat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var chat_style := StyleBoxFlat.new()
	chat_style.bg_color = COLOR_CHAT_BG
	chat_style.corner_radius_top_left = 4
	chat_style.corner_radius_top_right = 4
	chat_style.corner_radius_bottom_left = 4
	chat_style.corner_radius_bottom_right = 4
	chat_style.content_margin_top = 8.0
	chat_style.content_margin_bottom = 8.0
	chat_style.content_margin_left = 10.0
	chat_style.content_margin_right = 10.0
	chat_panel.add_theme_stylebox_override("panel", chat_style)
	right_vbox.add_child(chat_panel)

	_response_label = RichTextLabel.new()
	_response_label.name = "ResponseLabel"
	_response_label.bbcode_enabled = true
	_response_label.scroll_following = true
	_response_label.selection_enabled = true
	_response_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_response_label.add_theme_color_override("default_color", COLOR_TEXT)
	_response_label.add_theme_font_size_override("normal_font_size", 15)
	chat_panel.add_child(_response_label)

	# Loading indicator (overlaid on chat panel, hidden by default)
	_loading_label = Label.new()
	_loading_label.name = "LoadingLabel"
	_loading_label.text = "..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 18)
	_loading_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_loading_label.visible = false
	chat_panel.add_child(_loading_label)

	# Input area at the bottom
	var input_hbox := HBoxContainer.new()
	input_hbox.name = "InputHBox"
	input_hbox.add_theme_constant_override("separation", 8)
	right_vbox.add_child(input_hbox)

	_input_field = LineEdit.new()
	_input_field.name = "InputField"
	_input_field.placeholder_text = "메시지를 입력하세요..."
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.custom_minimum_size = Vector2(0, 36)
	_input_field.add_theme_color_override("font_color", COLOR_TEXT)
	_input_field.add_theme_color_override("font_placeholder_color", Color(0.5, 0.48, 0.45, 0.6))
	_input_field.add_theme_color_override("caret_color", COLOR_ACCENT)

	var input_style := StyleBoxFlat.new()
	input_style.bg_color = COLOR_INPUT_BG
	input_style.border_color = Color(0.3, 0.25, 0.35, 1.0)
	input_style.border_width_bottom = 1
	input_style.corner_radius_top_left = 4
	input_style.corner_radius_top_right = 4
	input_style.corner_radius_bottom_left = 4
	input_style.corner_radius_bottom_right = 4
	input_style.content_margin_left = 8.0
	input_style.content_margin_right = 8.0
	_input_field.add_theme_stylebox_override("normal", input_style)

	var input_focus_style := input_style.duplicate()
	input_focus_style.border_color = COLOR_ACCENT
	input_focus_style.border_width_bottom = 2
	_input_field.add_theme_stylebox_override("focus", input_focus_style)
	input_hbox.add_child(_input_field)

	_send_button = Button.new()
	_send_button.name = "SendButton"
	_send_button.text = "전송"
	_send_button.custom_minimum_size = Vector2(72, 36)
	_send_button.add_theme_font_size_override("font_size", 14)
	_send_button.add_theme_color_override("font_color", COLOR_TEXT)

	var send_style_normal := StyleBoxFlat.new()
	send_style_normal.bg_color = COLOR_BUTTON
	send_style_normal.border_color = COLOR_ACCENT
	send_style_normal.border_width_top = 1
	send_style_normal.border_width_bottom = 1
	send_style_normal.border_width_left = 1
	send_style_normal.border_width_right = 1
	send_style_normal.corner_radius_top_left = 4
	send_style_normal.corner_radius_top_right = 4
	send_style_normal.corner_radius_bottom_left = 4
	send_style_normal.corner_radius_bottom_right = 4
	_send_button.add_theme_stylebox_override("normal", send_style_normal)

	var send_style_hover := send_style_normal.duplicate()
	send_style_hover.bg_color = COLOR_BUTTON_HOVER
	_send_button.add_theme_stylebox_override("hover", send_style_hover)

	var send_style_pressed := send_style_normal.duplicate()
	send_style_pressed.bg_color = COLOR_BUTTON_PRESSED
	_send_button.add_theme_stylebox_override("pressed", send_style_pressed)
	input_hbox.add_child(_send_button)


# ── Signal Wiring ────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	_send_button.pressed.connect(_on_send_pressed)
	_input_field.text_submitted.connect(_on_input_submitted)
	_close_button.pressed.connect(_on_close_pressed)

	# Connect to AIClient if it is registered as an autoload.
	var ai_client := _get_ai_client()
	if ai_client != null:
		ai_client.npc_response_received.connect(_on_npc_response_received)
		ai_client.npc_state_received.connect(_on_npc_state_received)
		ai_client.ai_error.connect(_on_ai_error)


# ── Public API ───────────────────────────────────────────────────────────────

## Open the dialogue window for the given NPC.
func open_dialogue(npc_id: String, npc_name: String, npc_title: String = "") -> void:
	current_npc_id = npc_id
	current_npc_name = npc_name
	conversation_history.clear()

	_npc_name_label.text = npc_name
	_npc_title_label.text = npc_title
	_update_emotion("neutral")
	_affinity_bar.value = 0
	_affinity_label.text = "호감도: 0"
	_response_label.clear()
	_hint_label.clear()
	_input_field.text = ""
	_input_field.editable = true
	_send_button.disabled = false
	_loading_label.visible = false

	visible = true
	is_open = true
	get_tree().paused = true
	_input_field.grab_focus()
	dialogue_opened.emit(npc_id)

	# Fetch current NPC state from the server.
	var ai_client := _get_ai_client()
	if ai_client != null:
		ai_client.get_npc_state(npc_id)
	else:
		_append_system_message("서버 연결 불가 – 오프라인 모드")


## Close the dialogue window.
func close_dialogue() -> void:
	var npc_id := current_npc_id
	visible = false
	is_open = false
	_is_typing = false
	current_npc_id = ""
	current_npc_name = ""
	conversation_history.clear()
	_response_label.clear()
	get_tree().paused = false
	dialogue_closed.emit(npc_id)


## Send a player message to the AI server.
func send_message(message: String) -> void:
	if message.strip_edges().is_empty():
		return

	_append_player_message(message)
	conversation_history.append({"role": "player", "content": message})
	message_sent.emit(current_npc_id, message)

	_input_field.text = ""
	_input_field.editable = false
	_send_button.disabled = true
	_loading_label.visible = true

	var ai_client := _get_ai_client()
	if ai_client != null:
		# Build a minimal player_state dictionary.
		var player_state: Dictionary = {
			"level": 1,
			"current_floor": 1,
			"hp_ratio": 1.0,
			"inventory": [],
			"gold": 0,
		}
		ai_client.chat_with_npc(
			current_npc_id,
			message,
			player_state,
			conversation_history
		)
	else:
		# Offline fallback: show a generic message after a short delay.
		_loading_label.visible = false
		_input_field.editable = true
		_send_button.disabled = false
		var fallback_data: Dictionary = {
			"response": "......(주변의 어둠이 짙어져 대화를 이어가기 어렵다.)",
			"emotion": "neutral",
			"current_affinity": 0,
			"affinity_change": 0,
		}
		_display_response(fallback_data)


# ── Response Handling ────────────────────────────────────────────────────────

func _on_npc_response_received(data: Dictionary) -> void:
	if not is_open:
		return
	_loading_label.visible = false
	_input_field.editable = true
	_send_button.disabled = false
	_display_response(data)
	_input_field.grab_focus()


func _on_npc_state_received(data: Dictionary) -> void:
	if not is_open:
		return
	var emotion: String = data.get("emotion", "neutral")
	var affinity: int = data.get("affinity", data.get("current_affinity", 0))
	_update_emotion(emotion)
	_update_affinity(affinity, 0)

	# Show a greeting if the server returned one.
	var greeting: String = data.get("greeting", data.get("response", ""))
	if not greeting.is_empty():
		_display_response(data)


func _on_ai_error(endpoint: String, error: String) -> void:
	if not is_open:
		return
	# Only react to NPC-related errors while dialogue is open.
	if endpoint.find("npc") == -1:
		return
	_loading_label.visible = false
	_input_field.editable = true
	_send_button.disabled = false
	_append_system_message("서버 연결 불가 – %s" % error)


## Parse the server response and update the UI.
func _display_response(data: Dictionary) -> void:
	var npc_message: String = data.get("response", data.get("message", ""))
	var emotion: String = data.get("emotion", "neutral")
	var affinity: int = data.get("current_affinity", data.get("affinity", 0))
	var affinity_change: int = data.get("affinity_change", 0)
	var hints: Array = data.get("hints", [])

	conversation_history.append({"role": "npc", "content": npc_message})

	_update_emotion(emotion)
	_update_affinity(affinity, affinity_change)

	if hints.size() > 0:
		_show_hints(hints)

	# Prepend NPC name in gold, then start typewriter.
	var display_text: String = "\n[color=#ebca42]%s:[/color] " % current_npc_name
	_response_label.append_text(display_text)
	_start_typewriter(npc_message)


## Begin the typewriter animation for the given text.
func _start_typewriter(text: String) -> void:
	_full_response_text = text
	_current_char_index = 0
	_typewriter_timer = 0.0
	_is_typing = true


## Advance the typewriter effect each frame.
func _update_typewriter(delta: float) -> void:
	_typewriter_timer += delta
	while _typewriter_timer >= typing_speed and _current_char_index < _full_response_text.length():
		_typewriter_timer -= typing_speed
		var ch: String = _full_response_text[_current_char_index]
		_response_label.append_text(ch)
		_current_char_index += 1

	if _current_char_index >= _full_response_text.length():
		_is_typing = false
		_response_label.append_text("\n")


## Update the emotion icon.
func _update_emotion(emotion: String) -> void:
	var symbol: String = EMOTION_MAP.get(emotion, EMOTION_MAP["neutral"])
	_emotion_label.text = symbol


## Update the affinity bar value and color.
func _update_affinity(affinity: int, change: int) -> void:
	_affinity_bar.value = clampf(float(affinity), -100.0, 100.0)

	# Color the fill based on value.
	var fill_color: Color
	if affinity < -30:
		fill_color = COLOR_AFFINITY_LOW
	elif affinity > 30:
		fill_color = COLOR_AFFINITY_HIGH
	else:
		fill_color = COLOR_AFFINITY_MID

	var fill_style := _affinity_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	if fill_style != null:
		fill_style.bg_color = fill_color
		_affinity_bar.add_theme_stylebox_override("fill", fill_style)

	var change_str: String = ""
	if change > 0:
		change_str = " [color=#4dcc66](+%d)[/color]" % change
	elif change < 0:
		change_str = " [color=#cc4d4d](%d)[/color]" % change

	_affinity_label.text = "호감도: %d" % affinity


## Display hint information in the hint area.
func _show_hints(hints: Array) -> void:
	_hint_label.clear()
	_hint_label.append_text("[color=#9990b8]── 힌트 ──[/color]\n")
	for hint in hints:
		if hint is String:
			_hint_label.append_text("[color=#9990b8]• %s[/color]\n" % hint)
		elif hint is Dictionary:
			var hint_text: String = hint.get("text", hint.get("content", str(hint)))
			_hint_label.append_text("[color=#9990b8]• %s[/color]\n" % hint_text)


# ── Chat Formatting Helpers ──────────────────────────────────────────────────

func _append_player_message(text: String) -> void:
	_response_label.append_text("\n[color=#82b1ff]나:[/color] %s\n" % text)


func _append_system_message(text: String) -> void:
	_response_label.append_text(
		"\n[color=#666060][i]%s[/i][/color]\n" % text
	)


# ── Input Handlers ───────────────────────────────────────────────────────────

func _on_send_pressed() -> void:
	var text: String = _input_field.text.strip_edges()
	if text.is_empty():
		return
	# If still typing, finish immediately so the player can continue.
	if _is_typing:
		_finish_typewriter()
	send_message(text)


func _on_input_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return
	if _is_typing:
		_finish_typewriter()
	send_message(trimmed)


func _on_close_pressed() -> void:
	close_dialogue()


## Instantly complete the typewriter animation.
func _finish_typewriter() -> void:
	if not _is_typing:
		return
	var remaining: String = _full_response_text.substr(_current_char_index)
	_response_label.append_text(remaining + "\n")
	_is_typing = false


# ── Utility ──────────────────────────────────────────────────────────────────

## Safely retrieve the AIClient autoload.  Returns null if not found.
func _get_ai_client() -> Node:
	if Engine.has_singleton("AIClient"):
		return Engine.get_singleton("AIClient")
	# Autoloads are direct children of the scene tree root.
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node("AIClient"):
		return root.get_node("AIClient")
	return null
