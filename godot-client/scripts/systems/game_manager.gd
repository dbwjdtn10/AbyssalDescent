## Main game manager that orchestrates all major systems.
##
## Register this script as an autoload named "GameManager" in
## Project -> Project Settings -> Autoload.
## Ties together AIDungeonBuilder, NPCManager, QuestManager,
## PlayerTracker, and DifficultyManager via EventBus signals.
extends Node

# ── State ────────────────────────────────────────────────────────────────────

## Current dungeon floor (1-based).
var current_floor: int = 1

## Player character level.
var player_level: int = 1

## Gold currency.
var player_gold: int = 0

## Ratio of current HP to max HP (0.0 – 1.0).
var player_hp_ratio: float = 1.0

## List of item identifiers the player is carrying.
var player_inventory: Array[String] = []

## True while a dungeon run is in progress.
var is_game_active: bool = false

## Current experience points.
var player_xp: int = 0

## XP required for the next level.
var player_xp_to_next: int = 50

# ── Permanent Upgrades (persist across runs) ────────────────────────────────

## Bonus attack from gold upgrades.
var upgrade_atk: int = 0
## Bonus defense from gold upgrades.
var upgrade_def: int = 0
## Bonus max HP from gold upgrades.
var upgrade_hp: int = 0
## Total gold earned across all runs (only this gold is spendable on upgrades).
var permanent_gold: int = 0

## Cost to upgrade each stat (increases per level purchased).
const UPGRADE_BASE_COST: int = 30
const UPGRADE_COST_SCALE: float = 1.4

func get_upgrade_cost(stat_name: String) -> int:
	var level: int = 0
	match stat_name:
		"atk": level = upgrade_atk
		"def": level = upgrade_def
		"hp": level = upgrade_hp
	return int(UPGRADE_BASE_COST * pow(UPGRADE_COST_SCALE, float(level)))

func buy_upgrade(stat_name: String) -> bool:
	var cost: int = get_upgrade_cost(stat_name)
	if permanent_gold < cost:
		return false
	permanent_gold -= cost
	match stat_name:
		"atk": upgrade_atk += 1
		"def": upgrade_def += 1
		"hp": upgrade_hp += 1
	save_permanent()
	return true

# ── Constants ────────────────────────────────────────────────────────────────

const SAVE_PATH: String = "user://game_save.json"
const PERM_SAVE_PATH: String = "user://permanent_upgrades.json"

## HP recovered when entering a rest room (ratio of max HP).
const REST_HEAL_RATIO: float = 0.30

## HP recovered after winning combat (ratio of max HP).
const COMBAT_VICTORY_HEAL_RATIO: float = 0.08

## Base XP required per level — each level needs base * level.
const XP_PER_LEVEL_BASE: int = 70

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	load_permanent()
	call_deferred("_deferred_connect_signals")


# ── Public API ───────────────────────────────────────────────────────────────

## Initialize all systems and begin a fresh run.
func start_new_game() -> void:
	current_floor = 1
	player_level = 1
	player_gold = 0
	player_hp_ratio = 1.0
	player_xp = 0
	player_xp_to_next = XP_PER_LEVEL_BASE
	player_inventory.clear()
	is_game_active = true

	# Reset inventory for a fresh run.
	var inv := _get_autoload("InventorySystem")
	if inv != null:
		inv.items.clear()
		inv.equipped = {"weapon": {}, "armor": {}, "accessory": {}}
		inv.save_inventory()

	# Reset quest state for a fresh run.
	var quest_mgr := _get_autoload("QuestManager")
	if quest_mgr != null:
		quest_mgr.active_quests.clear()
		quest_mgr.completed_quests.clear()
		quest_mgr.failed_quests.clear()
		quest_mgr.save_quests()

	# Start at easy difficulty for a smoother early game.
	var diff_mgr := _get_autoload("DifficultyManager")
	if diff_mgr != null and diff_mgr.has_method("set_difficulty"):
		diff_mgr.set_difficulty("easy")

	start_floor(current_floor)


## Request dungeon generation and set up the given floor.
func start_floor(floor_number: int) -> void:
	current_floor = floor_number

	# Heal on new floor — scaled by difficulty healing_availability.
	var heal_ratio: float = 1.0
	var diff_mgr := _get_autoload("DifficultyManager")
	if diff_mgr != null and diff_mgr.has_method("get_current_params"):
		var diff_params: Dictionary = diff_mgr.get_current_params()
		heal_ratio = float(diff_params.get("healing_availability", 1.0))
	player_hp_ratio = minf(1.0, player_hp_ratio + heal_ratio)

	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.floor_started.emit(floor_number)

	# Tell PlayerTracker to begin floor tracking.
	var tracker := _get_autoload("PlayerTracker")
	# Room count is unknown until the dungeon is generated; use a
	# placeholder of 0 and update later if needed.
	if tracker != null and tracker.has_method("start_floor"):
		tracker.start_floor(floor_number, 0)

	# Request dungeon data from the AI server via AIDungeonBuilder.
	var builder := _find_dungeon_builder()
	if builder != null and builder.has_method("request_and_build_floor"):
		var diff: float = _get_difficulty_value()
		builder.request_and_build_floor(
			floor_number,
			diff,
			player_level,
			player_inventory as Array,
			[],  # visited room types — TODO: track across floors
			randi()
		)
	else:
		push_warning("GameManager: AIDungeonBuilder not found – cannot generate floor.")

	# NPCs will be spawned once the dungeon data arrives (see
	# _on_floor_built).


