## Corner minimap showing explored dungeon rooms.
##
## Builds its entire UI tree programmatically so it has no .tscn dependency.
## Renders rooms as small coloured rectangles in the top-right corner using
## Control-based drawing.  Rooms are revealed as the player explores.
class_name Minimap
extends CanvasLayer

# ── Theme Colors ─────────────────────────────────────────────────────────────

const COLOR_BG := Color(0.06, 0.04, 0.08, 0.85)
const COLOR_BORDER := Color(0.72, 0.58, 0.2, 0.6)
const COLOR_TEXT := Color("#e6e1d1")
const COLOR_ACCENT := Color("#ebca42")
const COLOR_PLAYER := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_CURRENT_ROOM := Color(0.92, 0.76, 0.26, 0.8)
const COLOR_CONNECTION := Color(0.4, 0.35, 0.5, 0.6)
const COLOR_UNEXPLORED := Color(0.15, 0.12, 0.18, 0.5)

## Room type → colour mapping.
const ROOM_COLORS: Dictionary = {
	"combat":        Color(0.75, 0.15, 0.15, 0.8),
	"boss":          Color(0.85, 0.10, 0.10, 1.0),
	"mini_boss":     Color(0.60, 0.10, 0.55, 0.9),
	"treasure":      Color(0.92, 0.76, 0.26, 0.8),
	"shop":          Color(0.30, 0.75, 0.35, 0.8),
	"rest":          Color(0.25, 0.55, 0.85, 0.8),
	"npc_encounter": Color(0.55, 0.45, 0.80, 0.8),
	"entrance":      Color(0.50, 0.50, 0.50, 0.8),
	"exit":          Color(0.90, 0.85, 0.20, 0.9),
	"empty":         Color(0.35, 0.30, 0.40, 0.6),
	"trap":          Color(0.80, 0.45, 0.10, 0.8),
	"puzzle":        Color(0.20, 0.70, 0.70, 0.8),
}

const DEFAULT_ROOM_COLOR: Color = Color(0.35, 0.30, 0.40, 0.6)

# ── Constants ────────────────────────────────────────────────────────────────

const MAP_SIZE: float = 200.0
const MAP_MARGIN: float = 16.0
const ROOM_SIZE: float = 16.0
const ROOM_SPACING: float = 24.0
const PLAYER_DOT_SIZE: float = 4.0
const BLINK_INTERVAL: float = 0.5

# ── UI Node References ──────────────────────────────────────────────────────

var _panel: PanelContainer
var _draw_control: Control
var _title_label: Label

# ── State ────────────────────────────────────────────────────────────────────

## Floor data containing rooms and connections.
var _floor_data: Dictionary = {}

## Rooms indexed by room_id: { grid_pos: Vector2, type: String, explored: bool, connections: Array }
var _rooms: Dictionary = {}

## Which room the player is currently in.
var _current_room_id: String = ""

## Player dot blink timer.
var _blink_timer: float = 0.0
var _blink_visible: bool = true

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 75
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()
	visible = true


func _process(delta: float) -> void:
	# Blink the player dot.
	_blink_timer += delta
	if _blink_timer >= BLINK_INTERVAL:
		_blink_timer = 0.0
		_blink_visible = not _blink_visible
		if _draw_control != null:
			_draw_control.queue_redraw()


# ── UI Construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "MinimapPanel"

	# Anchor to top-right corner.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -(MAP_SIZE + MAP_MARGIN)
	_panel.offset_right = -MAP_MARGIN
	_panel.offset_top = MAP_MARGIN
	_panel.offset_bottom = MAP_MARGIN + MAP_SIZE + 26.0  # Extra for title.
	_panel.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE + 26.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_BG
	panel_style.border_color = COLOR_BORDER
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.content_margin_top = 4.0
	panel_style.content_margin_bottom = 4.0
	panel_style.content_margin_left = 4.0
	panel_style.content_margin_right = 4.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_panel.add_child(vbox)

	# Title.
	_title_label = Label.new()
	_title_label.text = "지도"
	_title_label.add_theme_font_size_override("font_size", 11)
	_title_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title_label)

	# Drawing area.
	_draw_control = Control.new()
	_draw_control.name = "MinimapDraw"
	_draw_control.custom_minimum_size = Vector2(MAP_SIZE - 8.0, MAP_SIZE - 8.0)
	_draw_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_draw_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_control.draw.connect(_on_draw)
	vbox.add_child(_draw_control)


