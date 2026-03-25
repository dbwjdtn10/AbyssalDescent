## Turn-based combat system.
##
## Manages combat encounters between the player and groups of enemies.
## Emits EventBus signals for integration with other game systems
## (PlayerTracker, GameHUD, SoundManager, etc.).
class_name CombatSystem
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

signal combat_started(enemies: Array)
signal combat_ended(summary: Dictionary)
signal enemy_damaged(enemy_index: int, damage: float)
signal enemy_killed(enemy_index: int, enemy_data: Dictionary)
signal player_turn_started
signal enemy_turn_started
signal enemy_turn_finished
signal skill_used(skill: Dictionary, enemy_index: int, damage: float)

# ── Element System ──────────────────────────────────────────────────────────

## Elemental weakness chart: attacker_element → weak_defender_element.
## Deals 1.5× damage if the defender is weak to the attacker's element.
const ELEMENT_WEAKNESS: Dictionary = {
	"fire": "ice",
	"ice": "lightning",
	"lightning": "water",
	"water": "fire",
	"holy": "dark",
	"dark": "holy",
}

## Elemental resistance (0.5× damage).
const ELEMENT_RESIST: Dictionary = {
	"fire": "water",
	"ice": "fire",
	"lightning": "ice",
	"water": "lightning",
	"holy": "holy",
	"dark": "dark",
}

# ── Skills ──────────────────────────────────────────────────────────────────

## Skills the player currently knows.  Populated on level-up.
var player_skills: Array[Dictionary] = []

## All available skills in the game.  Unlocked by level requirement.
const SKILL_TABLE: Array[Dictionary] = [
	{"id": "fireball", "name": "화염구", "element": "fire", "power": 1.3, "mp_cost": 0, "level_req": 1, "desc": "불꽃을 날려 적을 태운다."},
	{"id": "ice_lance", "name": "얼음 창", "element": "ice", "power": 1.2, "mp_cost": 0, "level_req": 3, "desc": "날카로운 얼음 창을 발사한다."},
	{"id": "tidal_wave", "name": "해일", "element": "water", "power": 1.25, "mp_cost": 0, "level_req": 5, "desc": "물의 파도로 적을 쓸어버린다."},
	{"id": "thunder", "name": "번개", "element": "lightning", "power": 1.4, "mp_cost": 0, "level_req": 7, "desc": "하늘에서 번개를 내리친다."},
	{"id": "holy_smite", "name": "신성 강타", "element": "holy", "power": 1.25, "mp_cost": 0, "level_req": 9, "desc": "신성한 빛으로 적을 심판한다."},
	{"id": "dark_slash", "name": "어둠 베기", "element": "dark", "power": 1.35, "mp_cost": 0, "level_req": 11, "desc": "어둠의 힘으로 베어낸다."},
	{"id": "chain_lightning", "name": "연쇄 번개", "element": "lightning", "power": 0.6, "mp_cost": 0, "level_req": 6, "desc": "번개가 연쇄하여 모든 적을 타격한다.", "aoe": true},
	{"id": "flame_wave", "name": "화염 파동", "element": "fire", "power": 0.6, "mp_cost": 0, "level_req": 10, "desc": "화염의 파동이 모든 적을 휩쓴다.", "aoe": true},
	{"id": "abyssal_storm", "name": "심연의 폭풍", "element": "dark", "power": 0.65, "mp_cost": 0, "level_req": 14, "desc": "심연의 힘으로 모든 적을 삼킨다.", "aoe": true},
]

# ── State ────────────────────────────────────────────────────────────────────

## True while the player is engaged in a combat encounter.
var is_in_combat: bool = false

## Array of enemy dictionaries currently in combat.
## Each enemy dict: { name, level, hp, max_hp, attack, defense, rank, loot, element }
var current_enemies: Array = []

## Base player stats – combined with equipment bonuses at combat start.
var player_attack: float = 12.0
var player_defense: float = 5.0
var player_hp: float = 120.0
var player_max_hp: float = 120.0

