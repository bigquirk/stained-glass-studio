extends Control

# Each colour in the commission gets its own glass sheet on the cutting table.
# Pieces of that colour are nested on it; the surrounding glass is waste.
# Click a piece to score around its perimeter and snap it free.

const COLOUR_MAP = {
	"red":   Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}

const SHEET_W    := 300.0
const SHEET_H    := 200.0
const SHEET_GAP  := 60.0

var _piece_infos: Array = []   # {piece, poly_node, sheet_origin, cracked}
var _cut_count: int = 0
var _total_pieces: int = 0
var _cracking: bool = false

@onready var sheets_container = $SheetsContainer
@onready var done_button      = $Controls/DoneButton
@onready var instruction_label = $Controls/InstructionLabel
@onready var progress_label   = $Controls/ProgressLabel

func _ready():
	done_button.disabled = true
	done_button.pressed.connect(_on_done)

	await get_tree().process_frame
	_build_sheets()

func _build_sheets():
	# Group pieces by colour.
	var by_colour: Dictionary = {}
	for piece in GameState.current_cut_pieces:
		var c = piece.assigned_colour
		if not by_colour.has(c):
			by_colour[c] = []
		by_colour[c].append(piece)

	var colours = by_colour.keys()
	var count   = colours.size()
	_total_pieces = GameState.current_cut_pieces.size()

	# Centre all sheets horizontally; leave room for controls at the bottom.
	var total_w = count * SHEET_W + (count - 1) * SHEET_GAP
	var start_x = (get_viewport_rect().size.x - total_w) / 2.0
	var sheet_y = (get_viewport_rect().size.y - SHEET_H) / 2.0 - 40.0

	for i in range(count):
		var colour    = colours[i]
		var pieces    = by_colour[colour]
		var origin    = Vector2(start_x + i * (SHEET_W + SHEET_GAP), sheet_y)
		_create_sheet(colour, pieces, origin)

	_update_progress()

