## Central asset registry mapping game elements to asset file paths.
##
## When real assets are downloaded and placed in res://assets/,
## update the paths here. All other scripts reference assets through
## this registry so swapping assets requires changes in only one place.
class_name AssetRegistry
extends RefCounted

# ── 3D Models: Dungeon ───────────────────────────────────────────────────────

## Room prefab scenes by room type.
## Replace with actual .tscn/.glb paths after importing assets.
const ROOM_SCENES: Dictionary = {
	"entrance":  "",  # res://assets/models/dungeon/entrance.glb
	"corridor":  "",  # res://assets/models/dungeon/corridor.glb
	"combat":    "",  # res://assets/models/dungeon/combat_room.glb
	"treasure":  "",  # res://assets/models/dungeon/treasure_room.glb
	"trap":      "",  # res://assets/models/dungeon/trap_room.glb
	"puzzle":    "",  # res://assets/models/dungeon/puzzle_room.glb
	"rest":      "",  # res://assets/models/dungeon/rest_room.glb
	"shop":      "",  # res://assets/models/dungeon/shop_room.glb
	"boss":      "",  # res://assets/models/dungeon/boss_room.glb
	"secret":    "",  # res://assets/models/dungeon/secret_room.glb
	"event":     "",  # res://assets/models/dungeon/event_room.glb
}

const DUNGEON_PROPS: Dictionary = {
	"wall":      "res://assets/dungeon/wall.glb",
	"floor":     "res://assets/dungeon/floor.glb",
	"door":      "res://assets/dungeon/gate.glb",
	"stairs":    "res://assets/dungeon/stairs.glb",
	"torch":     "res://assets/dungeon/wood-structure.glb",
	"chest":     "res://assets/dungeon/chest.glb",
	"barrel":    "res://assets/dungeon/barrel.glb",
	"pillar":    "res://assets/dungeon/column.glb",
	"banner":    "res://assets/dungeon/banner.glb",
	"rocks":     "res://assets/dungeon/rocks.glb",
	"trap":      "res://assets/dungeon/trap.glb",
	"coin":      "res://assets/dungeon/coin.glb",
}

# ── 3D Models: Characters ────────────────────────────────────────────────────

const PLAYER_MODEL: String = "res://assets/characters/character_knight.gltf"

## NPC models by npc_id.
const NPC_MODELS: Dictionary = {
	"wandering_merchant":  "res://assets/characters/character_rogue.gltf",
	"captive_adventurer":  "res://assets/characters/character_barbarian.gltf",
	"mysterious_sage":     "res://assets/characters/character_mage.gltf",
	"fallen_knight":       "res://assets/characters/character_knight.gltf",
	"merchant":            "res://assets/characters/character_rogue.gltf",
	"sage":                "res://assets/characters/character_mage.gltf",
	"blacksmith":          "res://assets/characters/character_barbarian.gltf",
	"ghost_npc":           "",
}

## Monster models by monster type.
## Maps both fallback template types and detailed types to real assets.
const MONSTER_MODELS: Dictionary = {
	# ── Fallback template type keys (exact match) ─────────────────────
	"skeleton":     "res://assets/monsters/big/Orc_Skull.gltf",
	"ghost":        "res://assets/monsters/flying/Ghost.gltf",
	"slime":        "res://assets/monsters/blob/GreenBlob.gltf",
	"cultist":      "res://assets/monsters/blob/Wizard.gltf",
	"undead":       "res://assets/monsters/big/Tribal.gltf",
	"golem":        "res://assets/monsters/big/Orc.gltf",
	"bat":          "res://assets/monsters/flying/Armabee.gltf",
	"elemental":    "res://assets/monsters/flying/Goleling.gltf",
	"dragon":       "res://assets/monsters/flying/Dragon.gltf",
	"demon":        "res://assets/monsters/big/Demon.gltf",
	"boss":         "res://assets/monsters/big/BlueDemon.gltf",
	# ── Catacombs theme ───────────────────────────────────────────────
	"skeleton_warrior":  "res://assets/monsters/big/Orc_Skull.gltf",
	"ghoul":             "res://assets/monsters/blob/GreenSpikyBlob.gltf",
	"skeleton_mage":     "res://assets/monsters/blob/Wizard.gltf",
	"wraith":            "res://assets/monsters/flying/Ghost_Skull.gltf",
	# ── Abyss theme ──────────────────────────────────────────────────
	"abyss_watcher":     "res://assets/monsters/big/Ninja.gltf",
	"void_tentacle":     "res://assets/monsters/flying/Squidle.gltf",
	"shadow_stalker":    "res://assets/monsters/blob/Ninja.gltf",
	"abyss_screamer":    "res://assets/monsters/flying/Hywirl.gltf",
	# ── Fire theme ────────────────────────────────────────────────────
	"fire_elemental":    "res://assets/monsters/flying/Goleling_Evolved.gltf",
	"lava_golem":        "res://assets/monsters/big/Monkroose.gltf",
	"fire_bat_swarm":    "res://assets/monsters/flying/Armabee_Evolved.gltf",
	"fire_priest":       "res://assets/monsters/flying/Tribal.gltf",
	# ── Ice theme ─────────────────────────────────────────────────────
	"frost_spider":      "res://assets/monsters/blob/Alien.gltf",
	"ice_golem":         "res://assets/monsters/big/Yeti.gltf",
	"frost_wraith":      "res://assets/monsters/flying/Ghost.gltf",
	"cryo_mage":         "res://assets/monsters/flying/Glub_Evolved.gltf",
	# ── Corruption theme ──────────────────────────────────────────────
	"mutant":            "res://assets/monsters/blob/Mushnub_Evolved.gltf",
	"corrupted_knight":  "res://assets/dungeon/character-orc.glb",
	"spore_beast":       "res://assets/monsters/blob/Mushnub.gltf",
	"toxic_slime":       "res://assets/monsters/blob/PinkBlob.gltf",
	# ── Default fallback ──────────────────────────────────────────────
	"default":           "res://assets/monsters/blob/GreenBlob.gltf",
}