## HP gained per player level above 1.
const HP_PER_LEVEL: float = 15.0

## Monster critical hit chance (0.0 – 1.0).
const MONSTER_CRIT_CHANCE: float = 0.15
## Monster critical hit multiplier.
const MONSTER_CRIT_MULT: float = 1.8

## Player critical hit chance.
const PLAYER_CRIT_CHANCE: float = 0.10
const PLAYER_CRIT_MULT: float = 1.5

## Accumulated combat metrics for the summary.
var _total_damage_dealt: float = 0.0
var _total_damage_taken: float = 0.0
var _total_kills: int = 0
var _total_gold_earned: int = 0
var _total_xp_earned: int = 0

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Unlock starting skill.
	refresh_skills(1)


# ── Public API ───────────────────────────────────────────────────────────────

## Begin a combat encounter with the given array of enemy dictionaries.
## Each enemy should contain at minimum: name, level, hp, max_hp, attack, defense.
func start_combat(enemies: Array) -> void:
	if is_in_combat:
		push_warning("CombatSystem: already in combat – ignoring start_combat().")
		return

	current_enemies = enemies.duplicate(true)

	# Ensure every enemy has all required fields with defaults.
	# Scale stats by level so higher-level enemies are meaningfully harder.
	for i in range(current_enemies.size()):
		var e: Dictionary = current_enemies[i]
		var lvl: int = int(e.get("level", 1))
		# Moderate scaling: 15% per level — challenging but beatable with gear.
		var level_mult: float = pow(1.15, float(lvl - 1))
		e["hp"] = float(e.get("hp", e.get("max_hp", 45.0 * level_mult)))
		e["max_hp"] = float(e.get("max_hp", e.get("hp", 45.0 * level_mult)))
		e["attack"] = float(e.get("attack", 9.0 * level_mult))
		e["defense"] = float(e.get("defense", 3.5 * level_mult))
		e["level"] = lvl
		e["name"] = str(e.get("name", "적"))
		# Fallback data uses "type" instead of "rank" for boss identification.
		var rank_val: String = str(e.get("rank", ""))
		if rank_val.is_empty() or rank_val == "normal":
			var type_val: String = str(e.get("type", ""))
			if type_val == "boss":
				rank_val = "boss"
			elif rank_val.is_empty():
				rank_val = "normal"
		e["rank"] = rank_val
		# Apply rank-based stat multipliers.
		if rank_val == "boss":
			e["hp"] *= 2.0
			e["max_hp"] *= 2.0
			e["attack"] *= 1.5
			e["defense"] *= 1.25
		elif rank_val == "mini_boss":
			e["hp"] *= 1.6
			e["max_hp"] *= 1.6
			e["attack"] *= 1.35
			e["defense"] *= 1.2
		elif rank_val == "elite":
			e["hp"] *= 1.6
			e["max_hp"] *= 1.6
			e["attack"] *= 1.35
			e["defense"] *= 1.2
		# Apply DifficultyManager multipliers.
		var diff_mgr := _get_autoload("DifficultyManager")
		if diff_mgr != null and diff_mgr.has_method("get_current_params"):
			var diff_params: Dictionary = diff_mgr.get_current_params()
			e["hp"] *= float(diff_params.get("monster_hp_multiplier", 1.0))
			e["max_hp"] *= float(diff_params.get("monster_hp_multiplier", 1.0))
			e["attack"] *= float(diff_params.get("monster_damage_multiplier", 1.0))
		e["loot"] = e.get("loot", {})
		# Assign or validate element — name keywords always take priority
		# to prevent mismatches like "용암 전사" having lightning element.
		var name_elem: String = _element_from_name(str(e.get("name", "")))
		if not name_elem.is_empty():
			e["element"] = name_elem
		elif not e.has("element") or str(e["element"]).is_empty():
			e["element"] = _assign_monster_element(str(e.get("type", "")), rank_val)
		current_enemies[i] = e

	# Refresh player stats and skills from GameManager.
	_sync_player_stats()
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		refresh_skills(game_mgr.player_level)

	# Reset metrics.
	_total_damage_dealt = 0.0
	_total_damage_taken = 0.0
	_total_kills = 0
	_total_gold_earned = 0
	_total_xp_earned = 0

	is_in_combat = true
	combat_started.emit(current_enemies)

	# Notify global EventBus so HUD can sync HP.
	var event_bus_start := _get_autoload("EventBus")
	if event_bus_start != null:
		event_bus_start.combat_started.emit(current_enemies)

	# Play combat BGM.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_bgm"):
		# Determine if this is a boss fight.
		var has_boss: bool = false
		for e in current_enemies:
			if e.get("rank", "") in ["boss", "mini_boss"]:
				has_boss = true
				break
		sound_mgr.play_bgm("boss_bgm" if has_boss else "combat_bgm")

	player_turn_started.emit()


