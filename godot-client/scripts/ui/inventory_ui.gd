## Full-screen inventory overlay.
##
## Builds its entire UI tree programmatically so it has no .tscn dependency.
## Displays a 6x5 item grid, equipment panel, item detail panel, and player
## stat summary.  Toggle with the I key.
class_name InventoryUI
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal item_selected(item_data: Dictionary)
signal item_used(item_id: String)

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color("#140f1a")
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.1, 0.95)
const COLOR_PANEL_BORDER := Color(0.72, 0.58, 0.2, 1.0)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.7)
const COLOR_SLOT_BG := Color(0.1, 0.08, 0.12, 0.8)
const COLOR_SLOT_HOVER := Color(0.18, 0.14, 0.22, 1.0)
const COLOR_SLOT_SELECTED := Color(0.25, 0.20, 0.30, 1.0)
const COLOR_DETAIL_BG := Color(0.06, 0.04, 0.08, 1.0)
const COLOR_BUTTON := Color(0.18, 0.14, 0.22, 1.0)
const COLOR_BUTTON_HOVER := Color(0.28, 0.22, 0.34, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.12, 0.1, 0.16, 1.0)

# ── Rarity Colors ────────────────────────────────────────────────────────────

const RARITY_COLORS: Dictionary = {
	"common": Color("#c8c8c8"),
	"uncommon": Color("#4fc34f"),
	"rare": Color("#4f8fc3"),
	"epic": Color("#a64fc3"),
	"legendary": Color("#ebca42"),
}

# ── Constants ────────────────────────────────────────────────────────────────

const GRID_COLUMNS: int = 6
const GRID_ROWS: int = 5
const SLOT_SIZE: float = 64.0
const SLOT_SPACING: float = 4.0

# ── UI Node References ──────────────────────────────────────────────────────

var _overlay: ColorRect
var _main_panel: PanelContainer
var _grid_container: GridContainer
var _slot_panels: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _slot_qty_labels: Array[Label] = []

# Equipment slots.
var _equip_weapon_panel: PanelContainer
var _equip_armor_panel: PanelContainer
var _equip_accessory_panel: PanelContainer
var _equip_weapon_label: Label
var _equip_armor_label: Label
var _equip_accessory_label: Label

# Detail panel.
var _detail_panel: PanelContainer
var _detail_name_label: Label
var _detail_rarity_label: Label
var _detail_desc_label: RichTextLabel
var _detail_stats_label: Label
var _equip_button: Button
var _use_button: Button
var _discard_button: Button

# Stats panel.
var _stats_atk_label: Label
var _stats_def_label: Label
var _stats_hp_label: Label

# ── State ────────────────────────────────────────────────────────────────────

var _is_open: bool = false
var _selected_index: int = -1
var _selected_item: Dictionary = {}

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_I:
			_toggle()
			get_viewport().set_input_as_handled()


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen overlay.
	_overlay = ColorRect.new()
	_overlay.name = "InvOverlay"
	_overlay.color = COLOR_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Main panel.
	_main_panel = PanelContainer.new()
	_main_panel.name = "InventoryPanel"
	_main_panel.set_anchors_preset(Control.PRESET_CENTER)
	_main_panel.custom_minimum_size = Vector2(900, 580)
	_main_panel.size = Vector2(900, 580)
	_main_panel.position = Vector2(-450, -290)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	_apply_corner_radius(panel_style, 8)
	panel_style.content_margin_top = 14.0
	panel_style.content_margin_bottom = 14.0
	panel_style.content_margin_left = 14.0
	panel_style.content_margin_right = 14.0
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	_overlay.add_child(_main_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_main_panel.add_child(vbox)

	# Title bar.
	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)

	var title := Label.new()
	title.text = "인벤토리"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title_bar.add_child(title)

	var title_spacer := Control.new()
	title_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title_spacer)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.add_theme_color_override("font_color", COLOR_TEXT)
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.pressed.connect(func() -> void: _toggle())
	title_bar.add_child(close_btn)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)

	# Content: inventory grid (left) | equipment + stats (right).
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 12)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_hbox)

	_build_grid(content_hbox)
	_build_right_column(content_hbox)

	# Bottom: item detail panel.
	_build_detail_panel(vbox)


