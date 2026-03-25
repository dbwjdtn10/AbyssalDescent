## Combat interface overlay.
##
## Builds its entire UI tree programmatically so it has no .tscn dependency.
## Displays enemy list, action buttons, combat log, and player stats during
## turn-based combat encounters.
class_name CombatUI
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal attack_requested(enemy_index: int)
signal skill_requested(skill_id: String, enemy_index: int)
signal item_use_requested(item: Dictionary)
signal flee_requested

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color("#140f1a")
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.1, 0.95)
const COLOR_PANEL_BORDER := Color(0.72, 0.58, 0.2, 1.0)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_HP_BAR := Color(0.8, 0.13, 0.13, 1.0)
const COLOR_HP_BAR_BG := Color(0.25, 0.08, 0.08, 0.8)
const COLOR_ENEMY_HP := Color(0.75, 0.15, 0.15, 1.0)
const COLOR_ENEMY_HP_BG := Color(0.2, 0.06, 0.06, 0.8)
const COLOR_BUTTON := Color(0.18, 0.14, 0.22, 1.0)
const COLOR_BUTTON_HOVER := Color(0.28, 0.22, 0.34, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.12, 0.1, 0.16, 1.0)
const COLOR_ENEMY_SELECTED := Color(0.92, 0.76, 0.26, 0.3)
const COLOR_ENEMY_DEAD := Color(0.3, 0.3, 0.3, 0.5)
const COLOR_LOG_DAMAGE := Color(0.9, 0.3, 0.3, 1.0)
const COLOR_LOG_HEAL := Color(0.3, 0.85, 0.4, 1.0)
const COLOR_LOG_INFO := Color(0.7, 0.68, 0.62, 1.0)
const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.65)

const ELEMENT_COLORS: Dictionary = {
	"fire": Color(1.0, 0.4, 0.1),
	"ice": Color(0.5, 0.8, 1.0),
	"lightning": Color(1.0, 1.0, 0.3),
	"water": Color(0.2, 0.5, 1.0),
	"holy": Color(1.0, 0.95, 0.7),
	"dark": Color(0.6, 0.2, 0.8),
}

const ELEMENT_NAMES: Dictionary = {
	"fire": "화", "ice": "빙", "lightning": "뇌",
	"water": "수", "holy": "성", "dark": "암",
}

# ── UI Node References ──────────────────────────────────────────────────────

var _overlay: ColorRect
var _main_panel: PanelContainer
var _enemy_list_container: VBoxContainer
var _enemy_panels: Array[PanelContainer] = []
var _enemy_hp_bars: Array[ProgressBar] = []
var _enemy_hp_labels: Array[Label] = []
var _enemy_name_labels: Array[Label] = []
var _combat_log: RichTextLabel
var _player_hp_bar: ProgressBar
var _player_hp_label: Label
var _player_atk_label: Label
var _player_def_label: Label
var _attack_button: Button
var _skill_buttons: Array[Button] = []
var _skill_container: HBoxContainer
var _item_button: Button
var _flee_button: Button
var _item_popup: PanelContainer
var _item_popup_list: VBoxContainer

# ── State ────────────────────────────────────────────────────────────────────

var _selected_enemy: int = 0
var _is_visible: bool = false

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dark overlay.
	_overlay = ColorRect.new()
	_overlay.name = "CombatOverlay"
	_overlay.color = COLOR_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Main panel centred on screen.
	_main_panel = PanelContainer.new()
	_main_panel.name = "CombatPanel"
	_main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main_panel.offset_left = 40.0
	_main_panel.offset_right = -40.0
	_main_panel.offset_top = 40.0
	_main_panel.offset_bottom = -40.0

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	_apply_corner_radius(panel_style, 8)
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_bottom = 16.0
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_right = 16.0
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(_main_panel)

	# Horizontal split: enemies (left) | log (centre) | player (right).
	var h_box := HBoxContainer.new()
	h_box.name = "ContentHBox"
	h_box.add_theme_constant_override("separation", 12)
	_main_panel.add_child(h_box)

	_build_enemy_list(h_box)
	_build_combat_log(h_box)
	_build_player_panel(h_box)

	# Action buttons at the bottom.
	_build_action_buttons()


## Left panel: list of enemies with HP bars.
func _build_enemy_list(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "EnemyListPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.3

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.08, 1.0)
	_apply_corner_radius(style, 6)
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "EnemyListVBox"
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Header.
	var header := Label.new()
	header.text = "적 목록"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Scrollable enemy container.
	var scroll := ScrollContainer.new()
	scroll.name = "EnemyScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_enemy_list_container = VBoxContainer.new()
	_enemy_list_container.name = "EnemyContainer"
	_enemy_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_enemy_list_container)


