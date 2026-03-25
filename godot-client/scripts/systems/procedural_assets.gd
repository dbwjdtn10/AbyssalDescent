## Procedural asset factory – generates placeholder 3D models, textures, and
## audio at runtime so the game runs without external asset downloads.
##
## All assets are cached after first creation.  When real assets are later
## placed in res://assets/, AssetRegistry will load those instead and this
## factory is never called.
class_name ProceduralAssets
extends RefCounted

const MIX_RATE: int = 22050
const ICON_SIZE: int = 32
const PARTICLE_SIZE: int = 16

static var _model_cache: Dictionary = {}
static var _tex_cache: Dictionary = {}
static var _audio_cache: Dictionary = {}

# ── Monster configs ──────────────────────────────────────────────────────────
# shape: "capsule" | "sphere" | "box" | "cylinder"
# acc:   "sword" | "staff" | "shield" | "" (none)
# eyes:  true adds glowing eyes, eye_color overrides default red
# arms:  true adds simple arm stubs (humanoid shapes)
# horns: int — number of horn pairs (boss crowns)
# spikes: int — number of spike protrusions
# Optional: emit (Color), emit_e (float), alpha (float), y_off (float)

static var _monsters: Dictionary = {
	# ── Fallback dungeon template types (exact match keys) ─────────────
	"skeleton":     {"shape":"capsule","color":Color(0.92,0.88,0.72),"h":1.8,"r":0.3,"acc":"sword","eyes":true,"eye_color":Color(1.0,0.3,0.1),"arms":true},
	"ghost":        {"shape":"capsule","color":Color(0.6,0.7,0.9),"h":1.7,"r":0.35,"alpha":0.4,"emit":Color(0.5,0.6,0.9),"emit_e":2.0,"y_off":0.4,"eyes":true,"eye_color":Color(0.8,0.9,1.0)},
	"slime":        {"shape":"sphere","color":Color(0.2,0.8,0.15),"h":0.7,"r":0.5,"alpha":0.75,"emit":Color(0.1,0.9,0.0),"eyes":true,"eye_color":Color(1.0,1.0,0.2)},
	"cultist":      {"shape":"capsule","color":Color(0.25,0.1,0.15),"h":1.85,"r":0.32,"acc":"staff","eyes":true,"eye_color":Color(0.8,0.0,0.3),"arms":true},
	"undead":       {"shape":"capsule","color":Color(0.45,0.5,0.35),"h":1.75,"r":0.38,"acc":"sword","eyes":true,"eye_color":Color(0.6,1.0,0.2),"arms":true},
	"golem":        {"shape":"box","color":Color(0.5,0.45,0.4),"h":2.2,"r":0.6,"eyes":true,"eye_color":Color(1.0,0.6,0.0),"emit_e":1.5,"spikes":3},
	"bat":          {"shape":"sphere","color":Color(0.2,0.15,0.25),"h":0.6,"r":0.3,"eyes":true,"eye_color":Color(1.0,0.0,0.0),"y_off":1.5},
	"elemental":    {"shape":"sphere","color":Color(1.0,0.5,0.1),"h":1.5,"r":0.5,"emit":Color(1.0,0.4,0.0),"emit_e":3.0,"eyes":true,"eye_color":Color(1.0,1.0,0.5)},
	"dragon":       {"shape":"capsule","color":Color(0.6,0.15,0.05),"h":2.4,"r":0.55,"emit":Color(0.8,0.2,0.0),"emit_e":1.5,"eyes":true,"eye_color":Color(1.0,0.8,0.0),"horns":2,"arms":true},
	"demon":        {"shape":"capsule","color":Color(0.35,0.05,0.1),"h":2.0,"r":0.4,"emit":Color(0.6,0.0,0.1),"emit_e":1.5,"eyes":true,"eye_color":Color(1.0,0.0,0.0),"horns":1,"arms":true,"acc":"sword"},
	"boss":         {"shape":"capsule","color":Color(0.2,0.05,0.2),"h":3.2,"r":0.7,"emit":Color(0.6,0.0,0.8),"emit_e":3.0,"eyes":true,"eye_color":Color(1.0,0.0,0.5),"horns":3,"arms":true,"acc":"sword"},
	# ── Catacombs theme (detailed types) ───────────────────────────────
	"skeleton_warrior":  {"shape":"capsule","color":Color(0.9,0.85,0.7),"h":1.8,"r":0.35,"acc":"sword","eyes":true,"eye_color":Color(1.0,0.3,0.1),"arms":true},
	"ghoul":             {"shape":"capsule","color":Color(0.4,0.55,0.3),"h":1.4,"r":0.45,"eyes":true,"eye_color":Color(0.8,1.0,0.2),"arms":true},
	"skeleton_mage":     {"shape":"capsule","color":Color(0.85,0.85,0.95),"h":1.8,"r":0.3,"emit":Color(0.3,0.3,0.9),"acc":"staff","eyes":true,"arms":true},
	"wraith":            {"shape":"capsule","color":Color(0.6,0.7,0.85),"h":1.8,"r":0.35,"alpha":0.5,"emit":Color(0.4,0.5,0.8),"y_off":0.3,"eyes":true,"eye_color":Color(0.8,0.9,1.0)},
	# ── Abyss theme ───────────────────────────────────────────────────
	"abyss_watcher":     {"shape":"capsule","color":Color(0.3,0.1,0.4),"h":2.0,"r":0.35,"emit":Color(0.5,0.0,0.7),"eyes":true,"eye_color":Color(0.8,0.0,1.0),"arms":true},
	"void_tentacle":     {"shape":"cylinder","color":Color(0.2,0.05,0.3),"h":2.5,"r":0.15,"emit":Color(0.3,0.0,0.5),"spikes":4},
	"shadow_stalker":    {"shape":"capsule","color":Color(0.15,0.15,0.2),"h":1.7,"r":0.25,"eyes":true,"eye_color":Color(1.0,0.0,0.3)},
	"abyss_screamer":    {"shape":"capsule","color":Color(0.4,0.05,0.15),"h":1.6,"r":0.4,"emit":Color(0.6,0.0,0.2),"eyes":true,"arms":true},
	# ── Fire theme ────────────────────────────────────────────────────
	"fire_elemental":    {"shape":"sphere","color":Color(1.0,0.4,0.05),"h":1.5,"r":0.5,"emit":Color(1.0,0.3,0.0),"emit_e":3.0,"eyes":true,"eye_color":Color(1.0,1.0,0.5)},
	"lava_golem":        {"shape":"box","color":Color(0.3,0.1,0.05),"h":2.2,"r":0.6,"emit":Color(1.0,0.2,0.0),"emit_e":2.0,"eyes":true,"spikes":2},
	"fire_bat_swarm":    {"shape":"sphere","color":Color(0.8,0.2,0.1),"h":0.8,"r":0.25,"emit":Color(1.0,0.4,0.0),"eyes":true,"y_off":1.2},
	"fire_priest":       {"shape":"capsule","color":Color(0.7,0.2,0.1),"h":1.8,"r":0.3,"emit":Color(0.8,0.2,0.0),"acc":"staff","eyes":true,"arms":true},
	# ── Ice theme ─────────────────────────────────────────────────────
	"frost_spider":      {"shape":"sphere","color":Color(0.6,0.8,0.95),"h":0.8,"r":0.5,"emit":Color(0.3,0.6,0.9),"eyes":true,"eye_color":Color(0.5,0.8,1.0)},
	"ice_golem":         {"shape":"box","color":Color(0.7,0.85,0.95),"h":2.2,"r":0.6,"emit":Color(0.4,0.7,1.0),"eyes":true,"spikes":3},
	"frost_wraith":      {"shape":"capsule","color":Color(0.7,0.85,0.95),"h":1.8,"r":0.35,"alpha":0.5,"emit":Color(0.5,0.7,1.0),"eyes":true,"eye_color":Color(0.7,0.9,1.0)},
	"cryo_mage":         {"shape":"capsule","color":Color(0.4,0.6,0.85),"h":1.8,"r":0.3,"emit":Color(0.3,0.5,0.9),"acc":"staff","eyes":true,"arms":true},
	# ── Corruption theme ──────────────────────────────────────────────
	"mutant":            {"shape":"capsule","color":Color(0.3,0.5,0.15),"h":1.6,"r":0.5,"emit":Color(0.4,0.7,0.1),"eyes":true,"arms":true,"spikes":2},
	"corrupted_knight":  {"shape":"capsule","color":Color(0.4,0.1,0.1),"h":1.9,"r":0.4,"emit":Color(0.5,0.0,0.0),"acc":"sword","eyes":true,"arms":true},
	"spore_beast":       {"shape":"sphere","color":Color(0.3,0.5,0.2),"h":1.2,"r":0.5,"emit":Color(0.2,0.6,0.1),"emit_e":2.0,"eyes":true,"spikes":5},
	"toxic_slime":       {"shape":"sphere","color":Color(0.2,0.8,0.1),"h":0.6,"r":0.5,"alpha":0.7,"emit":Color(0.1,0.9,0.0),"eyes":true,"eye_color":Color(1.0,1.0,0.0)},
	# ── Bosses (larger, stronger glow, horns/crown) ───────────────────
	"boss_bone_lord":      {"shape":"capsule","color":Color(0.95,0.9,0.75),"h":3.0,"r":0.6,"emit":Color(0.8,0.6,0.2),"emit_e":2.0,"acc":"sword","eyes":true,"eye_color":Color(1.0,0.5,0.0),"horns":2,"arms":true},
	"boss_void_mother":    {"shape":"sphere","color":Color(0.15,0.0,0.2),"h":3.0,"r":1.0,"emit":Color(0.5,0.0,0.8),"emit_e":3.0,"eyes":true,"eye_color":Color(0.8,0.0,1.0),"spikes":6},
	"boss_flame_tyrant":   {"shape":"box","color":Color(0.4,0.1,0.0),"h":3.5,"r":0.8,"emit":Color(1.0,0.3,0.0),"emit_e":4.0,"eyes":true,"eye_color":Color(1.0,0.9,0.2),"horns":3,"arms":true},
	"boss_frozen_empress": {"shape":"capsule","color":Color(0.8,0.9,1.0),"h":2.8,"r":0.5,"emit":Color(0.5,0.8,1.0),"emit_e":3.0,"acc":"staff","eyes":true,"eye_color":Color(0.5,0.8,1.0),"horns":1,"arms":true},
	# ── Default fallback ──────────────────────────────────────────────
	"default":             {"shape":"capsule","color":Color(0.7,0.2,0.2),"h":1.8,"r":0.4,"eyes":true},
}