## Item grid: 6 columns x 5 rows.
func _build_grid(parent: HBoxContainer) -> void:
	var grid_panel := PanelContainer.new()
	grid_panel.name = "GridPanel"
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_stretch_ratio = 0.65

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_DETAIL_BG
	_apply_corner_radius(style, 6)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	grid_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(grid_panel)

	_grid_container = GridContainer.new()
	_grid_container.name = "ItemGrid"
	_grid_container.columns = GRID_COLUMNS
	_grid_container.add_theme_constant_override("h_separation", int(SLOT_SPACING))
	_grid_container.add_theme_constant_override("v_separation", int(SLOT_SPACING))
	grid_panel.add_child(_grid_container)

	for i in range(GRID_COLUMNS * GRID_ROWS):
		var slot := PanelContainer.new()
		slot.name = "Slot_%d" % i
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = COLOR_SLOT_BG
		slot_style.border_color = Color(0.3, 0.25, 0.35, 0.3)
		slot_style.border_width_top = 1
		slot_style.border_width_bottom = 1
		slot_style.border_width_left = 1
		slot_style.border_width_right = 1
		_apply_corner_radius(slot_style, 4)
		slot.add_theme_stylebox_override("panel", slot_style)

		# Item name label (centred).
		var lbl := Label.new()
		lbl.text = ""
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", COLOR_TEXT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		slot.add_child(lbl)

		# Quantity badge (bottom-right).
		var qty := Label.new()
		qty.text = ""
		qty.add_theme_font_size_override("font_size", 9)
		qty.add_theme_color_override("font_color", COLOR_ACCENT)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty.set_anchors_preset(Control.PRESET_FULL_RECT)
		qty.offset_right = -3.0
		qty.offset_bottom = -2.0
		slot.add_child(qty)

		# Make slot clickable.
		var idx: int = i
		slot.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_slot_clicked(idx)
		)

		_grid_container.add_child(slot)
		_slot_panels.append(slot)
		_slot_labels.append(lbl)
		_slot_qty_labels.append(qty)


## Right column: equipment panel and player stats.
func _build_right_column(parent: HBoxContainer) -> void:
	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 0.35
	right_vbox.add_theme_constant_override("separation", 10)
	parent.add_child(right_vbox)

	# Equipment header.
	var equip_header := Label.new()
	equip_header.text = "장비"
	equip_header.add_theme_font_size_override("font_size", 16)
	equip_header.add_theme_color_override("font_color", COLOR_ACCENT)
	equip_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(equip_header)

	# Equipment slots.
	_equip_weapon_panel = _create_equip_slot("무기", right_vbox)
	_equip_weapon_label = _equip_weapon_panel.get_child(0) as Label

	_equip_armor_panel = _create_equip_slot("방어구", right_vbox)
	_equip_armor_label = _equip_armor_panel.get_child(0) as Label

	_equip_accessory_panel = _create_equip_slot("장신구", right_vbox)
	_equip_accessory_label = _equip_accessory_panel.get_child(0) as Label

	# Spacer.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	right_vbox.add_child(spacer)

	# Player stats summary.
	var stats_header := Label.new()
	stats_header.text = "능력치"
	stats_header.add_theme_font_size_override("font_size", 16)
	stats_header.add_theme_color_override("font_color", COLOR_ACCENT)
	stats_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_vbox.add_child(stats_header)

	_stats_atk_label = Label.new()
	_stats_atk_label.text = "공격력: 10"
	_stats_atk_label.add_theme_font_size_override("font_size", 14)
	_stats_atk_label.add_theme_color_override("font_color", COLOR_TEXT)
	right_vbox.add_child(_stats_atk_label)

	_stats_def_label = Label.new()
	_stats_def_label.text = "방어력: 5"
	_stats_def_label.add_theme_font_size_override("font_size", 14)
	_stats_def_label.add_theme_color_override("font_color", COLOR_TEXT)
	right_vbox.add_child(_stats_def_label)

	_stats_hp_label = Label.new()
	_stats_hp_label.text = "HP: 100 / 100"
	_stats_hp_label.add_theme_font_size_override("font_size", 14)
	_stats_hp_label.add_theme_color_override("font_color", COLOR_TEXT)
	right_vbox.add_child(_stats_hp_label)


