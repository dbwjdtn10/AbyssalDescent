## Minimal on-screen quest tracker displayed in the top-right corner.
##
## Shows the currently tracked quest's title and active objectives as a
## compact checklist.  Auto-updates when quest progress changes.
## Builds its entire UI tree programmatically so it has no .tscn dependency.
class_name QuestHUD
extends CanvasLayer

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color(0.08, 0.06, 0.1, 0.65)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_COMPLETE := Color("#4a7a4a")
const COLOR_FAILED := Color("#7a4a4a")
const COLOR_NOTIFICATION_BG := Color(0.1, 0.08, 0.14, 0.9)

# ── Constants ────────────────────────────────────────────────────────────────

## Maximum number of objectives to display before truncation.
const MAX_VISIBLE_OBJECTIVES: int = 3

## Duration (seconds) that a notification popup stays on screen.
const NOTIFICATION_HOLD_TIME: float = 3.0

## Duration (seconds) for notification slide/fade animations.
const NOTIFICATION_ANIM_TIME: float = 0.4

# ── State ────────────────────────────────────────────────────────────────────

var _tracked_quest_id: String = ""
var _notification_queue: Array[Dictionary] = []
var _is_notification_active: bool = false

# ── UI Node References ──────────────────────────────────────────────────────

var _tracker_panel: PanelContainer
var _title_label: Label
var _objectives_container: VBoxContainer
var _notification_panel: PanelContainer
var _notification_label: Label
var _notification_tween: Tween

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_quest_manager()
	visible = true


# ── Public API ───────────────────────────────────────────────────────────────

## Set the quest to track on the HUD.
func set_tracked_quest(quest_id: String) -> void:
	_tracked_quest_id = quest_id
	refresh()


## Refresh the HUD display from QuestManager data.
func refresh() -> void:
	_clear_objectives()

	if _tracked_quest_id.is_empty():
		_tracker_panel.visible = false
		return

	var quest_mgr := _get_autoload("QuestManager")
	if quest_mgr == null:
		_tracker_panel.visible = false
		return

	var quest: Dictionary = quest_mgr.get_quest(_tracked_quest_id)
	if quest.is_empty():
		_tracker_panel.visible = false
		return

	_tracker_panel.visible = true
	_title_label.text = quest.get("title", _tracked_quest_id)

	var objectives: Array = quest.get("objectives", [])
	var progress: Dictionary = quest.get("progress", {})
	var shown: int = 0

	for i in range(objectives.size()):
		if shown >= MAX_VISIBLE_OBJECTIVES:
			# Show a "more" indicator.
			_add_objective_row("... 그 외 %d개" % (objectives.size() - shown), 0, 0, false, true)
			break

		var obj: Dictionary = objectives[i] if objectives[i] is Dictionary else {}
		var obj_id: String = obj.get("id", "obj_%d" % i)
		var obj_desc: String = obj.get("description", "목표 %d" % (i + 1))
		var obj_prog: Dictionary = progress.get(obj_id, {})
		var current: int = int(obj_prog.get("current", 0))
		var required: int = int(obj_prog.get("required", int(obj.get("count", 1))))
		var done: bool = obj_prog.get("completed", false)

		_add_objective_row(obj_desc, current, required, done, false)
		shown += 1