## Player attacks the enemy at the given index.
## Returns the damage dealt (0 if invalid target).
func player_attack_enemy(enemy_index: int) -> float:
	if not is_in_combat:
		return 0.0
	if enemy_index < 0 or enemy_index >= current_enemies.size():
		return 0.0
	if not is_enemy_alive(enemy_index):
		return 0.0

	var enemy: Dictionary = current_enemies[enemy_index]
	var damage: float = calculate_damage(player_attack, enemy["defense"])

	# Player critical hit.
	if randf() < PLAYER_CRIT_CHANCE:
		damage *= PLAYER_CRIT_MULT

	enemy["hp"] = maxf(0.0, enemy["hp"] - damage)
	# Snap to 0 if less than 1 to prevent floating-point ghost HP.
	if enemy["hp"] < 1.0:
		enemy["hp"] = 0.0
	current_enemies[enemy_index] = enemy
	_total_damage_dealt += damage

	enemy_damaged.emit(enemy_index, damage)

	# Play attack SFX.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_sfx"):
		sound_mgr.play_sfx("attack_hit")

	# Check if enemy died.
	if enemy["hp"] <= 0.0:
		_on_enemy_died(enemy_index)

	# Check if all enemies are dead → end combat.
	if _all_enemies_dead():
		# If player also died this turn, it's a loss.
		if player_hp <= 0.0:
			_on_player_died()
		else:
			end_combat()
	else:
		# Proceed to enemy turn if combat continues.
		enemy_turn()

	return damage


## All living enemies attack the player in sequence.
func enemy_turn() -> void:
	if not is_in_combat:
		return

	enemy_turn_started.emit()

	for i in range(current_enemies.size()):
		if not is_enemy_alive(i):
			continue

		var enemy: Dictionary = current_enemies[i]
		var damage: float = calculate_damage(enemy["attack"], player_defense)

		# Monster critical hit — unpredictable spike damage.
		var is_crit: bool = randf() < MONSTER_CRIT_CHANCE
		if is_crit:
			damage *= MONSTER_CRIT_MULT

		player_hp = maxf(0.0, player_hp - damage)
		_total_damage_taken += damage

		# Keep GameManager in sync during combat.
		var game_mgr_sync := _get_autoload("GameManager")
		if game_mgr_sync != null:
			game_mgr_sync.player_hp_ratio = player_hp / player_max_hp

		# Emit EventBus player_damaged for HUD / tracker integration.
		var event_bus := _get_autoload("EventBus")
		if event_bus != null:
			event_bus.player_damaged.emit(damage)
			if is_crit and event_bus.has_signal("combat_log"):
				event_bus.combat_log.emit("%s의 강타! %.0f 데미지!" % [enemy["name"], damage])

		# Play player hurt SFX.
		var sound_mgr := _get_autoload("SoundManager")
		if sound_mgr != null and sound_mgr.has_method("play_sfx"):
			sound_mgr.play_sfx("player_hurt")

		# Check for player death.
		if player_hp <= 0.0:
			_on_player_died()
			return

	enemy_turn_finished.emit()
	player_turn_started.emit()


