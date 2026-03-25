## Root scene controller that manages game flow and scene transitions.
##
## Coordinates Menu -> Game -> Game Over states and instantiates all
## major UI overlays.  Intended to be the root node of the main scene.
class_name MainScene
extends Node

# ── Game States ──────────────────────────────────────────────────────────────

enum State { MENU, PLAYING, PAUSED, GAME_OVER }

# ── Properties ───────────────────────────────────────────────────────────────

var current_state: State = State.MENU

# ── UI References ────────────────────────────────────────────────────────────

var _main_menu: MainMenu
var _game_hud: GameHUD
var _loading_screen: LoadingScreen
var _quest_log_ui: QuestLogUI
var _quest_hud: QuestHUD
var _npc_dialogue_ui: NPCDialogueUI
var _pause_menu: PauseMenu
var _death_screen: DeathScreen
var _combat_ui: CombatUI
var _inventory_ui: InventoryUI
var _floor_transition: FloorTransition
var _settings_ui: SettingsUI

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_instantiate_ui()
	_connect_signals()
	_show_main_menu()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_handle_escape()
			KEY_TAB:
				_handle_tab()


# ── UI Instantiation ────────────────────────────────────────────────────────

func _instantiate_ui() -> void:
	# Main menu.
	_main_menu = MainMenu.new()
	_main_menu.name = "MainMenu"
	add_child(_main_menu)

	# Game HUD (hidden until gameplay starts).
	_game_hud = GameHUD.new()
	_game_hud.name = "GameHUD"
	_game_hud.visible = false
	add_child(_game_hud)

	# Loading screen.
	_loading_screen = LoadingScreen.new()
	_loading_screen.name = "LoadingScreen"
	add_child(_loading_screen)

	# Quest HUD (top-right tracker, hidden until gameplay).
	_quest_hud = QuestHUD.new()
	_quest_hud.name = "QuestHUD"
	_quest_hud.visible = false
	add_child(_quest_hud)

	# Quest log overlay (toggled with Tab).
	_quest_log_ui = QuestLogUI.new()
	_quest_log_ui.name = "QuestLogUI"
	add_child(_quest_log_ui)

	# NPC dialogue overlay.
	_npc_dialogue_ui = NPCDialogueUI.new()
	_npc_dialogue_ui.name = "NPCDialogueUI"
	add_child(_npc_dialogue_ui)

	# Pause menu.
	_pause_menu = PauseMenu.new()
	_pause_menu.name = "PauseMenu"
	add_child(_pause_menu)

	# Death screen.
	_death_screen = DeathScreen.new()
	_death_screen.name = "DeathScreen"
	add_child(_death_screen)

	# Combat UI overlay.
	_combat_ui = CombatUI.new()
	_combat_ui.name = "CombatUI"
	add_child(_combat_ui)

	# Inventory UI overlay.
	_inventory_ui = InventoryUI.new()
	_inventory_ui.name = "InventoryUI"
	add_child(_inventory_ui)

	# Floor transition (listens for boss_defeated via EventBus).
	_floor_transition = FloorTransition.new()
	_floor_transition.name = "FloorTransition"
	add_child(_floor_transition)

	# Settings UI (AI server config).
	_settings_ui = SettingsUI.new()
	_settings_ui.name = "SettingsUI"
	add_child(_settings_ui)


# ── Signal Wiring ────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	# Main menu signals.
	_main_menu.new_game_requested.connect(_on_new_game_requested)
	_main_menu.continue_requested.connect(_on_continue_requested)

	# Main menu settings.
	_main_menu.settings_requested.connect(_on_settings_requested)

	# Pause menu signals.
	_pause_menu.resume_requested.connect(resume_game)
	_pause_menu.menu_requested.connect(return_to_menu)
	_pause_menu.settings_requested.connect(_on_settings_requested)

	# Death screen signals.
	_death_screen.retry_requested.connect(_on_retry_requested)
	_death_screen.menu_requested.connect(return_to_menu)

	# Connect to EventBus for player death.
	call_deferred("_deferred_connect_event_bus")


func _deferred_connect_event_bus() -> void:
	var event_bus := _get_autoload("EventBus")
	if event_bus != null and event_bus.has_signal("player_died"):
		event_bus.player_died.connect(_on_player_died)

	# Try to connect CombatUI to the player's CombatSystem once the player spawns.
	# We retry until the player appears in the tree.
	_try_connect_combat_ui()