## Show a brief notification popup for quest events.
## type can be: "new", "objective", "complete", "failed"
func show_quest_notification(text: String, type: String = "new") -> void:
	_notification_queue.append({"text": text, "type": type})
	if not _is_notification_active:
		_show_next_notification()


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# ── Tracker panel (top-right corner) ────────────────────────────────
	_tracker_panel = PanelContainer.new()
	_tracker_panel.name = "TrackerPanel"

	# Anchors: top-right
	_tracker_panel.anchor_left = 1.0
	_tracker_panel.anchor_right = 1.0
	_tracker_panel.anchor_top = 0.0
	_tracker_panel.anchor_bottom = 0.0
	_tracker_panel.offset_left = -280.0
	_tracker_panel.offset_right = -16.0
	_tracker_panel.offset_top = 16.0
	_tracker_panel.offset_bottom = 200.0
	_tracker_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tracker_panel.custom_minimum_size = Vector2(260, 60)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_BG
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	_tracker_panel.add_theme_stylebox_override("panel", panel_style)
	_tracker_panel.visible = false
	add_child(_tracker_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "TrackerVBox"
	vbox.add_theme_constant_override("separation", 4)
	_tracker_panel.add_child(vbox)

	# Quest title
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = ""
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_title_label)

	# Separator line
	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color(0.72, 0.58, 0.2, 0.3))
	vbox.add_child(separator)

	# Objectives container
	_objectives_container = VBoxContainer.new()
	_objectives_container.name = "ObjectivesContainer"
	_objectives_container.add_theme_constant_override("separation", 3)
	vbox.add_child(_objectives_container)

	# ── Notification panel (slides in from right edge) ───────────────────
	_notification_panel = PanelContainer.new()
	_notification_panel.name = "NotificationPanel"
	_notification_panel.anchor_left = 1.0
	_notification_panel.anchor_right = 1.0
	_notification_panel.anchor_top = 0.5
	_notification_panel.anchor_bottom = 0.5
	_notification_panel.offset_left = -320.0
	_notification_panel.offset_right = -16.0
	_notification_panel.offset_top = -24.0
	_notification_panel.offset_bottom = 24.0
	_notification_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notification_panel.custom_minimum_size = Vector2(200, 44)

	var notif_style := StyleBoxFlat.new()
	notif_style.bg_color = COLOR_NOTIFICATION_BG
	notif_style.border_color = COLOR_ACCENT
	notif_style.border_width_top = 1
	notif_style.border_width_bottom = 1
	notif_style.border_width_left = 2
	notif_style.border_width_right = 1
	notif_style.corner_radius_top_left = 4
	notif_style.corner_radius_top_right = 4
	notif_style.corner_radius_bottom_left = 4
	notif_style.corner_radius_bottom_right = 4
	notif_style.content_margin_top = 8.0
	notif_style.content_margin_bottom = 8.0
	notif_style.content_margin_left = 14.0
	notif_style.content_margin_right = 14.0
	_notification_panel.add_theme_stylebox_override("panel", notif_style)
	_notification_panel.modulate = Color(1, 1, 1, 0)
	_notification_panel.visible = false
	add_child(_notification_panel)

	_notification_label = Label.new()
	_notification_label.name = "NotificationLabel"
	_notification_label.text = ""
	_notification_label.add_theme_font_size_override("font_size", 15)
	_notification_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_panel.add_child(_notification_label)


# ── Objective Row ────────────────────────────────────────────────────────────

