## Inventory management singleton.
##
## Register this script as an autoload named "InventorySystem" in
## Project -> Project Settings -> Autoload.
## Stores player items, handles equipment, and persists to disk.
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

signal item_added(item_data: Dictionary)
signal item_removed(item_data: Dictionary)
signal item_equipped(item_data: Dictionary)
signal item_unequipped(slot: String, item_data: Dictionary)
signal item_used(item_data: Dictionary)
signal inventory_full

# ── Constants ────────────────────────────────────────────────────────────────

const SAVE_PATH: String = "user://inventory.json"
const MAX_SLOTS: int = 30

## Base player stats before equipment bonuses.
const BASE_ATTACK: float = 10.0
const BASE_DEFENSE: float = 5.0

# ── State ────────────────────────────────────────────────────────────────────

## All items the player is carrying.
## Each Dictionary: { id, name, type, rarity, stats, quantity, description, equipped }
var items: Array = []

## Equipment slots mapped to item data.  Keys: "weapon", "armor", "accessory".
var equipped: Dictionary = {
	"weapon": {},
	"armor": {},
	"accessory": {},
}

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	load_inventory()
	call_deferred("_deferred_connect_signals")


# ── Public API ───────────────────────────────────────────────────────────────

## Add an item to the inventory.  Returns true on success.
func add_item(item_data: Dictionary) -> bool:
	# Ensure required fields.
	var id: String = item_data.get("id", item_data.get("name", "item_%d" % randi()))
	item_data["id"] = id
	item_data["name"] = item_data.get("name", "알 수 없는 아이템")
	item_data["type"] = item_data.get("type", "misc")
	item_data["rarity"] = item_data.get("rarity", "common")
	item_data["quantity"] = int(item_data.get("quantity", 1))
	item_data["stats"] = item_data.get("stats", {})
	item_data["description"] = item_data.get("description", "")
	item_data["equipped"] = false

	# If the item is stackable, try to increase quantity of an existing stack.
	if _is_stackable(item_data):
		var existing := get_item(id)
		if not existing.is_empty():
			var idx: int = _get_item_index(id)
			if idx >= 0:
				items[idx]["quantity"] = items[idx]["quantity"] + item_data["quantity"]
				item_added.emit(item_data)
				save_inventory()
				return true

	# Check capacity.
	if get_item_count() >= MAX_SLOTS:
		inventory_full.emit()
		return false

	items.append(item_data)
	item_added.emit(item_data)
	save_inventory()
	return true


## Remove a given quantity of an item.  Returns true if removed.
func remove_item(item_id: String, quantity: int = 1) -> bool:
	var idx: int = _get_item_index(item_id)
	if idx < 0:
		return false

	var item: Dictionary = items[idx]

	# Unequip if currently equipped.
	if item.get("equipped", false):
		var slot: String = _get_equip_slot(item)
		if not slot.is_empty():
			unequip_slot(slot)

	if item["quantity"] <= quantity:
		items.remove_at(idx)
	else:
		items[idx]["quantity"] = item["quantity"] - quantity

	item_removed.emit(item)
	save_inventory()
	return true


## Use a consumable item (potions, scrolls, etc.).
func use_item(item_id: String) -> void:
	var item: Dictionary = get_item(item_id)
	if item.is_empty():
		return

	var item_type: String = item.get("type", "")
	if item_type not in ["potion", "consumable", "scroll"]:
		push_warning("InventorySystem: item '%s' is not consumable." % item_id)
		return

	# Apply effects.
	var stats: Dictionary = item.get("stats", {})
	var event_bus := _get_autoload("EventBus")

	if stats.has("heal"):
		var heal_amount: float = float(stats["heal"])
		# Actually apply the heal to GameManager HP.
		var game_mgr := _get_autoload("GameManager")
		if game_mgr != null:
			var max_hp: float = 100.0 + (game_mgr.player_level - 1) * 15.0
			max_hp += game_mgr.upgrade_hp * 10.0
			var heal_ratio: float = heal_amount / maxf(max_hp, 1.0)
			game_mgr.player_hp_ratio = minf(1.0, game_mgr.player_hp_ratio + heal_ratio)
		if event_bus != null:
			event_bus.player_healed.emit(heal_amount)

	if stats.has("attack_buff"):
		# Temporary buffs could be handled by a buff system; for now, log it.
		print("InventorySystem: attack buff +%s applied (placeholder)." % str(stats["attack_buff"]))

	# Emit item_used via EventBus for tracker integration.
	if event_bus != null:
		event_bus.item_used.emit(item)

	item_used.emit(item)
	remove_item(item_id, 1)


## Equip a weapon, armor, or accessory from inventory.
func equip_item(item_id: String) -> void:
	var item: Dictionary = get_item(item_id)
	if item.is_empty():
		return

	var slot: String = _get_equip_slot(item)
	if slot.is_empty():
		push_warning("InventorySystem: item '%s' cannot be equipped (type: %s)." % [item_id, item.get("type", "")])
		return

	# Unequip current item in that slot first.
	if not equipped[slot].is_empty():
		unequip_slot(slot)

	# Mark as equipped.
	var idx: int = _get_item_index(item_id)
	if idx >= 0:
		items[idx]["equipped"] = true

	equipped[slot] = item.duplicate()
	item_equipped.emit(item)
	save_inventory()