## Called when the player has cleared the current floor.
func complete_floor() -> void:
	if not is_game_active:
		return

	# Finalize PlayerTracker stats for the floor.
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null and tracker.has_method("finish_floor"):
		tracker.finish_floor()

	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.floor_cleared.emit(current_floor)

	# Check difficulty adjustment.
	var diff_mgr := _get_autoload("DifficultyManager")
	if diff_mgr != null and diff_mgr.has_method("should_check_difficulty"):
		if diff_mgr.should_check_difficulty(current_floor):
			diff_mgr.request_adjustment()

	# Advance to the next floor.
	current_floor += 1
	save_game()
	start_floor(current_floor)


## Grant XP and handle level-ups.  Returns the number of levels gained.
func grant_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	player_xp += amount
	var levels_gained: int = 0
	while player_xp >= player_xp_to_next:
		player_xp -= player_xp_to_next
		player_level += 1
		levels_gained += 1
		player_xp_to_next = XP_PER_LEVEL_BASE * player_level

	if levels_gained > 0:
		# Heal on level-up only if NOT in active combat
		# (during combat, end_combat() syncs HP and applies heals after).
		if not _is_in_combat():
			player_hp_ratio = minf(1.0, player_hp_ratio + 0.5)
		save_game()

	return levels_gained


## Heal the player by a ratio of max HP (0.0–1.0).
func heal_player(ratio: float) -> void:
	player_hp_ratio = minf(1.0, player_hp_ratio + ratio)
	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.player_healed.emit(ratio * 100.0)


## Handle player death.
func on_player_death() -> void:
	# Liquidate inventory items into gold (sell value = 50% of base price).
	var item_gold: int = 0
	var inv := _get_autoload("InventorySystem")
	if inv != null:
		for item: Variant in inv.items:
			if item is Dictionary:
				var d: Dictionary = item as Dictionary
				var base_price: int = int(d.get("price", d.get("value", 0)))
				if base_price <= 0:
					var stats: Dictionary = d.get("stats", {})
					base_price = int(stats.get("attack", 0)) * 8 + int(stats.get("defense", 0)) * 8 + int(stats.get("heal", 0)) * 2
				item_gold += maxi(1, base_price / 2)

	# All run gold + item gold → permanent gold (100% retained).
	var total_run_gold: int = player_gold + item_gold
	if total_run_gold > 0:
		permanent_gold += total_run_gold
		save_permanent()

	is_game_active = false

	# Delete run save to prevent gold duplication via "continue".
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	var tracker := _get_autoload("PlayerTracker")
	if tracker != null and tracker.has_method("record_death"):
		tracker.record_death()

	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.player_died.emit()


## Build a comprehensive game state snapshot for AI server communication.
func get_game_state() -> Dictionary:
	var state: Dictionary = {
		"current_floor": current_floor,
		"player_level": player_level,
		"player_gold": player_gold,
		"player_hp_ratio": player_hp_ratio,
		"player_inventory": player_inventory,
		"is_game_active": is_game_active,
	}

	# Append difficulty info.
	var diff_mgr := _get_autoload("DifficultyManager")
	if diff_mgr != null:
		state["difficulty"] = diff_mgr.get("current_difficulty") if "current_difficulty" in diff_mgr else "normal"
		if diff_mgr.has_method("get_current_params"):
			state["difficulty_params"] = diff_mgr.get_current_params()

	# Append player history.
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null and tracker.has_method("get_adapt_request_data"):
		state["player_history"] = tracker.get_adapt_request_data()

	# Append quest info.
	var quest_mgr := _get_autoload("QuestManager")
	if quest_mgr != null:
		state["active_quest_count"] = quest_mgr.active_quests.size()
		state["completed_quest_count"] = quest_mgr.completed_quests.size()

	return state


# ── Persistence ──────────────────────────────────────────────────────────────