## Boss models by boss_id.
const BOSS_MODELS: Dictionary = {
	"boss_bone_lord":      "res://assets/monsters/big/Orc_Skull.gltf",
	"boss_void_mother":    "res://assets/monsters/flying/Dragon_Evolved.gltf",
	"boss_flame_tyrant":   "res://assets/monsters/big/Demon.gltf",
	"boss_frozen_empress": "res://assets/monsters/big/Yeti.gltf",
}

# ── 3D Models: Items ─────────────────────────────────────────────────────────

## Weapon models by weapon subtype.
const WEAPON_MODELS: Dictionary = {
	"sword":      "res://assets/weapons/sword_A.fbx",
	"axe":        "res://assets/weapons/axe_A.fbx",
	"spear":      "res://assets/weapons/halberd.fbx",
	"dagger":     "res://assets/weapons/dagger_A.fbx",
	"bow":        "res://assets/weapons/bow_A_withString.fbx",
	"staff":      "res://assets/weapons/staff_A.fbx",
	"mace":       "res://assets/weapons/hammer_A.fbx",
	"greatsword": "res://assets/weapons/sword_B.fbx",
	"scythe":     "res://assets/weapons/halberd.fbx",
}

## Pickup item models (3D in-world).
const PICKUP_MODELS: Dictionary = {
	"potion":   "",
	"scroll":   "",
	"gem":      "res://assets/dungeon/coin.glb",
	"key":      "",
	"gold":     "res://assets/dungeon/coin.glb",
	"rune":     "",
}

# ── 2D Icons ─────────────────────────────────────────────────────────────────

## Item icons by item type (for inventory UI).
const ITEM_ICONS: Dictionary = {
	"weapon":     "",  # res://assets/icons/items/weapon.png
	"armor":      "",  # res://assets/icons/items/armor.png
	"accessory":  "",  # res://assets/icons/items/accessory.png
	"consumable": "",  # res://assets/icons/items/consumable.png
	"scroll":     "",  # res://assets/icons/items/scroll.png
	"rune":       "",  # res://assets/icons/items/rune.png
	"material":   "",  # res://assets/icons/items/material.png
	"key_item":   "",  # res://assets/icons/items/key_item.png
}

## NPC emotion icons/portraits.
const EMOTION_ICONS: Dictionary = {
	"neutral":    "",  # res://assets/icons/emotions/neutral.png
	"happy":      "",  # res://assets/icons/emotions/happy.png
	"sad":        "",  # res://assets/icons/emotions/sad.png
	"angry":      "",  # res://assets/icons/emotions/angry.png
	"afraid":     "",  # res://assets/icons/emotions/afraid.png
	"curious":    "",  # res://assets/icons/emotions/curious.png
	"suspicious": "",  # res://assets/icons/emotions/suspicious.png
	"grateful":   "",  # res://assets/icons/emotions/grateful.png
	"melancholy": "",  # res://assets/icons/emotions/melancholy.png
	"excited":    "",  # res://assets/icons/emotions/excited.png
	"disgusted":  "",  # res://assets/icons/emotions/disgusted.png
	"mysterious": "",  # res://assets/icons/emotions/mysterious.png
}