## Item detail panel at the bottom.
func _build_detail_panel(parent: VBoxContainer) -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.name = "DetailPanel"
	_detail_panel.custom_minimum_size = Vector2(0, 100)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_DETAIL_BG
	_apply_corner_radius(style, 6)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	_detail_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(_detail_panel)

	var detail_hbox := HBoxContainer.new()
	detail_hbox.add_theme_constant_override("separation", 12)
	_detail_panel.add_child(detail_hbox)

	# Left: item info.
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 4)
	detail_hbox.add_child(info_vbox)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	info_vbox.add_child(name_row)

	_detail_name_label = Label.new()
	_detail_name_label.text = "아이템을 선택하세요"
	_detail_name_label.add_theme_font_size_override("font_size", 16)
	_detail_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	name_row.add_child(_detail_name_label)

	_detail_rarity_label = Label.new()
	_detail_rarity_label.text = ""
	_detail_rarity_label.add_theme_font_size_override("font_size", 12)
	_detail_rarity_label.add_theme_color_override("font_color", RARITY_COLORS["common"])
	name_row.add_child(_detail_rarity_label)

	_detail_stats_label = Label.new()
	_detail_stats_label.text = ""
	_detail_stats_label.add_theme_font_size_override("font_size", 13)
	_detail_stats_label.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62, 1.0))
	info_vbox.add_child(_detail_stats_label)

	_detail_desc_label = RichTextLabel.new()
	_detail_desc_label.bbcode_enabled = true
	_detail_desc_label.scroll_active = false
	_detail_desc_label.fit_content = true
	_detail_desc_label.custom_minimum_size = Vector2(0, 30)
	_detail_desc_label.add_theme_font_size_override("normal_font_size", 12)
	_detail_desc_label.add_theme_color_override("default_color", Color(0.6, 0.58, 0.52, 1.0))
	info_vbox.add_child(_detail_desc_label)

	# Right: action buttons.
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 6)
	btn_vbox.custom_minimum_size = Vector2(100, 0)
	detail_hbox.add_child(btn_vbox)

	_equip_button = _create_detail_button("장착", btn_vbox)
	_equip_button.pressed.connect(_on_equip_pressed)

	_use_button = _create_detail_button("사용", btn_vbox)
	_use_button.pressed.connect(_on_use_pressed)

	_discard_button = _create_detail_button("버리기", btn_vbox)
	_discard_button.pressed.connect(_on_discard_pressed)

	_set_detail_buttons_visible(false)


# ── Public API ───────────────────────────────────────────────────────────────

## Open the inventory screen.
func open_inventory() -> void:
	_refresh_grid()
	_refresh_equipment()
	_refresh_stats()
	_clear_selection()
	visible = true
	_is_open = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


## Close the inventory screen.
func close_inventory() -> void:
	visible = false
	_is_open = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# ── Grid Refresh ─────────────────────────────────────────────────────────────

