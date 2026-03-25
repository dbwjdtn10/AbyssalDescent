## Magic circle loading animation displayed during AI server requests.
##
## Shows a rotating array of rune characters around a pulsing center,
## with a customizable loading message.  Automatically shows/hides when
## AIClient starts/finishes requests.
## Builds its entire UI tree programmatically so it has no .tscn dependency.
class_name LoadingScreen
extends CanvasLayer

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.7)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_RUNE := Color(0.92, 0.79, 0.26, 0.85)
const COLOR_RUNE_DIM := Color(0.6, 0.5, 0.2, 0.4)
const COLOR_DOT := Color(0.72, 0.58, 0.2, 0.35)
const COLOR_CENTER_GLOW := Color(0.92, 0.79, 0.26, 0.6)
const COLOR_ERROR := Color(0.85, 0.25, 0.25, 1.0)

# ── Rune Configuration ───────────────────────────────────────────────────────

const RUNE_CHARS: Array[String] = ["☽", "★", "✦", "◈", "▲", "◆", "♦", "✧"]
const INNER_RADIUS: float = 80.0
const OUTER_RADIUS: float = 120.0
const OUTER_DOT_COUNT: int = 16
const RUNE_ORBIT_SPEED: float = 0.4      # radians per second (inner ring)
const OUTER_ORBIT_SPEED: float = -0.25   # outer dots rotate opposite direction
const PULSE_SPEED: float = 2.5           # center glow oscillation speed
const ELLIPSIS_SPEED: float = 0.5        # seconds between dot changes

# ── Fade Timing ──────────────────────────────────────────────────────────────

const FADE_DURATION: float = 0.3

# ── State ────────────────────────────────────────────────────────────────────

var _is_showing: bool = false
var _elapsed: float = 0.0
var _ellipsis_timer: float = 0.0
var _ellipsis_count: int = 0
var _base_message: String = "로딩 중"
var _pending_requests: int = 0

# ── UI Node References ───────────────────────────────────────────────────────

var _overlay: ColorRect
var _center_container: CenterContainer
var _circle_root: Control
var _rune_labels: Array[Label] = []
var _outer_dots: Array[Label] = []
var _center_glow: ColorRect
var _message_label: Label
var _sub_message_label: Label
var _fade_tween: Tween

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()
	visible = false


func _process(delta: float) -> void:
	if not _is_showing:
		return

	_elapsed += delta

	# Rotate inner rune labels around center.
	for i in range(_rune_labels.size()):
		var angle: float = _elapsed * RUNE_ORBIT_SPEED + (TAU / _rune_labels.size()) * i
		var pos := Vector2(cos(angle), sin(angle)) * INNER_RADIUS
		_rune_labels[i].position = pos - _rune_labels[i].size * 0.5

		# Subtle alpha oscillation per rune.
		var alpha: float = lerpf(0.5, 1.0, (sin(_elapsed * 1.8 + float(i) * 0.7) + 1.0) * 0.5)
		_rune_labels[i].modulate = Color(COLOR_RUNE.r, COLOR_RUNE.g, COLOR_RUNE.b, alpha)

	# Rotate outer dots in opposite direction.
	for i in range(_outer_dots.size()):
		var dot_angle: float = _elapsed * OUTER_ORBIT_SPEED + (TAU / _outer_dots.size()) * i
		var dot_pos := Vector2(cos(dot_angle), sin(dot_angle)) * OUTER_RADIUS
		_outer_dots[i].position = dot_pos - _outer_dots[i].size * 0.5

		var dot_alpha: float = lerpf(0.2, 0.5, (sin(_elapsed * 2.0 + float(i) * 0.4) + 1.0) * 0.5)
		_outer_dots[i].modulate = Color(COLOR_DOT.r, COLOR_DOT.g, COLOR_DOT.b, dot_alpha)

	# Pulse center glow.
	var glow_alpha: float = lerpf(0.3, 0.8, (sin(_elapsed * PULSE_SPEED) + 1.0) * 0.5)
	_center_glow.modulate = Color(COLOR_CENTER_GLOW.r, COLOR_CENTER_GLOW.g, COLOR_CENTER_GLOW.b, glow_alpha)

	# Animate ellipsis.
	_ellipsis_timer += delta
	if _ellipsis_timer >= ELLIPSIS_SPEED:
		_ellipsis_timer -= ELLIPSIS_SPEED
		_ellipsis_count = (_ellipsis_count + 1) % 4
		_message_label.text = _base_message + ".".repeat(_ellipsis_count)


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dark overlay.
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = COLOR_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Center container for the magic circle and text.
	_center_container = CenterContainer.new()
	_center_container.name = "CenterContainer"
	_center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_center_container)

	# Main layout: circle + labels stacked vertically.
	var vbox := VBoxContainer.new()
	vbox.name = "MainVBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_container.add_child(vbox)

	# Circle container (needs a fixed-size control to position children).
	var circle_size: float = (OUTER_RADIUS + 40.0) * 2.0
	_circle_root = Control.new()
	_circle_root.name = "CircleRoot"
	_circle_root.custom_minimum_size = Vector2(circle_size, circle_size)
	_circle_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_circle_root)

	# Offset so that (0,0) is the visual center of _circle_root.
	var offset_container := Control.new()
	offset_container.name = "OffsetContainer"
	offset_container.position = Vector2(circle_size * 0.5, circle_size * 0.5)
	offset_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle_root.add_child(offset_container)

	# Center glow (small glowing square at center).
	_center_glow = ColorRect.new()
	_center_glow.name = "CenterGlow"
	_center_glow.color = COLOR_CENTER_GLOW
	_center_glow.custom_minimum_size = Vector2(16, 16)
	_center_glow.size = Vector2(16, 16)
	_center_glow.position = Vector2(-8, -8)
	_center_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	offset_container.add_child(_center_glow)

	# Inner rune labels.
	for i in range(RUNE_CHARS.size()):
		var lbl := Label.new()
		lbl.name = "Rune_%d" % i
		lbl.text = RUNE_CHARS[i]
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", COLOR_RUNE)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		offset_container.add_child(lbl)
		_rune_labels.append(lbl)

	# Outer ring of small dots.
	for i in range(OUTER_DOT_COUNT):
		var dot := Label.new()
		dot.name = "Dot_%d" % i
		dot.text = "·"
		dot.add_theme_font_size_override("font_size", 18)
		dot.add_theme_color_override("font_color", COLOR_DOT)
		dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		offset_container.add_child(dot)
		_outer_dots.append(dot)

	# Loading message label.
	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.text = "로딩 중..."
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 18)
	_message_label.add_theme_color_override("font_color", COLOR_TEXT)
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_message_label)

	# Sub-message label (what is being loaded).
	_sub_message_label = Label.new()
	_sub_message_label.name = "SubMessageLabel"
	_sub_message_label.text = ""
	_sub_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_message_label.add_theme_font_size_override("font_size", 14)
	_sub_message_label.add_theme_color_override("font_color", Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 0.6))
	_sub_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_sub_message_label)