## Centre panel: scrollable combat log.
func _build_combat_log(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "CombatLogPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.4

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.03, 0.07, 1.0)
	_apply_corner_radius(style, 6)
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "전투 기록"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	_combat_log = RichTextLabel.new()
	_combat_log.name = "CombatLog"
	_combat_log.bbcode_enabled = true
	_combat_log.scroll_following = true
	_combat_log.selection_enabled = false
	_combat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_combat_log.add_theme_font_size_override("normal_font_size", 13)
	_combat_log.add_theme_color_override("default_color", COLOR_LOG_INFO)
	vbox.add_child(_combat_log)


## Right panel: player stats display.
func _build_player_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "PlayerStatsPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.3

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.08, 1.0)
	_apply_corner_radius(style, 6)
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Header.
	var header := Label.new()
	header.text = "플레이어"
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# HP bar.
	var hp_header := Label.new()
	hp_header.text = "♥ HP"
	hp_header.add_theme_font_size_override("font_size", 14)
	hp_header.add_theme_color_override("font_color", COLOR_HP_BAR)
	vbox.add_child(hp_header)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.name = "PlayerHPBar"
	_player_hp_bar.min_value = 0.0
	_player_hp_bar.max_value = 100.0
	_player_hp_bar.value = 100.0
	_player_hp_bar.show_percentage = false
	_player_hp_bar.custom_minimum_size = Vector2(0, 18)

	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = COLOR_HP_BAR_BG
	_apply_corner_radius(hp_bg, 4)
	_player_hp_bar.add_theme_stylebox_override("background", hp_bg)

	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = COLOR_HP_BAR
	_apply_corner_radius(hp_fill, 4)
	_player_hp_bar.add_theme_stylebox_override("fill", hp_fill)
	vbox.add_child(_player_hp_bar)

	_player_hp_label = Label.new()
	_player_hp_label.name = "PlayerHPLabel"
	_player_hp_label.text = "100 / 100"
	_player_hp_label.add_theme_font_size_override("font_size", 13)
	_player_hp_label.add_theme_color_override("font_color", COLOR_TEXT)
	_player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_player_hp_label)

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Attack stat.
	_player_atk_label = Label.new()
	_player_atk_label.name = "PlayerAtkLabel"
	_player_atk_label.text = "공격력: 10"
	_player_atk_label.add_theme_font_size_override("font_size", 14)
	_player_atk_label.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(_player_atk_label)

	# Defense stat.
	_player_def_label = Label.new()
	_player_def_label.name = "PlayerDefLabel"
	_player_def_label.text = "방어력: 5"
	_player_def_label.add_theme_font_size_override("font_size", 14)
	_player_def_label.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(_player_def_label)


## Action buttons anchored to the bottom centre.
func _build_action_buttons() -> void:
	var button_bar := HBoxContainer.new()
	button_bar.name = "ActionButtons"
	button_bar.add_theme_constant_override("separation", 16)

	# Anchor to bottom-centre inside the overlay.
	button_bar.anchor_left = 0.5
	button_bar.anchor_right = 0.5
	button_bar.anchor_top = 1.0
	button_bar.anchor_bottom = 1.0
	button_bar.offset_left = -240.0
	button_bar.offset_right = 240.0
	button_bar.offset_top = -80.0
	button_bar.offset_bottom = -30.0
	_overlay.add_child(button_bar)

	_attack_button = _create_action_button("공격", button_bar)
	_attack_button.pressed.connect(_on_attack_pressed)

	_item_button = _create_action_button("아이템 사용", button_bar)
	_item_button.pressed.connect(_on_item_pressed)

	_flee_button = _create_action_button("도망", button_bar)
	_flee_button.pressed.connect(_on_flee_pressed)

	# Item selection popup (hidden by default).
	_build_item_popup()

	# Skill buttons bar (above action buttons).
	_skill_container = HBoxContainer.new()
	_skill_container.name = "SkillButtons"
	_skill_container.add_theme_constant_override("separation", 8)
	_skill_container.anchor_left = 0.5
	_skill_container.anchor_right = 0.5
	_skill_container.anchor_top = 1.0
	_skill_container.anchor_bottom = 1.0
	_skill_container.offset_left = -320.0
	_skill_container.offset_right = 320.0
	_skill_container.offset_top = -130.0
	_skill_container.offset_bottom = -85.0
	_skill_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay.add_child(_skill_container)


