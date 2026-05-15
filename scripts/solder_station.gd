extends Control

const COLOUR_MAP = {
	"red":   Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}

const SOLDER_DURATION := 1.2

var _seams: Array = []
var _seams_complete: int = 0
var _animating: bool = false
var _bead_glow_lines: Array = []
var _bead_primary_lines: Array = []
var _iron_cursor: Polygon2D

@onready var assembly_node   = $AssemblyNode
@onready var seam_progress   = $Controls/SeamProgressLabel
@onready var complete_button = $Controls/CompleteButton

func _ready():
	complete_button.disabled = true
	complete_button.pressed.connect(_on_complete)

	_iron_cursor = Polygon2D.new()
	var pts: PackedVector2Array = []
	for i in range(16):
		var a = TAU * i / 16.0
		pts.append(Vector2(cos(a), sin(a)) * 10.0)
	_iron_cursor.polygon = pts
	_iron_cursor.color = Color("#C8A870")
	_iron_cursor.visible = false
	assembly_node.add_child(_iron_cursor)

	await get_tree().process_frame
	assembly_node.position = get_viewport_rect().size / 2.0
	_draw_pieces()
	_build_seams()
	_update_progress()

func _draw_pieces():
	for piece in GameState.current_cut_pieces:
		var poly = Polygon2D.new()
		var local_pts = PackedVector2Array()
		for pt in piece.polygon_points:
			# polygon_points are in piece-local coords (centred at origin).
			# position_on_sheet is sheet-local (0–300, 0–200); subtract sheet centre
			# so everything is centred around assembly_node's origin.
			local_pts.append(pt + piece.position_on_sheet - Vector2(150, 100))
		poly.polygon = local_pts
		poly.color = COLOUR_MAP.get(piece.assigned_colour, Color.WHITE)
		assembly_node.add_child(poly)

		var border = Line2D.new()
		var bpts: Array = []
		for pt in local_pts:
			bpts.append(pt)
		bpts.append(bpts[0])
		border.points = PackedVector2Array(bpts)
		border.width = 2.0
		border.default_color = Color(0.08, 0.06, 0.04, 1.0)
		assembly_node.add_child(border)

func _build_seams():
	if not GameState.has_meta("cut_lines"):
		return
	var cut_lines = GameState.get_meta("cut_lines")

	for i in range(cut_lines.size()):
		var line_data = cut_lines[i]
		# cut_lines are already in centred coords (0,0 = sheet centre), use directly.
		var start = line_data[0]
		var end   = line_data[1]

		var seam_line = Line2D.new()
		seam_line.add_point(start)
		seam_line.add_point(end)
		seam_line.width = 3.0
		seam_line.default_color = Color(0.08, 0.06, 0.04, 0.85)
		assembly_node.add_child(seam_line)

		var glow = Line2D.new()
		glow.width = 9.0
		glow.default_color = Color(1, 0.95, 0.7, 0.2)
		glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		glow.end_cap_mode   = Line2D.LINE_CAP_ROUND
		assembly_node.add_child(glow)
		_bead_glow_lines.append(glow)

		var primary = Line2D.new()
		primary.width = 4.0
		primary.default_color = Color("#C8C0B0")
		primary.begin_cap_mode = Line2D.LINE_CAP_ROUND
		primary.end_cap_mode   = Line2D.LINE_CAP_ROUND
		assembly_node.add_child(primary)
		_bead_primary_lines.append(primary)

		_seams.append({
			"start": start, "end": end,
			"seam_line": seam_line,
			"complete": false,
			"index": i
		})

func _input(event):
	if _animating:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var local_click = assembly_node.to_local(event.position)
		for seam in _seams:
			if seam["complete"]:
				continue
			if _near_segment(local_click, seam["start"], seam["end"], 16.0):
				_run_solder(seam)
				get_viewport().set_input_as_handled()
				return

func _near_segment(pt: Vector2, a: Vector2, b: Vector2, threshold: float) -> bool:
	var ab = b - a
	var len_sq = ab.length_squared()
	if len_sq < 0.001:
		return pt.distance_to(a) < threshold
	var t = clamp((pt - a).dot(ab) / len_sq, 0.0, 1.0)
	return pt.distance_to(a + t * ab) < threshold

func _run_solder(seam: Dictionary):
	_animating = true
	_iron_cursor.visible = true
	_iron_cursor.position = seam["start"]

	var steps = 30
	var glow    = _bead_glow_lines[seam["index"]]
	var primary = _bead_primary_lines[seam["index"]]

	var tween = create_tween()
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var pt = seam["start"].lerp(seam["end"], t)
		tween.tween_callback(_advance_bead.bind(pt, glow, primary))
		tween.tween_interval(SOLDER_DURATION / steps)
	tween.tween_callback(_finish_solder.bind(seam))

func _advance_bead(pt: Vector2, glow: Line2D, primary: Line2D):
	_iron_cursor.position = pt
	glow.add_point(pt)
	primary.add_point(pt)

func _finish_solder(seam: Dictionary):
	seam["complete"] = true
	seam["seam_line"].hide()
	_seams_complete += 1
	_animating = false
	_iron_cursor.visible = false
	_update_progress()
	if _seams_complete >= _seams.size():
		complete_button.disabled = false

func _update_progress():
	seam_progress.text = "Seams: %d / %d" % [_seams_complete, _seams.size()]

func _on_complete():
	_show_delivery_modal()

func _show_delivery_modal():
	var modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	modal.custom_minimum_size = Vector2(400, 300)

	var style = StyleBoxFlat.new()
	style.bg_color = Color("#3A3028")
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	modal.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	modal.add_child(vbox)

	var title = Label.new()
	title.text = "Commission Complete!"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#F0E8D8"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var client_label = Label.new()
	client_label.text = "For: %s" % GameState.active_commission.client_name
	client_label.add_theme_color_override("font_color", Color("#C0B8A8"))
	client_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(client_label)

	var payout_label = Label.new()
	payout_label.text = "Payout: +%dg" % GameState.active_commission.payout
	payout_label.add_theme_font_size_override("font_size", 20)
	payout_label.add_theme_color_override("font_color", Color("#E8A838"))
	payout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(payout_label)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var deliver_btn = Button.new()
	deliver_btn.text = "Deliver"
	deliver_btn.custom_minimum_size = Vector2(120, 50)
	deliver_btn.pressed.connect(_on_deliver.bind(modal))
	vbox.add_child(deliver_btn)

	add_child(modal)
	await get_tree().process_frame
	modal.position = (get_viewport_rect().size - modal.size) / 2.0

func _on_deliver(modal: Control):
	GameState.wallet += GameState.active_commission.payout
	GameState.active_commission.is_complete = true
	GameState.active_commission = null
	GameState.current_cut_pieces = []
	modal.queue_free()
	get_tree().change_scene_to_file("res://scenes/CommissionBoard.tscn")
