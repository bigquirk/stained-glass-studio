extends Resource
class_name PatternPiece

@export var piece_id: String = ""
@export var polygon_points: PackedVector2Array
@export var assigned_colour: String = "clear"
@export var position_on_sheet: Vector2 = Vector2.ZERO
@export var rotation_degrees: float = 0.0
@export var is_cut: bool = false
