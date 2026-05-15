extends Control

const COLOURS = ["red", "amber", "green", "clear"]
const COLOUR_VALUES = {
	"red": Color("#D4534A"),
	"amber": Color("#E8A838"),
	"green": Color("#4A9E6B"),
	"clear": Color("#C8E8F0")
}
const PRICE = 10

@onready var wallet_display = $VBox/WalletDisplay
@onready var sheet_grid = $VBox/SheetGrid

func _ready():
	_update_wallet()
	_build_shop()
	$VBox/BackButton.pressed.connect(_on_back_pressed)

func _update_wallet():
	wallet_display.text = "Wallet: %dg" % GameState.wallet

func _build_shop():
	for colour in COLOURS:
		var panel = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color("#3A3028")
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		panel.add_theme_stylebox_override("panel", style)
		panel.custom_minimum_size = Vector2(120, 140)

		var vbox = VBoxContainer.new()
		panel.add_child(vbox)

		var swatch = ColorRect.new()
		swatch.color = COLOUR_VALUES[colour]
		swatch.custom_minimum_size = Vector2(100, 60)
		vbox.add_child(swatch)

		var label = Label.new()
		label.text = colour.capitalize()
		label.add_theme_color_override("font_color", Color("#F0E8D8"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(label)

		var price_label = Label.new()
		price_label.text = "%dg" % PRICE
		price_label.add_theme_color_override("font_color", Color("#C0B8A8"))
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(price_label)

		var btn = Button.new()
		btn.text = "Buy"
		btn.disabled = GameState.wallet < PRICE
		btn.pressed.connect(_on_buy.bind(colour, btn))
		vbox.add_child(btn)

		sheet_grid.add_child(panel)

func _on_buy(colour: String, _btn: Button):
	if GameState.wallet < PRICE:
		return
	GameState.wallet -= PRICE
	var sheet = GlassSheet.new()
	sheet.colour = colour
	GameState.inventory.append(sheet)
	_update_wallet()
	# Update all buy buttons
	for child in sheet_grid.get_children():
		var vbox = child.get_child(0)
		if vbox and vbox.get_child_count() >= 4:
			var buy_btn = vbox.get_child(3)
			if buy_btn is Button:
				buy_btn.disabled = GameState.wallet < PRICE

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/CommissionBoard.tscn")