## Damage formula: max(1, atk - def * 0.5) * random(0.7, 1.3)
func calculate_damage(attacker_atk: float, defender_def: float) -> float:
	var base: float = maxf(1.0, attacker_atk - defender_def * 0.5)
	var variance: float = randf_range(0.7, 1.3)
	var result: float = snappedf(base * variance, 0.1)
	return maxf(1.0, result)


## End the current combat encounter, grant rewards, and emit signals.
func end_combat() -> void:
	if not is_in_combat:
		return

	is_in_combat = false

	# Sync HP back to GameManager, THEN apply post-combat heals.
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		game_mgr.player_hp_ratio = player_hp / player_max_hp
		# Per-kill heal (applied AFTER ratio sync so it is not overwritten).
		if _total_kills > 0 and "COMBAT_VICTORY_HEAL_RATIO" in game_mgr:
			var kill_heal: float = game_mgr.COMBAT_VICTORY_HEAL_RATIO * float(_total_kills)
			game_mgr.heal_player(kill_heal)

	# Calculate rewards from killed enemies.
	for enemy in current_enemies:
		if enemy["hp"] <= 0.0:
			var loot: Dictionary = enemy.get("loot", {})
			var enemy_lvl: int = int(enemy.get("level", 1))
			var rank_str: String = str(enemy.get("rank", "normal"))
			# Gold scales with level and rank for better economy feel.
			var base_gold: int = 8 + enemy_lvl * 6
			if rank_str == "boss":
				base_gold *= 5
			elif rank_str == "mini_boss":
				base_gold *= 3
			elif rank_str == "elite":
				base_gold = int(base_gold * 1.8)
			_total_gold_earned += int(loot.get("gold", base_gold))
			_total_xp_earned += int(loot.get("xp", 5 * enemy_lvl))

	# Apply gold reward.
	var event_bus := _get_autoload("EventBus")
	if event_bus != null and _total_gold_earned > 0:
		var current_gold: int = 0
		if game_mgr != null:
			current_gold = game_mgr.player_gold
		event_bus.gold_changed.emit(current_gold + _total_gold_earned, _total_gold_earned)

	# Random item drops from killed enemies.
	_roll_random_drops(event_bus)

	var summary: Dictionary = get_combat_summary()
	combat_ended.emit(summary)

	# Notify global EventBus so HUD can sync HP.
	var event_bus_end := _get_autoload("EventBus")
	if event_bus_end != null:
		event_bus_end.combat_ended.emit(summary)

	# Restore dungeon BGM.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_bgm"):
		sound_mgr.play_bgm("dungeon_bgm")

	current_enemies.clear()


## Check whether the enemy at the given index is still alive.
func is_enemy_alive(enemy_index: int) -> bool:
	if enemy_index < 0 or enemy_index >= current_enemies.size():
		return false
	return current_enemies[enemy_index]["hp"] > 0.0


## Attempt to flee from combat.  Returns true if successful.
## Success rate decreases with more/stronger enemies.
func attempt_flee() -> bool:
	if not is_in_combat:
		return false

	var alive_count: int = 0
	var total_enemy_level: int = 0
	for e in current_enemies:
		if e["hp"] > 0.0:
			alive_count += 1
			total_enemy_level += e.get("level", 1)

	# Base flee chance: 60% minus 5% per enemy level above player level.
	var game_mgr := _get_autoload("GameManager")
	var player_level: int = game_mgr.player_level if game_mgr != null else 1
	var level_diff: float = float(total_enemy_level) / maxf(float(alive_count), 1.0) - float(player_level)
	var flee_chance: float = clampf(0.6 - level_diff * 0.05, 0.1, 0.9)

	# Bosses cannot be fled from.
	for e in current_enemies:
		if e.get("rank", "") == "boss" and e["hp"] > 0.0:
			return false

	if randf() < flee_chance:
		is_in_combat = false

		# Sync HP back to GameManager before clearing combat state.
		if game_mgr != null:
			game_mgr.player_hp_ratio = player_hp / player_max_hp

		current_enemies.clear()

		var sound_mgr := _get_autoload("SoundManager")
		if sound_mgr != null and sound_mgr.has_method("play_bgm"):
			sound_mgr.play_bgm("dungeon_bgm")

		combat_ended.emit(get_combat_summary())
		return true

	# Failed to flee – enemies get a free turn.
	enemy_turn()
	return false


