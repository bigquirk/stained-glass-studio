extends Control

const COLOUR_MAP = {
	"red": Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}

var _seams: Array = []
var _seam_paths: Array = []
var _active_seam_index: int = -1
var _is_dragging: bool = false
var _seams_complete: int = 0
var _bead_glow_lines: Array = []
var _bead_primary_lines: Array = []
var _content_offset: Vector2 = Vector2.ZERO

@onready var piece_assembly = $WorkArea/WorkpieceDisplay/PieceAssembly
@onready var seam_container = $WorkArea/WorkpieceDisplay/SeamContainer
@onready var bead_layer = $WorkArea/WorkpieceDisplay/BeadLayer
@onready var seam_progress = $Controls/SeamProgressBar
@onready var complete_button = $Controls/CompleteButton

var _iron_cursor: Polygon2D

func _ready():
	complete_button.disabled = true
	complete_button.pressed.connect(_on_complete)

	# Build iron cursor as a Polygon2D (Node2D) so it renders correctly in the 2D canvas.
	_iron_cursor = Polygon2D.new()
	var pts: PackedVector2Array = []
	var sides = 12
	for i in range(sides):
		var a = TAU * i / sides
		pts.append(Vector2(cos(a), sin(a)) * 12.0)
	_iron_cursor.polygon = pts
	_iron_cursor.color = Color("#8A7A6A")
	_iron_cursor.visible = false
	seam_container.add_child(_iron_cursor)

	# Wait one frame so Control layout is computed before reading global_position.
	# Node2D children of Control nodes have (0,0) at viewport origin, not parent position.
	await get_tree().process_frame
	_content_offset = $WorkArea.global_position
	_draw_pieces()
	_build_seams()
	_update_progress()

func _draw_pieces():
	for piece in GameState.current_cut_pieces:
		var poly = Polygon2D.new()
		var world_pts = PackedVector2Array()
		for pt in piece.polygon_points:
			world_pts.append(pt + Vector2(150, 100) + _content_offset)
		poly.polygon = world_pts
		var col = COLOUR_MAP.get(piece.assigned_colour, Color.WHITE)
		col.a = 0.85
		poly.color = col
		piece_assembly.add_child(poly)

func _build_seams():
	if not GameState.has_meta("cut_lines"):
		return
	var cut_lines = GameState.get_meta("cut_lines")

	for i in range(cut_lines.size()):
		var line_data = cut_lines[i]
		var start = line_data[0] + Vector2(150, 100) + _content_offset
		var end = line_data[1] + Vector2(150, 100) + _content_offset

		var path_pts = _generate_path_points(start, end)
		_seam_paths.append(path_pts)

		var seam_line = Line2D.new()
		seam_line.add_point(start)
		seam_line.add_point(end)
		seam_line.width = 3.0
		seam_line.default_color = Color(0.7, 0.7, 0.7, 0.6)
		seam_container.add_child(seam_line)
		_seams.append({"line": seam_line, "complete": false, "index": i})

		var area = Area2D.new()
		area.collision_layer = 1
		area.collision_mask = 1
		var shape = CollisionShape2D.new()
		var rect = RectangleShape2D.new()
		var vec = end - start
		rect.size = Vector2(vec.length(), 16)
		shape.shape = rect
		shape.position = (start + end) / 2.0
		shape.rotation = vec.angle()
		area.add_child(shape)
		area.set_meta("seam_index", i)
		area.input_event.connect(_on_seam_click.bind(i))
		area.input_pickable = true
		seam_container.add_child(area)

		# Pre-create bead lines
		var glow = Line2D.new()
		glow.width = 8.0
		glow.default_color = Color(1, 1, 1, 0.25)
		glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		glow.end_cap_mode = Line2D.LINE_CAP_ROUND
		bead_layer.add_child(glow)
		_bead_glow_lines.append(glow)

		var primary = Line2D.new()
		primary.width = 4.0
		primary.default_color = Color("#D4D4D4")
		primary.begin_cap_mode = Line2D.LINE_CAP_ROUND
		primary.end_cap_mode = Line2D.LINE_CAP_ROUND
		bead_layer.add_child(primary)
		_bead_primary_lines.append(primary)

func _generate_path_points(start: Vector2, end: Vector2) -> PackedVector2Array:
	var pts = PackedVector2Array()
	var steps = 30
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		pts.append(start.lerp(end, t))
	return pts

func _on_seam_click(_viewport, event, _shape, seam_index: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _seams[seam_index]["complete"]:
			_active_seam_index = seam_index
			_is_dragging = true
			_iron_cursor.visible = true
		elif not event.pressed:
			_is_dragging = false
			_iron_cursor.visible = false

func _process(_delta):
	if not _is_dragging or _active_seam_index < 0:
		return
	if _active_seam_index >= _seams.size():
		return
	if _seams[_active_seam_index]["complete"]:
		return

	var mouse = get_viewport().get_mouse_position()
	var local_mouse = seam_container.to_local(mouse)
	var path = _seam_paths[_active_seam_index]
	var closest = _closest_on_path(local_mouse, path)

	_iron_cursor.position = closest

	var glow = _bead_glow_lines[_active_seam_index]
	var primary = _bead_primary_lines[_active_seam_index]

	# Append if far enough from last point
	var should_add = true
	if glow.get_point_count() > 0:
		var last = glow.get_point_position(glow.get_point_count() - 1)
		if last.distance_to(closest) < 3.0:
			should_add = false

	if should_add:
		glow.add_point(closest)
		primary.add_point(closest)

	# Check if we reached the end
	var end_pt = path[path.size() - 1]
	if closest.distance_to(end_pt) < 15.0:
		_complete_seam(_active_seam_index)

func _closest_on_path(pos: Vector2, path: PackedVector2Array) -> Vector2:
	var best = path[0]
	var best_dist = pos.distance_to(best)
	for pt in path:
		var d = pos.distance_to(pt)
		if d < best_dist:
			best_dist = d
			best = pt
	return best

func _complete_seam(index: int):
	_seams[index]["complete"] = true
	_seams[index]["line"].default_color = Color(0.85, 0.85, 0.85, 1.0)
	_seams_complete += 1
	_is_dragging = false
	_iron_cursor.visible = false
	_active_seam_index = -1
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
	var commission = GameState.active_commission
	client_label.text = "For: %s" % commission.client_name
	client_label.add_theme_color_override("font_color", Color("#C0B8A8"))
	client_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(client_label)

	var payout_label = Label.new()
	payout_label.text = "Payout: +%dg" % commission.payout
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
	# Centre it after one frame so size is known
	await get_tree().process_frame
	modal.position = (get_viewport_rect().size - modal.size) / 2.0

func _on_deliver(modal: Control):
	var commission = GameState.active_commission
	GameState.wallet += commission.payout
	commission.is_complete = true
	GameState.active_commission = null
	GameState.current_cut_pieces = []
	modal.queue_free()
	get_tree().change_scene_to_file("res://scenes/CommissionBoard.tscn")
