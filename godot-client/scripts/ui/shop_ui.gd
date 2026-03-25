## NPC shop interface overlay.
##
## Builds its entire UI tree programmatically so it has no .tscn dependency.
## Two-panel layout: shop items (left) and player inventory (right).
## Supports NPC affinity discounts and AI-generated item variety.
class_name ShopUI
extends CanvasLayer

# ── Signals ──────────────────────────────────────────────────────────────────

signal item_bought(item_data: Dictionary)
signal item_sold(item_data: Dictionary)
signal shop_closed

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color("#140f1a")
const COLOR_PANEL_BG := Color(0.08, 0.06, 0.1, 0.95)
const COLOR_PANEL_BORDER := Color(0.72, 0.58, 0.2, 1.0)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_GOLD := Color("#FFD700")
const COLOR_OVERLAY := Color(0.0, 0.0, 0.0, 0.7)
const COLOR_ITEM_BG := Color(0.1, 0.08, 0.12, 0.8)
const COLOR_ITEM_HOVER := Color(0.18, 0.14, 0.22, 1.0)
const COLOR_ITEM_SELECTED := Color(0.25, 0.20, 0.30, 1.0)
const COLOR_DETAIL_BG := Color(0.06, 0.04, 0.08, 1.0)
const COLOR_BUTTON := Color(0.18, 0.14, 0.22, 1.0)
const COLOR_BUTTON_HOVER := Color(0.28, 0.22, 0.34, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.12, 0.1, 0.16, 1.0)
const COLOR_DISCOUNT := Color(0.3, 0.85, 0.4, 1.0)

const RARITY_COLORS: Dictionary = {
	"common": Color("#c8c8c8"),
	"uncommon": Color("#4fc34f"),
	"rare": Color("#4f8fc3"),
	"epic": Color("#a64fc3"),
	"legendary": Color("#ebca42"),
}

# ── UI Node References ──────────────────────────────────────────────────────

var _overlay: ColorRect
var _main_panel: PanelContainer
var _gold_label: Label
var _discount_label: Label
var _shop_list: VBoxContainer
var _player_list: VBoxContainer
var _detail_name_label: Label
var _detail_stats_label: Label
var _detail_price_label: Label
var _buy_button: Button
var _sell_button: Button

# ── State ────────────────────────────────────────────────────────────────────

var _is_open: bool = false
var _current_npc_id: String = ""
var _shop_items: Array = []
var _selected_shop_item: Dictionary = {}
var _selected_player_item: Dictionary = {}
var _selecting_from_shop: bool = true

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen overlay.
	_overlay = ColorRect.new()
	_overlay.name = "ShopOverlay"
	_overlay.color = COLOR_OVERLAY
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Main panel.
	_main_panel = PanelContainer.new()
	_main_panel.name = "ShopPanel"
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

	# Title row: shop name + gold + close.
	var title_bar := HBoxContainer.new()
	title_bar.add_theme_constant_override("separation", 16)
	vbox.add_child(title_bar)

	var title := Label.new()
	title.text = "상점"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	title_bar.add_child(title)

	_gold_label = Label.new()
	_gold_label.text = "골드: 0"
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.add_theme_color_override("font_color", COLOR_GOLD)
	title_bar.add_child(_gold_label)

	_discount_label = Label.new()
	_discount_label.text = ""
	_discount_label.add_theme_font_size_override("font_size", 13)
	_discount_label.add_theme_color_override("font_color", COLOR_DISCOUNT)
	title_bar.add_child(_discount_label)

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
	close_btn.pressed.connect(func() -> void: close_shop())
	title_bar.add_child(close_btn)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)

	# Content: shop items (left) | player inventory (right).
	var content_hbox := HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 12)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content_hbox)

	_build_shop_panel(content_hbox)
	_build_player_panel(content_hbox)

	# Bottom: detail + buy/sell buttons.
	_build_detail_bar(vbox)


func _build_shop_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "ShopItemsPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.5

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_DETAIL_BG
	_apply_corner_radius(style, 6)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "판매 상품"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_shop_list = VBoxContainer.new()
	_shop_list.name = "ShopList"
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_shop_list)


func _build_player_panel(parent: HBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.name = "PlayerItemsPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.5

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_DETAIL_BG
	_apply_corner_radius(style, 6)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "내 인벤토리"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", COLOR_ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_player_list = VBoxContainer.new()
	_player_list.name = "PlayerList"
	_player_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_player_list)


