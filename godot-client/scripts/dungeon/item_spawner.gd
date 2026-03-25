## Spawns placeholder item nodes inside dungeon rooms.
##
## Each item is a StaticBody3D with a small coloured cube, a floating
## bob animation, a Label3D name tag, and an Area3D for pickup detection.
class_name ItemSpawner
extends RefCounted

# ── Rarity colour mapping ───────────────────────────────────────────────────

const RARITY_COLORS: Dictionary = {
	"common":    Color(0.90, 0.90, 0.90),   # white
	"uncommon":  Color(0.20, 0.80, 0.20),   # green
	"rare":      Color(0.25, 0.40, 0.95),   # blue
	"epic":      Color(0.60, 0.15, 0.80),   # purple
	"legendary": Color(1.00, 0.55, 0.05),   # orange
	"abyssal":   Color(0.05, 0.05, 0.05),   # near-black (with glow)
}

const DEFAULT_RARITY_COLOR: Color = Color(0.90, 0.90, 0.90)

# Cube half-size
const ITEM_SIZE: float = 0.3
# Height at which items float
const FLOAT_BASE_Y: float = 0.8
# Bob animation amplitude
const BOB_AMPLITUDE: float = 0.15
# Bob cycle duration (seconds)
const BOB_DURATION: float = 2.0


# ── Public API ──────────────────────────────────────────────────────────────

## Create a single item placeholder at the given position.
## [param item_data]  Dictionary from the AI server (ItemDrop schema).
## [param parent]     Node to attach the item to.
## [param position]   World-space position for the item.
## Returns the created StaticBody3D node.
func spawn_item(item_data: Dictionary, parent: Node3D, position: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.name = "Item_%s" % item_data.get("item_id", item_data.get("name", "unknown"))
	body.position = position

	# ── Pivot node for the floating animation ────────────────────────────
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position.y = FLOAT_BASE_Y
	body.add_child(pivot)

	# ── Visual mesh ──────────────────────────────────────────────────────
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(ITEM_SIZE, ITEM_SIZE, ITEM_SIZE)
	mesh_inst.mesh = box_mesh

	var rarity: String = item_data.get("rarity", "common")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RARITY_COLORS.get(rarity, DEFAULT_RARITY_COLOR)
	mat.roughness = 0.3
	mat.metallic = 0.4

	# Abyssal and legendary items glow
	if rarity in ["abyssal", "legendary", "epic"]:
		mat.emission_enabled = true
		mat.emission = RARITY_COLORS.get(rarity, DEFAULT_RARITY_COLOR)
		if rarity == "abyssal":
			mat.emission = Color(0.3, 0.0, 0.5)
		mat.emission_energy_multiplier = 1.8

	mesh_inst.material_override = mat
	pivot.add_child(mesh_inst)

	# ── Name label ───────────────────────────────────────────────────────
	var label := Label3D.new()
	label.name = "NameLabel"
	label.text = item_data.get("name", "???")
	label.font_size = 40
	label.pixel_size = 0.01
	label.position = Vector3(0, ITEM_SIZE + 0.35, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = RARITY_COLORS.get(rarity, DEFAULT_RARITY_COLOR)
	label.outline_modulate = Color.BLACK
	label.outline_size = 6
	pivot.add_child(label)

	# ── Rarity label ─────────────────────────────────────────────────────
	var rarity_label := Label3D.new()
	rarity_label.name = "RarityLabel"
	rarity_label.text = "[%s]" % _get_rarity_display(rarity)
	rarity_label.font_size = 32
	rarity_label.pixel_size = 0.01
	rarity_label.position = Vector3(0, ITEM_SIZE + 0.6, 0)
	rarity_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	rarity_label.modulate = RARITY_COLORS.get(rarity, DEFAULT_RARITY_COLOR)
	rarity_label.outline_modulate = Color.BLACK
	rarity_label.outline_size = 4
	pivot.add_child(rarity_label)

	# ── Pickup Area3D ────────────────────────────────────────────────────
	var area := Area3D.new()
	area.name = "PickupArea"
	area.monitoring = true
	area.monitorable = false
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.2
	col.shape = sphere
	area.add_child(col)
	body.add_child(area)

	# ── Floating bob animation (Tween) ───────────────────────────────────
	# We defer the tween creation so the node is in the tree first.
	pivot.ready.connect(func() -> void:
		_start_bob_tween(pivot)
	)

	# ── Spin the mesh gently ─────────────────────────────────────────────
	mesh_inst.ready.connect(func() -> void:
		_start_spin_tween(mesh_inst)
	)

	# ── Metadata ─────────────────────────────────────────────────────────
	body.set_meta("item_data", item_data)
	body.set_meta("rarity", rarity)

	parent.add_child(body)
	return body


## Distribute an array of items across a room.
## [param items]      Array of ItemDrop dictionaries.
## [param room_node]  The room's Node3D root.
## [param room_size]  Room dimensions in grid cells (Vector2i).
func spawn_items_in_room(items: Array, room_node: Node3D, room_size: Vector2i) -> void:
	if items.is_empty():
		return

	var spawn_root := Node3D.new()
	spawn_root.name = "Items"
	room_node.add_child(spawn_root)

	var margin: float = 2.5
	var usable_x: float = maxf(room_size.x - margin * 2.0, 1.0)
	var usable_z: float = maxf(room_size.y - margin * 2.0, 1.0)

	var total: int = items.size()
	# Spread items evenly along a line or small grid.
	var cols: int = mini(total, 4)
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
			spawn_item(items[idx], spawn_root, pos)
			idx += 1


# ── Internal helpers ────────────────────────────────────────────────────────

## Start a looping vertical bob tween on the pivot node.
func _start_bob_tween(pivot: Node3D) -> void:
	var tween := pivot.create_tween()
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	var base_y: float = pivot.position.y
	tween.tween_property(pivot, "position:y", base_y + BOB_AMPLITUDE, BOB_DURATION * 0.5)
	tween.tween_property(pivot, "position:y", base_y, BOB_DURATION * 0.5)


## Start a slow continuous Y-axis spin on the mesh.
func _start_spin_tween(mesh: MeshInstance3D) -> void:
	var tween := mesh.create_tween()
	tween.set_loops()
	tween.tween_property(mesh, "rotation:y", TAU, 4.0).as_relative()


## Map rarity key to Korean display text.
func _get_rarity_display(rarity: String) -> String:
	match rarity:
		"common":
			return "일반"
		"uncommon":
			return "고급"
		"rare":
			return "희귀"
		"epic":
			return "영웅"
		"legendary":
			return "전설"
		"abyssal":
			return "심연"
		_:
			return rarity
