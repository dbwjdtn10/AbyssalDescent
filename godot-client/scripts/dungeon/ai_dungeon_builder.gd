## Main orchestrator that converts AI server dungeon responses into 3D scenes.
##
## Call [method request_and_build_floor] to ask the AI server for a new floor
## and have it built automatically, or call [method build_floor] directly with
## pre-fetched data.
##
## Expects an AIClient autoload singleton to be registered in the project.
class_name AIDungeonBuilder
extends Node3D

# ── Signals ─────────────────────────────────────────────────────────────────

signal floor_built(floor_data: Dictionary)
signal floor_cleared

# ── Configuration ───────────────────────────────────────────────────────────

## Distance between room centres on the layout grid (metres).
@export var room_spacing: float = 22.0

## Width of corridors connecting rooms (metres).
@export var corridor_width: float = 3.0

# ── State ───────────────────────────────────────────────────────────────────

## The raw dictionary returned by the AI server for the current floor.
var current_floor_data: Dictionary = {}

## Map of room_id → DungeonRoom node.
var rooms: Dictionary = {}

## All corridor instances on the current floor.
var corridors: Array[DungeonCorridor] = []

## Internal grid positions computed during layout.  room_id → Vector2i.
var _grid_positions: Dictionary = {}


# ── Public API ──────────────────────────────────────────────────────────────

## Request dungeon data from the AI server and build the floor on response.
## This is the primary high-level entry point.
func request_and_build_floor(
	floor_num: int,
	difficulty: float,
	player_level: int,
	inventory: Array = [],
	visited: Array = [],
	seed_val: int = 0
) -> void:
	# Use the AIClient autoload singleton.
	var ai_client := _get_ai_client()
	if ai_client == null:
		push_error("AIDungeonBuilder: AIClient autoload not found.")
		return

	# Connect to the response signal (one-shot).
	if not ai_client.dungeon_generated.is_connected(_on_dungeon_data_received):
		ai_client.dungeon_generated.connect(_on_dungeon_data_received, CONNECT_ONE_SHOT)
	else:
		# Already connected — disconnect and reconnect as one-shot.
		ai_client.dungeon_generated.disconnect(_on_dungeon_data_received)
		ai_client.dungeon_generated.connect(_on_dungeon_data_received, CONNECT_ONE_SHOT)

	ai_client.generate_dungeon(floor_num, difficulty, player_level, inventory, visited, seed_val)


## Build a dungeon floor from an AI server response dictionary.
## Expected keys: floor_number, floor_name, floor_description, rooms[], boss, seed.
func build_floor(floor_data: Dictionary) -> void:
	clear_floor()
	current_floor_data = floor_data

	var rooms_data: Array = floor_data.get("rooms", [])
	if rooms_data.is_empty():
		push_warning("AIDungeonBuilder: floor data contains no rooms.")
		return

	# 1. Compute grid positions for each room using BFS from entrance.
	_grid_positions = _layout_rooms(rooms_data)

	# 1b. Enrich connections with computed directions based on grid positions.
	_enrich_connections(rooms_data)

	# 2. Instantiate rooms.
	for room_data in rooms_data:
		var rid: String = room_data.get("id", "")
		var grid_pos: Vector2i = _grid_positions.get(rid, Vector2i.ZERO)
		var world_pos := Vector3(grid_pos.x * room_spacing, 0, grid_pos.y * room_spacing)
		var room_node := _create_room(room_data, world_pos)
		rooms[rid] = room_node

	# 3. Create corridors between connected rooms.
	_connect_rooms()

	floor_built.emit(floor_data)
	print("AIDungeonBuilder: floor %d built — %d rooms, %d corridors." % [
		floor_data.get("floor_number", 0),
		rooms.size(),
		corridors.size(),
	])