func _try_connect_combat_ui() -> void:
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player == null:
		# Player not spawned yet — retry after a short delay.
		get_tree().create_timer(1.0).timeout.connect(_try_connect_combat_ui)
		return

	var combat_sys: Node = player.get_node_or_null("CombatSystem")
	if combat_sys == null:
		get_tree().create_timer(1.0).timeout.connect(_try_connect_combat_ui)
		return

	# Connect CombatSystem signals → CombatUI.
	if not combat_sys.combat_started.is_connected(_on_combat_started):
		combat_sys.combat_started.connect(_on_combat_started)
	if not combat_sys.combat_ended.is_connected(_on_combat_ended_ui):
		combat_sys.combat_ended.connect(_on_combat_ended_ui)
	if not combat_sys.enemy_damaged.is_connected(_on_enemy_damaged_ui):
		combat_sys.enemy_damaged.connect(_on_enemy_damaged_ui)
	if not combat_sys.player_turn_started.is_connected(_on_player_turn_ui):
		combat_sys.player_turn_started.connect(_on_player_turn_ui)
	if not combat_sys.enemy_turn_started.is_connected(_on_enemy_turn_ui):
		combat_sys.enemy_turn_started.connect(_on_enemy_turn_ui)

	# Connect CombatUI signals → CombatSystem.
	if not _combat_ui.attack_requested.is_connected(_on_ui_attack):
		_combat_ui.attack_requested.connect(_on_ui_attack)
	if not _combat_ui.flee_requested.is_connected(_on_ui_flee):
		_combat_ui.flee_requested.connect(_on_ui_flee)
	if not _combat_ui.item_use_requested.is_connected(_on_ui_item_use):
		_combat_ui.item_use_requested.connect(_on_ui_item_use)
	if not _combat_ui.skill_requested.is_connected(_on_ui_skill):
		_combat_ui.skill_requested.connect(_on_ui_skill)

	print("MainScene: CombatUI connected to CombatSystem.")


# ── Public API ───────────────────────────────────────────────────────────────

## Initialize game systems and start a fresh run from floor 1.
func start_game() -> void:
	current_state = State.PLAYING
	get_tree().paused = false

	# Hide menu, show gameplay UI.
	_main_menu.visible = false
	_game_hud.visible = true
	_quest_hud.visible = true
	_death_screen.visible = false

	# Initialize via GameManager.
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null and game_mgr.has_method("start_new_game"):
		_loading_screen.show_dungeon_loading()
		game_mgr.start_new_game()

		# Update HUD with initial state (read HP from game manager ratio).
		var base_hp: float = 100.0 + game_mgr.upgrade_hp * 10.0  # Match CombatSystem base
		_game_hud.update_hp(base_hp, base_hp)
		_game_hud.update_level(1)
		_game_hud.update_gold(0)
		_game_hud.update_floor(1, "망자의 회랑 1층")
	else:
		push_warning("MainScene: GameManager not available – cannot start game.")


## Pause the game and show the pause menu.
func pause_game() -> void:
	if current_state != State.PLAYING:
		return

	current_state = State.PAUSED
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_pause_menu.show_pause()


## Unpause the game and hide the pause menu.
func resume_game() -> void:
	if current_state != State.PAUSED:
		return

	current_state = State.PLAYING
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_pause_menu.hide_pause()


## Show the death screen with game statistics.
func game_over() -> void:
	current_state = State.GAME_OVER
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_game_hud.visible = false
	_quest_hud.visible = false

	# Gather stats from GameManager and PlayerTracker.
	var stats: Dictionary = _gather_death_stats()
	_death_screen.show_death(stats)


## Return to the main menu from any state.
func return_to_menu() -> void:
	current_state = State.MENU
	get_tree().paused = false

	# Hide all gameplay UI.
	_game_hud.visible = false
	_quest_hud.visible = false
	_pause_menu.visible = false
	_death_screen.visible = false

	if _quest_log_ui.is_open:
		_quest_log_ui.toggle()
	if _npc_dialogue_ui.is_open:
		_npc_dialogue_ui.close_dialogue()

	_show_main_menu()


# ── Input Handlers ───────────────────────────────────────────────────────────

func _handle_escape() -> void:
	match current_state:
		State.PLAYING:
			# Don't pause during combat — combat UI handles its own flow.
			var cs: Node = _get_combat_system()
			if cs != null and cs.get("is_in_combat"):
				return
			# Check if NPC dialogue is open first.
			if _npc_dialogue_ui.is_open:
				_npc_dialogue_ui.close_dialogue()
			elif _quest_log_ui.is_open:
				_quest_log_ui.toggle()
			elif _inventory_ui.visible:
				_inventory_ui.visible = false
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				pause_game()
		State.PAUSED:
			resume_game()
		_:
			pass  # Menu and game-over states handle Escape internally.