# ── NPC configs ──────────────────────────────────────────────────────────────

static var _npcs: Dictionary = {
	"wandering_merchant":  {"shape":"capsule","color":Color(0.2,0.6,0.3),"h":1.7,"r":0.35,"eyes":true,"eye_color":Color(0.9,0.9,0.7),"arms":true,"hat":"flat"},
	"captive_adventurer":  {"shape":"capsule","color":Color(0.3,0.4,0.7),"h":1.8,"r":0.35,"acc":"sword","eyes":true,"eye_color":Color(0.6,0.8,1.0),"arms":true},
	"mysterious_sage":     {"shape":"capsule","color":Color(0.5,0.3,0.6),"h":1.8,"r":0.3,"emit":Color(0.4,0.2,0.6),"acc":"staff","eyes":true,"eye_color":Color(0.7,0.5,1.0),"arms":true,"hat":"pointed"},
	"fallen_knight":       {"shape":"capsule","color":Color(0.25,0.25,0.3),"h":1.9,"r":0.4,"acc":"sword","eyes":true,"eye_color":Color(0.8,0.2,0.2),"arms":true},
	"merchant":            {"shape":"capsule","color":Color(0.2,0.6,0.3),"h":1.7,"r":0.35,"eyes":true,"eye_color":Color(0.9,0.9,0.7),"arms":true,"hat":"flat"},
	"sage":                {"shape":"capsule","color":Color(0.5,0.3,0.6),"h":1.8,"r":0.3,"emit":Color(0.4,0.2,0.6),"acc":"staff","eyes":true,"eye_color":Color(0.7,0.5,1.0),"arms":true,"hat":"pointed"},
	"blacksmith":          {"shape":"capsule","color":Color(0.4,0.3,0.25),"h":1.9,"r":0.45,"eyes":true,"eye_color":Color(0.9,0.7,0.4),"arms":true},
	"ghost_npc":           {"shape":"capsule","color":Color(0.6,0.7,0.85),"h":1.7,"r":0.32,"alpha":0.45,"emit":Color(0.5,0.6,0.9),"eyes":true,"eye_color":Color(0.8,0.9,1.0),"y_off":0.3},
}

