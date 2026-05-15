extends Control

# Patterns define pieces in sheet-local coords (0,0 = sheet top-left, 300x200).
# Each piece has a poly centered at origin and a target position on the sheet.
# Cut lines use centered coords (0,0 = sheet centre = 150,100).
const PATTERNS = {
	"pattern_diamond": {
		"name": "Quartet",
		"pieces": [
			{"id": "d0", "poly": [Vector2(-70,-45),Vector2(70,-45),Vector2(70,45),Vector2(-70,45)], "target": Vector2(80, 55),  "colour_index": 0},
			{"id": "d1", "poly": [Vector2(-70,-45),Vector2(70,-45),Vector2(70,45),Vector2(-70,45)], "target": Vector2(220, 55),  "colour_index": 1},
			{"id": "d2", "poly": [Vector2(-70,-45),Vector2(70,-45),Vector2(70,45),Vector2(-70,45)], "target": Vector2(80, 145), "colour_index": 1},
			{"id": "d3", "poly": [Vector2(-70,-45),Vector2(70,-45),Vector2(70,45),Vector2(-70,45)], "target": Vector2(220, 145), "colour_index": 0},
		],
		"cut_lines": [
			[Vector2(-140, 0),   Vector2(140, 0)],
			[Vector2(0, -90),    Vector2(0, 90)],
		]
	},
	"pattern_sun": {
		"name": "Triptych",
		"pieces": [
			{"id": "s0", "poly": [Vector2(-45,-90),Vector2(45,-90),Vector2(45,90),Vector2(-45,90)], "target": Vector2(55,  100), "colour_index": 0},
			{"id": "s1", "poly": [Vector2(-45,-90),Vector2(45,-90),Vector2(45,90),Vector2(-45,90)], "target": Vector2(150, 100), "colour_index": 1},
			{"id": "s2", "poly": [Vector2(-45,-90),Vector2(45,-90),Vector2(45,90),Vector2(-45,90)], "target": Vector2(245, 100), "colour_index": 0},
		],
		"cut_lines": [
			[Vector2(-50, -90),  Vector2(-50, 90)],
			[Vector2(50,  -90),  Vector2(50,  90)],
		]
	},
	"pattern_arch": {
		"name": "Cathedral",
		"pieces": [
			{"id": "a0", "poly": [Vector2(-65,-30),Vector2(65,-30),Vector2(65,30),Vector2(-65,30)], "target": Vector2(85,  40),  "colour_index": 0},
			{"id": "a1", "poly": [Vector2(-65,-30),Vector2(65,-30),Vector2(65,30),Vector2(-65,30)], "target": Vector2(215, 40),  "colour_index": 1},
			{"id": "a2", "poly": [Vector2(-65,-30),Vector2(65,-30),Vector2(65,30),Vector2(-65,30)], "target": Vector2(85,  100), "colour_index": 1},
			{"id": "a3", "poly": [Vector2(-65,-30),Vector2(65,-30),Vector2(65,30),Vector2(-65,30)], "target": Vector2(215, 100), "colour_index": 0},
			{"id": "a4", "poly": [Vector2(-65,-30),Vector2(65,-30),Vector2(65,30),Vector2(-65,30)], "target": Vector2(85,  160), "colour_index": 0},
			{"id": "a5", "poly": [Vector2(-65,-30),Vector2(65,-30),Vector2(65,30),Vector2(-65,30)], "target": Vector2(215, 160), "colour_index": 1},
		],
		"cut_lines": [
			[Vector2(-130, -30), Vector2(130, -30)],
			[Vector2(-130,  30), Vector2(130,  30)],
			[Vector2(0,    -90), Vector2(0,     90)],
		]
	}
}

const COLOUR_MAP = {
	"red":   Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}

const SNAP_RADIUS := 55.0

var _pieces: Array = []
var _ghost_nodes: Array = []
var _dragging_piece = null
var _drag_offset: Vector2 = Vector2.ZERO
var _selected_sheet: GlassSheet = null
var _commission_colours: Array = []
var _sheet_origin: Vector2 = Vector2.ZERO  # global position of sheet top-left

@onready var glass_sheet_display = $MainContainer/SheetArea/GlassSheetDisplay
@onready var piece_container    = $MainContainer/SheetArea/PieceContainer
@onready var waste_display      = $MainContainer/Controls/WasteDisplay
@onready var confirm_button     = $MainContainer/Controls/ConfirmButton
@onready var sheet_selector     = $MainContainer/Controls/SheetSelector
@onready var instruction_label  = $MainContainer/Controls/InstructionLabel

