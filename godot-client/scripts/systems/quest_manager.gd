## Tracks active, completed, and failed quests.  Auto-updates objective
## progress by listening to EventBus signals and periodically checks the
## AI server for new quest triggers.
##
## Register this script as an autoload named "QuestManager" in
## Project -> Project Settings -> Autoload.
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

signal quest_offered(quest_data: Dictionary)
signal quest_accepted(quest_data: Dictionary)
signal quest_progress(quest_id: String, objective_id: String, current: int, required: int)
signal quest_completed(quest_data: Dictionary)
signal quest_failed(quest_id: String)

# ── State ────────────────────────────────────────────────────────────────────

## Active quests indexed by quest_id.  Each value is a Dictionary that
## includes the original quest data plus a "progress" sub-dictionary.
var active_quests: Dictionary = {}

## IDs of quests that have been completed this session or loaded from disk.
var completed_quests: Array[String] = []

## IDs of quests that were failed.
var failed_quests: Array[String] = []

## Maximum number of simultaneously active quests.
var max_active_quests: int = 5

# ── Trigger Check Timing ────────────────────────────────────────────────────

## Minimum interval (seconds) between automatic game-state analysis calls.
var _check_trigger_cooldown: float = 60.0

## Accumulator for periodic trigger checks.
var _time_since_last_check: float = 0.0

# ── Constants ────────────────────────────────────────────────────────────────

const SAVE_PATH: String = "user://quest_data.json"

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	load_quests()
	_connect_event_bus()

	# Listen for AI-generated quests coming from the AIClient.
	var ai_client := _get_ai_client()
	if ai_client != null:
		ai_client.quest_generated.connect(_on_quest_generated)
		if ai_client.has_signal("game_state_analyzed"):
			ai_client.game_state_analyzed.connect(_on_game_state_analyzed)


func _process(delta: float) -> void:
	_time_since_last_check += delta
	if _time_since_last_check >= _check_trigger_cooldown:
		_time_since_last_check = 0.0
		var game_state: Dictionary = _build_game_state()
		if not game_state.is_empty():
			check_triggers(game_state)

# ── Public API ───────────────────────────────────────────────────────────────

## Accept a quest and begin tracking it.  Returns false if the quest is
## already active or the active-quest limit has been reached.
func accept_quest(quest_data: Dictionary) -> bool:
	var quest_id: String = quest_data.get("id", "")
	if quest_id.is_empty():
		push_warning("QuestManager: cannot accept quest with empty id.")
		return false

	if active_quests.has(quest_id):
		push_warning("QuestManager: quest '%s' is already active." % quest_id)
		return false

	if active_quests.size() >= max_active_quests:
		push_warning("QuestManager: active quest limit reached (%d)." % max_active_quests)
		return false

	if completed_quests.has(quest_id):
		push_warning("QuestManager: quest '%s' has already been completed." % quest_id)
		return false

	# Initialize progress tracking for each objective.
	var objectives: Array = quest_data.get("objectives", [])
	var progress: Dictionary = {}
	for i in range(objectives.size()):
		var obj: Dictionary = objectives[i] if objectives[i] is Dictionary else {}
		var obj_id: String = obj.get("objective_id", obj.get("id", "obj_%d" % i))
		progress[obj_id] = {
			"current": int(obj.get("current_count", obj.get("current", 0))),
			"required": int(obj.get("required_count", obj.get("count", 1))),
			"completed": false,
		}

	var tracked_quest: Dictionary = quest_data.duplicate(true)
	tracked_quest["progress"] = progress
	tracked_quest["accepted_at"] = Time.get_unix_time_from_system()
	active_quests[quest_id] = tracked_quest

	quest_accepted.emit(tracked_quest)

	# Forward to EventBus so other systems can react.
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.quest_accepted.emit(tracked_quest)

	save_quests()
	return true


## Decline an offered quest (no-op storage-wise; exists for signal symmetry).
func decline_quest(quest_id: String) -> void:
	# Nothing persisted — the quest simply isn't tracked.
	pass


## Increment progress for a specific objective.
func update_objective(quest_id: String, objective_id: String, amount: int = 1) -> void:
	if not active_quests.has(quest_id):
		return

	var quest: Dictionary = active_quests[quest_id]
	var prog: Dictionary = quest.get("progress", {})
	if not prog.has(objective_id):
		return

	var obj_prog: Dictionary = prog[objective_id]
	if obj_prog.get("completed", false):
		return

	var current: int = int(obj_prog.get("current", 0)) + amount
	var required: int = int(obj_prog.get("required", 1))
	current = mini(current, required)
	obj_prog["current"] = current

	if current >= required:
		obj_prog["completed"] = true

	quest_progress.emit(quest_id, objective_id, current, required)

	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.quest_objective_updated.emit(quest_id, objective_id, current, required)

	# Auto-check completion whenever an objective updates.
	if check_quest_completion(quest_id):
		complete_quest(quest_id)
	else:
		save_quests()