## Convert simple string connections into direction-aware dictionaries
## based on computed grid positions.
func _enrich_connections(rooms_data: Array) -> void:
	for rd: Variant in rooms_data:
		if not rd is Dictionary:
			continue
		var rid: String = rd.get("id", "")
		var my_pos: Vector2i = _grid_positions.get(rid, Vector2i.ZERO)
		var raw_conns: Array = rd.get("connections", [])
		var enriched: Array = []

		for conn_item: Variant in raw_conns:
			var target_id: String = ""
			var direction: String = ""

			if conn_item is String:
				target_id = conn_item
			elif conn_item is Dictionary:
				target_id = conn_item.get("target_room_id", "")
				direction = conn_item.get("direction", "")

			if target_id.is_empty():
				continue

			# Compute direction from grid positions if missing.
			if direction.is_empty() and _grid_positions.has(target_id):
				var target_pos: Vector2i = _grid_positions.get(target_id, Vector2i.ZERO)
				var diff: Vector2i = target_pos - my_pos
				if abs(diff.x) >= abs(diff.y):
					direction = "east" if diff.x > 0 else "west"
				else:
					direction = "south" if diff.y > 0 else "north"

			enriched.append({
				"direction": direction,
				"target_room_id": target_id,
				"is_locked": false,
				"lock_type": "",
			})

		rd["connections"] = enriched


## Destroy all rooms and corridors for the current floor.
func clear_floor() -> void:
	for rid in rooms:
		var room_node: DungeonRoom = rooms[rid]
		if is_instance_valid(room_node):
			room_node.queue_free()
	rooms.clear()

	for corridor in corridors:
		if is_instance_valid(corridor):
			corridor.queue_free()
	corridors.clear()

	_grid_positions.clear()
	current_floor_data = {}

	floor_cleared.emit()


## Retrieve a room node by its id.
func get_room(room_id: String) -> DungeonRoom:
	return rooms.get(room_id, null) as DungeonRoom


## Return the world-space position of the entrance room (first room, or origin).
func get_entrance_position() -> Vector3:
	# Find the entrance room.
	for rid in rooms:
		var room_node: DungeonRoom = rooms[rid]
		if room_node.room_type == "entrance":
			return room_node.global_position
	# Fallback: return position of the first room.
	if not rooms.is_empty():
		var first_key: String = rooms.keys()[0]
		return (rooms[first_key] as DungeonRoom).global_position
	return Vector3.ZERO


# ── Layout algorithm ────────────────────────────────────────────────────────