func _ready():
	if not GameState.active_commission:
		get_tree().change_scene_to_file("res://scenes/CommissionBoard.tscn")
		return

	_commission_colours = GameState.active_commission.required_colours
	confirm_button.disabled = true
	confirm_button.pressed.connect(_on_confirm)
	$MainContainer/Controls/BackButton.pressed.connect(
		func(): get_tree().change_scene_to_file("res://scenes/CommissionBoard.tscn")
	)

	instruction_label.text = "Drag each piece to its outlined slot on the glass sheet."
	waste_display.text = "Placed: 0 / 0"

	_build_colour_info()
	_setup_sheet_display()
	await get_tree().process_frame
	_sheet_origin = glass_sheet_display.global_position
	_load_pattern()

func _build_colour_info():
	for child in sheet_selector.get_children():
		child.queue_free()

	var header = Label.new()
	header.text = "Required colours:"
	header.add_theme_color_override("font_color", Color("#F0E8D8"))
	sheet_selector.add_child(header)

	for colour in _commission_colours:
		var row = HBoxContainer.new()
		var swatch = ColorRect.new()
		swatch.color = COLOUR_MAP.get(colour, Color.WHITE)
		swatch.custom_minimum_size = Vector2(16, 16)
		row.add_child(swatch)
		var lbl = Label.new()
		lbl.text = "  " + colour.capitalize()
		lbl.add_theme_color_override("font_color", Color("#C0B8A8"))
		row.add_child(lbl)

		var has_sheet = false
		for sheet in GameState.inventory:
			if sheet.colour == colour:
				has_sheet = true
				break
		if not has_sheet:
			var warn = Label.new()
			warn.text = "  (missing!)"
			warn.add_theme_color_override("font_color", Color("#E8A838"))
			row.add_child(warn)

		sheet_selector.add_child(row)

func _setup_sheet_display():
	# Neutral frosted surface — coloured piece ghosts read against this.
	glass_sheet_display.color = Color(0.88, 0.88, 0.84, 1.0)

func _load_pattern():
	var pattern_id = GameState.active_commission.pattern_id
	if not PATTERNS.has(pattern_id):
		return

	var pattern_data = PATTERNS[pattern_id]
	_draw_ghost_outlines(pattern_data)
	_spawn_pieces(pattern_data)
	_update_placed_count()

func _draw_ghost_outlines(pattern_data: Dictionary):
	for piece_data in pattern_data["pieces"]:
		var target_screen = _sheet_origin + piece_data["target"]

		# Determine this slot's colour so the ghost shows what belongs here.
		var colour_index = piece_data["colour_index"] % max(_commission_colours.size(), 1)
		var colour_name = _commission_colours[colour_index] if _commission_colours.size() > 0 else "clear"
		var slot_col = COLOUR_MAP.get(colour_name, Color.WHITE)

		# Filled ghost — coloured at 30% so you can see the glass beneath.
		var ghost = Polygon2D.new()
		ghost.polygon = PackedVector2Array(piece_data["poly"])
		ghost.position = target_screen
		slot_col.a = 0.30
		ghost.color = slot_col
		piece_container.add_child(ghost)

		# Bright border so the slot boundary reads clearly.
		var outline = Line2D.new()
		var pts = piece_data["poly"].duplicate()
		pts.append(pts[0])
		outline.points = PackedVector2Array(pts)
		outline.position = target_screen
		outline.width = 2.0
		outline.default_color = Color(1, 1, 1, 0.85)
		piece_container.add_child(outline)

		_ghost_nodes.append({"poly": ghost, "outline": outline, "id": piece_data["id"]})