# ── Signal Wiring ────────────────────────────────────────────────────────────

func _connect_signals() -> void:
	call_deferred("_deferred_connect_signals")


func _deferred_connect_signals() -> void:
	var event_bus := _get_autoload("EventBus")
	if event_bus == null:
		return

	if event_bus.has_signal("room_entered"):
		event_bus.room_entered.connect(_on_room_entered)
	if event_bus.has_signal("floor_started"):
		event_bus.floor_started.connect(_on_floor_started)


func _on_room_entered(room_data: Dictionary) -> void:
	var room_id: String = room_data.get("room_id", room_data.get("id", ""))
	if not room_id.is_empty():
		update_player_room(room_id)
		reveal_room(room_id)


func _on_floor_started(_floor_number: int) -> void:
	# Clear the minimap when a new floor begins.
	_rooms.clear()
	_current_room_id = ""
	_floor_data = {}
	if _draw_control != null:
		_draw_control.queue_redraw()


# ── Public API ───────────────────────────────────────────────────────────────

## Initialize the minimap from floor generation data.
## Expects a dictionary with a "rooms" array, each room having:
##   id, type, grid_position (or position), connections.
func set_floor_data(floor_data: Dictionary) -> void:
	_floor_data = floor_data
	_rooms.clear()

	var rooms_array: Array = floor_data.get("rooms", [])
	for i in range(rooms_array.size()):
		var r: Dictionary = rooms_array[i] if rooms_array[i] is Dictionary else {}
		var room_id: String = r.get("id", r.get("room_id", "room_%d" % i))
		var room_type: String = r.get("type", "empty")

		# Determine grid position.
		var grid_pos := Vector2.ZERO
		if r.has("grid_position"):
			var gp = r["grid_position"]
			if gp is Dictionary:
				grid_pos = Vector2(float(gp.get("x", i % 5)), float(gp.get("y", i / 5)))
			elif gp is Array and gp.size() >= 2:
				grid_pos = Vector2(float(gp[0]), float(gp[1]))
		elif r.has("position"):
			var p = r["position"]
			if p is Dictionary:
				grid_pos = Vector2(float(p.get("x", i % 5)), float(p.get("y", i / 5)))
			elif p is Array and p.size() >= 2:
				grid_pos = Vector2(float(p[0]), float(p[1]))
		else:
			# Auto-layout in a grid if no position data.
			grid_pos = Vector2(float(i % 5), float(i / 5))

		var connections: Array = r.get("connections", r.get("connected_rooms", []))

		_rooms[room_id] = {
			"grid_pos": grid_pos,
			"type": room_type,
			"explored": false,
			"connections": connections,
		}

	# Reveal the entrance room automatically.
	for room_id in _rooms:
		if _rooms[room_id]["type"] in ["entrance", "start"]:
			reveal_room(room_id)
			update_player_room(room_id)
			break

	if _draw_control != null:
		_draw_control.queue_redraw()


## Move the player marker to a room.
func update_player_room(room_id: String) -> void:
	_current_room_id = room_id
	reveal_room(room_id)

	# Also reveal connected rooms (fog of war: show neighbours).
	if _rooms.has(room_id):
		var connections: Array = _rooms[room_id]["connections"]
		for conn_id in connections:
			if _rooms.has(str(conn_id)):
				# Don't fully reveal – just show them as outlines.
				pass

	if _draw_control != null:
		_draw_control.queue_redraw()


## Mark a room as explored so it is fully rendered.
func reveal_room(room_id: String) -> void:
	if _rooms.has(room_id):
		_rooms[room_id]["explored"] = true
		if _draw_control != null:
			_draw_control.queue_redraw()


# ── Drawing ──────────────────────────────────────────────────────────────────