func _build_detail_bar(parent: VBoxContainer) -> void:
	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(0, 60)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_DETAIL_BG
	_apply_corner_radius(style, 6)
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	detail_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(detail_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	detail_panel.add_child(hbox)

	# Item info.
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(info_vbox)

	_detail_name_label = Label.new()
	_detail_name_label.text = "상품을 선택하세요"
	_detail_name_label.add_theme_font_size_override("font_size", 15)
	_detail_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	info_vbox.add_child(_detail_name_label)

	_detail_stats_label = Label.new()
	_detail_stats_label.text = ""
	_detail_stats_label.add_theme_font_size_override("font_size", 12)
	_detail_stats_label.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62, 1.0))
	info_vbox.add_child(_detail_stats_label)

	_detail_price_label = Label.new()
	_detail_price_label.text = ""
	_detail_price_label.add_theme_font_size_override("font_size", 14)
	_detail_price_label.add_theme_color_override("font_color", COLOR_GOLD)
	info_vbox.add_child(_detail_price_label)

	# Buttons.
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 8)
	hbox.add_child(btn_hbox)

	_buy_button = _create_action_button("구매", btn_hbox)
	_buy_button.pressed.connect(_on_buy_pressed)
	_buy_button.visible = false

	_sell_button = _create_action_button("판매", btn_hbox)
	_sell_button.pressed.connect(_on_sell_pressed)
	_sell_button.visible = false


# ── Public API ───────────────────────────────────────────────────────────────

## Open the shop with items from the given NPC.
func open_shop(npc_id: String, items: Array) -> void:
	_current_npc_id = npc_id
	_shop_items = items.duplicate(true)
	_selected_shop_item = {}
	_selected_player_item = {}
	_selecting_from_shop = true

	_refresh_gold()
	_refresh_discount()
	_populate_shop_list()
	_populate_player_list()
	_clear_detail()

	# Play shop BGM.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_bgm"):
		sound_mgr.play_bgm("shop_bgm")

	visible = true
	_is_open = true


## Close the shop and return to gameplay.
func close_shop() -> void:
	visible = false
	_is_open = false
	_current_npc_id = ""
	_shop_items.clear()
	shop_closed.emit()

	# Restore dungeon BGM.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_bgm"):
		sound_mgr.play_bgm("dungeon_bgm")


# ── Shop Item List ──────────────────────────────────────────────────────────

func _populate_shop_list() -> void:
	_clear_children(_shop_list)
	for i in range(_shop_items.size()):
		var item: Dictionary = _shop_items[i]
		var price: int = _calculate_price(int(item.get("price", 100)), _current_npc_id)
		_add_item_row(_shop_list, item, price, true, i)


func _populate_player_list() -> void:
	_clear_children(_player_list)
	var inv := _get_autoload("InventorySystem")
	if inv == null:
		return

	for i in range(inv.items.size()):
		var item: Dictionary = inv.items[i]
		var sell_price: int = _get_sell_price(item)
		_add_item_row(_player_list, item, sell_price, false, i)


func _add_item_row(parent: VBoxContainer, item: Dictionary, price: int, is_shop: bool, index: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 40)

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ITEM_BG
	style.border_color = RARITY_COLORS.get(item.get("rarity", "common"), RARITY_COLORS["common"])
	style.border_width_left = 3
	style.border_width_top = 0
	style.border_width_bottom = 0
	style.border_width_right = 0
	_apply_corner_radius(style, 4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	var name_label := Label.new()
	name_label.text = item.get("name", "?")
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", RARITY_COLORS.get(item.get("rarity", "common"), COLOR_TEXT))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_label)

	# Stats preview.
	var stats: Dictionary = item.get("stats", {})
	var stats_text: String = ""
	if stats.has("attack"):
		stats_text += "ATK+%d " % int(stats["attack"])
	if stats.has("defense"):
		stats_text += "DEF+%d " % int(stats["defense"])
	if stats.has("heal"):
		stats_text += "HP+%d " % int(stats["heal"])

	if not stats_text.is_empty():
		var stats_lbl := Label.new()
		stats_lbl.text = stats_text.strip_edges()
		stats_lbl.add_theme_font_size_override("font_size", 11)
		stats_lbl.add_theme_color_override("font_color", Color(0.6, 0.58, 0.52, 1.0))
		hbox.add_child(stats_lbl)

	var price_label := Label.new()
	price_label.text = "%d 골드" % price
	price_label.add_theme_font_size_override("font_size", 13)
	price_label.add_theme_color_override("font_color", COLOR_GOLD)
	hbox.add_child(price_label)

	# Click handler.
	panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if is_shop:
				_on_shop_item_selected(index)
			else:
				_on_player_item_selected(index)
	)

	parent.add_child(panel)


# ── Selection ────────────────────────────────────────────────────────────────

func _on_shop_item_selected(index: int) -> void:
	if index >= _shop_items.size():
		return
	_selected_shop_item = _shop_items[index]
	_selected_player_item = {}
	_selecting_from_shop = true
	_show_detail(_selected_shop_item, true)


func _on_player_item_selected(index: int) -> void:
	var inv := _get_autoload("InventorySystem")
	if inv == null or index >= inv.items.size():
		return
	_selected_player_item = inv.items[index]
	_selected_shop_item = {}
	_selecting_from_shop = false
	_show_detail(_selected_player_item, false)


