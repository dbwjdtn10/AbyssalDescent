## A single room in the procedurally generated dungeon.
##
## Attached to a Node3D that represents one room.  Initialised from the AI
## server's JSON room data (models/dungeon.py → Room schema), it spawns
## geometry, monsters, items, and environmental effects.
class_name DungeonRoom
extends Node3D

# ── Signals ─────────────────────────────────────────────────────────────────

signal room_entered
signal room_cleared
signal item_picked_up(item_data: Dictionary)
signal monster_defeated(monster_data: Dictionary)

# ── Exported / public properties ────────────────────────────────────────────

## Unique identifier from the server (e.g. "room_1_00").
var room_id: String = ""

## Room type string — one of the RoomType enum values from the server.
var room_type: String = "corridor"

## Room dimensions in grid cells.
var room_size: Vector2i = Vector2i(10, 10)

## The full dictionary received from the AI server for this room.
var room_data: Dictionary = {}

## Parsed connection data.  Each entry is a Dictionary with keys:
## "direction", "target_room_id", "is_locked", "lock_type".
var connections: Array = []

## Whether the player has visited this room.
var is_explored: bool = false

# ── Internal references ─────────────────────────────────────────────────────

var _room_mesh: Node3D = null
var _monster_spawner: MonsterSpawner = MonsterSpawner.new()
var _item_spawner: ItemSpawner = ItemSpawner.new()
var _monsters_node: Node3D = null
var _items_node: Node3D = null
var _env_effects_node: Node3D = null

# ── Room detection area for player entry ────────────────────────────────────

var _entry_area: Area3D = null


# ── Setup ───────────────────────────────────────────────────────────────────

## Initialise the room from AI server JSON data.
## [param data]  A Dictionary matching the Room Pydantic model:
##   { id, type, shape, size, name, description,
##     connections: [{direction, target_room_id, is_locked, lock_type}],
##     monsters: [{monster_id, name, rank, level, count, description}],
##     items: [{item_id, name, rarity, description}],
##     environmental: [{effect_type, intensity, description}],
##     is_explored }
func setup(data: Dictionary) -> void:
	room_data = data
	room_id = data.get("id", "")
	room_type = data.get("type", "corridor")
	name = "Room_%s" % room_id

	# Parse size string to Vector2i.
	var size_str: String = data.get("size", "medium")
	room_size = RoomFactory.size_string_to_vector(size_str)

	# Parse connections.  Supports both formats:
	# - String array: ["room_a", "room_b"] (fallback data)
	# - Dictionary array: [{direction, target_room_id, ...}] (AI server data)
	connections = []
	var conn_arr: Array = data.get("connections", [])
	for c: Variant in conn_arr:
		if c is String:
			connections.append({
				"direction": "",
				"target_room_id": c,
				"is_locked": false,
				"lock_type": "",
			})
		elif c is Dictionary:
			connections.append({
				"direction": c.get("direction", ""),
				"target_room_id": c.get("target_room_id", ""),
				"is_locked": c.get("is_locked", false),
				"lock_type": c.get("lock_type", ""),
			})

	is_explored = data.get("is_explored", false)

	# Build connection lookup for wall doorways.
	var conn_lookup: Dictionary = {}
	for c in connections:
		conn_lookup[c["direction"]] = c["target_room_id"]

	# ── Generate room geometry ───────────────────────────────────────────
	_room_mesh = RoomFactory.create_room_mesh(room_type, room_size, conn_lookup)
	add_child(_room_mesh)

	# ── Create entry detection area ──────────────────────────────────────
	_setup_entry_area()

	# ── Spawn content ────────────────────────────────────────────────────
	# Support both AI server keys ("monsters"/"items") and fallback keys ("enemies"/"loot").
	var monsters_data: Array = data.get("monsters", [])
	if monsters_data.is_empty():
		monsters_data = data.get("enemies", [])
	if not monsters_data.is_empty():
		spawn_monsters(monsters_data)

	var items_data: Array = data.get("items", [])
	if items_data.is_empty():
		items_data = data.get("loot", [])
	if not items_data.is_empty():
		spawn_items(items_data)

	var env_data: Array = data.get("environmental", [])
	if not env_data.is_empty():
		apply_environment(env_data)

	# Apply explored state visuals.
	set_explored(is_explored)


