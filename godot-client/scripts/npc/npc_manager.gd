## Manages the lifecycle of AI-driven NPCs within the dungeon.
##
## Spawns, removes, and provides access to AINPC nodes.  Can be used as
## a standalone Node added to the scene or registered as an autoload.
class_name NPCManager
extends Node

# ── Known NPC Data ───────────────────────────────────────────────────────────

const NPC_DATABASE: Dictionary = {
	"wandering_merchant": {
		"name": "리라",
		"title": "떠돌이 상인",
	},
	"captive_adventurer": {
		"name": "카엘",
		"title": "포로가 된 모험자",
	},
	"mysterious_sage": {
		"name": "에른",
		"title": "수수께끼의 현자",
	},
	"fallen_knight": {
		"name": "다르크",
		"title": "타락한 기사",
	},
}

# ── State ────────────────────────────────────────────────────────────────────

## Active NPC instances indexed by npc_id.
var active_npcs: Dictionary = {}

# ── Public API ───────────────────────────────────────────────────────────────

## Spawn an NPC at the given world position and register it.
## Returns the newly created AINPC node.
func spawn_npc(
	npc_id: String,
	pos: Vector3,
	npc_name: String = "",
	npc_title: String = ""
) -> AINPC:
	# Resolve name/title from the database if not provided.
	if npc_name.is_empty() or npc_title.is_empty():
		var info: Dictionary = _get_npc_info(npc_id)
		if npc_name.is_empty():
			npc_name = info.get("name", npc_id)
		if npc_title.is_empty():
			npc_title = info.get("title", "")

	# Remove a previous instance of the same NPC, if any.
	if active_npcs.has(npc_id):
		remove_npc(npc_id)

	var npc := AINPC.new()
	npc.npc_id = npc_id
	npc.npc_name = npc_name
	npc.npc_title = npc_title
	npc.name = "NPC_%s" % npc_id

	add_child(npc)
	npc.global_position = pos
	active_npcs[npc_id] = npc
	return npc


## Remove and free an NPC by id.
func remove_npc(npc_id: String) -> void:
	if not active_npcs.has(npc_id):
		return
	var npc: AINPC = active_npcs[npc_id]
	active_npcs.erase(npc_id)
	if is_instance_valid(npc):
		npc.queue_free()


## Return the AINPC node for the given id, or null if not active.
func get_npc(npc_id: String) -> AINPC:
	if active_npcs.has(npc_id):
		var npc: AINPC = active_npcs[npc_id]
		if is_instance_valid(npc):
			return npc
		# Stale reference – clean up.
		active_npcs.erase(npc_id)
	return null


## Scan floor_data for rooms with "npc_encounter" type and spawn appropriate
## NPCs.  floor_data is expected to match the dictionary structure returned
## by the /api/dungeon/generate endpoint.
func spawn_npcs_for_floor(floor_data: Dictionary) -> void:
	var rooms: Array = floor_data.get("rooms", [])
	for room in rooms:
		if room is not Dictionary:
			continue
		var room_type: String = room.get("type", "")
		if room_type != "npc_encounter":
			continue

		var npc_id: String = room.get("npc_id", "")
		if npc_id.is_empty():
			# Try to infer from room metadata.
			npc_id = room.get("encounter_id", "wandering_merchant")

		# Compute a spawn position from room data (fallback to origin).
		var spawn_pos := Vector3.ZERO
		if room.has("position"):
			var p = room["position"]
			if p is Dictionary:
				spawn_pos = Vector3(
					float(p.get("x", 0)),
					float(p.get("y", 0)),
					float(p.get("z", 0))
				)
			elif p is Array and p.size() >= 3:
				spawn_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))

		var info: Dictionary = _get_npc_info(npc_id)
		var npc_name: String = room.get("npc_name", info.get("name", npc_id))
		var npc_title: String = room.get("npc_title", info.get("title", ""))

		spawn_npc(npc_id, spawn_pos, npc_name, npc_title)


## Remove and free every active NPC.
func clear_all_npcs() -> void:
	var ids: Array = active_npcs.keys().duplicate()
	for npc_id in ids:
		remove_npc(npc_id)
	active_npcs.clear()


# ── Private Helpers ──────────────────────────────────────────────────────────

## Look up known NPC info.  Returns a Dictionary with "name" and "title" keys.
func _get_npc_info(npc_id: String) -> Dictionary:
	if NPC_DATABASE.has(npc_id):
		return NPC_DATABASE[npc_id]
	# Return a sensible default for unknown NPCs.
	return {
		"name": npc_id.replace("_", " ").capitalize(),
		"title": "심연의 존재",
	}
