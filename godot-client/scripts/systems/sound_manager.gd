## Audio manager singleton.
##
## Register this script as an autoload named "SoundManager" in
## Project -> Project Settings -> Autoload.
## Manages BGM playback with crossfade and a pool of SFX players.
## Since actual audio files are not yet available, methods print placeholder
## messages indicating what would play.
extends Node

# ── Signals ──────────────────────────────────────────────────────────────────

signal bgm_changed(track_name: String)
signal sfx_played(sfx_name: String)

# ── Constants ────────────────────────────────────────────────────────────────

const SFX_POOL_SIZE: int = 5
const DEFAULT_CROSSFADE_TIME: float = 1.0

## Known BGM track names.
const BGM_TRACKS: Array = [
	"menu_bgm",
	"dungeon_bgm",
	"boss_bgm",
	"combat_bgm",
	"shop_bgm",
]

## Known SFX names.
const SFX_NAMES: Array = [
	"attack_hit",
	"attack_miss",
	"item_pickup",
	"door_open",
	"npc_talk",
	"quest_complete",
	"player_hurt",
	"player_death",
	"level_up",
	"gold_pickup",
]

# ── State ────────────────────────────────────────────────────────────────────

## AudioStreamPlayer for background music.
var bgm_player: AudioStreamPlayer = null

## Pool of AudioStreamPlayers for sound effects.
var sfx_players: Array[AudioStreamPlayer] = []

## Volume settings (0.0 – 1.0).
var master_volume: float = 0.8
var bgm_volume: float = 0.5
var sfx_volume: float = 0.7

## Name of the currently playing BGM track.
var current_bgm: String = ""

## Whether BGM is currently fading.
var _is_fading: bool = false

## Track name pending for crossfade.
var _pending_bgm_track: String = ""

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_create_audio_players()
	call_deferred("_deferred_connect_signals")


# ── Audio Player Setup ──────────────────────────────────────────────────────

func _create_audio_players() -> void:
	# BGM player.
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BGMPlayer"
	bgm_player.bus = "Master"
	bgm_player.volume_db = linear_to_db(bgm_volume * master_volume)
	add_child(bgm_player)

	# SFX player pool.
	for i in range(SFX_POOL_SIZE):
		var sfx: AudioStreamPlayer = AudioStreamPlayer.new()
		sfx.name = "SFXPlayer_%d" % i
		sfx.bus = "Master"
		sfx.volume_db = linear_to_db(sfx_volume * master_volume)
		add_child(sfx)
		sfx_players.append(sfx)


# ── Public API ───────────────────────────────────────────────────────────────

## Play a background music track.  Crossfades from the current track.
## [param track_name] One of the BGM_TRACKS constants.
func play_bgm(track_name: String) -> void:
	if track_name == current_bgm:
		return

	var previous_bgm: String = current_bgm
	current_bgm = track_name

	if not previous_bgm.is_empty():
		_crossfade_bgm(track_name)
	else:
		_start_bgm(track_name)

	bgm_changed.emit(track_name)


## Stop the current BGM with a fade-out.
func stop_bgm(fade_time: float = DEFAULT_CROSSFADE_TIME) -> void:
	if current_bgm.is_empty():
		return

	print("SoundManager: stopping BGM '%s' (fade %.1fs)" % [current_bgm, fade_time])

	if fade_time > 0.0 and bgm_player.playing:
		_is_fading = true
		var tween: Tween = create_tween()
		tween.tween_property(bgm_player, "volume_db", -80.0, fade_time)
		tween.tween_callback(_on_bgm_fade_out_done)
	else:
		bgm_player.stop()

	current_bgm = ""


## Play a sound effect from the pool.
## [param sfx_name] One of the SFX_NAMES constants.
## Per-SFX volume overrides (0.0–1.0 multiplier on top of sfx_volume).
const SFX_VOLUME_OVERRIDES: Dictionary = {
	"door_open": 0.35,
	"footstep_stone": 0.4,
	"ui_hover": 0.5,
}


func play_sfx(sfx_name: String) -> void:
	var stream: AudioStream = _load_sfx_stream(sfx_name)

	var player: AudioStreamPlayer = _get_available_sfx_player()
	if player == null:
		return

	if stream != null:
		player.stream = stream
		var vol_mult: float = SFX_VOLUME_OVERRIDES.get(sfx_name, 1.0)
		player.volume_db = linear_to_db(sfx_volume * master_volume * vol_mult)
		player.play()

	sfx_played.emit(sfx_name)


## Set the master volume (0.0 – 1.0) and update all players.
func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)
	_update_volumes()


## Set the BGM volume (0.0 – 1.0).
func set_bgm_volume(vol: float) -> void:
	bgm_volume = clampf(vol, 0.0, 1.0)
	_update_volumes()


## Set the SFX volume (0.0 – 1.0).
func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	_update_volumes()


# ── BGM Helpers ──────────────────────────────────────────────────────────────

func _start_bgm(track_name: String) -> void:
	var stream: AudioStream = _load_bgm_stream(track_name)
	if stream != null:
		bgm_player.stream = stream
		bgm_player.volume_db = linear_to_db(bgm_volume * master_volume)
		bgm_player.play()


