## Centralized event bus for game-wide communication.
##
## Register this script as an autoload named "EventBus" in
## Project -> Project Settings -> Autoload.
## All game systems emit and listen to signals through this singleton
## to avoid tight coupling between modules.
extends Node

@warning_ignore("unused_signal")

# ── Player Events ────────────────────────────────────────────────────────────

signal player_died
signal player_healed(amount: float)
signal player_damaged(amount: float)
signal player_leveled_up(new_level: int)

# ── Dungeon Events ───────────────────────────────────────────────────────────

signal room_entered(room_data: Dictionary)
signal room_cleared(room_id: String)
signal floor_started(floor_number: int)
signal floor_cleared(floor_number: int)

# ── Combat Events ────────────────────────────────────────────────────────────

signal combat_started(enemies: Array)
signal combat_ended(summary: Dictionary)
signal combat_log(message: String)
signal boss_defeated(boss_data: Dictionary)
signal monster_killed(monster_data: Dictionary)

# ── Item Events ──────────────────────────────────────────────────────────────

signal item_picked_up(item_data: Dictionary)
signal item_used(item_data: Dictionary)

# ── NPC Events ───────────────────────────────────────────────────────────────

signal npc_talked(npc_id: String, affinity: int)

# ── Quest Events ─────────────────────────────────────────────────────────────

signal quest_accepted(quest_data: Dictionary)
signal quest_objective_updated(quest_id: String, objective_id: String, current: int, required: int)
signal quest_completed(quest_data: Dictionary)
signal quest_failed(quest_id: String)

# ── Economy Events ───────────────────────────────────────────────────────────

signal gold_changed(new_amount: int, change: int)

# ── Difficulty Events ────────────────────────────────────────────────────────

signal difficulty_changed(new_difficulty: Dictionary)

# ── UI Events ───────────────────────────────────────────────────────────────

signal quest_log_toggled