## Spawn monster placeholder nodes from an array of MonsterSpawn data.
func spawn_monsters(monsters: Array) -> void:
	# Remove existing monsters if any.
	if _monsters_node != null and is_instance_valid(_monsters_node):
		_monsters_node.queue_free()

	_monster_spawner.spawn_monsters_in_room(monsters, self, room_size)
	# The spawner creates a "Monsters" child node.
	_monsters_node = get_node_or_null("Monsters")


## Spawn item placeholder nodes from an array of ItemDrop data.
func spawn_items(items: Array) -> void:
	if _items_node != null and is_instance_valid(_items_node):
		_items_node.queue_free()

	_item_spawner.spawn_items_in_room(items, self, room_size)
	_items_node = get_node_or_null("Items")

	# Connect pickup areas.
	if _items_node != null:
		_connect_item_pickups(_items_node)


## Apply environmental effects (lighting changes, fog, particles).
func apply_environment(effects: Array) -> void:
	if _env_effects_node != null and is_instance_valid(_env_effects_node):
		_env_effects_node.queue_free()

	_env_effects_node = Node3D.new()
	_env_effects_node.name = "EnvironmentEffects"
	add_child(_env_effects_node)

	for effect in effects:
		var effect_type: String = effect.get("effect_type", "")
		var intensity: float = effect.get("intensity", 0.5)
		_apply_single_effect(effect_type, intensity)


## Mark the room as explored or unexplored, updating visuals accordingly.
func set_explored(explored: bool) -> void:
	is_explored = explored

	if not is_explored:
		# Dim the room to indicate it has not been visited.
		_set_room_brightness(0.3)
	else:
		_set_room_brightness(1.0)


## Return connection points as a Dictionary mapping direction strings to
## world-space Vector3 positions on the room boundary.
func get_connection_points() -> Dictionary:
	var half_x: float = room_size.x * 0.5
	var half_z: float = room_size.y * 0.5
	var points: Dictionary = {}

	for c in connections:
		var dir: String = c.get("direction", "")
		match dir:
			"north":
				points["north"] = global_position + Vector3(0, 0, -half_z)
			"south":
				points["south"] = global_position + Vector3(0, 0, half_z)
			"east":
				points["east"] = global_position + Vector3(half_x, 0, 0)
			"west":
				points["west"] = global_position + Vector3(-half_x, 0, 0)

	return points


# ── Internal helpers ────────────────────────────────────────────────────────

## Create an Area3D that detects when the player enters the room.
func _setup_entry_area() -> void:
	_entry_area = Area3D.new()
	_entry_area.name = "EntryArea"
	_entry_area.monitoring = true
	_entry_area.monitorable = false

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(room_size.x * 0.8, RoomFactory.WALL_HEIGHT, room_size.y * 0.8)
	col.shape = box
	col.position.y = RoomFactory.WALL_HEIGHT * 0.5
	_entry_area.add_child(col)

	# When a body enters the area, emit room_entered.
	_entry_area.body_entered.connect(_on_body_entered_room)
	add_child(_entry_area)


func _on_body_entered_room(body: Node3D) -> void:
	# Only react to the player (assumed to be in group "player").
	if body.is_in_group("player"):
		if not is_explored:
			set_explored(true)
		room_entered.emit()

		# Emit via EventBus so GameManager can heal in rest rooms, etc.
		var eb: Node = _get_event_bus()
		if eb != null:
			eb.room_entered.emit(room_data)


## Adjust room light energy as a brightness multiplier.
func _set_room_brightness(brightness: float) -> void:
	if _room_mesh == null:
		return
	var light := _room_mesh.get_node_or_null("RoomLight")
	if light is OmniLight3D:
		light.light_energy = 1.2 * brightness