# ── Weapon configs ───────────────────────────────────────────────────────────
# bs: blade size, gs: guard size, hl: handle length, bc: blade color

static var _weapons: Dictionary = {
	"sword":      {"bs":Vector3(0.06,0.5,0.03),"gs":Vector3(0.18,0.04,0.04),"hl":0.15,"bc":Color(0.8,0.8,0.85)},
	"greatsword": {"bs":Vector3(0.08,0.7,0.04),"gs":Vector3(0.24,0.05,0.05),"hl":0.2,"bc":Color(0.75,0.75,0.8)},
	"axe":        {"bs":Vector3(0.2,0.25,0.03),"gs":Vector3(0.04,0.04,0.04),"hl":0.35,"bc":Color(0.6,0.6,0.65)},
	"dagger":     {"bs":Vector3(0.04,0.2,0.02),"gs":Vector3(0.1,0.03,0.03),"hl":0.08,"bc":Color(0.8,0.8,0.85)},
	"spear":      {"bs":Vector3(0.06,0.15,0.02),"gs":Vector3(0.02,0.02,0.02),"hl":0.8,"bc":Color(0.7,0.7,0.75)},
	"bow":        {"bs":Vector3(0.03,0.5,0.03),"gs":Vector3(0.01,0.01,0.01),"hl":0.0,"bc":Color(0.5,0.35,0.15)},
	"staff":      {"bs":Vector3(0.03,0.05,0.03),"gs":Vector3(0.01,0.01,0.01),"hl":0.7,"bc":Color(0.4,0.3,0.6),"orb":true},
	"mace":       {"bs":Vector3(0.12,0.12,0.12),"gs":Vector3(0.02,0.02,0.02),"hl":0.3,"bc":Color(0.55,0.55,0.6),"sphere_head":true},
	"scythe":     {"bs":Vector3(0.25,0.08,0.02),"gs":Vector3(0.02,0.02,0.02),"hl":0.6,"bc":Color(0.3,0.3,0.35)},
}

# ── Pickup configs ───────────────────────────────────────────────────────────

static var _pickups: Dictionary = {
	"potion": {"shape":"cylinder","color":Color(0.8,0.1,0.2),"h":0.2,"r":0.06},
	"scroll": {"shape":"cylinder","color":Color(0.9,0.85,0.7),"h":0.06,"r":0.08,"rx":PI*0.5},
	"gem":    {"shape":"box","color":Color(0.3,0.8,0.9),"h":0.1,"r":0.05,"emit":Color(0.3,0.8,0.9)},
	"key":    {"shape":"box","color":Color(0.85,0.75,0.2),"h":0.06,"r":0.08},
	"gold":   {"shape":"cylinder","color":Color(0.95,0.85,0.2),"h":0.03,"r":0.08},
	"rune":   {"shape":"box","color":Color(0.5,0.2,0.8),"h":0.08,"r":0.06,"emit":Color(0.5,0.2,0.8)},
}