## Return true if every objective in the quest has been met.
func check_quest_completion(quest_id: String) -> bool:
	if not active_quests.has(quest_id):
		return false

	var quest: Dictionary = active_quests[quest_id]
	var prog: Dictionary = quest.get("progress", {})
	for obj_id in prog:
		var obj_prog: Dictionary = prog[obj_id]
		if not obj_prog.get("completed", false):
			return false
	return true


## Mark a quest as completed and grant rewards.
func complete_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	var quest: Dictionary = active_quests[quest_id]
	quest["completed_at"] = Time.get_unix_time_from_system()
	active_quests.erase(quest_id)
	completed_quests.append(quest_id)

	# Grant rewards via EventBus (gold, etc.).
	var rewards: Dictionary = quest.get("rewards", {})
	var gold: int = int(rewards.get("gold", 0))
	if gold > 0:
		var event_bus := _get_event_bus()
		if event_bus != null:
			# GameManager is expected to handle the actual gold bookkeeping.
			event_bus.gold_changed.emit(-1, gold)  # -1 = current unknown here

	quest_completed.emit(quest)

	# Also emit via EventBus for other systems.
	var completion_bus := _get_event_bus()
	if completion_bus != null:
		completion_bus.quest_completed.emit(quest)

	save_quests()


## Mark a quest as failed and remove it from active tracking.
func fail_quest(quest_id: String) -> void:
	if not active_quests.has(quest_id):
		return

	active_quests.erase(quest_id)
	failed_quests.append(quest_id)

	quest_failed.emit(quest_id)

	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.quest_failed.emit(quest_id)

	save_quests()


## Return an array of all active quest dictionaries.
func get_active_quests() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest_id in active_quests:
		result.append(active_quests[quest_id])
	return result


## Return the full tracked data for a single quest.
func get_quest(quest_id: String) -> Dictionary:
	if active_quests.has(quest_id):
		return active_quests[quest_id]
	return {}


## Check whether the given quest is currently active.
func is_quest_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)


## Send the current game state to the AI server to check for new quest
## triggers.  The server may respond with quest_generated signals.
func check_triggers(game_state: Dictionary) -> void:
	var ai_client := _get_ai_client()
	if ai_client == null:
		return

	# Use the game/analyze endpoint for comprehensive quest trigger analysis.
	if ai_client.has_method("analyze_game_state"):
		ai_client.analyze_game_state(game_state)
	else:
		ai_client.generate_quest("trigger_check", "", game_state)


# ── Persistence ──────────────────────────────────────────────────────────────

## Save quest state to disk.
func save_quests() -> void:
	var data: Dictionary = {
		"active_quests": active_quests,
		"completed_quests": completed_quests,
		"failed_quests": failed_quests,
	}
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("QuestManager: could not open %s for writing (error %d)" % [
			SAVE_PATH, FileAccess.get_open_error()
		])
		return
	file.store_string(json_string)
	file.close()


## Load quest state from disk.
func load_quests() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("QuestManager: could not open %s for reading." % SAVE_PATH)
		return

	var json_string: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_warning("QuestManager: corrupt save file – %s" % json.get_error_message())
		return

	if json.data is not Dictionary:
		push_warning("QuestManager: unexpected save format.")
		return

	var data: Dictionary = json.data
	active_quests = data.get("active_quests", {}) as Dictionary

	# Parse typed arrays from JSON (they come back as plain Array).
	completed_quests = _parse_string_array(data.get("completed_quests", []))
	failed_quests = _parse_string_array(data.get("failed_quests", []))


# ── EventBus Auto-update ────────────────────────────────────────────────────

func _connect_event_bus() -> void:
	var event_bus := _get_event_bus()
	if event_bus == null:
		push_warning("QuestManager: EventBus not available – quest auto-tracking disabled.")
		return

	event_bus.monster_killed.connect(_on_monster_killed)
	event_bus.item_picked_up.connect(_on_item_picked_up)
	event_bus.room_entered.connect(_on_room_entered)
	event_bus.boss_defeated.connect(_on_boss_defeated)


func _on_monster_killed(monster_data: Dictionary) -> void:
	var monster_type: String = monster_data.get("type", "")
	_update_objectives_by_type("kill", monster_type)


func _on_item_picked_up(item_data: Dictionary) -> void:
	var item_type: String = item_data.get("type", "")
	var item_id: String = item_data.get("id", item_data.get("name", ""))
	_update_objectives_by_type("collect", item_id)
	if not item_type.is_empty():
		_update_objectives_by_type("collect", item_type)


func _on_room_entered(room_data: Dictionary) -> void:
	var room_type: String = room_data.get("type", "")
	var room_id: String = room_data.get("id", "")
	_update_objectives_by_type("explore", room_id)
	if not room_type.is_empty():
		_update_objectives_by_type("explore", room_type)
	_update_objectives_by_type("find", room_id)


