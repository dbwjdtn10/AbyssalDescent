## Floor transition trigger and animation.
##
## Detects when a floor is fully cleared, displays a cinematic transition
## screen, and advances to the next floor via GameManager.complete_floor().
class_name FloorTransition
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

signal transition_started(floor_number: int)
signal transition_completed(floor_number: int)

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color(0.0, 0.0, 0.0, 1.0)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_DIM_TEXT := Color(0.6, 0.58, 0.52, 1.0)

# ── Constants ────────────────────────────────────────────────────────────────

const FADE_IN_TIME: float = 0.6
const HOLD_TIME: float = 2.0
const FADE_OUT_TIME: float = 0.6
const CANVAS_LAYER_ORDER: int = 110

# ── Floor Name Templates ────────────────────────────────────────────────────

## Korean floor name templates by floor number bracket.
const FLOOR_NAMES: Dictionary = {
	1: "심연의 입구",
	2: "어둠의 회랑",
	3: "고대의 묘지",
	4: "잊혀진 신전",
	5: "피의 제단",
	6: "마왕의 심장부",
	7: "종말의 나선",
	8: "무한 심연",
	9: "절망의 심층",
	10: "최후의 어비스",
}

# ── State ────────────────────────────────────────────────────────────────────

var _is_transitioning: bool = false

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	call_deferred("_deferred_connect_signals")


# ── Public API ───────────────────────────────────────────────────────────────

## Check whether all combat rooms on the current floor have been cleared.
## [param rooms] Dictionary of room_id -> room_data, each room having a
## "type" and "cleared" field.
func check_floor_clear(rooms: Dictionary) -> bool:
	for room_id in rooms:
		var room: Dictionary = rooms[room_id]
		var room_type: String = room.get("type", "")

		# Only combat, boss, and mini-boss rooms must be cleared.
		if room_type in ["combat", "boss", "mini_boss"]:
			if not room.get("cleared", false):
				return false
	return true


## Begin the floor transition sequence.
## Call this after the boss or final required room is defeated.
func trigger_transition() -> void:
	if _is_transitioning:
		return

	_is_transitioning = true

	var game_mgr := _get_autoload("GameManager")
	var current_floor: int = game_mgr.current_floor if game_mgr != null else 1
	var next_floor: int = current_floor + 1
	var floor_name: String = _get_floor_name(next_floor)

	transition_started.emit(current_floor)

	# Play a transition SFX.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("stop_bgm"):
		sound_mgr.stop_bgm(FADE_IN_TIME)

	_show_transition_screen(floor_name, next_floor)


# ── Transition Screen ────────────────────────────────────────────────────────

## Create and animate the transition CanvasLayer.
func _show_transition_screen(floor_name: String, floor_number: int) -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "TransitionCanvas"
	canvas.layer = CANVAS_LAYER_ORDER
	canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(canvas)

	# Full-screen black background.
	var bg := ColorRect.new()
	bg.name = "TransitionBG"
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.modulate = Color(1, 1, 1, 0)
	canvas.add_child(bg)

	# "Descending..." text.
	var descend_label := Label.new()
	descend_label.name = "DescendLabel"
	descend_label.text = "다음 층으로 내려갑니다..."
	descend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	descend_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	descend_label.add_theme_font_size_override("font_size", 20)
	descend_label.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	descend_label.set_anchors_preset(Control.PRESET_CENTER)
	descend_label.offset_top = -20.0
	descend_label.offset_bottom = 20.0
	descend_label.offset_left = -300.0
	descend_label.offset_right = 300.0
	descend_label.modulate = Color(1, 1, 1, 0)
	canvas.add_child(descend_label)

	# Floor name text (larger, golden).
	var floor_label := Label.new()
	floor_label.name = "FloorLabel"
	floor_label.text = "— %d층: %s —" % [floor_number, floor_name]
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	floor_label.add_theme_font_size_override("font_size", 36)
	floor_label.add_theme_color_override("font_color", COLOR_ACCENT)
	floor_label.set_anchors_preset(Control.PRESET_CENTER)
	floor_label.offset_top = 20.0
	floor_label.offset_bottom = 70.0
	floor_label.offset_left = -400.0
	floor_label.offset_right = 400.0
	floor_label.modulate = Color(1, 1, 1, 0)
	canvas.add_child(floor_label)

	# Animate the sequence.
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Phase 1: Fade in black background.
	tween.tween_property(bg, "modulate", Color(1, 1, 1, 1), FADE_IN_TIME)

	# Phase 2: Show "descending" text.
	tween.tween_property(descend_label, "modulate", Color(1, 1, 1, 1), 0.4)
	tween.tween_interval(0.8)

	# Phase 3: Fade out "descending", fade in floor name.
	tween.tween_property(descend_label, "modulate", Color(1, 1, 1, 0), 0.3)
	tween.tween_property(floor_label, "modulate", Color(1, 1, 1, 1), 0.5)

	# Phase 4: Hold.
	tween.tween_interval(HOLD_TIME)

	# Phase 5: Fade everything out.
	tween.tween_property(floor_label, "modulate", Color(1, 1, 1, 0), 0.3)
	tween.tween_property(bg, "modulate", Color(1, 1, 1, 0), FADE_OUT_TIME)

	# Phase 6: Cleanup and advance.
	tween.tween_callback(func() -> void:
		canvas.queue_free()
		_on_transition_complete()
	)


## Called when the transition animation finishes.
func _on_transition_complete() -> void:
	_is_transitioning = false

	var game_mgr := _get_autoload("GameManager")
	var next_floor: int = 1
	if game_mgr != null:
		next_floor = game_mgr.current_floor + 1
		game_mgr.complete_floor()

	transition_completed.emit(next_floor)

	# Start floor BGM.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_bgm"):
		sound_mgr.play_bgm("dungeon_bgm")


# ── EventBus Wiring ─────────────────────────────────────────────────────────

func _deferred_connect_signals() -> void:
	var event_bus := _get_autoload("EventBus")
	if event_bus == null:
		return

	# Automatically trigger transition when a boss is defeated.
	if event_bus.has_signal("boss_defeated"):
		event_bus.boss_defeated.connect(_on_boss_defeated)


func _on_boss_defeated(_boss_data: Dictionary) -> void:
	# Give a short delay before starting the transition.
	await get_tree().create_timer(1.0).timeout
	trigger_transition()


# ── Helpers ──────────────────────────────────────────────────────────────────

## Get a thematic floor name for the given floor number.
func _get_floor_name(floor_number: int) -> String:
	if FLOOR_NAMES.has(floor_number):
		return FLOOR_NAMES[floor_number]
	# For floors beyond the predefined list, generate a generic name.
	return "심연 제%d층" % floor_number


## Safely retrieve an autoload node by name.
func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