func _add_objective_row(description: String, current: int, required: int, completed: bool, is_overflow: bool) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	if not is_overflow:
		# Checkbox
		var check := Label.new()
		check.text = "☑" if completed else "☐"
		check.add_theme_font_size_override("font_size", 13)
		check.add_theme_color_override("font_color", COLOR_COMPLETE if completed else COLOR_TEXT)
		check.custom_minimum_size = Vector2(18, 0)
		hbox.add_child(check)

	# Text
	var lbl := Label.new()
	var display: String = description
	if required > 1 and not is_overflow:
		display += " (%d/%d)" % [current, required]
	lbl.text = display
	lbl.add_theme_font_size_override("font_size", 12)

	var text_color: Color
	if is_overflow:
		text_color = Color(0.5, 0.48, 0.45, 0.6)
	elif completed:
		text_color = COLOR_COMPLETE
	else:
		text_color = COLOR_TEXT
	lbl.add_theme_color_override("font_color", text_color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	_objectives_container.add_child(hbox)


func _clear_objectives() -> void:
	for child in _objectives_container.get_children():
		child.queue_free()


# ── Notification Animation ──────────────────────────────────────────────────

func _show_next_notification() -> void:
	if _notification_queue.is_empty():
		_is_notification_active = false
		return

	_is_notification_active = true
	var notif: Dictionary = _notification_queue.pop_front()
	var text: String = notif.get("text", "")
	var type: String = notif.get("type", "new")

	# Set label color by type
	var color: Color = COLOR_ACCENT
	match type:
		"complete":
			color = COLOR_COMPLETE
		"failed":
			color = COLOR_FAILED
		"objective":
			color = Color(0.82, 0.78, 0.68, 1.0)

	_notification_label.text = text
	_notification_label.add_theme_color_override("font_color", color)

	# Start off-screen to the right, invisible
	_notification_panel.visible = true
	_notification_panel.modulate = Color(1, 1, 1, 0)
	_notification_panel.offset_left = 0.0
	_notification_panel.offset_right = 304.0

	# Kill any running tween
	if _notification_tween != null and _notification_tween.is_valid():
		_notification_tween.kill()

	_notification_tween = create_tween()
	_notification_tween.set_ease(Tween.EASE_OUT)
	_notification_tween.set_trans(Tween.TRANS_CUBIC)

	# Slide in + fade in
	_notification_tween.set_parallel(true)
	_notification_tween.tween_property(_notification_panel, "offset_left", -320.0, NOTIFICATION_ANIM_TIME)
	_notification_tween.tween_property(_notification_panel, "offset_right", -16.0, NOTIFICATION_ANIM_TIME)
	_notification_tween.tween_property(_notification_panel, "modulate", Color(1, 1, 1, 1), NOTIFICATION_ANIM_TIME)

	# Hold
	_notification_tween.set_parallel(false)
	_notification_tween.tween_interval(NOTIFICATION_HOLD_TIME)

	# Fade out
	_notification_tween.tween_property(_notification_panel, "modulate", Color(1, 1, 1, 0), NOTIFICATION_ANIM_TIME)

	# On completion, process the next queued notification
	_notification_tween.finished.connect(_on_notification_finished, CONNECT_ONE_SHOT)


func _on_notification_finished() -> void:
	_notification_panel.visible = false
	_show_next_notification()


# ── QuestManager Connection ──────────────────────────────────────────────────

func _connect_quest_manager() -> void:
	# Defer connection to give autoloads time to register.
	call_deferred("_deferred_connect_quest_manager")


func _deferred_connect_quest_manager() -> void:
	var quest_mgr := _get_autoload("QuestManager")
	if quest_mgr == null:
		push_warning("QuestHUD: QuestManager not available – HUD will not auto-update.")
		return

	quest_mgr.quest_accepted.connect(_on_quest_accepted)
	quest_mgr.quest_progress.connect(_on_quest_progress)
	quest_mgr.quest_completed.connect(_on_quest_completed)
	quest_mgr.quest_failed.connect(_on_quest_failed)
	quest_mgr.quest_offered.connect(_on_quest_offered)


func _on_quest_offered(_quest_data: Dictionary) -> void:
	show_quest_notification("새 퀘스트!", "new")


func _on_quest_accepted(quest_data: Dictionary) -> void:
	var quest_id: String = quest_data.get("id", "")
	# Auto-track the newly accepted quest if nothing is tracked.
	if _tracked_quest_id.is_empty():
		set_tracked_quest(quest_id)
	else:
		refresh()


func _on_quest_progress(quest_id: String, objective_id: String, current: int, required: int) -> void:
	if quest_id == _tracked_quest_id:
		refresh()
	if current >= required:
		show_quest_notification("목표 달성!", "objective")


func _on_quest_completed(quest_data: Dictionary) -> void:
	var quest_id: String = quest_data.get("id", "")
	show_quest_notification("퀘스트 완료!", "complete")
	if quest_id == _tracked_quest_id:
		_tracked_quest_id = ""
		# Auto-track the next active quest if available.
		var quest_mgr := _get_autoload("QuestManager")
		if quest_mgr != null:
			var active: Array = quest_mgr.get_active_quests()
			if not active.is_empty():
				set_tracked_quest(active[0].get("id", ""))
			else:
				refresh()


func _on_quest_failed(quest_id: String) -> void:
	show_quest_notification("퀘스트 실패...", "failed")
	if quest_id == _tracked_quest_id:
		_tracked_quest_id = ""
		refresh()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