func _handle_tab() -> void:
	if current_state == State.PLAYING:
		# Quest log handles its own Tab toggle via _unhandled_input,
		# but we guard against opening it during NPC dialogue.
		if _npc_dialogue_ui.is_open:
			return
		# Quest log toggle is handled by QuestLogUI._unhandled_input.


# ── Signal Handlers ──────────────────────────────────────────────────────────

func _on_new_game_requested() -> void:
	start_game()


func _on_continue_requested() -> void:
	current_state = State.PLAYING
	get_tree().paused = false

	_main_menu.visible = false
	_game_hud.visible = true
	_quest_hud.visible = true
	_death_screen.visible = false

	# Load saved game state.
	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		if game_mgr.has_method("load_game"):
			game_mgr.load_game()

		# Update HUD from loaded state.
		var floor_num: int = game_mgr.get("current_floor") if "current_floor" in game_mgr else 1
		var level: int = game_mgr.get("player_level") if "player_level" in game_mgr else 1
		var gold: int = game_mgr.get("player_gold") if "player_gold" in game_mgr else 0
		var hp_ratio: float = game_mgr.get("player_hp_ratio") if "player_hp_ratio" in game_mgr else 1.0

		_game_hud.update_level(level)
		_game_hud.update_gold(gold)
		_game_hud.update_hp(hp_ratio * 100.0, 100.0)
		_game_hud.update_floor(floor_num, "%d층" % floor_num)

		# Resume the floor.
		if game_mgr.has_method("start_floor"):
			_loading_screen.show_dungeon_loading()
			game_mgr.start_floor(floor_num)


func _on_settings_requested() -> void:
	_settings_ui.show_settings()


func _on_retry_requested() -> void:
	start_game()


func _on_player_died() -> void:
	if _combat_ui != null:
		_combat_ui.hide_combat()
	game_over()


# ── Combat UI Integration ────────────────────────────────────────────────────

func _get_combat_system() -> Node:
	var player: Node = get_tree().root.find_child("Player", true, false)
	if player != null:
		return player.get_node_or_null("CombatSystem")
	return null


func _on_combat_started(enemies: Array) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_combat_ui.show_combat(enemies)
	var cs: Node = _get_combat_system()
	if cs != null:
		_combat_ui.update_player_hp(cs.player_hp, cs.player_max_hp)
		_combat_ui.update_player_stats(cs.player_attack, cs.player_defense)


func _on_combat_ended_ui(_summary: Dictionary) -> void:
	_combat_ui.hide_combat()
	# Do NOT recapture mouse if the player died (death screen needs it).
	if current_state != State.GAME_OVER:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_enemy_damaged_ui(enemy_index: int, damage: float) -> void:
	var cs: Node = _get_combat_system()
	if cs == null:
		return
	var enemies: Array = cs.current_enemies
	if enemy_index < enemies.size():
		var e: Dictionary = enemies[enemy_index]
		_combat_ui.update_enemy_hp(enemy_index, e.get("hp", 0.0), e.get("max_hp", 50.0))
		_combat_ui.add_damage_log("플레이어", e.get("name", "적"), damage)
	_combat_ui.update_player_hp(cs.player_hp, cs.player_max_hp)


func _on_player_turn_ui() -> void:
	_combat_ui.set_player_turn(true)
	var cs: Node = _get_combat_system()
	if cs != null:
		_combat_ui.update_player_hp(cs.player_hp, cs.player_max_hp)


func _on_enemy_turn_ui() -> void:
	_combat_ui.set_player_turn(false)
	var cs: Node = _get_combat_system()
	if cs == null:
		return
	# Log enemy attacks.
	for e in cs.current_enemies:
		if e.get("hp", 0.0) > 0.0:
			var dmg: float = cs.calculate_damage(e.get("attack", 8.0), cs.player_defense)
			_combat_ui.add_damage_log(e.get("name", "적"), "플레이어", dmg)
	_combat_ui.update_player_hp(cs.player_hp, cs.player_max_hp)


func _on_ui_attack(enemy_index: int) -> void:
	var cs: Node = _get_combat_system()
	if cs != null and cs.has_method("player_attack_enemy"):
		cs.player_attack_enemy(enemy_index)


