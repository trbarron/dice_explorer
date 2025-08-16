extends Control

var dice_manager: Node3D
var roll_button: Button
var auto_roll_button: Button
var results_label: Label

var auto_roll_enabled: bool = false
var auto_roll_timer: Timer

func _ready():
	# Find nodes more safely
	dice_manager = get_node("../../DiceManager") if get_node_or_null("../../DiceManager") else null
	roll_button = get_node("VBoxContainer/RollButton") if get_node_or_null("VBoxContainer/RollButton") else null
	auto_roll_button = get_node("VBoxContainer/AutoRollButton") if get_node_or_null("VBoxContainer/AutoRollButton") else null
	results_label = get_node("VBoxContainer/ResultsLabel") if get_node_or_null("VBoxContainer/ResultsLabel") else null
	
	# Create and setup auto-roll timer
	auto_roll_timer = Timer.new()
	auto_roll_timer.wait_time = 0.2  # Auto-roll every 0.2 seconds
	auto_roll_timer.timeout.connect(_on_auto_roll_timeout)
	add_child(auto_roll_timer)
	
	# Connect signals only if nodes exist
	roll_button.pressed.connect(_on_roll_pressed)
	if auto_roll_button:
		auto_roll_button.pressed.connect(_on_auto_roll_pressed)
		auto_roll_button.text = "Start Auto-Roll"
	
	# Connect dice manager signals
	dice_manager.all_dice_settled.connect(_on_dice_settled)
	dice_manager.dice_timeout_reroll.connect(_on_dice_timeout_reroll)

func _on_roll_pressed():
	if auto_roll_enabled:
		return  # Don't allow manual rolls during auto-roll
	
	_perform_roll()

func _on_auto_roll_pressed():
	if not auto_roll_button:
		return
		
	auto_roll_enabled = !auto_roll_enabled
	
	if auto_roll_enabled:
		auto_roll_button.text = "Stop Auto-Roll"
		roll_button.disabled = true  # Disable manual roll during auto-roll
		_perform_roll()  # Start with immediate roll
	else:
		auto_roll_button.text = "Start Auto-Roll"
		auto_roll_timer.stop()
		roll_button.disabled = false  # Re-enable manual roll

func _perform_roll():
	if not dice_manager:
		return
	
	# Stop the auto-roll timer when starting a roll - it will restart when dice settle
	auto_roll_timer.stop()
	results_label.text = "Rolling..."
	dice_manager.roll_all_dice()

func _on_dice_settled(results: Array[int]):
	results_label.text = "Results: %s" % [str(results)]
	
	if auto_roll_enabled:
		# Start timer for next auto-roll only after dice have settled
		auto_roll_timer.start()
	else:
		# Re-enable roll button for manual rolling
		roll_button.disabled = false

func _on_dice_timeout_reroll():
	# Called when dice timeout and are automatically rerolled
	results_label.text = "Dice stuck - rerolling..."
	print("UI: Received timeout reroll signal")

func _on_auto_roll_timeout():
	if auto_roll_enabled:
		_perform_roll()