## NPC portrait images for dialogue UI.
const NPC_PORTRAITS: Dictionary = {
	"wandering_merchant": "",  # res://assets/icons/portraits/merchant.png
	"captive_adventurer": "",  # res://assets/icons/portraits/adventurer.png
	"mysterious_sage":    "",  # res://assets/icons/portraits/sage.png
	"fallen_knight":      "",  # res://assets/icons/portraits/knight.png
}

# ── UI Textures ──────────────────────────────────────────────────────────────

const UI_TEXTURES: Dictionary = {
	"panel_bg":        "",  # res://assets/textures/ui/panel_bg.png
	"hp_bar_fill":     "",  # res://assets/textures/ui/hp_bar_fill.png
	"hp_bar_empty":    "",  # res://assets/textures/ui/hp_bar_empty.png
	"affinity_bar":    "",  # res://assets/textures/ui/affinity_bar.png
	"inventory_slot":  "",  # res://assets/textures/ui/inventory_slot.png
	"button_normal":   "",  # res://assets/textures/ui/button_normal.png
	"button_hover":    "",  # res://assets/textures/ui/button_hover.png
	"button_pressed":  "",  # res://assets/textures/ui/button_pressed.png
	"minimap_frame":   "",  # res://assets/textures/ui/minimap_frame.png
}

# ── Audio: BGM ───────────────────────────────────────────────────────────────

const BGM_TRACKS: Dictionary = {
	"menu_bgm":    "res://assets/audio/bgm/dungeon.ogg",
	"dungeon_bgm": "res://assets/audio/bgm/dungeon.ogg",
	"combat_bgm":  "res://assets/audio/bgm/dungeon.ogg",
	"boss_bgm":    "res://assets/audio/bgm/dungeon.ogg",
	"shop_bgm":    "res://assets/audio/bgm/dungeon.ogg",
	"death_bgm":   "res://assets/audio/bgm/dungeon.ogg",
}

# ── Audio: SFX ───────────────────────────────────────────────────────────────

const SFX_SOUNDS: Dictionary = {
	# Combat
	"attack_hit":     "res://assets/audio/sfx/drawKnife1.ogg",
	"attack_miss":    "res://assets/audio/sfx/drawKnife2.ogg",
	"shield_block":   "res://assets/audio/sfx/impactPlate_light_000.ogg",
	"critical_hit":   "res://assets/audio/sfx/impactPunch_heavy_000.ogg",
	"enemy_hit":      "res://assets/audio/sfx/impactMining_000.ogg",
	"enemy_death":    "res://assets/audio/sfx/impactPunch_heavy_001.ogg",
	"player_hurt":    "res://assets/audio/sfx/impactPlate_light_001.ogg",
	"player_death":   "res://assets/audio/sfx/impactMining_001.ogg",
	# Magic
	"fire_spell":     "res://assets/audio/sfx/chop.ogg",
	"ice_spell":      "res://assets/audio/sfx/cloth1.ogg",
	"heal_spell":     "res://assets/audio/sfx/handleSmallLeather.ogg",
	"dark_spell":     "res://assets/audio/sfx/drawKnife3.ogg",
	# Items
	"item_pickup":    "res://assets/audio/sfx/handleSmallLeather.ogg",
	"potion_use":     "res://assets/audio/sfx/handleSmallLeather.ogg",
	"gold_pickup":    "res://assets/audio/sfx/handleCoins.ogg",
	"equip":          "res://assets/audio/sfx/metalClick.ogg",
	# Environment
	"door_open":      "res://assets/audio/sfx/doorOpen_1.ogg",
	"chest_open":     "res://assets/audio/sfx/metalLatch.ogg",
	"footstep_stone": "res://assets/audio/sfx/footstep_concrete_000.ogg",
	"trap_trigger":   "res://assets/audio/sfx/impactMining_001.ogg",
	# UI
	"ui_click":       "res://assets/audio/sfx/metalClick.ogg",
	"ui_hover":       "res://assets/audio/sfx/handleSmallLeather.ogg",
	"quest_accept":   "res://assets/audio/sfx/handleCoins2.ogg",
	"quest_complete": "res://assets/audio/sfx/handleCoins.ogg",
	"level_up":       "res://assets/audio/sfx/handleCoins2.ogg",
	# NPC
	"npc_talk":       "res://assets/audio/sfx/cloth1.ogg",
}

# ── Particle Textures ────────────────────────────────────────────────────────

