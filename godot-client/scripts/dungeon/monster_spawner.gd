## Spawns placeholder monster nodes inside dungeon rooms.
##
## Each monster is a CharacterBody3D with a coloured capsule mesh and a
## Label3D name tag.  Colour indicates rank (normal, elite, boss, etc.).
class_name MonsterSpawner
extends RefCounted

# ── Rank colour mapping ─────────────────────────────────────────────────────

const RANK_COLORS: Dictionary = {
	"minion":    Color(0.85, 0.30, 0.30),   # light red
	"normal":    Color(0.80, 0.15, 0.15),   # red
	"elite":     Color(0.55, 0.10, 0.70),   # purple
	"mini_boss": Color(0.30, 0.05, 0.45),   # dark purple
	"boss":      Color(0.05, 0.05, 0.05),   # near-black
}

const DEFAULT_RANK_COLOR: Color = Color(0.80, 0.15, 0.15)

# Capsule dimensions
const CAPSULE_RADIUS: float = 0.4
const CAPSULE_HEIGHT: float = 1.8


# ── Public API ──────────────────────────────────────────────────────────────

## Create a single monster placeholder at the given position.
## [param monster_data]  Dictionary from the AI server (MonsterSpawn schema).
## [param parent]        Node to attach the monster to.
## [param position]      World-space position for the monster.
## Returns the created CharacterBody3D node.
func spawn_monster(monster_data: Dictionary, parent: Node3D, position: Vector3) -> Node3D:
	var body := CharacterBody3D.new()
	var monster_id: String = monster_data.get("monster_id", monster_data.get("type", "unknown"))
	body.name = "Monster_%s" % monster_id
	body.position = position

	# ── Collision shape ──────────────────────────────────────────────────
	var col_shape := CollisionShape3D.new()
	col_shape.name = "CollisionShape"
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = CAPSULE_RADIUS
	capsule_shape.height = CAPSULE_HEIGHT
	col_shape.shape = capsule_shape
	col_shape.position.y = CAPSULE_HEIGHT * 0.5
	body.add_child(col_shape)

	# ── Visual: real model or procedural fallback ───────────────────────
	var monster_type: String = monster_data.get("monster_id", monster_data.get("type", "")).split("_room_")[0]
	var model_scene: PackedScene = AssetRegistry.get_monster_scene(monster_type)
	if model_scene == null:
		model_scene = AssetRegistry.get_monster_scene("default")
	var model_inst: Node3D = model_scene.instantiate() if model_scene != null else _make_fallback_capsule()
	model_inst.name = "Model"
	# Rotate model 180° so it faces forward (toward +Z / camera).
	model_inst.rotation.y = PI
	body.add_child(model_inst)

	var rank: String = monster_data.get("rank", "normal")

	# ── Name label (placed well above model, always visible) ────────────
	var model_h: float = CAPSULE_HEIGHT
	if model_inst != null:
		var aabb: AABB = _get_model_aabb(model_inst)
		if aabb.size.y > 0.1:
			model_h = aabb.size.y + aabb.position.y
	var label_y: float = maxf(model_h, CAPSULE_HEIGHT) + 0.6

	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = monster_data.get("name", "???")
	label.font_size = 48
	label.pixel_size = 0.01
	label.position = Vector3(0, label_y, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.outline_size = 8
	body.add_child(label)

	# ── Level indicator ──────────────────────────────────────────────────
	var level: int = monster_data.get("level", 1)
	var level_label := Label3D.new()
	level_label.name = "LevelLabel"
	level_label.text = "Lv.%d" % level
	level_label.font_size = 36
	level_label.pixel_size = 0.01
	level_label.position = Vector3(0, label_y + 0.3, 0)
	level_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	level_label.no_depth_test = false
	level_label.modulate = Color(1.0, 0.85, 0.3)
	level_label.outline_modulate = Color.BLACK
	level_label.outline_size = 6
	body.add_child(level_label)

	# ── Interaction prompt (shown when player is near) ───────────────
	var prompt := Label3D.new()
	prompt.name = "InteractPrompt"
	prompt.text = "[E] 전투"
	prompt.font_size = 32
	prompt.pixel_size = 0.01
	prompt.position = Vector3(0, label_y + 0.6, 0)
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt.no_depth_test = false
	prompt.modulate = Color(1.0, 0.9, 0.3, 0.9)
	prompt.outline_modulate = Color.BLACK
	prompt.outline_size = 6
	prompt.visible = false
	body.add_child(prompt)

	# ── Proximity detection for interaction prompt ─────────────────────
	var detect_area := Area3D.new()
	detect_area.name = "PromptArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 1
	var detect_shape := CollisionShape3D.new()
	var detect_sphere := SphereShape3D.new()
	detect_sphere.radius = 4.0
	detect_shape.shape = detect_sphere
	detect_area.add_child(detect_shape)
	body.add_child(detect_area)
	detect_area.body_entered.connect(func(_b: Node3D) -> void:
		if prompt != null: prompt.visible = true
	)
	detect_area.body_exited.connect(func(_b: Node3D) -> void:
		if prompt != null: prompt.visible = false
	)

	# ── Face-player script (monster looks at player each frame) ─────────
	var look_scr: GDScript = load("res://scripts/dungeon/look_at_player.gd")
	if look_scr != null:
		var look_node := Node.new()
		look_node.name = "LookAtPlayer"
		look_node.set_script(look_scr)
		body.add_child(look_node)

	# ── Metadata ─────────────────────────────────────────────────────────
	body.set_meta("monster_data", monster_data)
	body.set_meta("rank", rank)

	parent.add_child(body)
	return body


## Distribute an array of monsters across a room.
## [param monsters]   Array of MonsterSpawn dictionaries.
## [param room_node]  The room's Node3D root.
## [param room_size]  Room dimensions in grid cells (Vector2i).
func spawn_monsters_in_room(monsters: Array, room_node: Node3D, room_size: Vector2i) -> void:
	if monsters.is_empty():
		return

	var spawn_root := Node3D.new()
	spawn_root.name = "Monsters"
	room_node.add_child(spawn_root)

	# Calculate positions in a grid inside the room, keeping away from walls.
	var margin: float = 2.0
	var usable_x: float = maxf(room_size.x - margin * 2.0, 1.0)
	var usable_z: float = maxf(room_size.y - margin * 2.0, 1.0)

	# Apply difficulty monster_count_multiplier.
	var count_mult: float = 1.0
	var diff_mgr_node: Node = null
	if Engine.has_singleton("DifficultyManager"):
		diff_mgr_node = Engine.get_singleton("DifficultyManager")
	elif room_node.get_tree() != null and room_node.get_tree().root.has_node("DifficultyManager"):
		diff_mgr_node = room_node.get_tree().root.get_node("DifficultyManager")
	if diff_mgr_node != null and diff_mgr_node.has_method("get_current_params"):
		var diff_params: Dictionary = diff_mgr_node.get_current_params()
		count_mult = float(diff_params.get("monster_count_multiplier", 1.0))

	# Expand each MonsterSpawn entry by its count (scaled by difficulty).
	var expanded: Array[Dictionary] = []
	for m in monsters:
		var count: int = maxi(1, roundi(m.get("count", 1) * count_mult))
		for _i in range(count):
			expanded.append(m)

	var total: int = expanded.size()
	var cols: int = ceili(sqrt(float(total)))
	var rows: int = ceili(float(total) / cols)

	var step_x: float = usable_x / maxf(cols, 1)
	var step_z: float = usable_z / maxf(rows, 1)

	var idx: int = 0
	for row in range(rows):
		for col in range(cols):
			if idx >= total:
				break
			var pos := Vector3(
				-usable_x * 0.5 + step_x * (col + 0.5),
				0.0,
				-usable_z * 0.5 + step_z * (row + 0.5)
			)
			spawn_monster(expanded[idx], spawn_root, pos)
			idx += 1


## Compute the combined AABB of a model's mesh instances.
static func _get_model_aabb(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in model.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			if mi.mesh != null:
				var child_aabb: AABB = mi.mesh.get_aabb()
				child_aabb.position += mi.position
				if first:
					result = child_aabb
					first = false
				else:
					result = result.merge(child_aabb)
	return result


## Create a simple capsule mesh as a fallback when no model is available.
static func _make_fallback_capsule() -> Node3D:
	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	capsule.material = mat
	mesh_inst.mesh = capsule
	mesh_inst.position.y = 0.6
	return mesh_inst
