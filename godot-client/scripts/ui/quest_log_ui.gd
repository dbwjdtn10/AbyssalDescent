## Full-screen quest log overlay.
##
## Opened with the Tab key, displays active and completed quests in a
## two-panel layout.  Builds its entire UI tree programmatically so it
## has no .tscn dependency.
class_name QuestLogUI
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal quest_selected(quest_id: String)
signal quest_abandoned(quest_id: String)

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color("#140f1a")
const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.7)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_COMPLETE := Color("#4a7a4a")
const COLOR_FAILED := Color("#7a4a4a")
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.1, 0.95)
const COLOR_PANEL_BORDER := Color(0.72, 0.58, 0.2, 1.0)
const COLOR_LIST_ITEM_BG := Color(0.1, 0.08, 0.12, 0.8)
const COLOR_LIST_ITEM_HOVER := Color(0.15, 0.12, 0.18, 0.9)
const COLOR_LIST_ITEM_SELECTED := Color(0.2, 0.16, 0.25, 1.0)
const COLOR_BUTTON := Color(0.18, 0.14, 0.22, 1.0)
const COLOR_BUTTON_HOVER := Color(0.28, 0.22, 0.34, 1.0)
const COLOR_DETAIL_BG := Color(0.06, 0.04, 0.08, 1.0)
const COLOR_OBJECTIVE_DONE := Color(0.5, 0.7, 0.5, 0.8)
const COLOR_OBJECTIVE_PENDING := Color(0.9, 0.88, 0.82, 0.9)
const COLOR_LORE := Color(0.6, 0.55, 0.75, 1.0)

# ── Quest Type Icons ─────────────────────────────────────────────────────────

const TYPE_ICONS: Dictionary = {
	"combat": "crossed_swords",
	"kill": "crossed_swords",
	"collect": "gem",
	"explore": "compass",
	"rescue": "shield",
	"survival": "skull",
	"find": "magnifier",
	"interact": "hand",
}

# ── State ────────────────────────────────────────────────────────────────────

var is_open: bool = false
var _selected_quest_id: String = ""
var _showing_completed: bool = false

# ── UI Node References ──────────────────────────────────────────────────────

var _overlay: ColorRect
var _main_panel: PanelContainer
var _tab_active_btn: Button
var _tab_completed_btn: Button
var _quest_list_container: VBoxContainer
var _quest_list_scroll: ScrollContainer
var _detail_panel: PanelContainer
var _detail_title: Label
var _detail_type: Label
var _detail_description: RichTextLabel
var _detail_objectives: VBoxContainer
var _detail_rewards: RichTextLabel
var _detail_lore: RichTextLabel
var _close_button: Button
var _abandon_button: Button
var _track_button: Button
var _empty_label: Label

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_open:
			toggle()
			get_viewport().set_input_as_handled()

# ── Public API ───────────────────────────────────────────────────────────────

## Show or hide the quest log.
func toggle() -> void:
	if is_open:
		visible = false
		is_open = false
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		visible = true
		is_open = true
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		refresh()


## Rebuild the quest list from QuestManager data.
func refresh() -> void:
	_clear_quest_list()
	var quest_mgr := _get_quest_manager()
	if quest_mgr == null:
		_show_empty_message("퀘스트 시스템을 사용할 수 없습니다.")
		return

	if _showing_completed:
		_populate_completed_quests(quest_mgr)
	else:
		_populate_active_quests(quest_mgr)

	# If we had a selected quest, re-select it.
	if not _selected_quest_id.is_empty():
		_show_quest_detail(_selected_quest_id)

# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dark overlay
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = COLOR_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Main panel (centered, large)
	_main_panel = PanelContainer.new()
	_main_panel.name = "QuestLogPanel"
	_main_panel.set_anchors_preset(Control.PRESET_CENTER)
	_main_panel.custom_minimum_size = Vector2(960, 600)
	_main_panel.size = Vector2(960, 600)
	_main_panel.position = Vector2(-480, -300)

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
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(_main_panel)

	# Root vertical layout
	var root_vbox := VBoxContainer.new()
	root_vbox.name = "RootVBox"
	root_vbox.add_theme_constant_override("separation", 8)
	_main_panel.add_child(root_vbox)

	# ── Header row ───────────────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	root_vbox.add_child(header)

	var title_label := Label.new()
	title_label.text = "퀘스트 기록"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", COLOR_ACCENT)
	header.add_child(title_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	# Tab buttons
	_tab_active_btn = _create_tab_button("진행 중", true)
	_tab_active_btn.pressed.connect(_on_tab_active)
	header.add_child(_tab_active_btn)

	_tab_completed_btn = _create_tab_button("완료됨", false)
	_tab_completed_btn.pressed.connect(_on_tab_completed)
	header.add_child(_tab_completed_btn)

	# Close button
	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.custom_minimum_size = Vector2(32, 32)
	_close_button.add_theme_font_size_override("font_size", 18)
	_close_button.add_theme_color_override("font_color", COLOR_TEXT)
	_close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.3, 0.3, 1.0))
	var close_normal := StyleBoxFlat.new()
	close_normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	_close_button.add_theme_stylebox_override("normal", close_normal)
	var close_hover := StyleBoxFlat.new()
	close_hover.bg_color = Color(0.3, 0.1, 0.1, 0.5)
	_apply_corner_radius(close_hover, 4)
	_close_button.add_theme_stylebox_override("hover", close_hover)
	_close_button.pressed.connect(toggle)
	header.add_child(_close_button)

	# ── Content: horizontal split ────────────────────────────────────────
	var content := HBoxContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	root_vbox.add_child(content)

	# Left panel: quest list
	var left_panel := PanelContainer.new()
	left_panel.name = "LeftPanel"
	left_panel.custom_minimum_size = Vector2(300, 0)
	left_panel.size_flags_horizontal = Control.SIZE_FILL
	left_panel.size_flags_stretch_ratio = 0.4
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = COLOR_DETAIL_BG
	_apply_corner_radius(left_style, 6)
	left_style.content_margin_top = 8.0
	left_style.content_margin_bottom = 8.0
	left_style.content_margin_left = 8.0
	left_style.content_margin_right = 8.0
	left_panel.add_theme_stylebox_override("panel", left_style)
	content.add_child(left_panel)

	_quest_list_scroll = ScrollContainer.new()
	_quest_list_scroll.name = "QuestListScroll"
	_quest_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_quest_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(_quest_list_scroll)

	_quest_list_container = VBoxContainer.new()
	_quest_list_container.name = "QuestList"
	_quest_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list_container.add_theme_constant_override("separation", 4)
	_quest_list_scroll.add_child(_quest_list_container)

	_empty_label = Label.new()
	_empty_label.text = "진행 중인 퀘스트가 없습니다."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override("font_color", Color(0.5, 0.48, 0.45, 0.6))
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_label.visible = false
	_quest_list_container.add_child(_empty_label)

	# Right panel: quest detail
	_detail_panel = PanelContainer.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_stretch_ratio = 0.6
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = COLOR_DETAIL_BG
	_apply_corner_radius(detail_style, 6)
	detail_style.content_margin_top = 16.0
	detail_style.content_margin_bottom = 16.0
	detail_style.content_margin_left = 16.0
	detail_style.content_margin_right = 16.0
	_detail_panel.add_theme_stylebox_override("panel", detail_style)
	content.add_child(_detail_panel)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.add_child(detail_scroll)

	var detail_vbox := VBoxContainer.new()
	detail_vbox.name = "DetailVBox"
	detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_vbox.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(detail_vbox)

	# Detail: title
	_detail_title = Label.new()
	_detail_title.name = "DetailTitle"
	_detail_title.text = "퀘스트를 선택하세요"
	_detail_title.add_theme_font_size_override("font_size", 20)
	_detail_title.add_theme_color_override("font_color", COLOR_ACCENT)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_vbox.add_child(_detail_title)

	# Detail: type
	_detail_type = Label.new()
	_detail_type.name = "DetailType"
	_detail_type.text = ""
	_detail_type.add_theme_font_size_override("font_size", 12)
	_detail_type.add_theme_color_override("font_color", COLOR_LORE)
	detail_vbox.add_child(_detail_type)

	# Detail: description
	_detail_description = RichTextLabel.new()
	_detail_description.name = "DetailDescription"
	_detail_description.bbcode_enabled = true
	_detail_description.fit_content = true
	_detail_description.scroll_active = false
	_detail_description.custom_minimum_size = Vector2(0, 60)
	_detail_description.add_theme_color_override("default_color", COLOR_TEXT)
	_detail_description.add_theme_font_size_override("normal_font_size", 14)
	detail_vbox.add_child(_detail_description)

	# Detail: objectives header
	var obj_header := Label.new()
	obj_header.text = "── 목표 ──"
	obj_header.add_theme_font_size_override("font_size", 14)
	obj_header.add_theme_color_override("font_color", COLOR_ACCENT)
	obj_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_vbox.add_child(obj_header)

	# Detail: objectives list
	_detail_objectives = VBoxContainer.new()
	_detail_objectives.name = "DetailObjectives"
	_detail_objectives.add_theme_constant_override("separation", 6)
	detail_vbox.add_child(_detail_objectives)

	# Detail: rewards
	var reward_header := Label.new()
	reward_header.text = "── 보상 ──"
	reward_header.add_theme_font_size_override("font_size", 14)
	reward_header.add_theme_color_override("font_color", COLOR_ACCENT)
	reward_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_vbox.add_child(reward_header)

	_detail_rewards = RichTextLabel.new()
	_detail_rewards.name = "DetailRewards"
	_detail_rewards.bbcode_enabled = true
	_detail_rewards.fit_content = true
	_detail_rewards.scroll_active = false
	_detail_rewards.custom_minimum_size = Vector2(0, 30)
	_detail_rewards.add_theme_color_override("default_color", COLOR_TEXT)
	_detail_rewards.add_theme_font_size_override("normal_font_size", 13)
	detail_vbox.add_child(_detail_rewards)

	# Detail: lore
	_detail_lore = RichTextLabel.new()
	_detail_lore.name = "DetailLore"
	_detail_lore.bbcode_enabled = true
	_detail_lore.fit_content = true
	_detail_lore.scroll_active = false
	_detail_lore.custom_minimum_size = Vector2(0, 20)
	_detail_lore.add_theme_color_override("default_color", COLOR_LORE)
	_detail_lore.add_theme_font_size_override("normal_font_size", 12)
	detail_vbox.add_child(_detail_lore)

	# Action buttons at the bottom of detail
	var action_row := HBoxContainer.new()
	action_row.name = "ActionRow"
	action_row.add_theme_constant_override("separation", 8)
	detail_vbox.add_child(action_row)

	_track_button = _create_action_button("추적")
	_track_button.pressed.connect(_on_track_pressed)
	action_row.add_child(_track_button)

	_abandon_button = _create_action_button("포기")
	_abandon_button.add_theme_color_override("font_color", COLOR_FAILED)
	_abandon_button.pressed.connect(_on_abandon_pressed)
	action_row.add_child(_abandon_button)