func _refresh_grid() -> void:
	var inv := _get_autoload("InventorySystem")
	var inv_items: Array = inv.items if inv != null else []

	for i in range(GRID_COLUMNS * GRID_ROWS):
		if i < inv_items.size():
			var item: Dictionary = inv_items[i]
			var item_name: String = item.get("name", "?")
			var rarity: String = item.get("rarity", "common")
			var qty: int = int(item.get("quantity", 1))

			# Truncate long names for the grid cell.
			if item_name.length() > 6:
				item_name = item_name.substr(0, 5) + "…"
			_slot_labels[i].text = item_name
			_slot_labels[i].add_theme_color_override("font_color", RARITY_COLORS.get(rarity, RARITY_COLORS["common"]))

			_slot_qty_labels[i].text = "x%d" % qty if qty > 1 else ""

			# Update border colour by rarity.
			var style := _slot_panels[i].get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			if style != null:
				style.border_color = RARITY_COLORS.get(rarity, Color(0.3, 0.25, 0.35, 0.3))
				style.border_width_top = 2
				style.border_width_bottom = 2
				style.border_width_left = 2
				style.border_width_right = 2
				_slot_panels[i].add_theme_stylebox_override("panel", style)
		else:
			_slot_labels[i].text = ""
			_slot_qty_labels[i].text = ""
			var empty_style := _slot_panels[i].get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			if empty_style != null:
				empty_style.border_color = Color(0.3, 0.25, 0.35, 0.3)
				empty_style.border_width_top = 1
				empty_style.border_width_bottom = 1
				empty_style.border_width_left = 1
				empty_style.border_width_right = 1
				_slot_panels[i].add_theme_stylebox_override("panel", empty_style)


func _refresh_equipment() -> void:
	var inv := _get_autoload("InventorySystem")
	if inv == null:
		return

	var eq: Dictionary = inv.equipped
	_equip_weapon_label.text = "무기: %s" % _get_equip_display(eq.get("weapon", {}))
	_equip_armor_label.text = "방어구: %s" % _get_equip_display(eq.get("armor", {}))
	_equip_accessory_label.text = "장신구: %s" % _get_equip_display(eq.get("accessory", {}))


func _refresh_stats() -> void:
	var inv := _get_autoload("InventorySystem")
	if inv != null:
		_stats_atk_label.text = "공격력: %d" % int(inv.get_total_attack())
		_stats_def_label.text = "방어력: %d" % int(inv.get_total_defense())

	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		var max_hp: float = 100.0  # Placeholder.
		var current_hp: float = max_hp * game_mgr.player_hp_ratio
		_stats_hp_label.text = "HP: %d / %d" % [int(current_hp), int(max_hp)]


# ── Selection / Detail ───────────────────────────────────────────────────────

func _on_slot_clicked(index: int) -> void:
	var inv := _get_autoload("InventorySystem")
	if inv == null:
		return

	if index >= inv.items.size():
		_clear_selection()
		return

	_selected_index = index
	_selected_item = inv.items[index]
	_show_item_detail(_selected_item)
	item_selected.emit(_selected_item)

	# Highlight selected slot.
	for i in range(_slot_panels.size()):
		var style := _slot_panels[i].get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if style != null:
			if i == index:
				style.bg_color = COLOR_SLOT_SELECTED
			else:
				style.bg_color = COLOR_SLOT_BG
			_slot_panels[i].add_theme_stylebox_override("panel", style)