func _on_ui_skill(skill_id: String, enemy_index: int) -> void:
	var cs: Node = _get_combat_system()
	if cs == null or not cs.is_in_combat:
		return
	if not cs.has_method("player_use_skill"):
		return

	# Find skill info for logging.
	var skill_name: String = skill_id
	var skill_elem: String = ""
	for s in cs.player_skills:
		if s.get("id", "") == skill_id:
			skill_name = s.get("name", skill_id)
			skill_elem = s.get("element", "")
			break

	var damage: float = cs.player_use_skill(skill_id, enemy_index)
	if damage > 0.0:
		var enemies: Array = cs.current_enemies
		var target_name: String = "적"
		if enemy_index < enemies.size():
			target_name = enemies[enemy_index].get("name", "적")
			_combat_ui.update_enemy_hp(enemy_index, enemies[enemy_index].get("hp", 0.0), enemies[enemy_index].get("max_hp", 50.0))

		# Check element effectiveness.
		var enemy_elem: String = ""
		if enemy_index < enemies.size():
			enemy_elem = str(enemies[enemy_index].get("element", ""))
		var mult: float = cs.get_element_multiplier(skill_elem, enemy_elem)
		var effectiveness: String = ""
		if mult > 1.0:
			effectiveness = " [color=#ebca42](효과적!)[/color]"
		elif mult < 1.0:
			effectiveness = " [color=#888888](저항...)[/color]"

		_combat_ui.add_combat_log("[color=#4fc3f7]%s! %s에게 %d 피해!%s[/color]" % [skill_name, target_name, int(damage), effectiveness])
		_combat_ui.update_player_hp(cs.player_hp, cs.player_max_hp)


func _on_ui_item_use(item: Dictionary) -> void:
	var cs: Node = _get_combat_system()
	if cs == null or not cs.is_in_combat:
		return
	var heal: float = float(item.get("stats", {}).get("heal", item.get("heal", 0.0)))
	var item_name: String = item.get("name", "아이템")
	cs.use_item_in_combat(item)
	if heal > 0.0:
		_combat_ui.add_heal_log("플레이어", heal)
		_combat_ui.update_player_hp(cs.player_hp, cs.player_max_hp)
	_combat_ui.add_combat_log("[color=#4dcc66]%s 사용![/color]" % item_name)


func _on_ui_flee() -> void:
	var cs: Node = _get_combat_system()
	if cs != null and cs.has_method("attempt_flee"):
		var success: bool = cs.attempt_flee()
		if success:
			_combat_ui.add_combat_log("[color=#4dcc66]도주 성공![/color]")
		else:
			_combat_ui.add_combat_log("[color=#e64d4d]도주 실패! 적의 공격![/color]")


# ── Private Helpers ──────────────────────────────────────────────────────────

func _show_main_menu() -> void:
	_main_menu.visible = true
	_main_menu._check_save_exists()
	_main_menu._check_server_health()


func _gather_death_stats() -> Dictionary:
	var stats: Dictionary = {
		"floor": 1,
		"monsters_killed": 0,
		"gold_earned": 0,
		"play_time_seconds": 0.0,
		"quests_completed": 0,
		"item_gold": 0,
		"gold_retained": 0,
	}

	var game_mgr := _get_autoload("GameManager")
	if game_mgr != null:
		stats["floor"] = game_mgr.get("current_floor") if "current_floor" in game_mgr else 1
		stats["gold_earned"] = game_mgr.get("player_gold") if "player_gold" in game_mgr else 0

		# Calculate item liquidation value (same formula as GameManager.on_player_death).
		var inv := _get_autoload("InventorySystem")
		if inv != null:
			var item_gold: int = 0
			for item: Variant in inv.items:
				if item is Dictionary:
					var d: Dictionary = item as Dictionary
					var base_price: int = int(d.get("price", d.get("value", 0)))
					if base_price <= 0:
						var item_stats: Dictionary = d.get("stats", {})
						base_price = int(item_stats.get("attack", 0)) * 8 + int(item_stats.get("defense", 0)) * 8 + int(item_stats.get("heal", 0)) * 2
					item_gold += maxi(1, base_price / 2)
			stats["item_gold"] = item_gold

		var total_run_gold: int = int(stats["gold_earned"]) + int(stats["item_gold"])
		stats["gold_retained"] = total_run_gold

	var tracker := _get_autoload("PlayerTracker")
	if tracker != null:
		# Estimate play time from floor clear times.
		var clear_times: Array = tracker.get("floor_clear_times") if "floor_clear_times" in tracker else []
		var total_time: float = 0.0
		for t in clear_times:
			total_time += float(t)
		stats["play_time_seconds"] = total_time

	var quest_mgr := _get_autoload("QuestManager")
	if quest_mgr != null:
		var completed: Array = quest_mgr.get("completed_quests") if "completed_quests" in quest_mgr else []
		stats["quests_completed"] = completed.size()

	return stats


func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
