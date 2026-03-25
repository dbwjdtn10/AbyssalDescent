## 3D NPC character that builds its own visual representation and handles
## player interaction.  Attach this script to a CharacterBody3D or add one
## programmatically via NPCManager.spawn_npc().
class_name AINPC
extends CharacterBody3D

# ── Signals ──────────────────────────────────────────────────────────────────

signal interaction_started(npc_id: String)
signal interaction_ended(npc_id: String)

# ── Export Properties ────────────────────────────────────────────────────────

@export var npc_id: String = "wandering_merchant"
@export var npc_name: String = "리라"
@export var npc_title: String = "떠돌이 상인"
@export var interaction_range: float = 3.0
@export var idle_animation_speed: float = 1.0

# ── Runtime State ────────────────────────────────────────────────────────────

var is_player_nearby: bool = false
var can_interact: bool = true
var current_emotion: String = "neutral"
var current_affinity: int = 0

# ── Internal Nodes ───────────────────────────────────────────────────────────

var _body_mesh: MeshInstance3D
var _name_label: Label3D
var _prompt_label: Label3D
var _interaction_area: Area3D
var _collision_shape: CollisionShape3D  # CharacterBody3D collision

## Elapsed time used to drive the idle bob animation.
var _idle_time: float = 0.0

## Base Y position captured after initial placement.
var _base_y: float = 0.0

# ── Color Lookup ─────────────────────────────────────────────────────────────

## NPC body color based on archetype keywords in npc_id.
func _get_npc_color() -> Color:
	if npc_id.find("merchant") != -1:
		return Color(0.2, 0.6, 0.3, 1.0)   # green
	if npc_id.find("adventurer") != -1:
		return Color(0.25, 0.45, 0.75, 1.0) # blue
	if npc_id.find("sage") != -1:
		return Color(0.5, 0.25, 0.7, 1.0)   # purple
	if npc_id.find("knight") != -1:
		return Color(0.25, 0.25, 0.3, 1.0)  # dark gray
	# Default warm brown
	return Color(0.55, 0.4, 0.3, 1.0)

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_visual()
	_build_interaction_area()
	_base_y = global_position.y


func _process(delta: float) -> void:
	# Gentle idle bob animation.
	_idle_time += delta * idle_animation_speed
	var bob_offset: float = sin(_idle_time * 2.0) * 0.05
	position.y = _base_y + bob_offset

	# Rotate name label toward the camera so it is always readable.
	var camera := get_viewport().get_camera_3d()
	if camera != null and _name_label != null:
		_name_label.global_transform = _name_label.global_transform.looking_at(
			camera.global_position, Vector3.UP
		)
		# Keep the label upright.
		_name_label.rotation.x = 0.0
		_name_label.rotation.z = 0.0

	# Check for interaction input when the player is nearby.
	if is_player_nearby and can_interact:
		if Input.is_action_just_pressed("interact"):
			interact()


func _physics_process(_delta: float) -> void:
	# NPC does not move, but CharacterBody3D requires this override.
	pass

# ── Visual Construction ─────────────────────────────────────────────────────