## Assign grid positions to rooms using BFS outward from the entrance.
## Returns a Dictionary mapping room_id → Vector2i grid coordinate.
func _layout_rooms(rooms_data: Array) -> Dictionary:
	var positions: Dictionary = {}  # room_id → Vector2i
	var occupied: Dictionary = {}   # Vector2i key string → room_id

	# Build an adjacency map:  room_id → [{direction, target_room_id}]
	var adjacency: Dictionary = {}
	var room_map: Dictionary = {}   # room_id → room_data
	var entrance_id: String = ""

	for rd in rooms_data:
		var rid: String = rd.get("id", "")
		room_map[rid] = rd
		adjacency[rid] = rd.get("connections", [])
		if rd.get("type", "") == "entrance" and entrance_id.is_empty():
			entrance_id = rid

	# If no entrance found, use the first room.
	if entrance_id.is_empty() and not rooms_data.is_empty():
		entrance_id = rooms_data[0].get("id", "")

	# Direction → grid offset
	var dir_offsets: Dictionary = {
		"north": Vector2i(0, -1),
		"south": Vector2i(0, 1),
		"east":  Vector2i(1, 0),
		"west":  Vector2i(-1, 0),
	}

	# BFS — track used directions per room to spread children evenly.
	var used_dirs_per_room: Dictionary = {}  # room_id → Array[String]

	var queue: Array[String] = [entrance_id]
	positions[entrance_id] = Vector2i.ZERO
	occupied[_v2i_key(Vector2i.ZERO)] = entrance_id

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current_pos: Vector2i = positions[current_id]

		# Initialise used-directions for this room from already-placed neighbours.
		if not used_dirs_per_room.has(current_id):
			used_dirs_per_room[current_id] = [] as Array[String]
		var my_used: Array = used_dirs_per_room[current_id]

		var conns: Array = adjacency.get(current_id, [])

		# First pass: record directions already consumed by placed neighbours.
		for conn_item: Variant in conns:
			var tid: String = ""
			if conn_item is String:
				tid = conn_item
			elif conn_item is Dictionary:
				tid = conn_item.get("target_room_id", "")
			if tid.is_empty() or not positions.has(tid):
				continue
			var diff: Vector2i = positions[tid] - current_pos
			var used_dir: String = ""
			if diff == Vector2i(0, -1):
				used_dir = "north"
			elif diff == Vector2i(0, 1):
				used_dir = "south"
			elif diff == Vector2i(1, 0):
				used_dir = "east"
			elif diff == Vector2i(-1, 0):
				used_dir = "west"
			if not used_dir.is_empty() and used_dir not in my_used:
				my_used.append(used_dir)

		# Second pass: place unplaced neighbours.
		for conn_item: Variant in conns:
			var target_id: String = ""
			var dir_str: String = ""

			if conn_item is String:
				target_id = conn_item
			elif conn_item is Dictionary:
				target_id = conn_item.get("target_room_id", "")
				dir_str = conn_item.get("direction", "")

			if target_id.is_empty() or positions.has(target_id):
				continue

			# If no direction specified, pick a free cardinal direction
			# that hasn't been used from this room yet.
			if dir_str.is_empty():
				var tried_dirs: Array[String] = ["south", "east", "west", "north"]
				for try_dir: String in tried_dirs:
					if try_dir in my_used:
						continue
					var try_offset: Vector2i = dir_offsets[try_dir]
					var try_cell: Vector2i = current_pos + try_offset
					if not occupied.has(_v2i_key(try_cell)):
						dir_str = try_dir
						break
				# If all preferred directions used, fall back to any free one.
				if dir_str.is_empty():
					for try_dir: String in ["south", "east", "west", "north"]:
						var try_offset: Vector2i = dir_offsets[try_dir]
						var try_cell: Vector2i = current_pos + try_offset
						if not occupied.has(_v2i_key(try_cell)):
							dir_str = try_dir
							break

			if not dir_str.is_empty():
				my_used.append(dir_str)

			var offset: Vector2i = dir_offsets.get(dir_str, Vector2i(1, 0))
			var candidate: Vector2i = current_pos + offset

			# Resolve collisions — try the preferred direction first,
			# then spiral outward.
			candidate = _find_free_cell(candidate, occupied)

			positions[target_id] = candidate
			occupied[_v2i_key(candidate)] = target_id
			queue.append(target_id)

	# Handle any rooms not reached by BFS (disconnected subgraphs).
	var next_x: int = 0
	var next_z: int = 0
	for rd in rooms_data:
		var remaining_rid: String = rd.get("id", "")
		if positions.has(remaining_rid):
			continue
		# Place on the next available row below existing rooms.
		next_z += 2
		var fallback := _find_free_cell(Vector2i(next_x, next_z), occupied)
		positions[remaining_rid] = fallback
		occupied[_v2i_key(fallback)] = remaining_rid

	return positions


## Instantiate a DungeonRoom at the given world position.
func _create_room(room_data: Dictionary, position: Vector3) -> DungeonRoom:
	var room := DungeonRoom.new()
	room.position = position
	add_child(room)
	room.setup(room_data)
	return room