## Build a summary of the combat encounter.
func get_combat_summary() -> Dictionary:
	return {
		"kills": _total_kills,
		"damage_dealt": _total_damage_dealt,
		"damage_taken": _total_damage_taken,
		"gold_earned": _total_gold_earned,
		"xp_earned": _total_xp_earned,
		"player_hp_remaining": player_hp,
		"player_max_hp": player_max_hp,
		"victory": _all_enemies_dead(),
	}


## Use a consumable item during combat (e.g., health potion).
func use_item_in_combat(item_data: Dictionary) -> void:
	if not is_in_combat:
		return

	var item_type: String = item_data.get("type", "")
	if item_type == "potion" or item_type == "consumable":
		# Check stats.heal first (template items), then top-level heal/value.
		var stats_heal: float = float(item_data.get("stats", {}).get("heal", 0.0))
		var top_heal: float = float(item_data.get("heal", item_data.get("value", 0.0)))
		var heal_amount: float = maxf(stats_heal, top_heal)
		if heal_amount <= 0.0:
			heal_amount = 30.0
		player_hp = minf(player_hp + heal_amount, player_max_hp)

		# Keep GameManager in sync during combat.
		var game_mgr_sync := _get_autoload("GameManager")
		if game_mgr_sync != null:
			game_mgr_sync.player_hp_ratio = player_hp / player_max_hp

		# Remove the item from inventory.
		var inv := _get_autoload("InventorySystem")
		if inv != null and inv.has_method("remove_item"):
			var item_id: String = item_data.get("id", item_data.get("name", ""))
			inv.remove_item(item_id, 1)

		var event_bus := _get_autoload("EventBus")
		if event_bus != null:
			event_bus.player_healed.emit(heal_amount)
			event_bus.item_used.emit(item_data)

		# Using an item counts as the player's turn; enemies attack next.
		enemy_turn()


# ── Private Helpers ──────────────────────────────────────────────────────────

## Sync player stats from InventorySystem and GameManager.
func _sync_player_stats() -> void:
	var inv := _get_autoload("InventorySystem")
	if inv != null:
		if inv.has_method("get_total_attack"):
			player_attack = inv.get_total_attack()
		if inv.has_method("get_total_defense"):
			player_defense = inv.get_total_defense()

	# Scale max HP with player level + permanent upgrades.
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		player_max_hp = 100.0 + (game_mgr.player_level - 1) * HP_PER_LEVEL
		# Apply permanent upgrades.
		player_attack += game_mgr.upgrade_atk * 2.0
		player_defense += game_mgr.upgrade_def * 1.5
		player_max_hp += game_mgr.upgrade_hp * 10.0
		player_hp = player_max_hp * game_mgr.player_hp_ratio


## Called when an enemy's HP reaches zero.
func _on_enemy_died(enemy_index: int) -> void:
	_total_kills += 1
	var enemy: Dictionary = current_enemies[enemy_index]

	enemy_killed.emit(enemy_index, enemy)

	# Emit EventBus monster_killed.
	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.monster_killed.emit(enemy)

		# If this was a boss, emit boss_defeated to trigger floor transition.
		var rank: String = enemy.get("rank", enemy.get("type", ""))
		if rank == "boss":
			event_bus.boss_defeated.emit(enemy)

	# Play kill SFX.
	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_sfx"):
		sound_mgr.play_sfx("attack_hit")


