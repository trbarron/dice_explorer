extends Control

var dice_manager: Node3D
var roll_button: Button
var results_label: Label

func _ready():
	# Find nodes more safely
	dice_manager = get_node("../../DiceManager") if get_node_or_null("../../DiceManager") else null
	roll_button = get_node("VBoxContainer/RollButton") if get_node_or_null("VBoxContainer/RollButton") else null
	results_label = get_node("VBoxContainer/ResultsLabel") if get_node_or_null("VBoxContainer/ResultsLabel") else null
	
	# Check if all nodes were found
	if not dice_manager:
		print("ERROR: DiceManager not found! Check node path.")
		return
	if not roll_button:
		print("ERROR: RollButton not found! Check UI structure.")
		return
	if not results_label:
		print("ERROR: ResultsLabel not found! Check UI structure.")
		return
	
	# Connect signals only if nodes exist
	roll_button.pressed.connect(_on_roll_pressed)
	dice_manager.all_dice_settled.connect(_on_dice_settled)

func _on_roll_pressed():
	roll_button.disabled = true
	results_label.text = "Rolling..."
	dice_manager.roll_all_dice()

func _on_dice_settled(results: Array[int]):
	results_label.text = "Results: %s" % [str(results)]
	roll_button.disabled = false
