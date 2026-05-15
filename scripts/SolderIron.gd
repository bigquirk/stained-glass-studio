extends Node2D
class_name SolderIron

signal seam_complete(seam_index: int)

var _current_seam_path: Curve2D = null
var _current_seam_index: int = -1
var _is_soldering: bool = false
var _bead_primary: Line2D = null
var _bead_glow: Line2D = null
var _bead_layer: Node2D = null
var _path_points: PackedVector2Array
var _progress: float = 0.0
var _last_mouse_pos: Vector2 = Vector2.ZERO

func setup(bead_layer: Node2D):
	_bead_layer = bead_layer

func start_seam(seam_index: int, path_points: PackedVector2Array):
	_current_seam_index = seam_index
	_path_points = path_points
	_is_soldering = true
	_progress = 0.0

	_bead_glow = Line2D.new()
	_bead_glow.width = 8.0
	_bead_glow.default_color = Color(1, 1, 1, 0.25)
	_bead_glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_bead_glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	_bead_layer.add_child(_bead_glow)

	_bead_primary = Line2D.new()
	_bead_primary.width = 4.0
	_bead_primary.default_color = Color("#D4D4D4")
	_bead_primary.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_bead_primary.end_cap_mode = Line2D.LINE_CAP_ROUND
	_bead_layer.add_child(_bead_primary)

func _process(_delta):
	if not _is_soldering or _path_points.size() < 2:
		return

	var mouse = get_viewport().get_mouse_position()
	var closest_pt = _get_closest_point_on_path(mouse)
	global_position = closest_pt

	# Only append point if mouse moved
	if mouse.distance_to(_last_mouse_pos) > 2.0:
		_bead_glow.add_point(closest_pt)
		_bead_primary.add_point(closest_pt)
		_last_mouse_pos = mouse

		# Check if near end
		var end_pt = _path_points[_path_points.size() - 1]
		if closest_pt.distance_to(end_pt) < 15.0:
			_finish_seam()

func _get_closest_point_on_path(mouse_pos: Vector2) -> Vector2:
	var best_pt = _path_points[0]
	var best_dist = mouse_pos.distance_to(best_pt)
	for pt in _path_points:
		var d = mouse_pos.distance_to(pt)
		if d < best_dist:
			best_dist = d
			best_pt = pt
	return best_pt

func _finish_seam():
	_is_soldering = false
	emit_signal("seam_complete", _current_seam_index)

func stop_seam():
	_is_soldering = false