## Apply a single environmental effect (light colour shift, fog, particles).
func _apply_single_effect(effect_type: String, intensity: float) -> void:
	match effect_type:
		"darkness":
			_apply_darkness(intensity)
		"poison_fog", "corruption":
			_apply_fog(Color(0.2, 0.6, 0.1, 0.4 * intensity), intensity)
		"fire", "heat":
			_apply_fog(Color(1.0, 0.3, 0.0, 0.25 * intensity), intensity)
			_add_fire_light(intensity)
		"ice", "frost":
			_apply_fog(Color(0.6, 0.8, 1.0, 0.3 * intensity), intensity)
		"water":
			_apply_fog(Color(0.2, 0.4, 0.8, 0.2 * intensity), intensity)
		"void_corruption":
			_apply_fog(Color(0.3, 0.0, 0.4, 0.5 * intensity), intensity)
			_add_void_particles(intensity)
		_:
			# Unknown effect — add a subtle generic fog.
			_apply_fog(Color(0.5, 0.5, 0.5, 0.15 * intensity), intensity)


## Reduce room light for darkness effect.
func _apply_darkness(intensity: float) -> void:
	if _room_mesh == null:
		return
	var light := _room_mesh.get_node_or_null("RoomLight")
	if light is OmniLight3D:
		light.light_energy *= maxf(0.1, 1.0 - intensity * 0.8)
		light.light_color = light.light_color.lerp(Color(0.1, 0.1, 0.2), intensity * 0.5)


## Add a coloured MeshInstance3D plane as a simple ground-level fog indicator.
func _apply_fog(color: Color, intensity: float) -> void:
	var fog := MeshInstance3D.new()
	fog.name = "FogPlane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(room_size.x * 0.9, room_size.y * 0.9)
	fog.mesh = plane

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	fog.material_override = mat
	fog.position.y = 0.05 + intensity * 0.3

	_env_effects_node.add_child(fog)


## Add a flickering OmniLight3D for fire/heat effects.
func _add_fire_light(intensity: float) -> void:
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = Color(1.0, 0.5, 0.1)
	light.light_energy = 0.8 * intensity
	light.omni_range = maxf(room_size.x, room_size.y) * 0.5
	light.position = Vector3(0, 1.5, 0)
	_env_effects_node.add_child(light)


## Add a subtle GPUParticles3D for void corruption visual.
func _add_void_particles(intensity: float) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "VoidParticles"
	particles.amount = int(16 * intensity)
	particles.lifetime = 3.0
	particles.position = Vector3(0, 1.0, 0)

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.6
	mat.gravity = Vector3(0, -0.1, 0)
	mat.color = Color(0.4, 0.0, 0.6, 0.6)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(room_size.x * 0.4, 0.5, room_size.y * 0.4)
	particles.process_material = mat

	# Simple quad mesh for each particle.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	particles.draw_pass_1 = quad

	_env_effects_node.add_child(particles)


## Wire up pickup Area3D signals on spawned items.
func _connect_item_pickups(items_root: Node3D) -> void:
	for child in items_root.get_children():
		var area := child.get_node_or_null("PickupArea") as Area3D
		if area != null:
			var item_node := child  # capture for lambda
			area.body_entered.connect(func(body: Node3D) -> void:
				if body.is_in_group("player") and item_node.has_meta("item_data"):
					var data: Dictionary = item_node.get_meta("item_data")
					item_picked_up.emit(data)
					# Also emit via EventBus so InventorySystem picks it up.
					var eb: Node = _get_event_bus()
					if eb != null:
						eb.item_picked_up.emit(data)
					item_node.queue_free()
			)


## Check whether all monsters have been defeated and emit room_cleared.
func check_room_cleared() -> void:
	if _monsters_node == null or not is_instance_valid(_monsters_node):
		room_cleared.emit()
		return

	var alive: int = 0
	for child in _monsters_node.get_children():
		if is_instance_valid(child):
			alive += 1

	if alive == 0:
		room_cleared.emit()


## Call this when a monster in this room is defeated.
func on_monster_defeated(monster_node: Node3D) -> void:
	if monster_node.has_meta("monster_data"):
		monster_defeated.emit(monster_node.get_meta("monster_data"))
	monster_node.queue_free()
	# Defer the cleared check so the node has time to be freed.
	check_room_cleared.call_deferred()


func _get_event_bus() -> Node:
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node("EventBus"):
		return root.get_node("EventBus")
	return null