# ── SFX configs: [freq_start, freq_end, duration, volume, noise_mix] ────────

static var _sfx: Dictionary = {
	"attack_hit":     [200.0, 80.0, 0.15, 0.7, 0.5],
	"attack_miss":    [400.0, 200.0, 0.2, 0.3, 0.1],
	"shield_block":   [800.0, 200.0, 0.1, 0.6, 0.6],
	"critical_hit":   [300.0, 100.0, 0.2, 0.9, 0.4],
	"enemy_hit":      [150.0, 60.0, 0.12, 0.5, 0.5],
	"enemy_death":    [200.0, 30.0, 0.5, 0.6, 0.3],
	"player_hurt":    [250.0, 100.0, 0.15, 0.6, 0.4],
	"player_death":   [300.0, 20.0, 1.0, 0.7, 0.2],
	"fire_spell":     [600.0, 200.0, 0.4, 0.5, 0.7],
	"ice_spell":      [1200.0, 800.0, 0.3, 0.4, 0.3],
	"heal_spell":     [400.0, 800.0, 0.5, 0.4, 0.1],
	"dark_spell":     [100.0, 50.0, 0.6, 0.6, 0.5],
	"item_pickup":    [800.0, 1200.0, 0.1, 0.3, 0.0],
	"potion_use":     [600.0, 400.0, 0.2, 0.3, 0.2],
	"gold_pickup":    [1000.0, 1400.0, 0.15, 0.3, 0.1],
	"equip":          [500.0, 300.0, 0.1, 0.3, 0.3],
	"door_open":      [150.0, 100.0, 0.3, 0.4, 0.6],
	"chest_open":     [300.0, 200.0, 0.2, 0.3, 0.4],
	"footstep_stone": [100.0, 60.0, 0.05, 0.2, 0.8],
	"trap_trigger":   [400.0, 100.0, 0.3, 0.7, 0.5],
	"ui_click":       [1000.0, 800.0, 0.05, 0.2, 0.0],
	"ui_hover":       [1200.0, 1100.0, 0.03, 0.1, 0.0],
	"quest_accept":   [500.0, 800.0, 0.3, 0.4, 0.0],
	"quest_complete": [400.0, 1000.0, 0.5, 0.5, 0.0],
	"level_up":       [400.0, 1200.0, 0.6, 0.5, 0.0],
	"npc_talk":       [300.0, 350.0, 0.08, 0.2, 0.0],
}

# ── BGM configs ──────────────────────────────────────────────────────────────

static var _bgm: Dictionary = {
	"menu_bgm":    {"freqs":[110.0, 165.0], "dur":8.0, "vol":0.12},
	"dungeon_bgm": {"freqs":[80.0, 120.0, 160.0], "dur":10.0, "vol":0.08},
	"combat_bgm":  {"freqs":[110.0, 165.0, 220.0], "dur":4.0, "vol":0.15},
	"boss_bgm":    {"freqs":[80.0, 160.0, 240.0], "dur":4.0, "vol":0.2},
	"shop_bgm":    {"freqs":[220.0, 330.0, 440.0], "dur":8.0, "vol":0.08},
	"death_bgm":   {"freqs":[55.0, 82.5], "dur":6.0, "vol":0.12},
}

# ── Icon / particle colours ─────────────────────────────────────────────────

static var _icon_colors: Dictionary = {
	"weapon":     Color(0.7, 0.7, 0.8),
	"armor":      Color(0.4, 0.5, 0.7),
	"accessory":  Color(0.9, 0.75, 0.2),
	"consumable": Color(0.8, 0.2, 0.2),
	"scroll":     Color(0.85, 0.8, 0.6),
	"rune":       Color(0.5, 0.2, 0.8),
	"material":   Color(0.3, 0.8, 0.7),
	"key_item":   Color(0.9, 0.8, 0.3),
}

static var _particle_colors: Dictionary = {
	"fire":     Color(1.0, 0.4, 0.0),
	"smoke":    Color(0.5, 0.5, 0.5),
	"ice":      Color(0.5, 0.8, 1.0),
	"poison":   Color(0.2, 0.8, 0.1),
	"darkness": Color(0.2, 0.0, 0.3),
	"heal":     Color(0.2, 1.0, 0.4),
	"spark":    Color(1.0, 0.95, 0.5),
	"magic":    Color(0.6, 0.2, 0.9),
}


# ══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ══════════════════════════════════════════════════════════════════════════════

static func create_monster_model(monster_type: String) -> PackedScene:
	var key := "m_" + monster_type
	if _model_cache.has(key):
		return _model_cache[key]
	var cfg: Dictionary = _monsters.get(monster_type,
		{"shape":"capsule","color":Color.RED,"h":1.8,"r":0.4})
	var scene := _pack(_build_entity(cfg))
	_model_cache[key] = scene
	return scene


static func create_npc_model(npc_id: String) -> PackedScene:
	var key := "n_" + npc_id
	if _model_cache.has(key):
		return _model_cache[key]
	var cfg: Dictionary = _npcs.get(npc_id,
		{"shape":"capsule","color":Color.GREEN,"h":1.8,"r":0.35})
	var scene := _pack(_build_entity(cfg))
	_model_cache[key] = scene
	return scene