func _show_detail(item: Dictionary, is_shop_item: bool) -> void:
	var rarity: String = item.get("rarity", "common")
	_detail_name_label.text = item.get("name", "?")
	_detail_name_label.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, COLOR_TEXT))

	var stats: Dictionary = item.get("stats", {})
	var parts: Array = []
	if stats.has("attack"):
		parts.append("공격 +%d" % int(stats["attack"]))
	if stats.has("defense"):
		parts.append("방어 +%d" % int(stats["defense"]))
	if stats.has("heal"):
		parts.append("회복 +%d" % int(stats["heal"]))
	_detail_stats_label.text = " | ".join(parts) if parts.size() > 0 else ""

	if is_shop_item:
		var price: int = _calculate_price(int(item.get("price", 100)), _current_npc_id)
		_detail_price_label.text = "구매가: %d 골드" % price
		_buy_button.visible = true
		_sell_button.visible = false
	else:
		var sell_price: int = _get_sell_price(item)
		_detail_price_label.text = "판매가: %d 골드" % sell_price
		_buy_button.visible = false
		_sell_button.visible = true


func _clear_detail() -> void:
	_detail_name_label.text = "상품을 선택하세요"
	_detail_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_detail_stats_label.text = ""
	_detail_price_label.text = ""
	_buy_button.visible = false
	_sell_button.visible = false


# ── Buy / Sell ───────────────────────────────────────────────────────────────

func _on_buy_pressed() -> void:
	_on_buy(_selected_shop_item)


func _on_sell_pressed() -> void:
	_on_sell(_selected_player_item)


func _on_buy(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return

	var inv := _get_autoload("InventorySystem")
	var game_mgr := _get_autoload("GameManager")
	if inv == null or game_mgr == null:
		return

	var price: int = _calculate_price(int(item_data.get("price", 100)), _current_npc_id)

	# Check gold.
	if game_mgr.player_gold < price:
		print("ShopUI: 골드가 부족합니다.")
		return

	# Check inventory space.
	if inv.get_item_count() >= inv.MAX_SLOTS:
		print("ShopUI: 인벤토리가 가득 찼습니다.")
		return

	# Deduct gold.
	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.gold_changed.emit(game_mgr.player_gold - price, -price)

	# Add item to inventory.
	var item_copy: Dictionary = item_data.duplicate(true)
	item_copy.erase("price")
	inv.add_item(item_copy)

	# Play SFX.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_sfx"):
		sound_mgr.play_sfx("gold_pickup")

	item_bought.emit(item_data)
	_refresh_gold()
	_populate_player_list()
	_clear_detail()


func _on_sell(item_data: Dictionary) -> void:
	if item_data.is_empty():
		return

	var inv := _get_autoload("InventorySystem")
	var game_mgr := _get_autoload("GameManager")
	if inv == null or game_mgr == null:
		return

	var sell_price: int = _get_sell_price(item_data)
	var item_id: String = item_data.get("id", "")

	# Remove from inventory.
	if not inv.remove_item(item_id, 1):
		return

	# Add gold.
	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.gold_changed.emit(game_mgr.player_gold + sell_price, sell_price)

	# Play SFX.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_sfx"):
		sound_mgr.play_sfx("gold_pickup")

	item_sold.emit(item_data)
	_refresh_gold()
	_populate_player_list()
	_clear_detail()


# ── Price Calculation ────────────────────────────────────────────────────────

## Calculate the buy price with NPC affinity discount.
func _calculate_price(base_price: int, npc_id: String) -> int:
	var discount: float = _get_affinity_discount(npc_id)
	return maxi(1, int(float(base_price) * (1.0 - discount)))


## Sell price is 50% of the base price.
func _get_sell_price(item: Dictionary) -> int:
	var base: int = int(item.get("price", item.get("value", 50)))
	return maxi(1, base / 2)


## Determine discount rate based on NPC affinity (0.0 – 0.2 max).
func _get_affinity_discount(npc_id: String) -> float:
	var npc_mgr := _get_autoload("NPCManager")
	if npc_mgr == null:
		return 0.0

	if not npc_mgr.has_method("get_npc"):
		return 0.0

	var npc: Node = npc_mgr.get_npc(npc_id)
	if npc == null:
		return 0.0

	var affinity: int = npc.get("affinity") if "affinity" in npc else 0
	# Every 25 affinity points = 5% discount, up to 20%.
	var discount: float = clampf(float(affinity) / 25.0 * 0.05, 0.0, 0.2)
	return discount


# ── Refresh ──────────────────────────────────────────────────────────────────

func _refresh_gold() -> void:
	var game_mgr := _get_autoload("GameManager")
	var gold: int = game_mgr.player_gold if game_mgr != null else 0
	_gold_label.text = "골드: %d" % gold


func _refresh_discount() -> void:
	var discount: float = _get_affinity_discount(_current_npc_id)
	if discount > 0.0:
		_discount_label.text = "할인: %d%%" % int(discount * 100.0)
	else:
		_discount_label.text = ""


# ── Helpers ──────────────────────────────────────────────────────────────────

func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()


func _create_action_button(text: String, parent: Node) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 36)
	btn.add_theme_font_size_override("font_size", 15)
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
