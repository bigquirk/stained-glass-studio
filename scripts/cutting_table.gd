extends Control

# Guillotine-cut mechanic: score column cuts first, then within-column cuts.
# All pieces from the pattern are shown as paper templates on one glass sheet.
# Cut lines are presented phase by phase — complete all cuts in a phase to
# unlock the next. Click a highlighted guide line to score it.

const COLOUR_MAP = {
	"red":   Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}

# Display scale — pattern coords are 300×200 centred; scale for visibility.
const DISPLAY_SCALE := 2.0

var _cut_sequence: Array = []   # Array of phases; each phase = Array of [start, end]
var _current_phase: int = 0
var _phase_done: Array = []     # bool per cut in current phase
var _active_nodes: Array = []   # Line2D per active cut (highlighted)
var _animating: bool = false
var _total_cuts: int = 0
var _cuts_made: int = 0

@onready var sheets_container  = $SheetsContainer
@onready var done_button       = $Controls/DoneButton
@onready var instruction_label = $Controls/InstructionLabel
@onready var progress_label    = $Controls/ProgressLabel

func _ready():
	done_button.disabled = true
	done_button.pressed.connect(_on_done)

	await get_tree().process_frame
	sheets_container.position = get_viewport_rect().size / 2.0
	sheets_container.scale    = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)

	_draw_board()
	_draw_pieces()
	_load_cut_sequence()
	_show_current_phase()
	_update_progress()

# --- Drawing ---

func _draw_board():
	# Glass sheet background: frosted, full sheet extent (–150..150, –100..100).
	var sheet = Polygon2D.new()
	sheet.polygon = PackedVector2Array([
		Vector2(-150,-100), Vector2(150,-100),
		Vector2(150,100),   Vector2(-150,100)
	])
	sheet.color = Color(0.82, 0.88, 0.90, 0.65)
	sheets_container.add_child(sheet)

	var border = Line2D.new()
	for pt in [Vector2(-150,-100), Vector2(150,-100), Vector2(150,100), Vector2(-150,100), Vector2(-150,-100)]:
		border.add_point(pt)
	border.width = 1.5
	border.default_color = Color(1, 1, 1, 0.55)
	sheets_container.add_child(border)

func _draw_pieces():
	for piece in GameState.current_cut_pieces:
		# position_on_sheet is sheet-local (0–300, 0–200); shift to centred coords.
		var centre = piece.position_on_sheet - Vector2(150, 100)

		# Cream paper base.
		var paper = Polygon2D.new()
		paper.polygon = piece.polygon_points
		paper.position = centre
		paper.color = Color(0.96, 0.93, 0.88, 1.0)
		sheets_container.add_child(paper)

		# Colour tint — paint-by-numbers fill.
		var tint = Polygon2D.new()
		tint.polygon = piece.polygon_points
		tint.position = centre
		var col = COLOUR_MAP.get(piece.assigned_colour, Color.WHITE)
		col.a = 0.50
		tint.color = col
		sheets_container.add_child(tint)

		# Thick sharpie border.
		var bdr = Line2D.new()
		var pts: Array = []
		for pt in piece.polygon_points:
			pts.append(pt)
		pts.append(pts[0])
		bdr.points = PackedVector2Array(pts)
		bdr.position = centre
		bdr.width = 2.0
		bdr.default_color = Color(0.08, 0.05, 0.03, 0.95)
		sheets_container.add_child(bdr)

# --- Cut sequence ---

func _load_cut_sequence():
	if not GameState.has_meta("cut_sequence"):
		return
	_cut_sequence = GameState.get_meta("cut_sequence")
	for phase in _cut_sequence:
		_total_cuts += phase.size()

func _show_current_phase():
	for node in _active_nodes:
		node.queue_free()
	_active_nodes.clear()
	_phase_done.clear()

	if _current_phase >= _cut_sequence.size():
		done_button.disabled = false
		instruction_label.text = "All cuts made — proceed to solder."
		return

	var phase = _cut_sequence[_current_phase]
	for cut in phase:
		var line = Line2D.new()
		line.add_point(cut[0])
		line.add_point(cut[1])
		line.width = 2.0
		line.default_color = Color(1.0, 0.88, 0.25, 0.92)  # amber guide line
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode   = Line2D.LINE_CAP_ROUND
		sheets_container.add_child(line)
		_active_nodes.append(line)
		_phase_done.append(false)

	if _current_phase == 0:
		instruction_label.text = "Score the column cuts first — click a guide line."
	else:
		instruction_label.text = "Now score within each section — click a guide line."

# --- Input ---

func _input(event):
	if _animating or _current_phase >= _cut_sequence.size():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Convert to sheets_container local space (accounts for position + scale).
		var local_click = sheets_container.to_local(event.position)
		var phase = _cut_sequence[_current_phase]
		for i in range(phase.size()):
			if _phase_done[i]:
				continue
			var cut = phase[i]
			if _near_segment(local_click, cut[0], cut[1], 12.0):
				_run_cut(i, cut)
				get_viewport().set_input_as_handled()
				return

func _near_segment(pt: Vector2, a: Vector2, b: Vector2, threshold: float) -> bool:
	var ab = b - a
	var len_sq = ab.length_squared()
	if len_sq < 0.001:
		return pt.distance_to(a) < threshold
	var t = clamp((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + t * ab) < threshold

# --- Cut animation ---

func _run_cut(idx: int, cut: Array):
	_animating = true
	_active_nodes[idx].hide()

	var crack = Line2D.new()
	crack.width = 1.5
	crack.default_color = Color(1, 1, 1, 0.9)
	crack.begin_cap_mode = Line2D.LINE_CAP_ROUND
	crack.end_cap_mode   = Line2D.LINE_CAP_ROUND
	sheets_container.add_child(crack)

	var tween = create_tween()
	var steps = 20
	var duration = 0.35
	for i in range(steps + 1):
		var t = float(i) / steps
		var pt = cut[0].lerp(cut[1], t)
		tween.tween_callback(crack.add_point.bind(pt))
		tween.tween_interval(duration / steps)
	tween.tween_callback(_finish_cut.bind(idx, crack))

func _finish_cut(idx: int, crack: Line2D):
	_phase_done[idx] = true
	_cuts_made += 1
	_animating = false

	# Score mark: permanent dark line.
	crack.default_color = Color(0.12, 0.10, 0.08, 0.88)
	crack.width = 1.0

	_do_screen_shake()
	_update_progress()

	# Advance phase once every cut in this phase is done.
	if not _phase_done.has(false):
		_current_phase += 1
		_show_current_phase()

func _do_screen_shake():
	var tween = create_tween()
	var vp = get_viewport()
	for i in range(4):
		tween.tween_property(vp, "canvas_transform",
			Transform2D(0.0, Vector2(randf_range(-2,2), randf_range(-2,2))), 0.025)
	tween.tween_property(vp, "canvas_transform", Transform2D.IDENTITY, 0.025)

func _update_progress():
	progress_label.text = "Cuts: %d / %d" % [_cuts_made, _total_cuts]

func _on_done():
	get_tree().change_scene_to_file("res://scenes/SolderStation.tscn")
