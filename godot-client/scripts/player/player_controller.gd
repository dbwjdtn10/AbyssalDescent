## First-person player controller for dungeon exploration.
##
## Handles WASD movement, mouse look, interaction raycasts, and HP management.
## Emits events through the EventBus autoload for damage, healing, and death.
class_name PlayerController
extends CharacterBody3D

# ── Export Properties ────────────────────────────────────────────────────────

@export var speed: float = 5.0
@export var mouse_sensitivity: float = 0.003
@export var gravity: float = 9.8
@export var hp: float = 100.0
@export var max_hp: float = 100.0

# ── Internal References ─────────────────────────────────────────────────────

var _camera: Camera3D
var _camera_pivot: Node3D
var _interact_ray: RayCast3D
var _combat_system: CombatSystem = null
var _combat_monsters_parent: Node = null  # The "Monsters" node for the current fight

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Add to "player" group so rooms and items can detect us.
	add_to_group("player")

	# Capture mouse for first-person look.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Find camera pivot and camera among our children.
	_camera_pivot = $CameraPivot as Node3D
	_camera = $CameraPivot/Camera3D as Camera3D

	# Setup interaction raycast (forward from camera, ~3 metres).
	_interact_ray = RayCast3D.new()
	_interact_ray.target_position = Vector3(0, 0, -3.0)
	_interact_ray.enabled = true
	_interact_ray.collision_mask = 0xFFFFFFFF
	_camera.add_child(_interact_ray)

	# Create CombatSystem as a child node.
	_combat_system = CombatSystem.new()
	_combat_system.name = "CombatSystem"
	add_child(_combat_system)
	_combat_system.combat_ended.connect(_on_combat_ended)


func _input(event: InputEvent) -> void:
	# Mouse look — only when captured.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		# Horizontal rotation on the body (Y axis).
		rotate_y(-motion.relative.x * mouse_sensitivity)
		# Vertical rotation on the camera pivot (X axis), clamped.
		_camera_pivot.rotate_x(-motion.relative.y * mouse_sensitivity)
		_camera_pivot.rotation.x = clampf(_camera_pivot.rotation.x, -PI / 2.0, PI / 2.0)

	# Interact with E key (combat is handled by CombatUI).
	if event.is_action_pressed("interact"):
		if _combat_system == null or not _combat_system.is_in_combat:
			interact()

	# Quest log with Tab.
	if event.is_action_pressed("quest_log"):
		var event_bus := _get_event_bus()
		if event_bus != null and event_bus.has_signal("quest_log_toggled"):
			event_bus.quest_log_toggled.emit()


func _physics_process(delta: float) -> void:
	# Gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Gather input direction.
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("move_backward"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	input_dir = input_dir.normalized()

	# Convert to world-space direction based on player facing.
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()


# ── Public API ───────────────────────────────────────────────────────────────

## Reduce HP by the given amount. Emits player_damaged and player_died signals.
func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)

	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.player_damaged.emit(amount)

	if hp <= 0.0:
		_die()


## Restore HP by the given amount, clamped to max_hp. Emits player_healed.
func heal(amount: float) -> void:
	var actual := minf(amount, max_hp - hp)
	hp = minf(hp + amount, max_hp)

	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.player_healed.emit(actual)


## Return current HP as a ratio (0.0 to 1.0).
func get_hp_ratio() -> float:
	if max_hp <= 0.0:
		return 0.0
	return hp / max_hp


## Cast a ray forward from the camera to detect interactable objects.
func interact() -> void:
	if _interact_ray == null:
		return

	_interact_ray.force_raycast_update()

	if not _interact_ray.is_colliding():
		return

	var collider := _interact_ray.get_collider()
	if collider == null:
		return

	# Check for explicit interact methods first.
	if collider.has_method("interact"):
		collider.interact(self)
		return
	if collider.has_method("on_interact"):
		collider.on_interact(self)
		return

	# Check if we hit a monster (has monster_data meta).
	# The raycast may hit a child StaticBody; walk up to find monster_data.
	var target: Node = collider
	while target != null:
		if target.has_meta("monster_data"):
			_start_combat_with_monster(target)
			return
		target = target.get_parent()


# ── Combat ───────────────────────────────────────────────────────────────────

## Start combat with a monster node. Collects all monsters in the same room.
func _start_combat_with_monster(monster_node: Node) -> void:
	if _combat_system == null or _combat_system.is_in_combat:
		return

	# Collect all sibling monsters (same "Monsters" parent).
	var enemies: Array = []
	var monsters_parent: Node = monster_node.get_parent()
	if monsters_parent != null and monsters_parent.name == "Monsters":
		for child in monsters_parent.get_children():
			if child.has_meta("monster_data"):
				enemies.append(child.get_meta("monster_data"))
	else:
		enemies.append(monster_node.get_meta("monster_data"))

	if enemies.is_empty():
		return

	# Remember which Monsters node we're fighting so we only remove these.
	_combat_monsters_parent = monsters_parent if monsters_parent != null and monsters_parent.name == "Monsters" else null
	_combat_system.start_combat(enemies)


## Called when combat ends.
func _on_combat_ended(summary: Dictionary) -> void:
	if summary.get("victory", false):
		# Only remove monsters from the room we actually fought in.
		if _combat_monsters_parent != null and is_instance_valid(_combat_monsters_parent):
			for m in _combat_monsters_parent.get_children():
				m.queue_free()
	_combat_monsters_parent = null


# ── Private ──────────────────────────────────────────────────────────────────

func _die() -> void:
	var event_bus := _get_event_bus()
	if event_bus != null:
		event_bus.player_died.emit()
	# Disable further input processing.
	set_physics_process(false)
	set_process_input(false)


func _get_event_bus() -> Node:
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node("EventBus"):
		return root.get_node("EventBus")
	return null