## Load BGM stream (real asset or procedural fallback).
func _load_bgm_stream(track_name: String) -> AudioStream:
	return AssetRegistry.get_bgm_stream(track_name)


## Load SFX stream (real asset or procedural fallback).
func _load_sfx_stream(sfx_name: String) -> AudioStream:
	return AssetRegistry.get_sfx_stream(sfx_name)


func _crossfade_bgm(track_name: String) -> void:
	if _is_fading:
		return

	_is_fading = true
	_pending_bgm_track = track_name

	# Fade out current.
	var tween: Tween = create_tween()
	tween.tween_property(bgm_player, "volume_db", -80.0, DEFAULT_CROSSFADE_TIME * 0.5)
	tween.tween_callback(_on_crossfade_out_done)


func _on_bgm_fade_out_done() -> void:
	bgm_player.stop()
	bgm_player.volume_db = linear_to_db(bgm_volume * master_volume)
	_is_fading = false


func _on_crossfade_out_done() -> void:
	bgm_player.stop()
	_start_bgm(_pending_bgm_track)
	bgm_player.volume_db = -80.0

	var fade_in: Tween = create_tween()
	fade_in.tween_property(
		bgm_player, "volume_db",
		linear_to_db(bgm_volume * master_volume),
		DEFAULT_CROSSFADE_TIME * 0.5
	)
	fade_in.tween_callback(_on_crossfade_in_done)


func _on_crossfade_in_done() -> void:
	_is_fading = false


# ── SFX Helpers ──────────────────────────────────────────────────────────────

## Return the first SFX player that is not currently playing, or null.
func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in sfx_players:
		if not player.playing:
			return player
	# All busy – return the first one (it will be interrupted when actual audio plays).
	if sfx_players.size() > 0:
		return sfx_players[0]
	return null


# ── Volume Update ────────────────────────────────────────────────────────────

func _update_volumes() -> void:
	if bgm_player != null and not _is_fading:
		bgm_player.volume_db = linear_to_db(bgm_volume * master_volume)

	for player in sfx_players:
		player.volume_db = linear_to_db(sfx_volume * master_volume)


# ── EventBus Auto-Play ──────────────────────────────────────────────────────

func _deferred_connect_signals() -> void:
	var event_bus: Node = _get_autoload("EventBus")
	if event_bus == null:
		push_warning("SoundManager: EventBus not available – auto-play disabled.")
		return

	# Combat events.
	if event_bus.has_signal("monster_killed"):
		event_bus.monster_killed.connect(_on_monster_killed)
	if event_bus.has_signal("player_damaged"):
		event_bus.player_damaged.connect(_on_player_damaged)
	if event_bus.has_signal("player_healed"):
		event_bus.player_healed.connect(_on_player_healed)
	if event_bus.has_signal("player_died"):
		event_bus.player_died.connect(_on_player_died)

	# Item events.
	if event_bus.has_signal("item_picked_up"):
		event_bus.item_picked_up.connect(_on_item_picked_up)
	if event_bus.has_signal("item_used"):
		event_bus.item_used.connect(_on_item_used)

	# Dungeon events.
	if event_bus.has_signal("room_entered"):
		event_bus.room_entered.connect(_on_room_entered)

	# NPC events.
	if event_bus.has_signal("npc_talked"):
		event_bus.npc_talked.connect(_on_npc_talked)

	# Quest events.
	if event_bus.has_signal("quest_completed"):
		event_bus.quest_completed.connect(_on_quest_completed)

	# Gold events.
	if event_bus.has_signal("gold_changed"):
		event_bus.gold_changed.connect(_on_gold_changed)


func _on_monster_killed(_monster_data: Dictionary) -> void:
	play_sfx("attack_hit")


func _on_player_damaged(_amount: float) -> void:
	play_sfx("player_hurt")


func _on_player_healed(_amount: float) -> void:
	# No dedicated heal SFX in the list; use item_pickup as a placeholder.
	play_sfx("item_pickup")


func _on_player_died() -> void:
	play_sfx("player_death")


func _on_item_picked_up(_item_data: Dictionary) -> void:
	play_sfx("item_pickup")


func _on_item_used(_item_data: Dictionary) -> void:
	play_sfx("item_pickup")


func _on_room_entered(room_data: Dictionary) -> void:
	var room_type: String = room_data.get("type", "")
	if room_type in ["combat", "boss", "mini_boss"]:
		# Combat BGM is handled by CombatSystem.
		pass
	elif room_type == "shop":
		play_bgm("shop_bgm")
		play_sfx("door_open")
	else:
		# Play dungeon ambient BGM if not already playing.
		play_bgm("dungeon_bgm")
		play_sfx("door_open")


func _on_npc_talked(_npc_id: String, _affinity: int) -> void:
	play_sfx("npc_talk")


func _on_quest_completed(_quest_data: Dictionary) -> void:
	play_sfx("quest_complete")


func _on_gold_changed(_new_amount: int, change: int) -> void:
	if change > 0:
		play_sfx("gold_pickup")


# ── Helpers ──────────────────────────────────────────────────────────────────

## Safely retrieve an autoload node by name.
func _get_autoload(autoload_name: String) -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var root: Window = tree.root
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