# ── Public API ───────────────────────────────────────────────────────────────

## Show the combat overlay and populate enemy list.
func show_combat(enemies: Array) -> void:
	_clear_enemy_list()
	_selected_enemy = 0

	for i in range(enemies.size()):
		_add_enemy_entry(i, enemies[i])

	_combat_log.clear()
	add_combat_log("전투 시작!")

	# Log enemy elements.
	for e in enemies:
		var elem: String = str(e.get("element", ""))
		if not elem.is_empty() and ELEMENT_NAMES.has(elem):
			var ecolor: Color = ELEMENT_COLORS.get(elem, COLOR_TEXT)
			add_combat_log("[color=#%s]%s: %s 속성[/color]" % [ecolor.to_html(false), e.get("name", "적"), ELEMENT_NAMES[elem]])

	_build_skill_buttons()
	_update_enemy_selection()
	_set_buttons_enabled(true)
	visible = true
	_is_visible = true


## Hide the combat overlay.
func hide_combat() -> void:
	visible = false
	_is_visible = false
	_clear_enemy_list()
	_clear_skill_buttons()


## Update a specific enemy's HP bar display.
func update_enemy_hp(index: int, current: float, max_hp: float) -> void:
	if index < 0 or index >= _enemy_hp_bars.size():
		return

	_enemy_hp_bars[index].max_value = max_hp
	_enemy_hp_bars[index].value = current
	_enemy_hp_labels[index].text = "%d / %d" % [int(current), int(max_hp)]

	# Grey out dead enemies.
	if current <= 0.0:
		_enemy_panels[index].modulate = COLOR_ENEMY_DEAD


## Update the player's HP display.
func update_player_hp(current: float, max_hp: float) -> void:
	_player_hp_bar.max_value = max_hp
	_player_hp_bar.value = current
	_player_hp_label.text = "%d / %d" % [int(current), int(max_hp)]


## Update the player's attack / defense stat labels.
func update_player_stats(atk: float, def: float) -> void:
	_player_atk_label.text = "공격력: %d" % int(atk)
	_player_def_label.text = "방어력: %d" % int(def)


## Add a message to the combat log.  Supports BBCode.
func add_combat_log(message: String) -> void:
	_combat_log.append_text(message + "\n")


## Add a damage message to the log (red text).
func add_damage_log(attacker: String, target: String, damage: float) -> void:
	var msg := "[color=#e64d4d]%s이(가) %s에게 %d 피해![/color]" % [attacker, target, int(damage)]
	add_combat_log(msg)


## Add a heal message to the log (green text).
func add_heal_log(target: String, amount: float) -> void:
	var msg := "[color=#4dcc66]%s이(가) %d 회복![/color]" % [target, int(amount)]
	add_combat_log(msg)


## Enable or disable the action buttons.
func set_player_turn(is_player_turn: bool) -> void:
	_set_buttons_enabled(is_player_turn)


# ── Input Handlers ──────────────────────────────────────────────────────────

func _on_attack_pressed() -> void:
	# Find next alive enemy if selected one is dead.
	_select_next_alive_enemy()
	attack_requested.emit(_selected_enemy)


func _on_item_pressed() -> void:
	_toggle_item_popup()


func _on_flee_pressed() -> void:
	flee_requested.emit()


# ── Enemy Selection ──────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_visible:
		return

	if event is InputEventKey and event.pressed:
		# Tab to cycle enemy selection.
		if event.keycode == KEY_TAB:
			_cycle_enemy_selection()
			get_viewport().set_input_as_handled()
		# Number keys to select enemy directly.
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx: int = event.keycode - KEY_1
			if idx < _enemy_panels.size():
				_selected_enemy = idx
				_update_enemy_selection()
				get_viewport().set_input_as_handled()


func _cycle_enemy_selection() -> void:
	var start: int = _selected_enemy
	for _i in range(_enemy_panels.size()):
		_selected_enemy = (_selected_enemy + 1) % _enemy_panels.size()
		# Check if this enemy is alive by inspecting HP bar value.
		if _enemy_hp_bars[_selected_enemy].value > 0.0:
			break
	_update_enemy_selection()


func _select_next_alive_enemy() -> void:
	if _selected_enemy < _enemy_hp_bars.size() and _enemy_hp_bars[_selected_enemy].value > 0.0:
		return
	_cycle_enemy_selection()


func _update_enemy_selection() -> void:
	for i in range(_enemy_panels.size()):
		var style := _enemy_panels[i].get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if style != null:
			if i == _selected_enemy:
				style.border_color = COLOR_ACCENT
				style.border_width_left = 3
			else:
				style.border_color = Color(0.3, 0.25, 0.35, 0.4)
				style.border_width_left = 1
			_enemy_panels[i].add_theme_stylebox_override("panel", style)