# ── Quest List Population ────────────────────────────────────────────────────

func _populate_active_quests(quest_mgr: Node) -> void:
	var quests: Array = quest_mgr.get_active_quests()
	if quests.is_empty():
		_show_empty_message("진행 중인 퀘스트가 없습니다.")
		return

	_empty_label.visible = false
	for quest in quests:
		_add_quest_list_item(quest, false)


func _populate_completed_quests(quest_mgr: Node) -> void:
	var completed_ids: Array = quest_mgr.completed_quests
	if completed_ids.is_empty():
		_show_empty_message("완료된 퀘스트가 없습니다.")
		return

	_empty_label.visible = false
	for quest_id in completed_ids:
		# Completed quests have minimal data; show id-based item.
		var placeholder: Dictionary = {
			"id": quest_id,
			"title": quest_id.replace("_", " ").capitalize(),
			"type": "completed",
		}
		_add_quest_list_item(placeholder, true)


func _add_quest_list_item(quest: Dictionary, is_completed: bool) -> void:
	var quest_id: String = quest.get("id", "")
	var title: String = quest.get("title", quest_id)
	var quest_type: String = quest.get("type", "")

	var item_btn := Button.new()
	item_btn.name = "QuestItem_%s" % quest_id
	item_btn.custom_minimum_size = Vector2(0, 48)
	item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Build display text with progress
	var display_text: String = ""
	var type_symbol: String = _get_type_symbol(quest_type)
	if not type_symbol.is_empty():
		display_text += "[%s] " % type_symbol

	display_text += title

	if not is_completed:
		var progress_pct: int = _calc_quest_progress(quest)
		display_text += "  (%d%%)" % progress_pct

	item_btn.text = display_text

	# Styling
	var text_color: Color = COLOR_TEXT if not is_completed else Color(0.5, 0.5, 0.5, 0.8)
	if not is_completed:
		text_color = COLOR_ACCENT

	item_btn.add_theme_color_override("font_color", text_color)
	item_btn.add_theme_font_size_override("font_size", 14)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = COLOR_LIST_ITEM_BG
	_apply_corner_radius(normal_style, 4)
	normal_style.content_margin_left = 10.0
	normal_style.content_margin_right = 10.0
	item_btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = COLOR_LIST_ITEM_HOVER
	item_btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = COLOR_LIST_ITEM_SELECTED
	item_btn.add_theme_stylebox_override("pressed", pressed_style)

	item_btn.pressed.connect(_on_quest_item_pressed.bind(quest_id))
	_quest_list_container.add_child(item_btn)