static func create_weapon_model(weapon_type: String) -> PackedScene:
	var key := "w_" + weapon_type
	if _model_cache.has(key):
		return _model_cache[key]
	var cfg: Dictionary = _weapons.get(weapon_type,
		{"bs":Vector3(0.06,0.5,0.03),"gs":Vector3(0.15,0.04,0.04),"hl":0.15,"bc":Color(0.7,0.7,0.75)})
	var scene := _pack(_build_weapon(cfg))
	_model_cache[key] = scene
	return scene


static func create_pickup_model(pickup_type: String) -> PackedScene:
	var key := "p_" + pickup_type
	if _model_cache.has(key):
		return _model_cache[key]
	var cfg: Dictionary = _pickups.get(pickup_type,
		{"shape":"box","color":Color.WHITE,"h":0.1,"r":0.05})
	var scene := _pack(_build_pickup(cfg))
	_model_cache[key] = scene
	return scene


static func create_item_icon(item_type: String) -> ImageTexture:
	var key := "icon_" + item_type
	if _tex_cache.has(key):
		return _tex_cache[key]
	var color: Color = _icon_colors.get(item_type, Color.WHITE)
	var tex := _build_item_icon(item_type, color)
	_tex_cache[key] = tex
	return tex


static func create_particle_texture(particle_type: String) -> ImageTexture:
	var key := "ptcl_" + particle_type
	if _tex_cache.has(key):
		return _tex_cache[key]
	var color: Color = _particle_colors.get(particle_type, Color.WHITE)
	var tex := _build_radial_gradient(PARTICLE_SIZE, color)
	_tex_cache[key] = tex
	return tex


static func create_sfx(sfx_name: String) -> AudioStreamWAV:
	var key := "sfx_" + sfx_name
	if _audio_cache.has(key):
		return _audio_cache[key]
	var cfg: Array = _sfx.get(sfx_name, [440.0, 220.0, 0.2, 0.3, 0.0])
	var f0: float = cfg[0]
	var f1: float = cfg[1]
	var dur: float = cfg[2]
	var vol: float = cfg[3]
	var nz: float = cfg[4]
	var data := _generate_sweep(f0, f1, dur, vol, nz)
	var wav := _make_wav(data, false)
	_audio_cache[key] = wav
	return wav


static func create_bgm(track_name: String) -> AudioStreamWAV:
	var key := "bgm_" + track_name
	if _audio_cache.has(key):
		return _audio_cache[key]
	var cfg: Dictionary = _bgm.get(track_name,
		{"freqs":[110.0], "dur":8.0, "vol":0.1})
	var freqs: Array = cfg["freqs"]
	var dur: float = cfg["dur"]
	var vol: float = cfg["vol"]
	var data := _generate_drone(freqs, dur, vol)
	var wav := _make_wav(data, true)
	_audio_cache[key] = wav
	return wav


# ══════════════════════════════════════════════════════════════════════════════
# 3D MODEL BUILDERS
# ══════════════════════════════════════════════════════════════════════════════