func _on_boss_defeated(boss_data: Dictionary) -> void:
	var boss_type: String = boss_data.get("type", "boss")
	var boss_id: String = boss_data.get("id", boss_data.get("name", ""))
	_update_objectives_by_type("kill", boss_id)
	_update_objectives_by_type("kill", boss_type)


## Scan all active quests for objectives matching the given type and target,
## then increment them.
func _update_objectives_by_type(obj_type: String, target: String) -> void:
	if target.is_empty():
		return

	for quest_id in active_quests:
		var quest: Dictionary = active_quests[quest_id]
		var objectives: Array = quest.get("objectives", [])
		for i in range(objectives.size()):
			var obj: Dictionary = objectives[i] if objectives[i] is Dictionary else {}
			if obj.get("type", "") != obj_type:
				continue
			if obj.get("target", "") != target:
				continue
			var obj_id: String = obj.get("objective_id", obj.get("id", "obj_%d" % i))
			update_objective(quest_id, obj_id, 1)


# ── AI Quest Generation Handler ─────────────────────────────────────────────

func _on_quest_generated(data: Dictionary) -> void:
	_on_game_state_analyzed(data)


## Handle a new quest from the AI server or trigger-check response.
func _on_game_state_analyzed(data: Dictionary) -> void:
	# Handle /api/game/analyze response format: {triggered_quests: [...], ...}
	var quests: Array = []
	if data.has("triggered_quests"):
		for tq in data["triggered_quests"]:
			if tq is Dictionary and tq.has("quest"):
				var quest_data: Dictionary = tq["quest"]
				quest_data["trigger_type"] = tq.get("trigger_type", "")
				quest_data["context_message"] = tq.get("context_message", "")
				quests.append(quest_data)
	elif data.has("quests"):
		quests = data["quests"] if data["quests"] is Array else [data["quests"]]
	elif data.has("quest_id"):
		quests = [data]

	for quest_data in quests:
		if quest_data is not Dictionary:
			continue
		var quest_id: String = quest_data.get("quest_id", quest_data.get("id", ""))
		if quest_id.is_empty():
			continue
		quest_data["id"] = quest_id  # Normalize to "id" for internal use
		# Don't offer quests that are already active, completed, or failed.
		if active_quests.has(quest_id) or completed_quests.has(quest_id):
			continue
		quest_offered.emit(quest_data)


## Build a snapshot of the current game state matching the server's GameState model.
func _build_game_state() -> Dictionary:
	var state: Dictionary = {
		"player_level": 1,
		"current_floor": 1,
		"deaths": 0,
		"total_kills": 0,
		"exploration_rate": 0.5,
		"hp_ratio": 1.0,
		"gold": 0,
		"inventory": [],
		"npc_affinities": {},
		"floors_cleared": [],
		"bosses_defeated": [],
		"active_quest_ids": active_quests.keys() as Array,
		"damage_taken_ratio": 0.5,
		"healing_item_usage": 0.3,
		"play_time_minutes": 0.0,
		"consecutive_deaths": 0,
		"elite_kills": 0,
		"secrets_found": 0,
	}

	# Gather data from GameManager.
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		state["current_floor"] = game_mgr.get("current_floor") if "current_floor" in game_mgr else 1
		state["player_level"] = game_mgr.get("player_level") if "player_level" in game_mgr else 1
		state["gold"] = game_mgr.get("player_gold") if "player_gold" in game_mgr else 0
		state["hp_ratio"] = game_mgr.get("player_hp_ratio") if "player_hp_ratio" in game_mgr else 1.0
		state["inventory"] = game_mgr.get("player_inventory") if "player_inventory" in game_mgr else []

	# Gather data from PlayerTracker.
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null:
		state["deaths"] = tracker.get("total_deaths") if "total_deaths" in tracker else 0
		if tracker.has_method("get_adapt_request_data"):
			var adapt: Dictionary = tracker.get_adapt_request_data()
			state["damage_taken_ratio"] = adapt.get("damage_taken_ratio", 0.5)
			state["healing_item_usage"] = adapt.get("healing_item_usage", 0.3)
			state["exploration_rate"] = adapt.get("exploration_rate", 0.5)

	return state

# ── Helpers ──────────────────────────────────────────────────────────────────

## Safely retrieve the EventBus autoload.
func _get_event_bus() -> Node:
	return _get_autoload("EventBus")


## Safely retrieve the AIClient autoload.
func _get_ai_client() -> Node:
	return _get_autoload("AIClient")


## Generic autoload lookup.
func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null


## Convert a Variant array (from JSON) into a typed Array[String].
func _parse_string_array(source: Variant) -> Array[String]:
	var result: Array[String] = []
	if source is Array:
		for item in source:
			result.append(str(item))
	return result