## Handle the player dying during combat.
func _on_player_died() -> void:
	is_in_combat = false

	var event_bus := _get_autoload("EventBus")
	if event_bus != null:
		event_bus.player_died.emit()

	var sound_mgr := _get_autoload("SoundManager")
	if sound_mgr != null and sound_mgr.has_method("play_sfx"):
		sound_mgr.play_sfx("player_death")

	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		game_mgr.player_hp_ratio = 0.0
		if game_mgr.has_method("on_player_death"):
			game_mgr.on_player_death()

	combat_ended.emit(get_combat_summary())
	current_enemies.clear()


## Use a skill on the enemy at the given index.
## AoE skills hit ALL alive enemies at reduced power.
## Returns the total damage dealt.
func player_use_skill(skill_id: String, enemy_index: int) -> float:
	if not is_in_combat:
		return 0.0
	if enemy_index < 0 or enemy_index >= current_enemies.size():
		return 0.0
	if not is_enemy_alive(enemy_index):
		return 0.0

	# Find the skill.
	var skill: Dictionary = {}
	for s in player_skills:
		if s["id"] == skill_id:
			skill = s
			break
	if skill.is_empty():
		return 0.0

	var is_aoe: bool = skill.get("aoe", false)
	var skill_elem: String = skill.get("element", "")
	var total_dmg: float = 0.0

	var sound_mgr := _get_autoload("SoundManager")

	if is_aoe:
		# Hit ALL alive enemies.
		for i in range(current_enemies.size()):
			if not is_enemy_alive(i):
				continue
			var e: Dictionary = current_enemies[i]
			var base_d: float = calculate_damage(player_attack, e["defense"])
			var dmg: float = base_d * skill.get("power", 0.6)
			dmg *= get_element_multiplier(skill_elem, str(e.get("element", "")))
			e["hp"] = maxf(0.0, e["hp"] - dmg)
			if e["hp"] < 1.0:
				e["hp"] = 0.0
			current_enemies[i] = e
			_total_damage_dealt += dmg
			total_dmg += dmg
			enemy_damaged.emit(i, dmg)
			if e["hp"] <= 0.0:
				_on_enemy_died(i)
		skill_used.emit(skill, enemy_index, total_dmg)
	else:
		# Single target skill.
		var enemy: Dictionary = current_enemies[enemy_index]
		var base_dmg: float = calculate_damage(player_attack, enemy["defense"])
		var skill_dmg: float = base_dmg * skill.get("power", 1.0)
		var elem_mult: float = get_element_multiplier(skill_elem, str(enemy.get("element", "")))
		skill_dmg *= elem_mult
		enemy["hp"] = maxf(0.0, enemy["hp"] - skill_dmg)
		if enemy["hp"] < 1.0:
			enemy["hp"] = 0.0
		current_enemies[enemy_index] = enemy
		_total_damage_dealt += skill_dmg
		total_dmg = skill_dmg
		enemy_damaged.emit(enemy_index, skill_dmg)
		skill_used.emit(skill, enemy_index, skill_dmg)
		if enemy["hp"] <= 0.0:
			_on_enemy_died(enemy_index)

	if sound_mgr != null and sound_mgr.has_method("play_sfx"):
		sound_mgr.play_sfx("attack_hit")

	if _all_enemies_dead():
		if player_hp <= 0.0:
			_on_player_died()
		else:
			end_combat()
	else:
		enemy_turn()

	return total_dmg


## Get the element damage multiplier (attacker vs defender).
func get_element_multiplier(atk_element: String, def_element: String) -> float:
	if atk_element.is_empty() or def_element.is_empty():
		return 1.0
	# Check weakness (1.5×).
	if ELEMENT_WEAKNESS.get(atk_element, "") == def_element:
		return 1.5
	# Check resistance (0.5×).
	if ELEMENT_RESIST.get(atk_element, "") == def_element:
		return 0.5
	return 1.0