## Create corridors based on connection data in each room.
func _connect_rooms() -> void:
	var connected_pairs: Dictionary = {}  # "id_a|id_b" → true

	# Build Rect2 list of all room XZ bounding boxes for corridor avoidance.
	var room_rects: Dictionary = {}  # room_id → Rect2
	for rid in rooms:
		var rn: DungeonRoom = rooms[rid]
		var hx: float = rn.room_size.x * 0.5
		var hz: float = rn.room_size.y * 0.5
		var gp: Vector3 = rn.global_position
		room_rects[rid] = Rect2(gp.x - hx, gp.z - hz, rn.room_size.x, rn.room_size.y)

	for rid in rooms:
		var room_node: DungeonRoom = rooms[rid]
		var conn_points: Dictionary = room_node.get_connection_points()

		for conn_item: Variant in room_node.connections:
			var target_id: String = ""
			var dir_str: String = ""
			if conn_item is String:
				target_id = conn_item
			elif conn_item is Dictionary:
				target_id = conn_item.get("target_room_id", "")
				dir_str = conn_item.get("direction", "")

			if target_id.is_empty() or not rooms.has(target_id):
				continue

			# Avoid duplicate corridors.
			var pair_key: String = _pair_key(rid, target_id)
			if connected_pairs.has(pair_key):
				continue
			connected_pairs[pair_key] = true

			var target_node: DungeonRoom = rooms[target_id]

			var from_pos: Vector3 = conn_points.get(dir_str, room_node.global_position)
			# Find the opposite direction's connection point on the target.
			var opposite_dir: String = _opposite_direction(dir_str)
			var target_points: Dictionary = target_node.get_connection_points()
			var to_pos: Vector3 = target_points.get(opposite_dir, target_node.global_position)

			# Collect room rects to avoid (exclude source and target rooms).
			var avoid: Array = []
			for other_rid in room_rects:
				if other_rid != rid and other_rid != target_id:
					avoid.append(room_rects[other_rid])

			var corridor := _create_corridor(from_pos, to_pos, avoid)
			corridor.start_room_id = rid
			corridor.end_room_id = target_id


## Create a single corridor between two world positions.
func _create_corridor(from_pos: Vector3, to_pos: Vector3, avoid_rects: Array = []) -> DungeonCorridor:
	var corridor := DungeonCorridor.new()
	corridor.name = "Corridor_%d" % corridors.size()
	add_child(corridor)
	corridor.build_between(from_pos, to_pos, corridor_width, avoid_rects)
	corridors.append(corridor)
	return corridor


# ── Helpers ─────────────────────────────────────────────────────────────────

## Convert Vector2i to a string key for dictionary lookups.
func _v2i_key(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]


## Find a free grid cell near the candidate position, spiralling outward.
func _find_free_cell(candidate: Vector2i, occupied: Dictionary) -> Vector2i:
	if not occupied.has(_v2i_key(candidate)):
		return candidate

	# Spiral search for the nearest unoccupied cell.
	for radius in range(1, 50):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dz) != radius:
					continue  # only check the ring edge
				var test := Vector2i(candidate.x + dx, candidate.y + dz)
				if not occupied.has(_v2i_key(test)):
					return test

	# Fallback — shouldn't happen with sane room counts.
	return candidate + Vector2i(50, 50)


## Generate a canonical key for a pair of room ids (order-independent).
func _pair_key(a: String, b: String) -> String:
	if a < b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]


## Return the opposite cardinal direction.
func _opposite_direction(dir: String) -> String:
	match dir:
		"north":
			return "south"
		"south":
			return "north"
		"east":
			return "west"
		"west":
			return "east"
		_:
			return ""


## Retrieve the AIClient autoload singleton.
func _get_ai_client() -> Node:
	if not Engine.has_singleton("AIClient"):
		# Try finding it on the scene tree (registered via autoload).
		var root: Window = get_tree().root if get_tree() != null else null
		if root != null:
			return root.get_node_or_null("AIClient")
		return null
	return Engine.get_singleton("AIClient")


## Callback for AIClient.dungeon_generated signal.
func _on_dungeon_data_received(data: Dictionary) -> void:
	build_floor(data)
