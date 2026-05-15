extends Node

var wallet: int = 50
var inventory: Array = []
var commissions: Array = []
var active_commission = null
var current_cut_pieces: Array = []

func _ready():
	_init_commissions()

func _init_commissions():
	var c1 = Commission.new()
	c1.client_name = "Mrs. Albrecht"
	c1.pattern_id = "pattern_diamond"
	c1.required_colours = ["red", "amber"]
	c1.deadline_days = 5
	c1.payout = 25

	var c2 = Commission.new()
	c2.client_name = "The Harbour Church"
	c2.pattern_id = "pattern_sun"
	c2.required_colours = ["amber", "clear"]
	c2.deadline_days = 7
	c2.payout = 40

	var c3 = Commission.new()
	c3.client_name = "Theo (your neighbour)"
	c3.pattern_id = "pattern_arch"
	c3.required_colours = ["clear", "green"]
	c3.deadline_days = 10
	c3.payout = 60

	commissions = [c1, c2, c3]