func _build_visual() -> void:
	# CharacterBody3D collision shape (capsule matching the mesh).
	_collision_shape = CollisionShape3D.new()
	_collision_shape.name = "BodyCollision"
	var capsule_collision := CapsuleShape3D.new()
	capsule_collision.radius = 0.35
	capsule_collision.height = 1.6
	_collision_shape.shape = capsule_collision
	_collision_shape.position = Vector3(0, 0.8, 0)
	add_child(_collision_shape)

	# Load NPC model (real asset or procedural fallback).
	var model_scene: PackedScene = AssetRegistry.get_npc_scene(npc_id)
	var model_inst: Node3D = model_scene.instantiate()
	model_inst.name = "NPCModel"
	add_child(model_inst)

	# Cache the body mesh for affinity-based tinting.
	var body_node := model_inst.find_child("Body")
	if body_node is MeshInstance3D:
		_body_mesh = body_node

	# Name + title label floating above head.
	_name_label = Label3D.new()
	_name_label.name = "NameLabel"
	_name_label.text = "%s\n%s" % [npc_name, npc_title]
	_name_label.font_size = 18
	_name_label.outline_size = 4
	_name_label.modulate = Color(0.92, 0.76, 0.26, 1.0)  # Gold
	_name_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	_name_label.position = Vector3(0, 2.0, 0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_name_label.no_depth_test = true
	_name_label.fixed_size = false
	add_child(_name_label)

	# Interaction prompt (hidden by default).
	_prompt_label = Label3D.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.text = "[E] 대화하기"
	_prompt_label.font_size = 14
	_prompt_label.outline_size = 3
	_prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	_prompt_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
	_prompt_label.position = Vector3(0, 2.5, 0)
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.no_depth_test = true
	_prompt_label.visible = false
	add_child(_prompt_label)

# ── Interaction Area ─────────────────────────────────────────────────────────

func _build_interaction_area() -> void:
	_interaction_area = Area3D.new()
	_interaction_area.name = "InteractionArea"
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = 1  # Detect bodies on layer 1 (player)

	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = interaction_range
	var area_collision := CollisionShape3D.new()
	area_collision.name = "InteractionCollision"
	area_collision.shape = sphere_shape
	_interaction_area.add_child(area_collision)
	add_child(_interaction_area)

	_interaction_area.body_entered.connect(_on_body_entered)
	_interaction_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	# Assume the player node is named "Player" or is in the "player" group.
	if _is_player(body):
		is_player_nearby = true
		if can_interact and _prompt_label != null:
			_prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if _is_player(body):
		is_player_nearby = false
		if _prompt_label != null:
			_prompt_label.visible = false

# ── Interaction ──────────────────────────────────────────────────────────────

## Called when the player presses the interact key while in range.
func interact() -> void:
	if not can_interact:
		return
	can_interact = false
	_prompt_label.visible = false
	interaction_started.emit(npc_id)

	# Find NPCDialogueUI in the scene tree and open the dialogue.
	var dialogue_ui := _find_dialogue_ui()
	if dialogue_ui != null:
		dialogue_ui.open_dialogue(npc_id, npc_name, npc_title)
		# Re-enable interaction when the dialogue closes.
		if not dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed):
			dialogue_ui.dialogue_closed.connect(_on_dialogue_closed, CONNECT_ONE_SHOT)
	else:
		push_warning("AINPC: NPCDialogueUI not found in scene tree.")
		can_interact = true


## Update the NPC's visual state to reflect emotion and affinity changes.
func update_state(emotion: String, affinity: int) -> void:
	current_emotion = emotion
	current_affinity = affinity

	# Tint the body slightly based on affinity for subtle visual feedback.
	if _body_mesh != null and _body_mesh.material_override is StandardMaterial3D:
		var base_color: Color = _get_npc_color()
		var mat: StandardMaterial3D = _body_mesh.material_override as StandardMaterial3D
		if affinity > 50:
			mat.albedo_color = base_color.lerp(Color(0.9, 0.85, 0.4), 0.15)  # Warm glow
		elif affinity < -50:
			mat.albedo_color = base_color.lerp(Color(0.3, 0.1, 0.1), 0.2)   # Dark tint
		else:
			mat.albedo_color = base_color

# ── Private Helpers ──────────────────────────────────────────────────────────

func _on_dialogue_closed(_closed_npc_id: String) -> void:
	can_interact = true
	interaction_ended.emit(npc_id)
	if is_player_nearby and _prompt_label != null:
		_prompt_label.visible = true


## Determine whether a body is the player character.
func _is_player(body: Node3D) -> bool:
	if body.is_in_group("player"):
		return true
	if body.name == "Player":
		return true
	return false


## Search the scene tree for an NPCDialogueUI instance.
func _find_dialogue_ui() -> NPCDialogueUI:
	# Check autoload / root children first.
	var root := get_tree().root
	for child in root.get_children():
		if child is NPCDialogueUI:
			return child as NPCDialogueUI

	# Recursive search (limited depth to avoid performance issues).
	return _find_in_children(root, 4) as NPCDialogueUI


func _find_in_children(node: Node, depth: int) -> Node:
	if depth <= 0:
		return null
	for child in node.get_children():
		if child is NPCDialogueUI:
			return child
		var found := _find_in_children(child, depth - 1)
		if found != null:
			return found
	return null
