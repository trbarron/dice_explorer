extends Node3D

@export var die_scene: PackedScene
@export var number_of_dice: int = 3
@export var throw_force_range: Vector2 = Vector2(0, 0.001)
@export var throw_height: float = 0.1
@export var spread_radius: float = 1.0

signal all_dice_settled(results: Array[int])

var dice_array: Array[RigidBody3D] = []
var settled_dice: int = 0
var dice_results: Array[int] = []

func _ready():
	create_dice()

func create_dice():
	# Clear existing dice
	for die in dice_array:
		if is_instance_valid(die):
			die.queue_free()
	dice_array.clear()
	
	# Wait a frame for cleanup
	await get_tree().process_frame
	
	# Create new dice
	for i in range(number_of_dice):
		var die_instance = die_scene.instantiate() as RigidBody3D
		add_child(die_instance)
		
		# Position dice slightly apart
		var angle = (2.0 * PI * i) / number_of_dice
		var offset = Vector3(
			cos(angle) * spread_radius,
			throw_height,
			sin(angle) * spread_radius
		)
		die_instance.global_position = global_position + offset
		
		# Connect to settlement signal
		die_instance.die_settled.connect(_on_die_settled)
		dice_array.append(die_instance)
	
	print("Created ", dice_array.size(), " dice")

func roll_all_dice():
	settled_dice = 0
	dice_results.clear()
	
	# Initialize results array with correct size
	for i in range(number_of_dice):
		dice_results.append(0)
	
	print("Rolling ", number_of_dice, " dice...")
	print("Results array initialized with size: ", dice_results.size())
	
	for i in range(dice_array.size()):
		var die = dice_array[i]
		
		# Generate random throw parameters
		var force_magnitude = randf_range(throw_force_range.x, throw_force_range.y)
		var throw_direction = Vector3(
			randf_range(-0.005, 0.005),
			randf_range(0.001, 0.0018),  # Always throw somewhat upward
			randf_range(-0.005, 0.005)
		).normalized()
		
		var throw_force = throw_direction * force_magnitude
		var throw_torque = Vector3(
			randf_range(0, 0.15),
			randf_range(0, 0.15),
			randf_range(0, 0.15)
		)
		
		die.roll_die(throw_force, throw_torque)

func _on_die_settled(value: int):
	# Find which die settled and record its value
	for i in range(dice_array.size()):
		var die = dice_array[i]
		if die.is_settled and i < dice_results.size() and dice_results[i] == 0:  # Not yet recorded
			dice_results[i] = value
			break
	
	settled_dice += 1
	
	# Check if all dice have settled
	if settled_dice >= number_of_dice:
		all_dice_settled.emit(dice_results)
		print("All dice settled. Results: ", dice_results)
