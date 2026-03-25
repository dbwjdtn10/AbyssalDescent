## Manages adaptive difficulty state and applies AI-driven recommendations.
##
## Register this script as an autoload named "DifficultyManager" in
## Project -> Project Settings -> Autoload.
## Connects to PlayerTracker for adaptation data and EventBus for
## floor-clear events.
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

signal difficulty_changed(difficulty: String, params: Dictionary)

# ── Difficulty Tiers ─────────────────────────────────────────────────────────

const DIFFICULTY_TIERS: Array[String] = ["easy", "normal", "hard", "nightmare", "abyss"]

const DIFFICULTY_NAMES_KR: Dictionary = {
	"easy": "쉬움",
	"normal": "보통",
	"hard": "어려움",
	"nightmare": "악몽",
	"abyss": "심연",
}

const DIFFICULTY_COLORS: Dictionary = {
	"easy": Color(0.4, 0.7, 0.4, 1.0),
	"normal": Color(0.9, 0.88, 0.82, 1.0),
	"hard": Color(0.92, 0.6, 0.2, 1.0),
	"nightmare": Color(0.8, 0.2, 0.2, 1.0),
	"abyss": Color(0.5, 0.1, 0.6, 1.0),
}

## Default parameter presets for each difficulty tier.
const DEFAULT_PARAMS: Dictionary = {
	"easy": {
		"monster_level_offset": -1,
		"monster_count_multiplier": 0.7,
		"monster_damage_multiplier": 0.75,
		"monster_hp_multiplier": 0.8,
		"loot_quality_bonus": 0.0,
		"trap_frequency": 0.3,
		"healing_availability": 1.5,
	},
	"normal": {
		"monster_level_offset": 0,
		"monster_count_multiplier": 1.0,
		"monster_damage_multiplier": 1.0,
		"monster_hp_multiplier": 1.0,
		"loot_quality_bonus": 0.0,
		"trap_frequency": 0.5,
		"healing_availability": 1.0,
	},
	"hard": {
		"monster_level_offset": 1,
		"monster_count_multiplier": 1.3,
		"monster_damage_multiplier": 1.25,
		"monster_hp_multiplier": 1.3,
		"loot_quality_bonus": 0.1,
		"trap_frequency": 0.7,
		"healing_availability": 0.8,
	},
	"nightmare": {
		"monster_level_offset": 2,
		"monster_count_multiplier": 1.6,
		"monster_damage_multiplier": 1.5,
		"monster_hp_multiplier": 1.6,
		"loot_quality_bonus": 0.2,
		"trap_frequency": 0.85,
		"healing_availability": 0.5,
	},
	"abyss": {
		"monster_level_offset": 3,
		"monster_count_multiplier": 2.0,
		"monster_damage_multiplier": 2.0,
		"monster_hp_multiplier": 2.0,
		"loot_quality_bonus": 0.35,
		"trap_frequency": 1.0,
		"healing_availability": 0.3,
	},
}

# ── State ────────────────────────────────────────────────────────────────────

## Current difficulty tier name.
var current_difficulty: String = "normal"

## Active difficulty parameters (may be a blend of defaults + AI overrides).
var difficulty_params: Dictionary = {}

## Whether automatic difficulty adjustment is enabled.
var auto_adjust: bool = true

## The last floor where difficulty was adjusted (to prevent re-checks on
## the same floor).
var _last_adjustment_floor: int = 0

## Minimum number of floors between automatic difficulty checks.
const CHECK_INTERVAL_FLOORS: int = 2

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Initialize with default normal parameters.
	difficulty_params = DEFAULT_PARAMS["normal"].duplicate(true)
	_connect_signals()


# ── Public API ───────────────────────────────────────────────────────────────

## Apply a difficulty recommendation from the AI server.
## The data Dictionary is expected to contain optional keys like
## "recommended_difficulty", "monster_level_offset", etc.
func apply_recommendation(data: Dictionary) -> void:
	var recommended: String = data.get("recommended_difficulty", "")
	if not recommended.is_empty() and DIFFICULTY_TIERS.has(recommended):
		current_difficulty = recommended
		difficulty_params = DEFAULT_PARAMS[current_difficulty].duplicate(true)
	else:
		# If no tier recommendation, keep the current tier but merge
		# individual parameter overrides.
		pass

	# Merge any fine-grained parameter overrides from the server.
	for key in data:
		if key == "recommended_difficulty" or key == "fallback":
			continue
		if difficulty_params.has(key):
			difficulty_params[key] = data[key]

	difficulty_changed.emit(current_difficulty, difficulty_params)

	# Forward to EventBus.
	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.difficulty_changed.emit({
			"difficulty": current_difficulty,
			"params": difficulty_params,
		})


## Return the current difficulty parameters.
func get_current_params() -> Dictionary:
	return difficulty_params.duplicate(true)


## Manually set the difficulty tier, overriding auto-adjustment.
func set_difficulty(difficulty_name: String) -> void:
	if not DIFFICULTY_TIERS.has(difficulty_name):
		push_warning("DifficultyManager: unknown difficulty tier '%s'." % difficulty_name)
		return

	current_difficulty = difficulty_name
	difficulty_params = DEFAULT_PARAMS[current_difficulty].duplicate(true)

	difficulty_changed.emit(current_difficulty, difficulty_params)

	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.difficulty_changed.emit({
			"difficulty": current_difficulty,
			"params": difficulty_params,
		})


## Determine whether a difficulty check should run on the given floor.
func should_check_difficulty(current_floor: int) -> bool:
	if not auto_adjust:
		return false
	if current_floor <= _last_adjustment_floor:
		return false
	return (current_floor - _last_adjustment_floor) >= CHECK_INTERVAL_FLOORS


## Ask PlayerTracker to send adaptation data to the AI server.
func request_adjustment() -> void:
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null and tracker.has_method("request_difficulty_adaptation"):
		tracker.request_difficulty_adaptation()
	else:
		push_warning("DifficultyManager: PlayerTracker not available for adaptation request.")


## Return the Korean display name for the current difficulty.
func get_difficulty_display_name() -> String:
	return DIFFICULTY_NAMES_KR.get(current_difficulty, "보통")


## Return the theme color associated with the current difficulty.
func get_difficulty_color() -> Color:
	return DIFFICULTY_COLORS.get(current_difficulty, Color.WHITE)


# ── Signal Connections ───────────────────────────────────────────────────────

func _connect_signals() -> void:
	# Defer so other autoloads have time to register.
	call_deferred("_deferred_connect_signals")


func _deferred_connect_signals() -> void:
	# Listen for AI difficulty recommendations via PlayerTracker.
	var tracker := _get_autoload("PlayerTracker")
	if tracker != null:
		if tracker.has_signal("difficulty_recommendation_received"):
			tracker.difficulty_recommendation_received.connect(_on_difficulty_recommendation)

	# Listen for floor clears to trigger auto-adjustment.
	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.floor_cleared.connect(_on_floor_cleared)


func _on_difficulty_recommendation(data: Dictionary) -> void:
	apply_recommendation(data)


func _on_floor_cleared(floor_number: int) -> void:
	# Auto-upgrade from easy to normal after floor 2.
	if current_difficulty == "easy" and floor_number >= 2:
		set_difficulty("normal")
		_last_adjustment_floor = floor_number
		return
	if should_check_difficulty(floor_number):
		_last_adjustment_floor = floor_number
		request_adjustment()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