# ── Enemy List Management ───────────────────────────────────────────────────

func _add_enemy_entry(index: int, enemy: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "Enemy_%d" % index
	panel.custom_minimum_size = Vector2(0, 60)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.12, 0.8)
	style.border_color = Color(0.3, 0.25, 0.35, 0.4)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	_apply_corner_radius(style, 4)
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)

	# Name + Level + Element.
	var name_label := Label.new()
	var enemy_name: String = enemy.get("name", "적")
	var enemy_level: int = int(enemy.get("level", 1))
	var enemy_elem: String = str(enemy.get("element", ""))
	var elem_tag: String = ""
	if not enemy_elem.is_empty() and ELEMENT_NAMES.has(enemy_elem):
		elem_tag = " [%s]" % ELEMENT_NAMES[enemy_elem]
	name_label.text = "%s (Lv.%d)%s" % [enemy_name, enemy_level, elem_tag]
	name_label.add_theme_font_size_override("font_size", 13)
	var name_color: Color = ELEMENT_COLORS.get(enemy_elem, COLOR_TEXT)
	name_label.add_theme_color_override("font_color", name_color)
	vbox.add_child(name_label)

	# HP bar.
	var hp: float = float(enemy.get("hp", 50.0))
	var max_hp: float = float(enemy.get("max_hp", 50.0))

	var hp_bar := ProgressBar.new()
	hp_bar.min_value = 0.0
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(0, 12)

	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = COLOR_ENEMY_HP_BG
	_apply_corner_radius(hp_bg, 3)
	hp_bar.add_theme_stylebox_override("background", hp_bg)

	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = COLOR_ENEMY_HP
	_apply_corner_radius(hp_fill, 3)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	vbox.add_child(hp_bar)

	# HP label.
	var hp_label := Label.new()
	hp_label.text = "%d / %d" % [int(hp), int(max_hp)]
	hp_label.add_theme_font_size_override("font_size", 11)
	hp_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6, 1.0))
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(hp_label)

	# Make clickable for selection.
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_selected_enemy = index
			_update_enemy_selection()
	)

	_enemy_list_container.add_child(panel)
	_enemy_panels.append(panel)
	_enemy_hp_bars.append(hp_bar)
	_enemy_hp_labels.append(hp_label)
	_enemy_name_labels.append(name_label)


## Build skill buttons from the player's CombatSystem.
func _build_skill_buttons() -> void:
	_clear_skill_buttons()
	# Find the player's CombatSystem to read available skills.
	var player: Node = null
	if get_tree() != null:
		player = get_tree().root.find_child("Player", true, false)
	if player == null:
		return
	var cs: Node = player.get_node_or_null("CombatSystem")
	if cs == null:
		return
	var skills: Array = cs.get("player_skills") if "player_skills" in cs else []
	for skill in skills:
		var skill_id: String = skill.get("id", "")
		var skill_name: String = skill.get("name", "?")
		var elem: String = skill.get("element", "")
		var elem_color: Color = ELEMENT_COLORS.get(elem, COLOR_ACCENT)

		var btn := Button.new()
		btn.text = skill_name
		btn.custom_minimum_size = Vector2(100, 35)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", elem_color)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.1, 0.16, 0.9)
		style.border_color = elem_color * Color(1, 1, 1, 0.5)
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.border_width_left = 1
		style.border_width_right = 1
		_apply_corner_radius(style, 4)
		btn.add_theme_stylebox_override("normal", style)

		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.2, 0.16, 0.24, 1.0)
		hover.border_color = elem_color
		btn.add_theme_stylebox_override("hover", hover)

		var pressed := style.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(0.08, 0.06, 0.1, 1.0)
		btn.add_theme_stylebox_override("pressed", pressed)

		var disabled := style.duplicate() as StyleBoxFlat
		disabled.bg_color = Color(0.1, 0.08, 0.12, 0.5)
		disabled.border_color = Color(0.3, 0.25, 0.35, 0.3)
		btn.add_theme_stylebox_override("disabled", disabled)

		var captured_id: String = skill_id
		btn.pressed.connect(func() -> void:
			_select_next_alive_enemy()
			skill_requested.emit(captured_id, _selected_enemy)
		)
		_skill_container.add_child(btn)
		_skill_buttons.append(btn)


