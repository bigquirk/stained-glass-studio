extends Control

const COLOUR_MAP = {
	"red":   Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}

var _crack_nodes: Array = []   # {start, end, cracked, line_visual}
var _cracked_count: int = 0
var _total_lines: int = 0
var _sheet_offset: Vector2 = Vector2.ZERO

@onready var sheet_display      = $SheetArea/SheetDisplay
@onready var cut_lines_container = $SheetArea/CutLinesContainer
@onready var crack_anim_layer   = $SheetArea/CrackAnimationLayer
@onready var revealed_layer     = $SheetArea/RevealedPiecesLayer
@onready var done_button        = $Controls/DoneButton
@onready var instruction_label  = $Controls/InstructionLabel

func _ready():
	done_button.disabled = true
	done_button.pressed.connect(_on_done)

	var sheet_colour = Color("#C8E8F0")
	if GameState.current_cut_pieces.size() > 0:
		sheet_colour = COLOUR_MAP.get(GameState.current_cut_pieces[0].assigned_colour, sheet_colour)
	sheet_display.color = sheet_colour

	await get_tree().process_frame
	_sheet_offset = sheet_display.global_position
	_draw_pieces_under_sheet()
	_load_cut_lines()

func _draw_pieces_under_sheet():
	for piece in GameState.current_cut_pieces:
		var poly = Polygon2D.new()
		var world_pts = PackedVector2Array()
		for pt in piece.polygon_points:
			world_pts.append(pt + _sheet_offset + Vector2(150, 100))
		poly.polygon = world_pts
		var col = COLOUR_MAP.get(piece.assigned_colour, Color.WHITE)
		col.a = 0.55
		poly.color = col
		revealed_layer.add_child(poly)

func _load_cut_lines():
	if not GameState.has_meta("cut_lines"):
		instruction_label.text = "No cut lines found — press Done to continue."
		done_button.disabled = false
		return

	var cut_lines = GameState.get_meta("cut_lines")
	_total_lines = cut_lines.size()

	for i in range(cut_lines.size()):
		var line_data = cut_lines[i]
		# cut_lines use centered coords (0,0 = sheet centre = offset + 150,100)
		var start = line_data[0] + _sheet_offset + Vector2(150, 100)
		var end   = line_data[1] + _sheet_offset + Vector2(150, 100)
		_spawn_cut_line(start, end)

func _spawn_cut_line(start: Vector2, end: Vector2):
	var line = Line2D.new()
	line.add_point(start)
	line.add_point(end)
	line.width = 2.0
	line.default_color = Color(1, 1, 1, 0.75)
	cut_lines_container.add_child(line)

	_crack_nodes.append({
		"start": start,
		"end": end,
		"cracked": false,
		"line_visual": line
	})

# Click detection via distance-to-line — Area2D input_event is unreliable
# in Control-rooted scenes.
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

	var crack = Line2D.new()
	crack.width = 3.0
	crack.default_color = Color.WHITE
	crack.begin_cap_mode = Line2D.LINE_CAP_ROUND
	crack.end_cap_mode   = Line2D.LINE_CAP_ROUND
	crack_anim_layer.add_child(crack)

	var tween = create_tween()
	var steps = 20
	var duration = 0.45
	for i in range(1, steps + 1):
		var t = float(i) / float(steps)
		tween.tween_callback(_grow_crack.bind(crack, start, end, t))
		tween.tween_interval(duration / steps)
	tween.tween_callback(_crack_done.bind(entry))

func _grow_crack(crack: Line2D, start: Vector2, end: Vector2, t: float):
	crack.clear_points()
	crack.add_point(start)
	crack.add_point(start.lerp(end, t))
	crack.width = lerp(3.0, 1.0, t)
	var grey = lerp(1.0, 0.75, t)
	crack.default_color = Color(grey, grey, grey, 1.0)

func _crack_done(entry: Dictionary):
	_cracked_count += 1
	_do_screen_shake()
	_spawn_particles(entry["start"], entry["end"])
	if _cracked_count >= _total_lines:
		done_button.disabled = false
		instruction_label.text = "All cuts done — press Done to solder."

func _spawn_particles(start: Vector2, end: Vector2):
	for i in range(8):
		var particle = Polygon2D.new()
		particle.color = Color(0.9, 0.95, 1.0, 0.85)
		particle.polygon = PackedVector2Array([Vector2(-2,-2),Vector2(2,-2),Vector2(2,2),Vector2(-2,2)])
		var t = randf()
		particle.position = start.lerp(end, t) + Vector2(randf_range(-5, 5), randf_range(-5, 5))
		crack_anim_layer.add_child(particle)
		var tw = create_tween()
		tw.tween_property(particle, "position", particle.position + Vector2(randf_range(-20,20), randf_range(-20,20)), 0.4)
		tw.parallel().tween_property(particle, "modulate:a", 0.0, 0.4)
		tw.tween_callback(particle.queue_free)

func _do_screen_shake():
	var viewport = get_viewport()
	var tween = create_tween()
	for i in range(5):
		tween.tween_property(viewport, "canvas_transform",
			Transform2D(0.0, Vector2(randf_range(-2,2), randf_range(-2,2))), 0.03)
	tween.tween_property(viewport, "canvas_transform", Transform2D.IDENTITY, 0.03)

func _on_done():
	get_tree().change_scene_to_file("res://scenes/SolderStation.tscn")