## Refresh available skills based on player level.
func refresh_skills(player_level: int) -> void:
	player_skills.clear()
	for skill in SKILL_TABLE:
		if skill.get("level_req", 99) <= player_level:
			player_skills.append(skill.duplicate())


## Assign a thematic element to a monster based on its type and name.
func _assign_monster_element(monster_type: String, rank: String) -> String:
	# Type-based element mapping.
	match monster_type:
		"skeleton", "undead":
			return "dark"
		"ghost":
			return "dark"
		"slime":
			return "water"
		"cultist":
			return "dark"
		"elemental":
			return "fire"
		"golem":
			# Golems are earth-like; no dedicated earth element, so use ice (stone/cold).
			return "ice"
		"dragon":
			return "fire"
		"demon":
			return "dark"
		"bat":
			return "dark"
		"boss":
			# Bosses get a random element for variety.
			var elements: Array[String] = ["fire", "ice", "dark", "lightning"]
			return elements[randi() % elements.size()]
		_:
			# Random element for unknown types.
			var all_elems: Array[String] = ["fire", "ice", "water", "lightning", "dark", "holy"]
			return all_elems[randi() % all_elems.size()]


## Override element based on keywords in the monster's name.
## Called after type-based assignment to ensure name takes priority.
func _element_from_name(monster_name: String) -> String:
	var name_lower: String = monster_name
	# Fire keywords.
	if "화염" in name_lower or "불꽃" in name_lower or "용암" in name_lower \
		or "마그마" in name_lower or "화산" in name_lower or "화룡" in name_lower:
		return "fire"
	# Ice / Stone keywords (golems share ice since no earth element).
	if "얼음" in name_lower or "빙" in name_lower or "냉" in name_lower \
		or "서리" in name_lower or "동결" in name_lower \
		or "돌" in name_lower or "흑철" in name_lower or "골렘" in name_lower \
		or "흑요석" in name_lower or "수정" in name_lower:
		return "ice"
	# Lightning keywords.
	if "번개" in name_lower or "뇌" in name_lower or "전기" in name_lower \
		or "천둥" in name_lower:
		return "lightning"
	# Water keywords.
	if "물" in name_lower or "해일" in name_lower or "수" in name_lower \
		or "파도" in name_lower:
		return "water"
	# Holy keywords.
	if "신성" in name_lower or "성스러운" in name_lower or "천사" in name_lower \
		or "정화" in name_lower:
		return "holy"
	# Dark keywords.
	if "어둠" in name_lower or "암흑" in name_lower or "그림자" in name_lower \
		or "저주" in name_lower or "망자" in name_lower or "타락" in name_lower:
		return "dark"
	return ""


## Return true when every enemy in the encounter has 0 HP.
func _all_enemies_dead() -> bool:
	for e in current_enemies:
		if e["hp"] > 0.0:
			return false
	return true


## Roll random item drops from killed enemies and emit them via EventBus.
func _roll_random_drops(event_bus: Node) -> void:
	if event_bus == null:
		return
	for enemy in current_enemies:
		if enemy["hp"] > 0.0:
			continue
		var lvl: int = int(enemy.get("level", 1))
		var rank: String = str(enemy.get("rank", "normal"))

		# Drop chance: 35% normal, 65% elite, 100% boss/mini_boss
		var drop_chance: float = 0.35
		if rank == "elite":
			drop_chance = 0.65
		elif rank in ["boss", "mini_boss"]:
			drop_chance = 1.0

		if randf() > drop_chance:
			continue

		# Pick a random drop from the loot table.
		var drop: Dictionary = _generate_random_drop(lvl, rank)
		if not drop.is_empty():
			event_bus.item_picked_up.emit(drop)