## Display the detail view for the selected quest.
func _show_quest_detail(quest_id: String) -> void:
	_selected_quest_id = quest_id
	quest_selected.emit(quest_id)

	var quest_mgr := _get_quest_manager()
	if quest_mgr == null:
		return

	var quest: Dictionary = quest_mgr.get_quest(quest_id)
	var is_completed: bool = quest_mgr.completed_quests.has(quest_id)

	if quest.is_empty() and not is_completed:
		_detail_title.text = "알 수 없는 퀘스트"
		_detail_description.clear()
		return

	# Title
	_detail_title.text = quest.get("title", quest_id)

	# Type
	var quest_type: String = quest.get("type", "")
	_detail_type.text = _get_type_display(quest_type)

	# Description
	_detail_description.clear()
	_detail_description.append_text(quest.get("description", ""))

	# Objectives
	_clear_objectives()
	var objectives: Array = quest.get("objectives", [])
	var progress: Dictionary = quest.get("progress", {})
	for i in range(objectives.size()):
		var obj: Dictionary = objectives[i] if objectives[i] is Dictionary else {}
		var obj_id: String = obj.get("id", "obj_%d" % i)
		var obj_desc: String = obj.get("description", "목표 %d" % (i + 1))
		var obj_prog: Dictionary = progress.get(obj_id, {})
		var current: int = int(obj_prog.get("current", 0))
		var required: int = int(obj_prog.get("required", int(obj.get("count", 1))))
		var done: bool = obj_prog.get("completed", false)
		_add_objective_item(obj_desc, current, required, done)

	# Rewards
	_detail_rewards.clear()
	var rewards: Dictionary = quest.get("rewards", {})
	var reward_lines: Array[String] = []
	var gold: int = int(rewards.get("gold", 0))
	var xp: int = int(rewards.get("experience", 0))
	if gold > 0:
		reward_lines.append("[color=#ebca42]골드: %d[/color]" % gold)
	if xp > 0:
		reward_lines.append("[color=#82b1ff]경험치: %d[/color]" % xp)
	var reward_items: Array = rewards.get("items", [])
	for item in reward_items:
		if item is Dictionary:
			var rarity_color: String = _get_rarity_color(item.get("rarity", "common"))
			reward_lines.append("[color=%s]%s[/color]" % [rarity_color, item.get("name", "아이템")])
	if reward_lines.is_empty():
		_detail_rewards.append_text("[color=#666060]보상 정보 없음[/color]")
	else:
		_detail_rewards.append_text("\n".join(reward_lines))

	# Lore
	_detail_lore.clear()
	var lore: String = quest.get("lore", "")
	if not lore.is_empty():
		_detail_lore.append_text("[i]%s[/i]" % lore)

	# Show/hide action buttons
	_track_button.visible = not is_completed
	_abandon_button.visible = not is_completed


func _add_objective_item(description: String, current: int, required: int, completed: bool) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	# Checkbox icon
	var check := Label.new()
	check.text = "☑" if completed else "☐"
	check.add_theme_font_size_override("font_size", 16)
	check.add_theme_color_override("font_color", COLOR_OBJECTIVE_DONE if completed else COLOR_OBJECTIVE_PENDING)
	check.custom_minimum_size = Vector2(20, 0)
	hbox.add_child(check)

	# Objective text
	var text := Label.new()
	var display: String = description
	if required > 1:
		display += " (%d/%d)" % [current, required]
	if completed:
		display = "[완료] " + display
	text.text = display
	text.add_theme_font_size_override("font_size", 13)
	var text_color: Color = COLOR_OBJECTIVE_DONE if completed else COLOR_OBJECTIVE_PENDING
	text.add_theme_color_override("font_color", text_color)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text)

	_detail_objectives.add_child(hbox)


