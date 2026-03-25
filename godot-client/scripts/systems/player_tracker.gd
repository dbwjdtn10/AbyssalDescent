## Tracks player behavior metrics across dungeon floors for adaptive
## difficulty.  Data is persisted to user://player_stats.json between
## sessions and can be sent to the AI server via POST /api/dungeon/adapt.
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

signal difficulty_recommendation_received(data: Dictionary)

# ── Persistent Stats ─────────────────────────────────────────────────────────

var total_deaths: int = 0
var floor_clear_times: Array[float] = []
var damage_taken_history: Array[float] = []
var healing_used_history: Array[float] = []
var exploration_rates: Array[float] = []

# ── Current Floor Tracking ───────────────────────────────────────────────────

var current_floor_start_time: float = 0.0
var current_floor_damage_taken: float = 0.0
var current_floor_healing_used: float = 0.0
var rooms_explored: int = 0
var total_rooms: int = 0

## The floor number currently being tracked (-1 = not tracking).
var _current_floor: int = -1

# ── Constants ────────────────────────────────────────────────────────────────

const SAVE_PATH: String = "user://player_stats.json"

## Maximum number of entries kept per history array to prevent unbounded
## growth.  Older entries are discarded first.
const MAX_HISTORY_SIZE: int = 50

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	load_data()

	# Connect to AIClient difficulty signal if available.
	var ai_client := _get_ai_client()
	if ai_client != null:
		ai_client.difficulty_adapted.connect(_on_difficulty_adapted)

# ── Public API ───────────────────────────────────────────────────────────────

## Begin tracking a new floor.
func start_floor(floor_number: int, room_count: int) -> void:
	_current_floor = floor_number
	current_floor_start_time = Time.get_unix_time_from_system()
	current_floor_damage_taken = 0.0
	current_floor_healing_used = 0.0
	rooms_explored = 0
	total_rooms = room_count


## Record a player death.
func record_death() -> void:
	total_deaths += 1
	save_data()


## Track damage the player has taken on the current floor.
func record_damage(amount: float) -> void:
	current_floor_damage_taken += absf(amount)


## Track healing the player has used on the current floor.
func record_healing(amount: float) -> void:
	current_floor_healing_used += absf(amount)


## Increment the number of rooms the player has explored on this floor.
func record_room_explored() -> void:
	rooms_explored += 1


## Finalize the current floor and store the summary.
## Returns a Dictionary with the floor's tracking data.
func finish_floor() -> Dictionary:
	var elapsed: float = Time.get_unix_time_from_system() - current_floor_start_time
	var explore_rate: float = 0.0
	if total_rooms > 0:
		explore_rate = float(rooms_explored) / float(total_rooms)

	# Append to history arrays (with size cap).
	_append_capped(floor_clear_times, elapsed)
	_append_capped(damage_taken_history, current_floor_damage_taken)
	_append_capped(healing_used_history, current_floor_healing_used)
	_append_capped(exploration_rates, explore_rate)

	var summary: Dictionary = {
		"floor_number": _current_floor,
		"clear_time": elapsed,
		"damage_taken": current_floor_damage_taken,
		"healing_used": current_floor_healing_used,
		"rooms_explored": rooms_explored,
		"total_rooms": total_rooms,
		"exploration_rate": explore_rate,
	}

	# Reset per-floor counters.
	_current_floor = -1
	current_floor_start_time = 0.0
	current_floor_damage_taken = 0.0
	current_floor_healing_used = 0.0
	rooms_explored = 0
	total_rooms = 0

	save_data()
	return summary


## Format the accumulated data into the shape expected by
## POST /api/dungeon/adapt  (player_history payload).
func get_adapt_request_data() -> Dictionary:
	var avg_clear_time: float = _array_average(floor_clear_times)
	var avg_damage: float = _array_average(damage_taken_history)
	var avg_healing: float = _array_average(healing_used_history)
	var avg_exploration: float = _array_average(exploration_rates)

	return {
		"total_deaths": total_deaths,
		"floors_completed": floor_clear_times.size(),
		"average_clear_time": avg_clear_time,
		"average_damage_taken": avg_damage,
		"average_healing_used": avg_healing,
		"average_exploration_rate": avg_exploration,
		"recent_clear_times": _recent_slice(floor_clear_times, 5),
		"recent_damage_taken": _recent_slice(damage_taken_history, 5),
		"recent_healing_used": _recent_slice(healing_used_history, 5),
		"recent_exploration_rates": _recent_slice(exploration_rates, 5),
	}


## Send the current tracking data to the AI server for difficulty adaptation.
func request_difficulty_adaptation() -> void:
	var ai_client := _get_ai_client()
	if ai_client == null:
		push_warning("PlayerTracker: AIClient not available – cannot request adaptation.")
		return

	var history: Dictionary = get_adapt_request_data()
	ai_client.adapt_difficulty(history)


# ── Persistence ──────────────────────────────────────────────────────────────

## Save all tracking data to disk.
func save_data() -> void:
	var data: Dictionary = {
		"total_deaths": total_deaths,
		"floor_clear_times": floor_clear_times,
		"damage_taken_history": damage_taken_history,
		"healing_used_history": healing_used_history,
		"exploration_rates": exploration_rates,
	}
	var json_string: String = JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("PlayerTracker: could not open %s for writing (error %d)" % [
			SAVE_PATH, FileAccess.get_open_error()
		])
		return
	file.store_string(json_string)
	file.close()


## Load tracking data from disk.
func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("PlayerTracker: could not open %s for reading." % SAVE_PATH)
		return

	var json_string: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		push_warning("PlayerTracker: corrupt save file – %s" % json.get_error_message())
		return

	if json.data is not Dictionary:
		push_warning("PlayerTracker: unexpected save format.")
		return

	var data: Dictionary = json.data
	total_deaths = int(data.get("total_deaths", 0))

	floor_clear_times = _parse_float_array(data.get("floor_clear_times", []))
	damage_taken_history = _parse_float_array(data.get("damage_taken_history", []))
	healing_used_history = _parse_float_array(data.get("healing_used_history", []))
	exploration_rates = _parse_float_array(data.get("exploration_rates", []))


# ── Signal Handlers ──────────────────────────────────────────────────────────

func _on_difficulty_adapted(data: Dictionary) -> void:
	difficulty_recommendation_received.emit(data)


# ── Private Helpers ──────────────────────────────────────────────────────────

## Safely retrieve the AIClient autoload.
func _get_ai_client() -> Node:
	if Engine.has_singleton("AIClient"):
		return Engine.get_singleton("AIClient")
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node("AIClient"):
		return root.get_node("AIClient")
	return null


## Append a value to a typed float array, discarding the oldest entry if the
## array exceeds MAX_HISTORY_SIZE.
func _append_capped(arr: Array[float], value: float) -> void:
	arr.append(value)
	while arr.size() > MAX_HISTORY_SIZE:
		arr.remove_at(0)


## Compute the arithmetic mean of a float array.
func _array_average(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var total: float = 0.0
	for v in arr:
		total += v
	return total / float(arr.size())


## Return the last `count` elements of a float array as a plain Array (for
## JSON serialization).
func _recent_slice(arr: Array[float], count: int) -> Array:
	var start: int = maxi(0, arr.size() - count)
	var result: Array = []
	for i in range(start, arr.size()):
		result.append(arr[i])
	return result


## Convert a Variant array (from JSON parsing) into a typed Array[float].
func _parse_float_array(source: Variant) -> Array[float]:
	var result: Array[float] = []
	if source is Array:
		for item in source:
			result.append(float(item))
	return result