func _on_draw() -> void:
	if _rooms.is_empty():
		return

	# Calculate bounding box of all room positions to centre them.
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for room_id in _rooms:
		var gp: Vector2 = _rooms[room_id]["grid_pos"]
		min_pos = Vector2(minf(min_pos.x, gp.x), minf(min_pos.y, gp.y))
		max_pos = Vector2(maxf(max_pos.x, gp.x), maxf(max_pos.y, gp.y))

	var range_size := max_pos - min_pos
	var draw_area := _draw_control.size
	var padding: float = ROOM_SIZE + 4.0

	# Scale factor to fit all rooms within the draw area.
	var scale_x: float = (draw_area.x - padding * 2.0) / maxf(range_size.x * ROOM_SPACING, 1.0)
	var scale_y: float = (draw_area.y - padding * 2.0) / maxf(range_size.y * ROOM_SPACING, 1.0)
	var scale_factor: float = minf(scale_x, scale_y)
	scale_factor = minf(scale_factor, 1.0)  # Don't zoom in past 1:1.

	var offset := draw_area * 0.5

	# Draw connections first.
	for room_id in _rooms:
		var room: Dictionary = _rooms[room_id]
		if not room["explored"]:
			continue
		var from_pos: Vector2 = _grid_to_screen(room["grid_pos"], min_pos, scale_factor, offset)
		for conn_id in room["connections"]:
			var cid: String = str(conn_id)
			if _rooms.has(cid):
				var to_pos: Vector2 = _grid_to_screen(_rooms[cid]["grid_pos"], min_pos, scale_factor, offset)
				_draw_control.draw_line(from_pos, to_pos, COLOR_CONNECTION, 1.0)

	# Draw rooms.
	for room_id in _rooms:
		var draw_room: Dictionary = _rooms[room_id]
		var screen_pos: Vector2 = _grid_to_screen(draw_room["grid_pos"], min_pos, scale_factor, offset)
		_draw_room(room_id, screen_pos, draw_room["type"], draw_room["explored"])

	# Draw player dot.
	if _current_room_id != "" and _rooms.has(_current_room_id) and _blink_visible:
		var player_screen_pos: Vector2 = _grid_to_screen(_rooms[_current_room_id]["grid_pos"], min_pos, scale_factor, offset)
		_draw_control.draw_circle(player_screen_pos, PLAYER_DOT_SIZE, COLOR_PLAYER)


## Draw a single room rectangle on the minimap.
func _draw_room(room_id: String, screen_pos: Vector2, type: String, explored: bool) -> void:
	var half := ROOM_SIZE * 0.5
	var rect := Rect2(screen_pos.x - half, screen_pos.y - half, ROOM_SIZE, ROOM_SIZE)

	if explored:
		var color: Color = ROOM_COLORS.get(type, DEFAULT_ROOM_COLOR)
		_draw_control.draw_rect(rect, color, true)

		# Highlight current room border.
		if room_id == _current_room_id:
			_draw_control.draw_rect(rect, COLOR_CURRENT_ROOM, false, 2.0)
	else:
		# Unexplored: draw a faint outline only.
		_draw_control.draw_rect(rect, COLOR_UNEXPLORED, true)


## Convert a grid position to screen coordinates within the draw control.
func _grid_to_screen(grid_pos: Vector2, min_pos: Vector2, scale_factor: float, offset: Vector2) -> Vector2:
	var relative := (grid_pos - min_pos) * ROOM_SPACING * scale_factor
	# Centre the map.
	var total_range := (_get_max_grid_pos() - min_pos) * ROOM_SPACING * scale_factor
	var centering := (offset * 2.0 - total_range) * 0.5
	return relative + centering


func _get_max_grid_pos() -> Vector2:
	var max_pos := Vector2(-INF, -INF)
	for room_id in _rooms:
		var gp: Vector2 = _rooms[room_id]["grid_pos"]
		max_pos = Vector2(maxf(max_pos.x, gp.x), maxf(max_pos.y, gp.y))
	return max_pos


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_autoload(autoload_name: String) -> Node:
	if Engine.has_singleton(autoload_name):
		return Engine.get_singleton(autoload_name)
	var root: Window = get_tree().root if get_tree() != null else null
	if root != null and root.has_node(autoload_name):
		return root.get_node(autoload_name)
	return null