## Remove the item from the given equipment slot.
func unequip_slot(slot: String) -> void:
	if not equipped.has(slot) or equipped[slot].is_empty():
		return

	var old_item: Dictionary = equipped[slot]
	var old_id: String = old_item.get("id", "")

	# Mark the inventory entry as unequipped.
	var idx: int = _get_item_index(old_id)
	if idx >= 0:
		items[idx]["equipped"] = false

	item_unequipped.emit(slot, old_item)
	equipped[slot] = {}
	save_inventory()


## Return the item dictionary for the given id, or an empty Dictionary.
func get_item(item_id: String) -> Dictionary:
	for item in items:
		if item.get("id", "") == item_id:
			return item
	return {}


## Return all items matching the given type string.
func get_items_by_type(type: String) -> Array:
	var result: Array = []
	for item in items:
		if item.get("type", "") == type:
			result.append(item)
	return result


## Total attack including base + equipment bonuses.
func get_total_attack() -> float:
	var total: float = BASE_ATTACK
	for slot in equipped:
		var item: Dictionary = equipped[slot]
		if item.is_empty():
			continue
		var stats: Dictionary = item.get("stats", {})
		total += float(stats.get("attack", 0.0))
	return total


## Total defense including base + equipment bonuses.
func get_total_defense() -> float:
	var total: float = BASE_DEFENSE
	for slot in equipped:
		var item: Dictionary = equipped[slot]
		if item.is_empty():
			continue
		var stats: Dictionary = item.get("stats", {})
		total += float(stats.get("defense", 0.0))
	return total


## Check whether the player has at least one of the given item.
func has_item(item_id: String) -> bool:
	return not get_item(item_id).is_empty()


## Return the total number of unique item stacks (occupied slots).
func get_item_count() -> int:
	return items.size()


## Sort inventory items by rarity tier (legendary first).
func sort_by_rarity() -> void:
	var rarity_order: Dictionary = {
		"legendary": 0,
		"epic": 1,
		"rare": 2,
		"uncommon": 3,
		"common": 4,
	}
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra: int = rarity_order.get(a.get("rarity", "common"), 5)
		var rb: int = rarity_order.get(b.get("rarity", "common"), 5)
		return ra < rb
	)


# ── Persistence ──────────────────────────────────────────────────────────────

## Save the current inventory and equipment to disk.
func save_inventory() -> void:
	var data: Dictionary = {
		"items": items,
		"equipped": equipped,
	}
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("InventorySystem: could not open %s for writing (error %d)." % [
			SAVE_PATH, FileAccess.get_open_error()
		])
		return
	file.store_string(json_string)
	file.close()


## Load inventory and equipment from disk.
func load_inventory() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("InventorySystem: could not open %s for reading." % SAVE_PATH)
		return

	var json_string: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_warning("InventorySystem: corrupt save file – %s" % json.get_error_message())
		return

	if json.data is not Dictionary:
		push_warning("InventorySystem: unexpected save format.")
		return

	var data: Dictionary = json.data
	items = data.get("items", []) as Array
	var loaded_equipped: Variant = data.get("equipped", {})
	if loaded_equipped is Dictionary:
		for slot in ["weapon", "armor", "accessory"]:
			equipped[slot] = loaded_equipped.get(slot, {})


# ── EventBus Integration ────────────────────────────────────────────────────

func _deferred_connect_signals() -> void:
	var event_bus := _get_autoload("EventBus")
	if event_bus == null:
		push_warning("InventorySystem: EventBus not available.")
		return

	if event_bus.has_signal("item_picked_up"):
		event_bus.item_picked_up.connect(_on_item_picked_up)


func _on_item_picked_up(item_data: Dictionary) -> void:
	add_item(item_data)
	_try_auto_equip(item_data)


# ── Private Helpers ──────────────────────────────────────────────────────────

## Return the inventory array index for the given item id, or -1.
func _get_item_index(item_id: String) -> int:
	for i in range(items.size()):
		if items[i].get("id", "") == item_id:
			return i
	return -1


## Determine which equipment slot an item belongs to.
func _get_equip_slot(item: Dictionary) -> String:
	var item_type: String = item.get("type", "")
	match item_type:
		"weapon", "sword", "staff", "bow":
			return "weapon"
		"armor", "shield", "helmet", "chest":
			return "armor"
		"accessory", "ring", "amulet", "trinket":
			return "accessory"
		_:
			return ""


## Auto-equip a picked-up item if the slot is empty or the new item is stronger.
func _try_auto_equip(item_data: Dictionary) -> void:
	var slot: String = _get_equip_slot(item_data)
	if slot.is_empty():
		return
	var item_id: String = item_data.get("id", item_data.get("name", ""))
	if item_id.is_empty():
		return

	var current: Dictionary = equipped.get(slot, {})
	if current.is_empty():
		# Slot is empty — equip immediately.
		equip_item(item_id)
		return

	# Compare main stat (attack for weapons, defense for armor/accessories).
	var new_stats: Dictionary = item_data.get("stats", {})
	var old_stats: Dictionary = current.get("stats", {})
	var compare_key: String = "attack" if slot == "weapon" else "defense"
	var new_val: float = float(new_stats.get(compare_key, 0.0))
	var old_val: float = float(old_stats.get(compare_key, 0.0))
	if new_val > old_val:
		equip_item(item_id)


## Consumables and materials are stackable; equipment is not.
func _is_stackable(item: Dictionary) -> bool:
	var item_type: String = item.get("type", "")
	return item_type in ["potion", "consumable", "scroll", "material", "misc"]


## Safely retrieve an autoload node by name.
func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