## Save core game state to disk.
func save_game() -> void:
	var data: Dictionary = {
		"current_floor": current_floor,
		"player_level": player_level,
		"player_gold": player_gold,
		"player_hp_ratio": player_hp_ratio,
		"player_xp": player_xp,
		"player_xp_to_next": player_xp_to_next,
		"player_inventory": player_inventory,
		"is_game_active": is_game_active,
	}
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameManager: could not open %s for writing (error %d)" % [
			SAVE_PATH, FileAccess.get_open_error()
		])
		return
	file.store_string(json_string)
	file.close()


## Load core game state from disk.
func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("GameManager: could not open %s for reading." % SAVE_PATH)
		return

	var json_string: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_warning("GameManager: corrupt save file – %s" % json.get_error_message())
		return

	if json.data is not Dictionary:
		push_warning("GameManager: unexpected save format.")
		return

	var data: Dictionary = json.data
	current_floor = int(data.get("current_floor", 1))
	player_level = int(data.get("player_level", 1))
	player_gold = int(data.get("player_gold", 0))
	player_hp_ratio = float(data.get("player_hp_ratio", 1.0))
	is_game_active = bool(data.get("is_game_active", false))
	player_xp = int(data.get("player_xp", 0))
	player_xp_to_next = int(data.get("player_xp_to_next", XP_PER_LEVEL_BASE * player_level))

	player_inventory = _parse_string_array(data.get("player_inventory", []))


