extends Control

@onready var commission_list = $MainVBox/CommissionList
@onready var wallet_display = $MainVBox/WalletDisplay

const CARD_COLOURS = {
	"red": Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}

func _ready():
	wallet_display.text = "Wallet: %dg" % GameState.wallet
	_populate_commissions()
	$MainVBox/ShopButton.pressed.connect(_on_shop_pressed)

func _populate_commissions():
	for child in commission_list.get_children():
		child.queue_free()

	for i in range(GameState.commissions.size()):
		var commission = GameState.commissions[i]
		if commission.is_complete:
			continue
		var card = _make_card(commission, i)
		commission_list.add_child(card)

func _make_card(commission: Commission, index: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 100)

	var style = StyleBoxFlat.new()
	style.bg_color = Color("#3A3028")
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var name_label = Label.new()
	name_label.text = commission.client_name
	name_label.add_theme_color_override("font_color", Color("#F0E8D8"))
	name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_label)

	var pattern_label = Label.new()
	pattern_label.text = "Pattern: %s" % commission.pattern_id.replace("pattern_", "").capitalize()
	pattern_label.add_theme_color_override("font_color", Color("#C0B8A8"))
	vbox.add_child(pattern_label)

	var deadline_label = Label.new()
	deadline_label.text = "Deadline: %d days  |  Payout: %dg" % [commission.deadline_days, commission.payout]
	deadline_label.add_theme_color_override("font_color", Color("#C0B8A8"))
	vbox.add_child(deadline_label)

	# Colour swatches
	var swatch_hbox = HBoxContainer.new()
	for colour in commission.required_colours:
		var swatch = ColorRect.new()
		swatch.color = CARD_COLOURS.get(colour, Color.WHITE)
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch_hbox.add_child(swatch)
	vbox.add_child(swatch_hbox)

	var select_btn = Button.new()
	select_btn.text = "Accept"
	select_btn.custom_minimum_size = Vector2(80, 60)
	select_btn.pressed.connect(_on_commission_selected.bind(index))
	hbox.add_child(select_btn)

	return panel

func _on_commission_selected(index: int):
	GameState.active_commission = GameState.commissions[index]
	get_tree().change_scene_to_file("res://scenes/PatternLayout.tscn")

func _on_shop_pressed():
	get_tree().change_scene_to_file("res://scenes/Shop.tscn")