const PARTICLE_TEXTURES: Dictionary = {
	"fire":      "",  # res://assets/particles/fire.png
	"smoke":     "",  # res://assets/particles/smoke.png
	"ice":       "",  # res://assets/particles/ice.png
	"poison":    "",  # res://assets/particles/poison.png
	"darkness":  "",  # res://assets/particles/darkness.png
	"heal":      "",  # res://assets/particles/heal.png
	"spark":     "",  # res://assets/particles/spark.png
	"magic":     "",  # res://assets/particles/magic.png
}

# ── Helper Methods ───────────────────────────────────────────────────────────

## Try to load a resource; return null if path is empty or not found.
static func try_load(path: String) -> Resource:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Load a 3D model scene, returning null if not available.
static func load_model(path: String) -> PackedScene:
	var res: Resource = try_load(path)
	if res is PackedScene:
		return res
	return null


## Load a texture, returning null if not available.
static func load_texture(path: String) -> Texture2D:
	var res: Resource = try_load(path)
	if res is Texture2D:
		return res
	return null


## Load an audio stream, returning null if not available.
static func load_audio(path: String) -> AudioStream:
	var res: Resource = try_load(path)
	if res is AudioStream:
		return res
	return null


## Get the monster model path, with fallback to empty string.
static func get_monster_model(monster_type: String) -> String:
	return MONSTER_MODELS.get(monster_type, "")


## Get the NPC model path.
static func get_npc_model(npc_id: String) -> String:
	return NPC_MODELS.get(npc_id, "")


## Get item icon path by type.
static func get_item_icon(item_type: String) -> String:
	return ITEM_ICONS.get(item_type, "")


## Get BGM track path.
static func get_bgm(track_name: String) -> String:
	return BGM_TRACKS.get(track_name, "")


## Get SFX path.
static func get_sfx(sfx_name: String) -> String:
	return SFX_SOUNDS.get(sfx_name, "")


## Check if a specific asset category has any real assets configured.
static func has_real_assets(category: Dictionary) -> bool:
	for key in category:
		if not category[key].is_empty():
			return true
	return false


# ── Resource getters with procedural fallback ────────────────────────────────

## Get monster PackedScene – real asset or procedural fallback.
## Checks MONSTER_MODELS first, then BOSS_MODELS, then procedural.
static func get_monster_scene(monster_type: String) -> PackedScene:
	var path: String = get_monster_model(monster_type)
	var scene: PackedScene = load_model(path)
	if scene:
		return scene
	# Also check boss models.
	var boss_path: String = BOSS_MODELS.get(monster_type, "")
	var boss_scene: PackedScene = load_model(boss_path)
	if boss_scene:
		return boss_scene
	return ProceduralAssets.create_monster_model(monster_type)


## Get NPC PackedScene.
static func get_npc_scene(npc_id: String) -> PackedScene:
	var path: String = get_npc_model(npc_id)
	var scene: PackedScene = load_model(path)
	if scene:
		return scene
	return ProceduralAssets.create_npc_model(npc_id)


## Get weapon PackedScene.
static func get_weapon_scene(weapon_type: String) -> PackedScene:
	var path: String = WEAPON_MODELS.get(weapon_type, "")
	var scene: PackedScene = load_model(path)
	if scene:
		return scene
	return ProceduralAssets.create_weapon_model(weapon_type)


## Get pickup item PackedScene.
static func get_pickup_scene(pickup_type: String) -> PackedScene:
	var path: String = PICKUP_MODELS.get(pickup_type, "")
	var scene: PackedScene = load_model(path)
	if scene:
		return scene
	return ProceduralAssets.create_pickup_model(pickup_type)


## Get item icon Texture2D.
static func get_item_icon_texture(item_type: String) -> Texture2D:
	var path: String = get_item_icon(item_type)
	var tex: Texture2D = load_texture(path)
	if tex:
		return tex
	return ProceduralAssets.create_item_icon(item_type)


## Get particle Texture2D.
static func get_particle_tex(particle_type: String) -> Texture2D:
	var path: String = PARTICLE_TEXTURES.get(particle_type, "")
	var tex: Texture2D = load_texture(path)
	if tex:
		return tex
	return ProceduralAssets.create_particle_texture(particle_type)


## Get SFX AudioStream.
static func get_sfx_stream(sfx_name: String) -> AudioStream:
	var path: String = get_sfx(sfx_name)
	var stream: AudioStream = load_audio(path)
	if stream:
		return stream
	return ProceduralAssets.create_sfx(sfx_name)


## Get BGM AudioStream.
static func get_bgm_stream(track_name: String) -> AudioStream:
	var path: String = get_bgm(track_name)
	var stream: AudioStream = load_audio(path)
	if stream:
		return stream
	return ProceduralAssets.create_bgm(track_name)