func _spawn_pieces(pattern_data: Dictionary):
	var colours = _commission_colours
	# Place pieces to the right of the sheet, spaced by their actual bounding height.
	var start_x = _sheet_origin.x + 300.0 + 50.0
	var cursor_y = _sheet_origin.y + 20.0

	for i in range(pattern_data["pieces"].size()):
		var piece_data = pattern_data["pieces"][i]
		var colour_index = piece_data["colour_index"] % max(colours.size(), 1)
		var colour_name = colours[colour_index] if colours.size() > 0 else "clear"

		# Compute bounding box so we can space correctly.
		var min_y_local = INF
		var max_y_local = -INF
		for pt in piece_data["poly"]:
			min_y_local = min(min_y_local, pt.y)
			max_y_local = max(max_y_local, pt.y)
		var piece_h = max_y_local - min_y_local

		var node = Node2D.new()
		node.set_meta("piece_id",      piece_data["id"])
		node.set_meta("poly",          piece_data["poly"])
		node.set_meta("colour_name",   colour_name)
		node.set_meta("snapped",       false)
		node.set_meta("target_screen", _sheet_origin + piece_data["target"])

		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array(piece_data["poly"])
		var col = COLOUR_MAP.get(colour_name, Color.WHITE)
		col.a = 0.9
		poly.color = col
		node.add_child(poly)

		var outline = Line2D.new()
		var pts = piece_data["poly"].duplicate()
		pts.append(pts[0])
		outline.points = PackedVector2Array(pts)
		outline.width = 2.0
		outline.default_color = Color(1, 1, 1, 0.9)
		node.add_child(outline)

		# Position at the vertical centre of this piece's slot in the stack.
		node.position = Vector2(start_x, cursor_y + piece_h * 0.5)
		cursor_y += piece_h + 20.0

		piece_container.add_child(node)
		_pieces.append(node)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_try_start_drag(event.position)
			else:
				_end_drag()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _dragging_piece:
				_dragging_piece.rotation_degrees += 45.0

	if event is InputEventMouseMotion and _dragging_piece:
		_dragging_piece.position = event.position + _drag_offset

	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		if _dragging_piece:
			_dragging_piece.rotation_degrees += 45.0

func _try_start_drag(mouse_pos: Vector2):
	# Iterate in reverse so topmost piece is picked first.
	for i in range(_pieces.size() - 1, -1, -1):
		var piece = _pieces[i]
		if piece.get_meta("snapped", false):
			continue
		if _point_in_piece(mouse_pos, piece):
			_dragging_piece = piece
			_drag_offset = piece.position - mouse_pos
			return

func _point_in_piece(mouse_pos: Vector2, piece: Node2D) -> bool:
	var local_pos = piece.to_local(mouse_pos)
	return Geometry2D.is_point_in_polygon(local_pos, PackedVector2Array(piece.get_meta("poly")))

func _end_drag():
	if not _dragging_piece:
		return

	var piece = _dragging_piece
	_dragging_piece = null

	var target_screen = piece.get_meta("target_screen") as Vector2
	if piece.position.distance_to(target_screen) < SNAP_RADIUS:
		_snap_piece(piece, target_screen)
	else:
		_restore_piece_colour(piece)

	_update_placed_count()

func _snap_piece(piece: Node2D, target: Vector2):
	piece.position = target
	piece.rotation_degrees = 0.0
	piece.set_meta("snapped", true)

	# Brighten the piece to show it's locked in.
	var poly = piece.get_child(0) as Polygon2D
	if poly:
		var colour_name = piece.get_meta("colour_name", "clear")
		var col = COLOUR_MAP.get(colour_name, Color.WHITE)
		col.a = 1.0
		poly.color = col

	# Ghost disappears — piece now fills the slot.
	var piece_id = piece.get_meta("piece_id")
	for ghost in _ghost_nodes:
		if ghost["id"] == piece_id:
			ghost["poly"].color    = Color(0, 0, 0, 0)
			ghost["outline"].default_color = Color(1, 1, 1, 0.20)

	if _all_snapped():
		confirm_button.disabled = false
		instruction_label.text = "All pieces placed. Press Confirm to cut."

func _restore_piece_colour(piece: Node2D):
	var poly = piece.get_child(0) as Polygon2D
	if poly:
		var colour_name = piece.get_meta("colour_name", "clear")
		var col = COLOUR_MAP.get(colour_name, Color.WHITE)
		col.a = 0.9
		poly.color = col

func _all_snapped() -> bool:
	for piece in _pieces:
		if not piece.get_meta("snapped", false):
			return false
	return true

func _update_placed_count():
	var placed = 0
	for piece in _pieces:
		if piece.get_meta("snapped", false):
			placed += 1
	waste_display.text = "Placed: %d / %d" % [placed, _pieces.size()]

func _on_confirm():
	var pattern_id = GameState.active_commission.pattern_id
	var pattern_data = PATTERNS[pattern_id]
	GameState.current_cut_pieces = []
	for piece in _pieces:
		var pp = PatternPiece.new()
		pp.piece_id       = piece.get_meta("piece_id")
		pp.polygon_points = PackedVector2Array(piece.get_meta("poly"))
		pp.assigned_colour = piece.get_meta("colour_name")
		pp.position_on_sheet = piece.position
		pp.rotation_degrees  = piece.rotation_degrees
		GameState.current_cut_pieces.append(pp)
	GameState.set_meta("cut_lines", pattern_data["cut_lines"])
	get_tree().change_scene_to_file("res://scenes/CuttingTable.tscn")