static func _build_entity(cfg: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"

	var shape: String = cfg.get("shape", "capsule")
	var color: Color = cfg.get("color", Color.RED)
	var h: float = cfg.get("h", 1.8)
	var r: float = cfg.get("r", 0.4)
	var alpha: float = cfg.get("alpha", 1.0)
	var emit: Variant = cfg.get("emit", null)
	var emit_e: float = cfg.get("emit_e", 2.0)
	var y_off: float = cfg.get("y_off", 0.0)

	# Body mesh
	var body := MeshInstance3D.new()
	body.name = "Body"

	match shape:
		"capsule":
			var m := CapsuleMesh.new()
			m.radius = r
			m.height = h
			body.mesh = m
		"sphere":
			var m := SphereMesh.new()
			m.radius = r
			m.height = h
			body.mesh = m
		"box":
			var m := BoxMesh.new()
			m.size = Vector3(r * 2.0, h, r * 1.5)
			body.mesh = m
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = r
			m.bottom_radius = r * 1.2
			m.height = h
			body.mesh = m

	body.position.y = h * 0.5 + y_off
	body.material_override = _make_mat(color, emit, emit_e, alpha)
	root.add_child(body)

	# ── Eyes ────────────────────────────────────────────────────────
	if cfg.get("eyes", false):
		var eye_c: Color = cfg.get("eye_color", Color(1.0, 0.2, 0.1))
		var eye_y: float = h * 0.72 + y_off
		var eye_sep: float = r * 0.45
		var eye_r: float = clampf(r * 0.12, 0.03, 0.08)
		for side in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.name = "Eye_L" if side < 0 else "Eye_R"
			var em := SphereMesh.new()
			em.radius = eye_r
			em.height = eye_r * 2.0
			eye.mesh = em
			eye.position = Vector3(side * eye_sep, eye_y, r * 0.85)
			eye.material_override = _make_mat(eye_c, eye_c, 4.0)
			root.add_child(eye)

	# ── Arms ────────────────────────────────────────────────────────
	if cfg.get("arms", false) and shape in ["capsule", "cylinder"]:
		var arm_y: float = h * 0.55 + y_off
		var arm_len: float = h * 0.3
		var arm_r: float = r * 0.2
		for side in [-1.0, 1.0]:
			var arm := MeshInstance3D.new()
			arm.name = "Arm_L" if side < 0 else "Arm_R"
			var am := CapsuleMesh.new()
			am.radius = arm_r
			am.height = arm_len
			arm.mesh = am
			arm.position = Vector3(side * (r + arm_r * 0.8), arm_y, 0)
			arm.rotation.z = side * 0.25
			arm.material_override = _make_mat(color.darkened(0.15), emit, emit_e, alpha)
			root.add_child(arm)

	# ── Horns ───────────────────────────────────────────────────────
	var horn_count: int = cfg.get("horns", 0)
	if horn_count > 0:
		var horn_base_y: float = h * 0.88 + y_off
		for hi in range(horn_count):
			for side in [-1.0, 1.0]:
				var horn := MeshInstance3D.new()
				horn.name = "Horn_%d_%s" % [hi, "L" if side < 0 else "R"]
				var hm := CylinderMesh.new()
				hm.top_radius = 0.01
				hm.bottom_radius = 0.04 + hi * 0.01
				hm.height = 0.25 + hi * 0.08
				horn.mesh = hm
				var spread: float = 0.15 + hi * 0.1
				horn.position = Vector3(side * spread, horn_base_y + hi * 0.05, 0)
				horn.rotation.z = side * (0.3 + hi * 0.15)
				var horn_c: Color = color.lightened(0.3)
				horn.material_override = _make_mat(horn_c, null, 0.0, 1.0, 0.6, 0.3)
				root.add_child(horn)

	# ── Spikes ──────────────────────────────────────────────────────
	var spike_count: int = cfg.get("spikes", 0)
	if spike_count > 0:
		var spike_base_y: float = h * 0.5 + y_off
		for si in range(spike_count):
			var angle: float = TAU * float(si) / float(spike_count)
			var spike := MeshInstance3D.new()
			spike.name = "Spike_%d" % si
			var sm := CylinderMesh.new()
			sm.top_radius = 0.01
			sm.bottom_radius = 0.04
			sm.height = r * 0.6
			spike.mesh = sm
			spike.position = Vector3(
				cos(angle) * r * 0.9,
				spike_base_y + sin(angle * 3.0) * h * 0.15,
				sin(angle) * r * 0.9
			)
			spike.rotation = Vector3(-cos(angle) * 0.8, 0, sin(angle) * 0.8)
			var spike_c: Color = color.lightened(0.2) if emit == null else (emit as Color).lightened(0.1)
			spike.material_override = _make_mat(spike_c, emit, emit_e * 0.5, alpha, 0.4, 0.4)
			root.add_child(spike)

	# ── Hat (NPC only) ──────────────────────────────────────────────
	var hat: String = cfg.get("hat", "")
	if hat == "flat":
		var brim := MeshInstance3D.new()
		brim.name = "HatBrim"
		var bm := CylinderMesh.new()
		bm.top_radius = r * 1.2
		bm.bottom_radius = r * 1.2
		bm.height = 0.04
		brim.mesh = bm
		brim.position.y = h * 0.85 + y_off
		brim.material_override = _make_mat(Color(0.35, 0.2, 0.1))
		root.add_child(brim)
		var crown := MeshInstance3D.new()
		crown.name = "HatCrown"
		var cm := CylinderMesh.new()
		cm.top_radius = r * 0.6
		cm.bottom_radius = r * 0.75
		cm.height = 0.2
		crown.mesh = cm
		crown.position.y = h * 0.85 + 0.12 + y_off
		crown.material_override = _make_mat(Color(0.35, 0.2, 0.1))
		root.add_child(crown)
	elif hat == "pointed":
		var cone := MeshInstance3D.new()
		cone.name = "HatCone"
		var pm := CylinderMesh.new()
		pm.top_radius = 0.01
		pm.bottom_radius = r * 0.9
		pm.height = 0.45
		cone.mesh = pm
		cone.position.y = h * 0.88 + 0.2 + y_off
		cone.material_override = _make_mat(Color(0.25, 0.15, 0.4), Color(0.3, 0.1, 0.5), 1.0)
		root.add_child(cone)

	# ── Optional weapon accessory ───────────────────────────────────
	var acc: String = cfg.get("acc", "")
	if not acc.is_empty():
		_add_accessory(root, acc, h, y_off)

	return root


static func _add_accessory(root: Node3D, acc: String, h: float, y_off: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Accessory"

	match acc:
		"sword":
			var m := BoxMesh.new()
			m.size = Vector3(0.08, 0.7, 0.04)
			mi.mesh = m
			mi.position = Vector3(0.5, h * 0.4 + y_off, 0)
			mi.rotation.z = -0.3
			mi.material_override = _make_mat(
				Color(0.75, 0.75, 0.8), null, 0.0, 1.0, 0.8, 0.3)
		"staff":
			var m := CylinderMesh.new()
			m.top_radius = 0.03
			m.bottom_radius = 0.03
			m.height = 1.2
			mi.mesh = m
			mi.position = Vector3(0.4, h * 0.5 + y_off, 0)
			mi.material_override = _make_mat(Color(0.45, 0.3, 0.15))
			# Glowing orb at the tip
			var orb := MeshInstance3D.new()
			orb.name = "Orb"
			var om := SphereMesh.new()
			om.radius = 0.08
			om.height = 0.16
			orb.mesh = om
			orb.position.y = 0.65
			orb.material_override = _make_mat(
				Color(0.3, 0.5, 1.0), Color(0.3, 0.5, 1.0), 3.0)
			mi.add_child(orb)
		"shield":
			var m := BoxMesh.new()
			m.size = Vector3(0.06, 0.5, 0.4)
			mi.mesh = m
			mi.position = Vector3(-0.45, h * 0.4 + y_off, 0)
			mi.material_override = _make_mat(
				Color(0.5, 0.35, 0.2), null, 0.0, 1.0, 0.5)

	root.add_child(mi)


static func _build_weapon(cfg: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon"

	var bs: Vector3 = cfg.get("bs", Vector3(0.06, 0.5, 0.03))
	var gs: Vector3 = cfg.get("gs", Vector3(0.15, 0.04, 0.04))
	var hl: float = cfg.get("hl", 0.15)
	var bc: Color = cfg.get("bc", Color(0.7, 0.7, 0.75))
	var is_sphere: bool = cfg.get("sphere_head", false)
	var has_orb: bool = cfg.get("orb", false)

	# Handle
	if hl > 0.01:
		var handle := MeshInstance3D.new()
		handle.name = "Handle"
		var hm := CylinderMesh.new()
		hm.top_radius = 0.02
		hm.bottom_radius = 0.025
		hm.height = hl
		handle.mesh = hm
		handle.position.y = hl * 0.5
		handle.material_override = _make_mat(Color(0.4, 0.25, 0.12))
		root.add_child(handle)

	# Guard
	if gs.length() > 0.05:
		var guard := MeshInstance3D.new()
		guard.name = "Guard"
		var gm := BoxMesh.new()
		gm.size = gs
		guard.mesh = gm
		guard.position.y = hl
		guard.material_override = _make_mat(
			Color(0.6, 0.5, 0.2), null, 0.0, 1.0, 0.6, 0.4)
		root.add_child(guard)

	# Blade / Head
	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	if is_sphere:
		var bm := SphereMesh.new()
		bm.radius = bs.x
		bm.height = bs.y
		blade.mesh = bm
	else:
		var bm := BoxMesh.new()
		bm.size = bs
		blade.mesh = bm
	blade.position.y = hl + bs.y * 0.5
	blade.material_override = _make_mat(bc, null, 0.0, 1.0, 0.7, 0.3)
	root.add_child(blade)

	# Staff orb
	if has_orb:
		var orb := MeshInstance3D.new()
		orb.name = "Orb"
		var om := SphereMesh.new()
		om.radius = 0.06
		om.height = 0.12
		orb.mesh = om
		orb.position.y = hl + bs.y + 0.08
		orb.material_override = _make_mat(
			Color(0.4, 0.3, 0.9), Color(0.4, 0.3, 0.9), 3.0)
		root.add_child(orb)

	return root


static func _build_pickup(cfg: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Pickup"

	var shape: String = cfg.get("shape", "box")
	var color: Color = cfg.get("color", Color.WHITE)
	var h: float = cfg.get("h", 0.1)
	var r: float = cfg.get("r", 0.05)
	var emit: Variant = cfg.get("emit", null)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"

	match shape:
		"cylinder":
			var m := CylinderMesh.new()
			m.top_radius = r * 0.7
			m.bottom_radius = r
			m.height = h
			mi.mesh = m
		_:
			var m := BoxMesh.new()
			m.size = Vector3(r * 2.0, h, r * 2.0)
			mi.mesh = m

	mi.position.y = h * 0.5

	var rx: float = cfg.get("rx", 0.0)
	var ry: float = cfg.get("ry", 0.0)
	if rx != 0.0:
		mi.rotation.x = rx
	if ry != 0.0:
		mi.rotation.y = ry

	var metallic: bool = cfg.get("metallic", false)
	var met: float = 0.8 if metallic else 0.0
	var rough: float = 0.3 if metallic else 0.7
	mi.material_override = _make_mat(color, emit, 2.0, 1.0, met, rough)
	root.add_child(mi)

	return root


# ══════════════════════════════════════════════════════════════════════════════
# 2D TEXTURE BUILDERS
# ══════════════════════════════════════════════════════════════════════════════

static func _build_item_icon(item_type: String, color: Color) -> ImageTexture:
	var img := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var s := ICON_SIZE

	match item_type:
		"weapon":
			_fill_rect(img, s / 2 - 1, 4, 3, 20, color)
			_fill_rect(img, s / 2 - 5, 22, 11, 2, color.darkened(0.2))
			_fill_rect(img, s / 2 - 1, 24, 3, 5, Color(0.4, 0.25, 0.12))
		"armor":
			_fill_rect(img, 8, 6, 16, 18, color)
			_fill_rect(img, 6, 8, 20, 14, color)
			_fill_rect(img, 10, 10, 12, 8, color.lightened(0.2))
		"accessory":
			_fill_circle(img, s / 2, s / 2, 10, color)
			_fill_circle(img, s / 2, s / 2, 6, Color.TRANSPARENT)
		"consumable":
			_fill_rect(img, 12, 4, 8, 4, color.lightened(0.3))
			_fill_rect(img, 9, 8, 14, 16, color)
			_fill_rect(img, 11, 10, 10, 10, color.lightened(0.2))
		"scroll":
			_fill_rect(img, 6, 10, 20, 12, color)
			_fill_circle(img, 7, 16, 4, color.darkened(0.1))
			_fill_circle(img, 25, 16, 4, color.darkened(0.1))
		"rune":
			for i in range(12):
				var w: int = (i if i < 6 else 12 - i) * 2 + 1
				_fill_rect(img, s / 2 - w / 2, 4 + i * 2, w, 2, color)
			_fill_rect(img, s / 2 - 2, s / 2 - 2, 5, 5, color.lightened(0.4))
		"material":
			for i in range(10):
				var w: int = (i if i < 5 else 10 - i) * 3
				_fill_rect(img, s / 2 - w / 2, 6 + i * 2, maxi(w, 1), 2, color)
			_fill_rect(img, s / 2 - 1, 8, 3, 6, color.lightened(0.3))
		"key_item":
			_fill_circle(img, 10, 10, 5, color)
			_fill_circle(img, 10, 10, 2, Color.TRANSPARENT)
			_fill_rect(img, 14, 9, 12, 3, color)
			_fill_rect(img, 22, 12, 3, 4, color)
			_fill_rect(img, 18, 12, 3, 3, color)
		_:
			_fill_rect(img, 6, 6, 20, 20, color)

	return ImageTexture.create_from_image(img)


static func _build_radial_gradient(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var max_dist := size * 0.5
	for y in range(size):
		for x in range(size):
			var dist := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var t := clampf(1.0 - dist / max_dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, t * t))
	return ImageTexture.create_from_image(img)


# ══════════════════════════════════════════════════════════════════════════════
# AUDIO BUILDERS
# ══════════════════════════════════════════════════════════════════════════════

## Generate a frequency-sweep tone with optional noise.
static func _generate_sweep(f_start: float, f_end: float, dur: float,
		vol: float, noise: float) -> PackedByteArray:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / MIX_RATE
		var pos := float(i) / count
		var freq := lerpf(f_start, f_end, pos)
		var env := _envelope(pos)
		var tone := sin(TAU * freq * t)
		var nz: float = randf_range(-1.0, 1.0) if noise > 0.0 else 0.0
		var val := (tone * (1.0 - noise) + nz * noise) * vol * env * 32767.0
		data.encode_s16(i * 2, int(clampf(val, -32768.0, 32767.0)))
	return data


## Generate a layered sine-drone for ambient BGM.
static func _generate_drone(freqs: Array, dur: float, vol: float) -> PackedByteArray:
	var count := int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var n: float = maxf(float(freqs.size()), 1.0)
	for i in range(count):
		var t := float(i) / MIX_RATE
		var pos := float(i) / count
		var mix := 0.0
		for f_idx in range(freqs.size()):
			var freq: float = freqs[f_idx]
			# Slow LFO for organic feel
			var lfo := 1.0 + 0.3 * sin(TAU * (0.1 + f_idx * 0.07) * t)
			mix += sin(TAU * freq * t) * lfo
		mix = mix / n * vol * 32767.0
		# Fade in/out to avoid clicks at loop boundary
		var fade := minf(pos * 20.0, 1.0) * minf((1.0 - pos) * 20.0, 1.0)
		data.encode_s16(i * 2, int(clampf(mix * fade, -32768.0, 32767.0)))
	return data


# ══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════════════

## Pack a standalone Node3D tree into a PackedScene and free the source nodes.
static func _pack(root: Node3D) -> PackedScene:
	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


## Recursively set owner on all descendant nodes (required for pack).
static func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)


## Create a StandardMaterial3D with optional emission and transparency.
static func _make_mat(color: Color, emission: Variant = null,
		emit_energy: float = 2.0, alpha: float = 1.0,
		metallic: float = 0.0, roughness: float = 0.7) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.metallic = metallic
	mat.roughness = roughness
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission is Color:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emit_energy
	return mat


## Simple attack-decay envelope for SFX.
static func _envelope(pos: float) -> float:
	if pos < 0.05:
		return pos / 0.05
	return maxf(0.0, 1.0 - (pos - 0.05) / 0.95)


## Create an AudioStreamWAV from raw 16-bit PCM data.
static func _make_wav(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = data.size() / 2
	return wav


## Fill a rectangle on an Image.
static func _fill_rect(img: Image, x: int, y: int, w: int, h: int,
		color: Color) -> void:
	for py in range(maxi(y, 0), mini(y + h, img.get_height())):
		for px in range(maxi(x, 0), mini(x + w, img.get_width())):
			if color.a < 0.01:
				img.set_pixel(px, py, Color.TRANSPARENT)
			else:
				img.set_pixel(px, py, color)


## Fill a circle on an Image.
static func _fill_circle(img: Image, cx: int, cy: int, radius: int,
		color: Color) -> void:
	var r2 := radius * radius
	for py in range(maxi(cy - radius, 0), mini(cy + radius + 1, img.get_height())):
		for px in range(maxi(cx - radius, 0), mini(cx + radius + 1, img.get_width())):
			if (px - cx) * (px - cx) + (py - cy) * (py - cy) <= r2:
				if color.a < 0.01:
					img.set_pixel(px, py, Color.TRANSPARENT)
				else:
					img.set_pixel(px, py, color)
