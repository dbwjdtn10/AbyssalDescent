## A corridor connecting two dungeon rooms.
##
## Generates a simple hallway with floor, walls, and ceiling between two
## world-space points.  Supports both straight and L-shaped corridors.
class_name DungeonCorridor
extends Node3D

# ── Properties ──────────────────────────────────────────────────────────────

## Room id at the start of the corridor.
var start_room_id: String = ""

## Room id at the end of the corridor.
var end_room_id: String = ""

## Total path length of the corridor in metres.
var length: float = 0.0

# ── Constants ───────────────────────────────────────────────────────────────

const WALL_HEIGHT: float = 4.0
const WALL_THICKNESS: float = 0.3
const FLOOR_Y_OFFSET: float = 0.0
const CEILING_ALPHA: float = 0.25

# ── Material cache ──────────────────────────────────────────────────────────

var _floor_mat: StandardMaterial3D = null
var _wall_mat: StandardMaterial3D = null
var _ceiling_mat: StandardMaterial3D = null


# ── Public API ──────────────────────────────────────────────────────────────

## Build corridor geometry between two world-space points.
## [param start_pos]  World position of the corridor entrance.
## [param end_pos]    World position of the corridor exit.
## [param width]      Width of the corridor in metres.
## [param avoid_rects] Array of Rect2 (XZ bounding boxes) of rooms to avoid.
func build_between(start_pos: Vector3, end_pos: Vector3, width: float = 3.0, avoid_rects: Array = []) -> void:
	_init_materials()

	# Clear any existing geometry.
	for child in get_children():
		child.queue_free()

	# Determine if the corridor needs to be L-shaped.
	var dx: float = end_pos.x - start_pos.x
	var dz: float = end_pos.z - start_pos.z

	# Position the corridor root at the start.
	global_position = start_pos

	if absf(dx) < 0.1 or absf(dz) < 0.1:
		# Straight corridor (aligned on one axis).
		_build_straight_segment(start_pos, end_pos, width)
		length = start_pos.distance_to(end_pos)
	else:
		# L-shaped: try both routing options and pick the one that avoids rooms.
		var corner_x_first := Vector3(end_pos.x, start_pos.y, start_pos.z)
		var corner_z_first := Vector3(start_pos.x, start_pos.y, end_pos.z)

		var use_x_first: bool = true
		if not avoid_rects.is_empty():
			var x_first_clear: bool = _route_avoids_rooms(start_pos, corner_x_first, end_pos, width, avoid_rects)
			var z_first_clear: bool = _route_avoids_rooms(start_pos, corner_z_first, end_pos, width, avoid_rects)
			if not x_first_clear and z_first_clear:
				use_x_first = false

		var corner: Vector3 = corner_x_first if use_x_first else corner_z_first
		_build_straight_segment(start_pos, corner, width)
		_build_straight_segment(corner, end_pos, width)
		_build_corner(corner, start_pos, end_pos, width)
		length = absf(dx) + absf(dz)


# ── Geometry builders ───────────────────────────────────────────────────────