## Generate a random item based on monster level and rank.
func _generate_random_drop(monster_level: int, rank: String) -> Dictionary:
	# Rarity roll: higher level/rank = better odds
	var roll: float = randf()
	var rarity_bonus: float = monster_level * 0.03
	if rank == "boss":
		rarity_bonus += 0.25
	elif rank == "mini_boss":
		rarity_bonus += 0.15
	elif rank == "elite":
		rarity_bonus += 0.08
	roll = maxf(0.0, roll - rarity_bonus)

	var rarity: String
	if roll < 0.05:
		rarity = "epic"
	elif roll < 0.15:
		rarity = "rare"
	elif roll < 0.35:
		rarity = "uncommon"
	else:
		rarity = "common"

	# Item type roll: 40% consumable, 30% weapon, 20% armor, 10% accessory
	var type_roll: float = randf()
	if type_roll < 0.4:
		return _make_consumable(rarity, monster_level)
	elif type_roll < 0.7:
		return _make_equipment("weapon", rarity, monster_level)
	elif type_roll < 0.9:
		return _make_equipment("armor", rarity, monster_level)
	else:
		return _make_equipment("accessory", rarity, monster_level)


func _make_consumable(rarity: String, level: int) -> Dictionary:
	var heal_amount: int = 0
	var item_name: String = ""
	match rarity:
		"common":
			heal_amount = 25 + level * 5
			item_name = "흐린 치유 물약 [회복 %d]" % heal_amount
		"uncommon":
			heal_amount = 40 + level * 8
			item_name = "맑은 치유 물약 [회복 %d]" % heal_amount
		_:  # rare, epic
			heal_amount = 60 + level * 10
			item_name = "활력의 영약 [회복 %d]" % heal_amount
	return {
		"id": "potion_%d_%d" % [level, randi()],
		"name": item_name,
		"type": "consumable",
		"rarity": rarity,
		"stats": {"heal": heal_amount},
	}


func _make_equipment(eq_type: String, rarity: String, level: int) -> Dictionary:
	var base_atk: float = 2.0 + level * 1.5
	var base_def: float = 1.5 + level * 1.0
	var rarity_mult: float = 1.0
	match rarity:
		"uncommon":
			rarity_mult = 1.4
		"rare":
			rarity_mult = 2.0
		"epic":
			rarity_mult = 3.0

	var names: Dictionary = {
		"weapon": {
			"common": ["녹슨 검", "낡은 도끼", "뼈 단검"],
			"uncommon": ["강화 장검", "독묻은 단도", "뼈 도끼"],
			"rare": ["심연의 검", "망자의 낫", "혼돈의 창"],
			"epic": ["파멸의 대검", "어둠의 지팡이", "영혼 포식자"],
		},
		"armor": {
			"common": ["가죽 조끼", "낡은 사슬갑옷"],
			"uncommon": ["강화 가죽갑옷", "사슬 갑옷 조각"],
			"rare": ["망자의 갑주", "심연의 로브"],
			"epic": ["파멸의 갑주", "고대 용의 비늘"],
		},
		"accessory": {
			"common": ["빛바랜 반지", "낡은 부적"],
			"uncommon": ["해독 부적", "힘의 반지"],
			"rare": ["피의 반지", "심연의 귀걸이"],
			"epic": ["심연왕의 왕관", "태고의 목걸이"],
		},
	}

	var name_pool: Array = names.get(eq_type, {}).get(rarity, ["알 수 없는 장비"])
	var item_name: String = name_pool[randi() % name_pool.size()]
	var stats: Dictionary = {}

	match eq_type:
		"weapon":
			stats["attack"] = int(base_atk * rarity_mult)
		"armor":
			stats["defense"] = int(base_def * rarity_mult)
		"accessory":
			stats["attack"] = int(base_atk * rarity_mult * 0.4)
			stats["defense"] = int(base_def * rarity_mult * 0.4)

	return {
		"id": "%s_%d_%d" % [eq_type, level, randi()],
		"name": item_name,
		"type": eq_type,
		"rarity": rarity,
		"stats": stats,
	}


## Safely retrieve an autoload node by name.
func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