# ── Signal Wiring ────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	call_deferred("_deferred_connect_signals")


func _deferred_connect_signals() -> void:
	var ai_client := _get_autoload("AIClient")
	if ai_client == null:
		return

	# Connect to AI error signal to show error state.
	if ai_client.has_signal("ai_error"):
		ai_client.ai_error.connect(_on_ai_error)

	# Connect to response signals so we can auto-hide.
	if ai_client.has_signal("dungeon_generated"):
		ai_client.dungeon_generated.connect(_on_request_completed)
	if ai_client.has_signal("npc_response_received"):
		ai_client.npc_response_received.connect(_on_request_completed)
	if ai_client.has_signal("npc_state_received"):
		ai_client.npc_state_received.connect(_on_request_completed)
	if ai_client.has_signal("item_generated"):
		ai_client.item_generated.connect(_on_request_completed)
	if ai_client.has_signal("quest_generated"):
		ai_client.quest_generated.connect(_on_request_completed)
	if ai_client.has_signal("difficulty_adapted"):
		ai_client.difficulty_adapted.connect(_on_request_completed)
	if ai_client.has_signal("server_health_checked"):
		ai_client.server_health_checked.connect(_on_health_completed)


# ── Public API ───────────────────────────────────────────────────────────────

## Display the loading screen with a message.
func show_loading(message: String = "로딩 중") -> void:
	_pending_requests += 1
	_base_message = message
	_ellipsis_count = 0
	_ellipsis_timer = 0.0
	_message_label.text = message
	_sub_message_label.text = ""
	_sub_message_label.add_theme_color_override("font_color", Color(COLOR_TEXT.r, COLOR_TEXT.g, COLOR_TEXT.b, 0.6))

	if _is_showing:
		return  # Already visible; just update message.

	_is_showing = true
	_elapsed = 0.0
	visible = true

	# Fade in.
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_overlay.modulate = Color(1, 1, 1, 0)
	_fade_tween.tween_property(_overlay, "modulate", Color(1, 1, 1, 1), FADE_DURATION)


## Hide the loading screen with a fade-out.
func hide_loading() -> void:
	_pending_requests = maxi(0, _pending_requests - 1)
	if _pending_requests > 0:
		return  # Other requests still in flight.

	if not _is_showing:
		return

	_is_showing = false

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_overlay, "modulate", Color(1, 1, 1, 0), FADE_DURATION)
	_fade_tween.finished.connect(_on_fade_out_finished, CONNECT_ONE_SHOT)


## Update the main loading text.
func set_message(message: String) -> void:
	_base_message = message
	_ellipsis_count = 0
	_message_label.text = message


## Update the sub-message text (detail of what is loading).
func set_sub_message(text: String) -> void:
	_sub_message_label.text = text


## Show the loading screen specifically for dungeon generation.
func show_dungeon_loading() -> void:
	show_loading("심연의 힘을 불러오는 중")
	set_sub_message("던전 생성 중...")


## Show the loading screen specifically for NPC interaction.
func show_npc_loading() -> void:
	show_loading("심연의 힘을 불러오는 중")
	set_sub_message("NPC 응답 대기 중...")


## Show the loading screen specifically for quest processing.
func show_quest_loading() -> void:
	show_loading("심연의 힘을 불러오는 중")
	set_sub_message("퀘스트 분석 중...")


# ── Signal Handlers ──────────────────────────────────────────────────────────

func _on_request_completed(_data: Variant) -> void:
	hide_loading()


func _on_health_completed(_is_healthy: bool) -> void:
	hide_loading()


func _on_ai_error(endpoint: String, error: String) -> void:
	if not _is_showing:
		return
	# Show error state briefly before hiding.
	_message_label.text = "연결 오류"
	_sub_message_label.text = "%s – %s" % [endpoint, error]
	_sub_message_label.add_theme_color_override("font_color", COLOR_ERROR)

	# Auto-hide after a short delay.
	_pending_requests = 0
	await get_tree().create_timer(1.5).timeout
	if _is_showing:
		hide_loading()


func _on_fade_out_finished() -> void:
	visible = false


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