## Build a straight corridor segment between two axis-aligned points.
func _build_straight_segment(from: Vector3, to: Vector3, width: float) -> void:
	var delta := to - from
	var seg_length: float = delta.length()
	if seg_length < 0.01:
		return

	# Extend segment slightly to seal gaps at room wall junctions.
	seg_length += WALL_THICKNESS * 2.0

	var mid := (from + to) * 0.5
	# The segment is local to this node; convert to local coords.
	var local_mid := mid - global_position

	# Determine orientation (rotation around Y).
	var y_rot: float = 0.0
	if absf(delta.x) > absf(delta.z):
		# Runs along X axis.
		y_rot = 0.0
	else:
		# Runs along Z axis.
		y_rot = PI * 0.5

	var segment := Node3D.new()
	segment.name = "Segment"
	segment.position = local_mid
	segment.rotation.y = y_rot
	add_child(segment)

	# ── Floor ────────────────────────────────────────────────────────────
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "CorridorFloor"
	var plane := PlaneMesh.new()
	# When y_rot == 0, the segment extends along X, so plane X = seg_length.
	plane.size = Vector2(seg_length, width)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _floor_mat
	floor_mesh.position.y = FLOOR_Y_OFFSET
	segment.add_child(floor_mesh)

	# Floor collision
	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorBody"
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(seg_length, 0.1, width)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0, FLOOR_Y_OFFSET - 0.05, 0)
	floor_body.add_child(floor_col)
	segment.add_child(floor_body)

	# ── Walls ────────────────────────────────────────────────────────────
	var half_w: float = width * 0.5

	# Left wall
	var left_wall := _create_wall_mesh(seg_length, WALL_HEIGHT, WALL_THICKNESS)
	left_wall.name = "WallLeft"
	left_wall.position = Vector3(0, WALL_HEIGHT * 0.5, -half_w)
	segment.add_child(left_wall)

	# Right wall
	var right_wall := _create_wall_mesh(seg_length, WALL_HEIGHT, WALL_THICKNESS)
	right_wall.name = "WallRight"
	right_wall.position = Vector3(0, WALL_HEIGHT * 0.5, half_w)
	segment.add_child(right_wall)

	# ── Ceiling ──────────────────────────────────────────────────────────
	var ceiling := MeshInstance3D.new()
	ceiling.name = "CorridorCeiling"
	var ceil_plane := PlaneMesh.new()
	ceil_plane.size = Vector2(seg_length, width)
	ceiling.mesh = ceil_plane
	ceiling.material_override = _ceiling_mat
	ceiling.position.y = WALL_HEIGHT
	ceiling.rotation.x = PI  # flip to face downward
	segment.add_child(ceiling)

	# ── Lighting ─────────────────────────────────────────────────────────
	var light := OmniLight3D.new()
	light.name = "CorridorLight"
	light.light_color = Color(0.7, 0.65, 0.55)
	light.light_energy = 0.6
	light.omni_range = seg_length * 0.6
	light.omni_attenuation = 1.5
	light.position = Vector3(0, WALL_HEIGHT * 0.7, 0)
	segment.add_child(light)


## Build a small floor patch at the corner of an L-shaped corridor,
## including outer walls to seal the bend.
func _build_corner(corner_pos: Vector3, start_pos: Vector3, end_pos: Vector3, width: float) -> void:
	var local_corner := corner_pos - global_position
	var corner_node := Node3D.new()
	corner_node.name = "Corner"
	corner_node.position = local_corner
	add_child(corner_node)

	var half_w: float = width * 0.5

	# Square floor at the corner.
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "CornerFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, width)
	floor_mesh.mesh = plane
	floor_mesh.material_override = _floor_mat
	floor_mesh.position.y = FLOOR_Y_OFFSET
	corner_node.add_child(floor_mesh)

	# Corner floor collision
	var floor_body := StaticBody3D.new()
	floor_body.name = "CornerFloorBody"
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(width, 0.1, width)
	floor_col.shape = floor_shape
	floor_col.position = Vector3(0, FLOOR_Y_OFFSET - 0.05, 0)
	floor_body.add_child(floor_col)
	corner_node.add_child(floor_body)

	# Ceiling at the corner.
	var ceiling := MeshInstance3D.new()
	ceiling.name = "CornerCeiling"
	var ceil_plane := PlaneMesh.new()
	ceil_plane.size = Vector2(width, width)
	ceiling.mesh = ceil_plane
	ceiling.material_override = _ceiling_mat
	ceiling.position.y = WALL_HEIGHT
	ceiling.rotation.x = PI
	corner_node.add_child(ceiling)

	# ── Outer corner walls ──────────────────────────────────────────────
	# Determine which two sides of the corner square are "outer" (not
	# facing a corridor segment) and need walls.
	var dx_in: float = corner_pos.x - start_pos.x  # direction FROM start TO corner
	var dz_in: float = corner_pos.z - start_pos.z
	var dx_out: float = end_pos.x - corner_pos.x    # direction FROM corner TO end
	var dz_out: float = end_pos.z - corner_pos.z

	# Incoming segment arrives along X or Z.  Outgoing departs along the other.
	# We need walls on the two outer edges of the L-bend.
	# Outer edge 1: perpendicular to incoming, on the side opposite to the turn.
	# Outer edge 2: perpendicular to outgoing, on the side opposite to the turn.

	# Determine outer wall positions based on the L-bend direction.
	var wall_positions: Array[Dictionary] = []

	if absf(dx_in) > 0.1:
		# Incoming runs along X.  Outgoing runs along Z.
		# Outer wall along Z side (perpendicular to incoming).
		var z_sign: float = -signf(dz_out)  # opposite side of the turn
		wall_positions.append({
			"pos": Vector3(0, WALL_HEIGHT * 0.5, z_sign * half_w),
			"length": width,
			"rot": 0.0,
		})
		# Outer wall along X side (perpendicular to outgoing).
		var x_sign: float = signf(dx_in)  # same side as where we came from
		wall_positions.append({
			"pos": Vector3(x_sign * half_w, WALL_HEIGHT * 0.5, 0),
			"length": width,
			"rot": PI * 0.5,
		})
	else:
		# Incoming runs along Z.  Outgoing runs along X.
		# Outer wall along X side (perpendicular to incoming).
		var x_sign: float = -signf(dx_out)
		wall_positions.append({
			"pos": Vector3(x_sign * half_w, WALL_HEIGHT * 0.5, 0),
			"length": width,
			"rot": PI * 0.5,
		})
		# Outer wall along Z side (perpendicular to outgoing).
		var z_sign: float = signf(dz_in)
		wall_positions.append({
			"pos": Vector3(0, WALL_HEIGHT * 0.5, z_sign * half_w),
			"length": width,
			"rot": 0.0,
		})

	for wp: Dictionary in wall_positions:
		var wall := _create_wall_mesh(wp["length"] as float, WALL_HEIGHT, WALL_THICKNESS)
		wall.name = "CornerWall"
		wall.position = wp["pos"] as Vector3
		wall.rotation.y = wp["rot"] as float
		corner_node.add_child(wall)


