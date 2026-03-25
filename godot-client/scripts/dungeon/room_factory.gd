## Factory for creating procedural room geometry based on room type.
##
## Generates floor, walls (with doorway gaps), ceiling, and ambient lighting —
## all using built-in Godot primitives so no external assets are required.
class_name RoomFactory
extends RefCounted

# ── Room-type colour palette ────────────────────────────────────────────────

const ROOM_COLORS: Dictionary = {
	"entrance":  Color("#888888"),
	"corridor":  Color("#555555"),
	"combat":    Color("#8B0000"),
	"treasure":  Color("#DAA520"),
	"trap":      Color("#CC4400"),
	"puzzle":    Color("#4169E1"),
	"rest":      Color("#DEB887"),
	"shop":      Color("#228B22"),
	"boss":      Color("#4B0082"),
	"secret":    Color("#008080"),
	"event":     Color("#C0C0C0"),
}

# Default colour when the room type is unknown.
const DEFAULT_COLOR: Color = Color("#666666")

# Wall thickness in metres.
const WALL_THICKNESS: float = 0.4
# Wall height in metres.
const WALL_HEIGHT: float = 4.0
# Doorway opening width in metres.
const DOOR_WIDTH: float = 3.0
# Doorway opening height in metres.
const DOOR_HEIGHT: float = 3.5

# ── Size look-up ────────────────────────────────────────────────────────────

## Translate the server's size string ("small" .. "huge") to a Vector2i
## representing the room dimensions in grid cells.  Each cell ≈ 1 m.
static func size_string_to_vector(size_str: String) -> Vector2i:
	match size_str:
		"small":
			return Vector2i(6, 6)
		"medium":
			return Vector2i(10, 10)
		"large":
			return Vector2i(14, 14)
		"huge":
			return Vector2i(18, 18)
		_:
			return Vector2i(10, 10)


# ── Public API ──────────────────────────────────────────────────────────────

