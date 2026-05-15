extends Control

const COLOUR_MAP = {
	"red":   Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}

var _crack_nodes: Array = []
var _cracked_count: int = 0
var _total_lines: int = 0
var _content_offset: Vector2 = Vector2.ZERO  # global position of SheetArea top-left

@onready var sheet_area         = $SheetArea
@onready var sheet_display      = $SheetArea/SheetDisplay
@onready var cut_lines_container = $SheetArea/CutLinesContainer
@onready var crack_anim_layer   = $SheetArea/CrackAnimationLayer
@onready var revealed_layer     = $SheetArea/RevealedPiecesLayer
@onready var done_button        = $Controls/DoneButton
@onready var instruction_label  = $Controls/InstructionLabel

func _ready():
	done_button.disabled = true
	done_button.pressed.connect(_on_done)

	# The sheet display is just the cutting mat background now — neutral dark green.
	sheet_display.color = Color(0.18, 0.22, 0.18, 1.0)

	await get_tree().process_frame
	_content_offset = sheet_display.global_position
	_draw_pieces()
	_load_cut_lines()

# Draw the actual glass pieces at full opacity — these ARE the thing being cut.
func _draw_pieces():
	for piece in GameState.current_cut_pieces:
		var poly = Polygon2D.new()
		var world_pts = PackedVector2Array()
		for pt in piece.polygon_points:
			world_pts.append(pt + _content_offset + Vector2(150, 100))
		poly.polygon = world_pts
		poly.color = COLOUR_MAP.get(piece.assigned_colour, Color.WHITE)
		revealed_layer.add_child(poly)

		# Thin dark border between pieces so edges read clearly.
		var border = Line2D.new()
		var bpts = piece.polygon_points.duplicate()
		bpts.append(bpts[0])
		for pt in bpts:
			border.add_point(pt + _content_offset + Vector2(150, 100))
		border.width = 1.5
		border.default_color = Color(0, 0, 0, 0.5)
		revealed_layer.add_child(border)

func _load_cut_lines():
	if not GameState.has_meta("cut_lines"):
		instruction_label.text = "No cut lines — press Done to continue."
		done_button.disabled = false
		return

	var cut_lines = GameState.get_meta("cut_lines")
	_total_lines = cut_lines.size()
	for line_data in cut_lines:
		var start = line_data[0] + _content_offset + Vector2(150, 100)
		var end   = line_data[1] + _content_offset + Vector2(150, 100)
		_spawn_cut_line(start, end)

func _spawn_cut_line(start: Vector2, end: Vector2):
	# Score line drawn on top of the glass pieces.
	var line = Line2D.new()
	line.add_point(start)
	line.add_point(end)
	line.width = 2.5
	line.default_color = Color(1, 1, 1, 0.9)
	cut_lines_container.add_child(line)

	_crack_nodes.append({"start": start, "end": end, "cracked": false, "line_visual": line})

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for entry in _crack_nodes:
			if entry["cracked"]:
				continue
			if _near_segment(event.position, entry["start"], entry["end"], 14.0):
				_do_crack(entry)
				get_viewport().set_input_as_handled()
				return

func _near_segment(pt: Vector2, a: Vector2, b: Vector2, threshold: float) -> bool:
	var ab = b - a
	var len_sq = ab.length_squared()
	if len_sq < 0.001:
		return pt.distance_to(a) < threshold
	var t = clamp((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + t * ab) < threshold

func _do_crack(entry: Dictionary):
	entry["cracked"] = true
	entry["line_visual"].hide()

	var start: Vector2 = entry["start"]
	var end:   Vector2 = entry["end"]

	# The crack races across the glass surface.
	var crack = Line2D.new()
	crack.width = 3.0
	crack.default_color = Color(1, 1, 1, 1)
	crack.begin_cap_mode = Line2D.LINE_CAP_ROUND
	crack.end_cap_mode   = Line2D.LINE_CAP_ROUND
	crack_anim_layer.add_child(crack)

	var tween = create_tween()
	var steps = 20
	for i in range(1, steps + 1):
		var t = float(i) / float(steps)
		tween.tween_callback(_grow_crack.bind(crack, start, end, t))
		tween.tween_interval(0.45 / steps)
	tween.tween_callback(_crack_done.bind(entry, crack))

func _grow_crack(crack: Line2D, start: Vector2, end: Vector2, t: float):
	crack.clear_points()
	crack.add_point(start)
	crack.add_point(start.lerp(end, t))
	crack.width = lerp(3.0, 1.5, t)
	var grey = lerp(1.0, 0.6, t)
	crack.default_color = Color(grey, grey, grey, 1.0)

func _crack_done(entry: Dictionary, crack: Line2D):
	_cracked_count += 1
	# Leave a permanent dark crack line on the glass.
	crack.default_color = Color(0.15, 0.12, 0.10, 0.9)
	crack.width = 1.5
	_do_screen_shake()
	_spawn_particles(entry["start"], entry["end"])
	if _cracked_count >= _total_lines:
		done_button.disabled = false
		instruction_label.text = "All cuts done — proceed to solder."

func _spawn_particles(start: Vector2, end: Vector2):
	for i in range(8):
		var p = Polygon2D.new()
		p.color = Color(0.9, 0.95, 1.0, 0.85)
		p.polygon = PackedVector2Array([Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)])
		p.position = start.lerp(end, randf()) + Vector2(randf_range(-5,5), randf_range(-5,5))
		crack_anim_layer.add_child(p)
		var tw = create_tween()
		tw.tween_property(p, "position", p.position + Vector2(randf_range(-20,20), randf_range(-20,20)), 0.4)
		tw.parallel().tween_property(p, "modulate:a", 0.0, 0.4)
		tw.tween_callback(p.queue_free)

func _do_screen_shake():
	var tween = create_tween()
	var vp = get_viewport()
	for i in range(5):
		tween.tween_property(vp, "canvas_transform",
			Transform2D(0.0, Vector2(randf_range(-2,2), randf_range(-2,2))), 0.03)
	tween.tween_property(vp, "canvas_transform", Transform2D.IDENTITY, 0.03)

func _on_done():
	get_tree().change_scene_to_file("res://scenes/SolderStation.tscn")
