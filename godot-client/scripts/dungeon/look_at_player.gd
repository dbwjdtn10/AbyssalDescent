## Rotates the parent node to face the active camera each frame.
extends Node

var _body: Node3D


func _ready() -> void:
	_body = get_parent()


func _process(_delta: float) -> void:
	if _body == null:
		return
	if not _body.is_inside_tree():
		return
	var viewport := _body.get_viewport()
	if viewport == null:
		return
	var cam := viewport.get_camera_3d()
	if cam == null:
		return
	var target := cam.global_position
	target.y = _body.global_position.y
	if target.distance_to(_body.global_position) > 0.1:
		_body.look_at(target, Vector3.UP)