# ── Handlers ─────────────────────────────────────────────────────────────────

func _on_tab_active() -> void:
	_showing_completed = false
	_update_tab_visuals()
	_selected_quest_id = ""
	refresh()


func _on_tab_completed() -> void:
	_showing_completed = true
	_update_tab_visuals()
	_selected_quest_id = ""
	refresh()


func _on_quest_item_pressed(quest_id: String) -> void:
	_show_quest_detail(quest_id)


func _on_track_pressed() -> void:
	if _selected_quest_id.is_empty():
		return
	# Tell the QuestHUD to track this quest.
	var hud := _get_autoload("QuestHUD")
	if hud != null and hud.has_method("set_tracked_quest"):
		hud.set_tracked_quest(_selected_quest_id)


func _on_abandon_pressed() -> void:
	if _selected_quest_id.is_empty():
		return
	var quest_mgr := _get_quest_manager()
	if quest_mgr != null:
		quest_mgr.fail_quest(_selected_quest_id)
	quest_abandoned.emit(_selected_quest_id)
	_selected_quest_id = ""
	refresh()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _clear_quest_list() -> void:
	for child in _quest_list_container.get_children():
		if child != _empty_label:
			child.queue_free()


func _clear_objectives() -> void:
	for child in _detail_objectives.get_children():
		child.queue_free()


func _show_empty_message(text: String) -> void:
	_empty_label.text = text
	_empty_label.visible = true


func _calc_quest_progress(quest: Dictionary) -> int:
	var progress: Dictionary = quest.get("progress", {})
	if progress.is_empty():
		return 0
	var total_current: float = 0.0
	var total_required: float = 0.0
	for obj_id in progress:
		var obj_prog: Dictionary = progress[obj_id]
		total_current += float(obj_prog.get("current", 0))
		total_required += float(obj_prog.get("required", 1))
	if total_required <= 0.0:
		return 0
	return int((total_current / total_required) * 100.0)


func _get_type_symbol(quest_type: String) -> String:
	match quest_type:
		"combat", "kill":
			return "⚔"
		"collect":
			return "◆"
		"explore":
			return "◎"
		"rescue":
			return "♦"
		"survival":
			return "☠"
		"find", "interact":
			return "◉"
		_:
			return "●"


func _get_type_display(quest_type: String) -> String:
	match quest_type:
		"combat", "kill":
			return "전투 퀘스트"
		"collect":
			return "수집 퀘스트"
		"explore":
			return "탐험 퀘스트"
		"rescue":
			return "구출 퀘스트"
		"survival":
			return "생존 퀘스트"
		"find":
			return "탐색 퀘스트"
		"interact":
			return "상호작용 퀘스트"
		_:
			return "퀘스트"


func _get_rarity_color(rarity: String) -> String:
	match rarity:
		"common":
			return "#c8c8c8"
		"uncommon":
			return "#4fc34f"
		"rare":
			return "#4f8fc3"
		"epic":
			return "#a64fc3"
		"legendary":
			return "#ebca42"
		_:
			return "#e6e1d1"


func _update_tab_visuals() -> void:
	var active_color: Color = COLOR_ACCENT if not _showing_completed else Color(0.6, 0.58, 0.52, 0.8)
	var completed_color: Color = COLOR_ACCENT if _showing_completed else Color(0.6, 0.58, 0.52, 0.8)
	_tab_active_btn.add_theme_color_override("font_color", active_color)
	_tab_completed_btn.add_theme_color_override("font_color", completed_color)


func _create_tab_button(text: String, is_active: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(80, 30)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", COLOR_ACCENT if is_active else Color(0.6, 0.58, 0.52, 0.8))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	btn.add_theme_stylebox_override("normal", style)
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_LIST_ITEM_HOVER
	_apply_corner_radius(hover, 4)
	btn.add_theme_stylebox_override("hover", hover)
	return btn


func _create_action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(80, 32)
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BUTTON
	style.border_color = COLOR_PANEL_BORDER
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	_apply_corner_radius(style, 4)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = COLOR_BUTTON_HOVER
	btn.add_theme_stylebox_override("hover", hover)
	return btn


func _apply_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius


func _get_quest_manager() -> Node:
	return _get_autoload("QuestManager")


func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