func _show_item_detail(item: Dictionary) -> void:
	var rarity: String = item.get("rarity", "common")
	var rarity_kr: Dictionary = {
		"common": "일반", "uncommon": "고급", "rare": "희귀",
		"epic": "영웅", "legendary": "전설",
	}

	_detail_name_label.text = item.get("name", "?")
	_detail_name_label.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, RARITY_COLORS["common"]))

	_detail_rarity_label.text = "[%s]" % rarity_kr.get(rarity, rarity)
	_detail_rarity_label.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, RARITY_COLORS["common"]))

	# Stats.
	var stats: Dictionary = item.get("stats", {})
	var stat_parts: Array = []
	if stats.has("attack"):
		stat_parts.append("공격 +%d" % int(stats["attack"]))
	if stats.has("defense"):
		stat_parts.append("방어 +%d" % int(stats["defense"]))
	if stats.has("heal"):
		stat_parts.append("회복 +%d" % int(stats["heal"]))
	_detail_stats_label.text = " | ".join(stat_parts) if stat_parts.size() > 0 else ""

	_detail_desc_label.clear()
	_detail_desc_label.append_text(item.get("description", ""))

	# Show appropriate buttons.
	var item_type: String = item.get("type", "")
	var is_equipment: bool = item_type in ["weapon", "sword", "staff", "bow", "armor", "shield", "helmet", "chest", "accessory", "ring", "amulet", "trinket"]
	var is_consumable: bool = item_type in ["potion", "consumable", "scroll"]

	_equip_button.visible = is_equipment
	_equip_button.text = "해제" if item.get("equipped", false) else "장착"
	_use_button.visible = is_consumable
	_discard_button.visible = true
	_set_detail_buttons_visible(true)


func _clear_selection() -> void:
	_selected_index = -1
	_selected_item = {}
	_detail_name_label.text = "아이템을 선택하세요"
	_detail_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_detail_rarity_label.text = ""
	_detail_stats_label.text = ""
	_detail_desc_label.clear()
	_set_detail_buttons_visible(false)


# ── Action Handlers ──────────────────────────────────────────────────────────

func _on_equip_pressed() -> void:
	if _selected_item.is_empty():
		return
	var inv := _get_autoload("InventorySystem")
	if inv == null:
		return

	var item_id: String = _selected_item.get("id", "")
	if _selected_item.get("equipped", false):
		var slot: String = _get_equip_slot_for_type(_selected_item.get("type", ""))
		inv.unequip_slot(slot)
	else:
		inv.equip_item(item_id)

	_refresh_grid()
	_refresh_equipment()
	_refresh_stats()
	if _selected_index >= 0:
		_on_slot_clicked(_selected_index)


func _on_use_pressed() -> void:
	if _selected_item.is_empty():
		return
	var inv := _get_autoload("InventorySystem")
	if inv == null:
		return

	var item_id: String = _selected_item.get("id", "")
	inv.use_item(item_id)
	item_used.emit(item_id)

	_refresh_grid()
	_refresh_stats()
	_clear_selection()


func _on_discard_pressed() -> void:
	if _selected_item.is_empty():
		return
	var inv := _get_autoload("InventorySystem")
	if inv == null:
		return

	var item_id: String = _selected_item.get("id", "")
	inv.remove_item(item_id, _selected_item.get("quantity", 1))

	_refresh_grid()
	_refresh_equipment()
	_refresh_stats()
	_clear_selection()


# ── Toggle ───────────────────────────────────────────────────────────────────

func _toggle() -> void:
	if _is_open:
		close_inventory()
	else:
		open_inventory()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _create_equip_slot(label_text: String, parent: VBoxContainer) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 36)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_SLOT_BG
	style.border_color = Color(0.4, 0.35, 0.5, 0.4)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1
	style.border_width_right = 1
	_apply_corner_radius(style, 4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var lbl := Label.new()
	lbl.text = "%s: 없음" % label_text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(lbl)

	return panel


func _create_detail_button(text: String, parent: VBoxContainer) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(90, 28)
	btn.add_theme_font_size_override("font_size", 13)
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

	parent.add_child(btn)
	return btn


func _get_equip_display(item: Dictionary) -> String:
	if item.is_empty():
		return "없음"
	return item.get("name", "?")


func _get_equip_slot_for_type(item_type: String) -> String:
	match item_type:
		"weapon", "sword", "staff", "bow":
			return "weapon"
		"armor", "shield", "helmet", "chest":
			return "armor"
		"accessory", "ring", "amulet", "trinket":
			return "accessory"
		_:
			return ""


func _set_detail_buttons_visible(vis: bool) -> void:
	_equip_button.visible = vis
	_use_button.visible = vis
	_discard_button.visible = vis


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
