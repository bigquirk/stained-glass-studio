extends Node2D
class_name CrackLine

signal crack_complete(line_index: int)

@export var line_index: int = 0
@export var start_point: Vector2 = Vector2.ZERO
@export var end_point: Vector2 = Vector2.ZERO

var _cracked: bool = false
var _crack_visual: Line2D
var _cut_line_visual: Line2D
var _area: Area2D

func _ready():
	_cut_line_visual = Line2D.new()
	_cut_line_visual.add_point(start_point)
	_cut_line_visual.add_point(end_point)
	_cut_line_visual.width = 2.0
	_cut_line_visual.default_color = Color(1, 1, 1, 0.8)
	add_child(_cut_line_visual)

	_area = Area2D.new()
	_area.collision_layer = 1
	_area.collision_mask = 1
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	var line_vec = end_point - start_point
	var length = line_vec.length()
	rect.size = Vector2(length, 12)
	shape.shape = rect
	shape.position = (start_point + end_point) / 2.0
	shape.rotation = line_vec.angle()
	_area.add_child(shape)
	add_child(_area)
	_area.input_event.connect(_on_area_input)
	_area.input_pickable = true

func _on_area_input(_viewport, event, _shape_idx):
	if _cracked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_start_crack()

func _start_crack():
	_cracked = true
	_cut_line_visual.hide()

	_crack_visual = Line2D.new()
	_crack_visual.width = 3.0
	_crack_visual.default_color = Color.WHITE
	_crack_visual.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_crack_visual.end_cap_mode = Line2D.LINE_CAP_ROUND
	_crack_visual.add_point(start_point)
	get_parent().add_child(_crack_visual)

	var tween = create_tween()
	var steps = 20
	var duration = 0.5
	for i in range(1, steps + 1):
		var t = float(i) / float(steps)
		var pt = start_point.lerp(end_point, t)
		tween.tween_callback(_add_crack_point.bind(pt, t))
		tween.tween_interval(duration / steps)
	tween.tween_callback(_finish_crack)

func _add_crack_point(pt: Vector2, t: float):
	_crack_visual.add_point(pt)
	_crack_visual.width = lerp(3.0, 1.0, t)
	_crack_visual.default_color = Color(1.0, lerp(1.0, 0.8, t), lerp(1.0, 0.8, t), 1.0)

func _finish_crack():
	emit_signal("crack_complete", line_index)
	_do_screen_shake()

func _do_screen_shake():
	var viewport = get_viewport()
	if not viewport:
		return
	var tween = create_tween()
	var shake_count = 6
	for i in range(shake_count):
		var offset = Vector2(randf_range(-2, 2), randf_range(-2, 2))
		tween.tween_property(viewport, "canvas_transform", Transform2D(0, offset), 0.025)
	tween.tween_property(viewport, "canvas_transform", Transform2D.IDENTITY, 0.025)