# ── Helpers ─────────────────────────────────────────────────────────────────

## Create a wall MeshInstance3D with collision.
func _create_wall_mesh(seg_length: float, height: float, thickness: float) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(seg_length, height, thickness)
	mesh_inst.mesh = box
	mesh_inst.material_override = _wall_mat

	# Static collision.
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	mesh_inst.add_child(body)

	return mesh_inst


## Check whether an L-shaped route (start → corner → end) avoids all room rects.
## [param avoid_rects] Array of Rect2 representing room XZ bounding boxes.
func _route_avoids_rooms(start: Vector3, corner: Vector3, end: Vector3, width: float, avoid_rects: Array) -> bool:
	var half_w: float = width * 0.5 + 0.5  # small margin

	# Segment 1: start → corner
	var seg1_rect: Rect2 = _segment_to_rect(start, corner, half_w)
	# Segment 2: corner → end
	var seg2_rect: Rect2 = _segment_to_rect(corner, end, half_w)

	for rect: Variant in avoid_rects:
		if not rect is Rect2:
			continue
		var r: Rect2 = rect as Rect2
		if seg1_rect.intersects(r) or seg2_rect.intersects(r):
			return false
	return true


## Convert a corridor segment (two 3D points) to an XZ Rect2.
func _segment_to_rect(from: Vector3, to: Vector3, half_w: float) -> Rect2:
	var min_x: float = minf(from.x, to.x) - half_w
	var max_x: float = maxf(from.x, to.x) + half_w
	var min_z: float = minf(from.z, to.z) - half_w
	var max_z: float = maxf(from.z, to.z) + half_w
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


## Initialise shared materials for the corridor.
func _init_materials() -> void:
	if _floor_mat != null:
		return

	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = Color(0.25, 0.22, 0.20)
	_floor_mat.roughness = 0.9

	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.35, 0.32, 0.30)
	_wall_mat.roughness = 0.85

	_ceiling_mat = StandardMaterial3D.new()
	_ceiling_mat.albedo_color = Color(0.15, 0.15, 0.18, CEILING_ALPHA)
	_ceiling_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ceiling_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_ceiling_mat.roughness = 1.0