## Build the item selection popup (anchored above the item button).
func _build_item_popup() -> void:
	_item_popup = PanelContainer.new()
	_item_popup.name = "ItemPopup"
	_item_popup.anchor_left = 0.5
	_item_popup.anchor_right = 0.5
	_item_popup.anchor_top = 1.0
	_item_popup.anchor_bottom = 1.0
	_item_popup.offset_left = -140.0
	_item_popup.offset_right = 140.0
	_item_popup.offset_top = -260.0
	_item_popup.offset_bottom = -140.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.1, 0.95)
	style.border_color = COLOR_PANEL_BORDER
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	_apply_corner_radius(style, 6)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	_item_popup.add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 100)
	_item_popup.add_child(scroll)

	_item_popup_list = VBoxContainer.new()
	_item_popup_list.name = "ItemList"
	_item_popup_list.add_theme_constant_override("separation", 4)
	_item_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_popup_list)

	_item_popup.visible = false
	_overlay.add_child(_item_popup)


## Toggle the item selection popup, refreshing the list from inventory.
func _toggle_item_popup() -> void:
	if _item_popup.visible:
		_item_popup.visible = false
		return

	# Clear old entries.
	for child in _item_popup_list.get_children():
		child.queue_free()

	# Fetch consumables from inventory.
	var inv: Node = null
	if get_tree() != null:
		var root: Window = get_tree().root
		if root.has_node("InventorySystem"):
			inv = root.get_node("InventorySystem")
	if inv == null or not inv.has_method("get_items_by_type"):
		_add_popup_label("인벤토리를 사용할 수 없습니다.")
		_item_popup.visible = true
		return

	var consumables: Array = inv.get_items_by_type("consumable")
	var potions: Array = inv.get_items_by_type("potion")
	consumables.append_array(potions)

	if consumables.is_empty():
		_add_popup_label("사용할 수 있는 아이템이 없습니다.")
		_item_popup.visible = true
		return

	for item in consumables:
		var item_name: String = item.get("name", "???")
		var heal: int = int(item.get("stats", {}).get("heal", item.get("heal", 0)))
		var label_text: String = "%s (회복 %d)" % [item_name, heal] if heal > 0 else item_name

		var btn := Button.new()
		btn.text = label_text
		btn.custom_minimum_size = Vector2(240, 30)
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", COLOR_LOG_HEAL)

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.12, 0.1, 0.16, 0.9)
		_apply_corner_radius(btn_style, 3)
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := btn_style.duplicate() as StyleBoxFlat
		hover_style.bg_color = Color(0.2, 0.16, 0.24, 1.0)
		btn.add_theme_stylebox_override("hover", hover_style)

		var captured_item: Dictionary = item.duplicate(true)
		btn.pressed.connect(func() -> void:
			_item_popup.visible = false
			item_use_requested.emit(captured_item)
		)
		_item_popup_list.add_child(btn)

	_item_popup.visible = true


func _add_popup_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", COLOR_LOG_INFO)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_popup_list.add_child(lbl)


func _clear_skill_buttons() -> void:
	for btn in _skill_buttons:
		if is_instance_valid(btn):
			btn.queue_free()
	_skill_buttons.clear()


func _clear_enemy_list() -> void:
	for child in _enemy_list_container.get_children():
		child.queue_free()
	_enemy_panels.clear()
	_enemy_hp_bars.clear()
	_enemy_hp_labels.clear()
	_enemy_name_labels.clear()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _create_action_button(text: String, parent: Node) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 40)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", COLOR_TEXT)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = COLOR_BUTTON
	normal_style.border_color = COLOR_ACCENT
	normal_style.border_width_top = 1
	normal_style.border_width_bottom = 1
	normal_style.border_width_left = 1
	normal_style.border_width_right = 1
	_apply_corner_radius(normal_style, 4)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = COLOR_BUTTON_HOVER
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := normal_style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = COLOR_BUTTON_PRESSED
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style := normal_style.duplicate() as StyleBoxFlat
	disabled_style.bg_color = Color(0.1, 0.08, 0.12, 0.5)
	disabled_style.border_color = Color(0.3, 0.25, 0.35, 0.3)
	btn.add_theme_stylebox_override("disabled", disabled_style)

	parent.add_child(btn)
	return btn


func _set_buttons_enabled(enabled: bool) -> void:
	_attack_button.disabled = not enabled
	_item_button.disabled = not enabled
	_flee_button.disabled = not enabled
	for btn in _skill_buttons:
		if is_instance_valid(btn):
			btn.disabled = not enabled


func _apply_corner_radius(style: StyleBoxFlat, radius: int) -> void:
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