## Save permanent upgrade data to a separate file.
func save_permanent() -> void:
	var data: Dictionary = {
		"upgrade_atk": upgrade_atk,
		"upgrade_def": upgrade_def,
		"upgrade_hp": upgrade_hp,
		"permanent_gold": permanent_gold,
	}
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(PERM_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameManager: could not save permanent upgrades.")
		return
	file.store_string(json_string)
	file.close()


## Load permanent upgrade data from disk.
func load_permanent() -> void:
	if not FileAccess.file_exists(PERM_SAVE_PATH):
		return
	var file := FileAccess.open(PERM_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json_string: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_string) != OK:
		return
	if json.data is not Dictionary:
		return
	var data: Dictionary = json.data
	upgrade_atk = int(data.get("upgrade_atk", 0))
	upgrade_def = int(data.get("upgrade_def", 0))
	upgrade_hp = int(data.get("upgrade_hp", 0))
	permanent_gold = int(data.get("permanent_gold", 0))


# ── EventBus Routing ─────────────────────────────────────────────────────────

func _deferred_connect_signals() -> void:
	var event_bus := _get_autoload("EventBus")
	if event_bus == null:
		push_warning("GameManager: EventBus not available.")
		return

	event_bus.player_damaged.connect(_on_player_damaged)
	event_bus.player_healed.connect(_on_player_healed)
	event_bus.player_died.connect(_on_player_died_signal)
	event_bus.gold_changed.connect(_on_gold_changed)
	event_bus.item_picked_up.connect(_on_item_picked_up)
	event_bus.item_used.connect(_on_item_used)
	event_bus.room_entered.connect(_on_room_entered)
	event_bus.monster_killed.connect(_on_monster_killed)

	# Connect to AIDungeonBuilder floor_built signal if available.
	var builder := _find_dungeon_builder()
	if builder != null and builder.has_signal("floor_built"):
		builder.floor_built.connect(_on_floor_built)


func _on_player_damaged(amount: float) -> void:
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null and tracker.has_method("record_damage"):
		tracker.record_damage(amount)


func _on_player_healed(amount: float) -> void:
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null and tracker.has_method("record_healing"):
		tracker.record_healing(amount)


func _on_player_died_signal() -> void:
	# The actual death handling is done in on_player_death(); this just
	# ensures deaths emitted via EventBus are also recorded.
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null and tracker.has_method("record_death"):
		tracker.record_death()


func _on_gold_changed(new_amount: int, change: int) -> void:
	if new_amount >= 0:
		player_gold = new_amount
	else:
		# If new_amount is -1 the caller doesn't know the total; apply delta.
		player_gold = maxi(0, player_gold + change)


func _on_item_picked_up(item_data: Dictionary) -> void:
	var item_id: String = item_data.get("id", item_data.get("name", ""))
	if not item_id.is_empty() and not player_inventory.has(item_id):
		player_inventory.append(item_id)


func _on_item_used(item_data: Dictionary) -> void:
	var item_id: String = item_data.get("id", item_data.get("name", ""))
	var idx: int = player_inventory.find(item_id)
	if idx >= 0:
		player_inventory.remove_at(idx)


func _on_room_entered(room_data: Dictionary) -> void:
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null and tracker.has_method("record_room_explored"):
		tracker.record_room_explored()

	# Heal the player when entering a rest room.
	var room_type: String = room_data.get("type", "")
	if room_type == "rest":
		heal_player(REST_HEAL_RATIO)


func _on_monster_killed(monster_data: Dictionary) -> void:
	# Grant XP based on monster level.
	var monster_level: int = int(monster_data.get("level", 1))
	var rank: String = str(monster_data.get("rank", monster_data.get("type", "normal")))
	var base_xp: int = 12 * monster_level
	if rank == "elite":
		base_xp = int(base_xp * 2.5)
	elif rank == "boss":
		base_xp = base_xp * 5
	elif rank == "mini_boss":
		base_xp = base_xp * 3

	var levels_gained: int = grant_xp(base_xp)

	# Update HUD.
	var event_bus := _get_autoload("EventBus")
	if event_bus != null and levels_gained > 0:
		event_bus.player_leveled_up.emit(player_level)

	# NOTE: Per-kill heal is applied in CombatSystem.end_combat() AFTER
	# syncing player_hp_ratio, to avoid being overwritten.


func _on_floor_built(floor_data: Dictionary) -> void:
	# Spawn NPCs for the newly built floor.
	var npc_mgr := _find_node("NPCManager")
	if npc_mgr != null and npc_mgr.has_method("spawn_npcs_for_floor"):
		npc_mgr.clear_all_npcs()
		npc_mgr.spawn_npcs_for_floor(floor_data)

	# Update PlayerTracker with the actual room count.
	var rooms: Array = floor_data.get("rooms", [])
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null:
		tracker.total_rooms = rooms.size()

	# Spawn or reposition the player at the entrance.
	_spawn_player_at_entrance()


## Spawn the player character at the dungeon entrance.
func _spawn_player_at_entrance() -> void:
	var builder: Node = _find_dungeon_builder()
	if builder == null:
		return

	var entrance_pos: Vector3 = Vector3.ZERO
	if builder.has_method("get_entrance_position"):
		entrance_pos = builder.get_entrance_position()

	# Check if player already exists in the scene tree.
	var existing_player: Node = get_tree().root.find_child("Player", true, false)
	if existing_player != null and existing_player is CharacterBody3D:
		existing_player.global_position = entrance_pos + Vector3(0, 1, 0)
		return

	# Instantiate the player scene.
	var player_scene: PackedScene = load("res://scenes/player.tscn") as PackedScene
	if player_scene == null:
		push_error("GameManager: Failed to load player.tscn")
		return

	var player: CharacterBody3D = player_scene.instantiate() as CharacterBody3D

	# Add to scene tree FIRST, then set position.
	var world: Node = builder.get_parent()
	if world != null:
		world.add_child(player)
	else:
		get_tree().root.add_child(player)

	player.global_position = entrance_pos + Vector3(0, 1, 0)


# ── Helpers ──────────────────────────────────────────────────────────────────

## Map the current difficulty tier to a float value used by the dungeon
## generator (0.0 = easy, 1.0 = abyss).
func _get_difficulty_value() -> float:
	var diff_mgr := _get_autoload("DifficultyManager")
	if diff_mgr == null:
		return 0.5

	var tier: String = diff_mgr.get("current_difficulty") if "current_difficulty" in diff_mgr else "normal"
	match tier:
		"easy":
			return 0.2
		"normal":
			return 0.5
		"hard":
			return 0.7
		"nightmare":
			return 0.85
		"abyss":
			return 1.0
		_:
			return 0.5


## Locate the AIDungeonBuilder node.  It may be an autoload or a child of
## the current scene.
func _find_dungeon_builder() -> Node:
	# Check autoload first.
	var builder: Node = _get_autoload("AIDungeonBuilder")
	if builder != null:
		return builder

	# Search the scene tree recursively using find_child.
	var root: Window = get_tree().root if get_tree() != null else null
	if root == null:
		return null

	var found: Node = root.find_child("AIDungeonBuilder", true, false)
	if found != null:
		return found

	# Fallback: look for any node with the method.
	for child in root.get_children():
		if child.has_method("request_and_build_floor"):
			return child
		var deep: Node = child.find_child("AIDungeonBuilder", true, false)
		if deep != null:
			return deep
	return null


func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null


## Find a node anywhere in the scene tree by name.
func _find_node(node_name: String) -> Node:
	var root: Window = get_tree().root if get_tree() != null else null
	if root == null:
		return null
	return root.find_child(node_name, true, false)


## Check whether combat is currently active.
func _is_in_combat() -> bool:
	var root: Window = get_tree().root if get_tree() != null else null
	if root == null:
		return false
	var player: Node = root.find_child("Player", true, false)
	if player == null:
		return false
	var cs: Node = player.get_node_or_null("CombatSystem")
	if cs != null and "is_in_combat" in cs:
		return cs.is_in_combat
	return false


## Convert a Variant array (from JSON) into a typed Array[String].
func _parse_string_array(source: Variant) -> Array[String]:
	var result: Array[String] = []
	if source is Array:
		for item in source:
			result.append(str(item))
	return result