func _create_sheet(colour: String, pieces: Array, origin: Vector2):
	var glass_col = COLOUR_MAP.get(colour, Color.WHITE)

	# --- Sheet background (the whole pane of glass) ---
	var sheet_bg = Polygon2D.new()
	sheet_bg.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(SHEET_W, 0),
		Vector2(SHEET_W, SHEET_H), Vector2(0, SHEET_H)
	])
	sheet_bg.position = origin
	var bg_col = glass_col
	bg_col.a = 0.55      # slightly transparent so it reads as glass
	sheet_bg.color = bg_col
	sheets_container.add_child(sheet_bg)

	# Sheet border
	var border = Line2D.new()
	for pt in [Vector2(0,0), Vector2(SHEET_W,0), Vector2(SHEET_W,SHEET_H), Vector2(0,SHEET_H), Vector2(0,0)]:
		border.add_point(origin + pt)
	border.width = 2.0
	border.default_color = Color(1, 1, 1, 0.4)
	sheets_container.add_child(border)

	# Colour label above the sheet
	var label = Label.new()
	label.text = colour.capitalize() + " sheet"
	label.add_theme_color_override("font_color", Color("#C0B8A8"))
	label.position = origin + Vector2(0, -28)
	label.size = Vector2(SHEET_W, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheets_container.add_child(label)

	# --- Pieces nested on the sheet ---
	for piece in pieces:
		# position_on_sheet is the piece centre in sheet-local coords (0–300, 0–200).
		var piece_origin = origin + piece.position_on_sheet

		var poly_node = Polygon2D.new()
		poly_node.polygon = piece.polygon_points
		poly_node.position = piece_origin
		poly_node.color = glass_col   # same glass colour, full opacity
		sheets_container.add_child(poly_node)

		# Dark border so each piece reads as a distinct shape to cut.
		var piece_border = Line2D.new()
		var bpts = []
		for pt in piece.polygon_points:
			bpts.append(piece_origin + pt)
		bpts.append(bpts[0])
		piece_border.points = PackedVector2Array(bpts)
		piece_border.width = 2.0
		piece_border.default_color = Color(0.1, 0.08, 0.06, 0.9)
		sheets_container.add_child(piece_border)

		_piece_infos.append({
			"piece":        piece,
			"poly_node":    poly_node,
			"border":       piece_border,
			"sheet_origin": origin,
			"cracked":      false
		})

func _input(event):
	if _cracking:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for info in _piece_infos:
			if info["cracked"]:
				continue
			if _click_hits_piece(event.position, info):
				_score_piece(info)
				get_viewport().set_input_as_handled()
				return

func _click_hits_piece(click: Vector2, info: Dictionary) -> bool:
	var piece: PatternPiece = info["piece"]
	var piece_origin: Vector2 = info["sheet_origin"] + piece.position_on_sheet
	var world_poly = PackedVector2Array()
	for pt in piece.polygon_points:
		world_poly.append(piece_origin + pt)
	return Geometry2D.is_point_in_polygon(click, world_poly)

# Score around the perimeter of the piece, then snap it free.
func _score_piece(info: Dictionary):
	_cracking = true
	var piece: PatternPiece = info["piece"]
	var piece_origin: Vector2 = info["sheet_origin"] + piece.position_on_sheet

	# Build world-space polygon for animation.
	var world_pts: Array = []
	for pt in piece.polygon_points:
		world_pts.append(piece_origin + pt)
	world_pts.append(world_pts[0])   # close the loop

	var crack = Line2D.new()
	crack.width = 2.5
	crack.default_color = Color(1, 1, 1, 0.95)
	crack.begin_cap_mode = Line2D.LINE_CAP_ROUND
	crack.end_cap_mode   = Line2D.LINE_CAP_ROUND
	sheets_container.add_child(crack)

	# Animate the score line growing around the perimeter.
	var tween = create_tween()
	var n = world_pts.size()
	var duration = 0.5
	for i in range(n):
		tween.tween_callback(crack.add_point.bind(world_pts[i]))
		tween.tween_interval(duration / n)
	tween.tween_callback(_finish_cut.bind(info, crack))

func _finish_cut(info: Dictionary, crack: Line2D):
	info["cracked"] = true
	_cut_count += 1
	_cracking = false

	# Leave the crack as a permanent dark score mark.
	crack.default_color = Color(0.15, 0.12, 0.10, 0.85)
	crack.width = 1.5

	# Brighten the piece to show it's been freed from the sheet.
	var poly: Polygon2D = info["poly_node"]
	poly.color.a = 1.0
	var col = poly.color
	col = col.lightened(0.12)
	poly.color = col

	_do_screen_shake()
	_spawn_chips(info)
	_update_progress()

	if _cut_count >= _total_pieces:
		done_button.disabled = false
		instruction_label.text = "All pieces cut — proceed to solder."

func _spawn_chips(info: Dictionary):
	var piece: PatternPiece = info["piece"]
	var piece_origin = info["sheet_origin"] + piece.position_on_sheet
	for i in range(6):
		var pt_idx = i % piece.polygon_points.size()
		var spawn = piece_origin + piece.polygon_points[pt_idx]
		var chip = Polygon2D.new()
		chip.polygon = PackedVector2Array([Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)])
		chip.color = Color(0.9, 0.95, 1.0, 0.85)
		chip.position = spawn + Vector2(randf_range(-4,4), randf_range(-4,4))
		sheets_container.add_child(chip)
		var tw = create_tween()
		tw.tween_property(chip, "position", chip.position + Vector2(randf_range(-18,18), randf_range(-18,18)), 0.35)
		tw.parallel().tween_property(chip, "modulate:a", 0.0, 0.35)
		tw.tween_callback(chip.queue_free)

func _do_screen_shake():
	var tween = create_tween()
	var vp = get_viewport()
	for i in range(4):
		tween.tween_property(vp, "canvas_transform",
			Transform2D(0.0, Vector2(randf_range(-2,2), randf_range(-2,2))), 0.025)
	tween.tween_property(vp, "canvas_transform", Transform2D.IDENTITY, 0.025)

func _update_progress():
	progress_label.text = "Pieces cut: %d / %d" % [_cut_count, _total_pieces]

func _on_done():
	get_tree().change_scene_to_file("res://scenes/SolderStation.tscn")