## Create the complete room mesh hierarchy (floor + walls + ceiling + light).
## [param room_type]  One of the RoomType enum strings from the server.
## [param size]       Room dimensions in grid cells.
## [param connections] Dictionary mapping direction strings to target room ids.
##                     Used to decide which walls get doorway openings.
static func create_room_mesh(room_type: String, size: Vector2i, connections: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "RoomMesh"

	# Floor
	var floor_mesh := create_floor_mesh(size, room_type)
	root.add_child(floor_mesh)

	# Walls (with doorway gaps where connections exist)
	var walls := create_walls(size, connections, room_type)
	root.add_child(walls)

	# Ceiling
	var ceiling := create_ceiling(size)
	root.add_child(ceiling)

	# Ambient light coloured to match room type
	var light := _create_room_light(room_type, size)
	root.add_child(light)

	# Decorative props (columns, barrels, etc.) using Kenney dungeon assets
	var props := _spawn_room_props(room_type, size)
	if props != null:
		root.add_child(props)

	return root


## Return a StandardMaterial3D tinted to the room type colour.
static func get_room_material(room_type: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var color: Color = ROOM_COLORS.get(room_type, DEFAULT_COLOR)
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.05
	return mat


## Create the floor plane.
static func create_floor_mesh(size: Vector2i, room_type: String = "corridor") -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Floor"

	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.y)
	mesh_inst.mesh = plane

	var mat := get_room_material(room_type)
	# Darken the floor slightly relative to the base colour.
	mat.albedo_color = mat.albedo_color.darkened(0.25)
	mesh_inst.material_override = mat

	# Floor sits at y = 0.
	mesh_inst.position = Vector3.ZERO

	# Add collision so CharacterBody3D doesn't fall through.
	var body := StaticBody3D.new()
	body.name = "FloorBody"
	var col := CollisionShape3D.new()
	col.name = "FloorCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(size.x), 0.1, float(size.y))
	col.shape = shape
	col.position = Vector3(0, -0.05, 0)
	body.add_child(col)
	mesh_inst.add_child(body)

	return mesh_inst


## Create walls around the room perimeter.
## Walls are omitted (or have a doorway gap) on sides that have connections.
static func create_walls(size: Vector2i, connections: Dictionary = {}, room_type: String = "corridor") -> Node3D:
	var walls_root := Node3D.new()
	walls_root.name = "Walls"

	var half_x: float = size.x * 0.5
	var half_z: float = size.y * 0.5
	var mat := get_room_material(room_type)
	mat.albedo_color = mat.albedo_color.lightened(0.1)

	# Each cardinal direction: position, rotation, length
	var sides: Array[Dictionary] = [
		{
			"dir": "north",
			"pos": Vector3(0, WALL_HEIGHT * 0.5, -half_z),
			"rot": 0.0,
			"length": float(size.x),
		},
		{
			"dir": "south",
			"pos": Vector3(0, WALL_HEIGHT * 0.5, half_z),
			"rot": 0.0,
			"length": float(size.x),
		},
		{
			"dir": "east",
			"pos": Vector3(half_x, WALL_HEIGHT * 0.5, 0),
			"rot": PI * 0.5,
			"length": float(size.y),
		},
		{
			"dir": "west",
			"pos": Vector3(-half_x, WALL_HEIGHT * 0.5, 0),
			"rot": PI * 0.5,
			"length": float(size.y),
		},
	]

	for side in sides:
		var has_door: bool = connections.has(side["dir"])
		if has_door:
			# Build wall with a doorway opening in the centre.
			var wall_pair := _create_wall_with_doorway(
				side["length"] as float,
				side["pos"] as Vector3,
				side["rot"] as float,
				side["dir"] as String,
				mat
			)
			walls_root.add_child(wall_pair)
		else:
			# Solid wall segment.
			var wall := _create_solid_wall(
				side["length"] as float,
				side["pos"] as Vector3,
				side["rot"] as float,
				mat
			)
			walls_root.add_child(wall)

	return walls_root


## Create a ceiling plane (semi-transparent so the camera can see in).
static func create_ceiling(size: Vector2i) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Ceiling"

	var plane := PlaneMesh.new()
	plane.size = Vector2(size.x, size.y)
	mesh_inst.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.2, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_FRONT  # visible from below
	mat.roughness = 1.0
	mesh_inst.material_override = mat

	mesh_inst.position = Vector3(0, WALL_HEIGHT, 0)
	return mesh_inst


# ── Internal helpers ────────────────────────────────────────────────────────

## A full-length solid wall (no doorway) with stone-like appearance.
static func _create_solid_wall(length: float, pos: Vector3, y_rot: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Wall"
	var box := BoxMesh.new()
	box.size = Vector3(length, WALL_HEIGHT, WALL_THICKNESS)
	mesh_inst.mesh = box
	# Stone wall material — darker, rougher than room color
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = mat.albedo_color.lerp(Color(0.25, 0.22, 0.2), 0.7)
	wall_mat.roughness = 0.95
	wall_mat.metallic = 0.05
	mesh_inst.material_override = wall_mat
	mesh_inst.position = pos
	mesh_inst.rotation.y = y_rot
	var body := StaticBody3D.new()
	body.name = "WallBody"
	var shape := BoxShape3D.new()
	shape.size = box.size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	mesh_inst.add_child(body)
	return mesh_inst


## A wall split into two segments with a doorway gap in the centre.
static func _create_wall_with_doorway(length: float, pos: Vector3, y_rot: float, dir_name: String, mat: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Wall_%s" % dir_name
	root.position = pos
	root.rotation.y = y_rot

	# Calculate segment sizes.
	var segment_length: float = (length - DOOR_WIDTH) * 0.5
	if segment_length < 0.1:
		# Room too small for a proper doorway; skip wall entirely.
		return root

	var offset: float = (DOOR_WIDTH + segment_length) * 0.5

	# Left segment
	var left := MeshInstance3D.new()
	left.name = "WallLeft"
	var box_l := BoxMesh.new()
	box_l.size = Vector3(segment_length, WALL_HEIGHT, WALL_THICKNESS)
	left.mesh = box_l
	left.material_override = mat
	left.position = Vector3(-offset, 0, 0)

	var body_l := StaticBody3D.new()
	var shape_l := BoxShape3D.new()
	shape_l.size = box_l.size
	var col_l := CollisionShape3D.new()
	col_l.shape = shape_l
	body_l.add_child(col_l)
	left.add_child(body_l)
	root.add_child(left)

	# Right segment
	var right := MeshInstance3D.new()
	right.name = "WallRight"
	var box_r := BoxMesh.new()
	box_r.size = Vector3(segment_length, WALL_HEIGHT, WALL_THICKNESS)
	right.mesh = box_r
	right.material_override = mat
	right.position = Vector3(offset, 0, 0)

	var body_r := StaticBody3D.new()
	var shape_r := BoxShape3D.new()
	shape_r.size = box_r.size
	var col_r := CollisionShape3D.new()
	col_r.shape = shape_r
	body_r.add_child(col_r)
	right.add_child(body_r)
	root.add_child(right)

	# Lintel above doorway
	var lintel := MeshInstance3D.new()
	lintel.name = "Lintel"
	var lintel_height: float = WALL_HEIGHT - DOOR_HEIGHT
	if lintel_height > 0.05:
		var box_t := BoxMesh.new()
		box_t.size = Vector3(DOOR_WIDTH, lintel_height, WALL_THICKNESS)
		lintel.mesh = box_t
		lintel.material_override = mat
		lintel.position = Vector3(0, (WALL_HEIGHT - lintel_height) * 0.5, 0)
		var body_t := StaticBody3D.new()
		var shape_t := BoxShape3D.new()
		shape_t.size = box_t.size
		var col_t := CollisionShape3D.new()
		col_t.shape = shape_t
		body_t.add_child(col_t)
		lintel.add_child(body_t)
		root.add_child(lintel)

	return root


## Create an OmniLight3D centred in the room, tinted by room type.
static func _create_room_light(room_type: String, size: Vector2i) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "RoomLight"

	var color: Color = ROOM_COLORS.get(room_type, DEFAULT_COLOR)
	# Blend toward white so the light is not overly saturated.
	light.light_color = color.lerp(Color.WHITE, 0.55)
	light.light_energy = 1.2
	light.omni_range = maxf(size.x, size.y) * 0.75
	light.omni_attenuation = 1.2
	light.shadow_enabled = true
	light.position = Vector3(0, WALL_HEIGHT * 0.8, 0)

	return light


## Spawn decorative props in the room using Kenney dungeon assets.
static func _spawn_room_props(room_type: String, size: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Props"

	var half_x: float = size.x * 0.5 - 1.0
	var half_z: float = size.y * 0.5 - 1.0

	# Columns in corners for medium+ rooms
	if size.x >= 8 and size.y >= 8:
		var col_scene: PackedScene = AssetRegistry.load_model(AssetRegistry.DUNGEON_PROPS.get("pillar", ""))
		if col_scene != null:
			for corner in [Vector3(-half_x + 1, 0, -half_z + 1), Vector3(half_x - 1, 0, -half_z + 1),
						   Vector3(-half_x + 1, 0, half_z - 1), Vector3(half_x - 1, 0, half_z - 1)]:
				var col_inst: Node3D = col_scene.instantiate()
				col_inst.position = corner
				root.add_child(col_inst)

	# Room-type specific props
	match room_type:
		"treasure":
			var chest_scene: PackedScene = AssetRegistry.load_model(AssetRegistry.DUNGEON_PROPS.get("chest", ""))
			if chest_scene != null:
				var chest: Node3D = chest_scene.instantiate()
				chest.position = Vector3(0, 0, -half_z * 0.3)
				root.add_child(chest)
		"rest":
			var banner_scene: PackedScene = AssetRegistry.load_model(AssetRegistry.DUNGEON_PROPS.get("banner", ""))
			if banner_scene != null:
				var banner: Node3D = banner_scene.instantiate()
				banner.position = Vector3(0, 0, -half_z * 0.5)
				root.add_child(banner)
		"shop":
			var barrel_scene: PackedScene = AssetRegistry.load_model(AssetRegistry.DUNGEON_PROPS.get("barrel", ""))
			if barrel_scene != null:
				for bx in [-2.0, 2.0]:
					var barrel: Node3D = barrel_scene.instantiate()
					barrel.position = Vector3(bx, 0, -half_z * 0.4)
					root.add_child(barrel)

	# Scattered rocks for combat/boss rooms
	if room_type in ["combat", "boss"]:
		var rocks_scene: PackedScene = AssetRegistry.load_model(AssetRegistry.DUNGEON_PROPS.get("rocks", ""))
		if rocks_scene != null:
			var rng := RandomNumberGenerator.new()
			rng.seed = int(half_x * 1000 + half_z)
			for _i in range(rng.randi_range(2, 4)):
				var rock: Node3D = rocks_scene.instantiate()
				rock.position = Vector3(
					rng.randf_range(-half_x * 0.6, half_x * 0.6), 0,
					rng.randf_range(-half_z * 0.6, half_z * 0.6))
				rock.rotation.y = rng.randf_range(0, TAU)
				root.add_child(rock)

	return root
