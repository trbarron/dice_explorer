# Enhanced DiceManager.gd - Centered throws with reduced horizontal movement + Timeout System
extends Node3D

@export var die_scene: PackedScene
@export var number_of_dice: int = 12

@export_group("Throw Behavior")
@export var center_throws: bool = true  # Start throws from center
@export var horizontal_force_multiplier: float = 0.3  # Reduce horizontal components
@export var vertical_force_multiplier: float = 1.0  # Keep vertical force normal
@export var max_horizontal_spread: float = 0.002  # Maximum horizontal throw force
@export var throw_force_range: Vector2 = Vector2(0.02, 0.003)
@export var throw_height: float = 8

@export_group("Timeout System")
@export var settlement_timeout: float = 15.0  # Auto-reroll if dice don't settle

@export_group("Multi-Die Support")
@export var use_multi_die_mode: bool = false
@export var die_scenes: Array[PackedScene] = []
@export var die_type_counts: Array[int] = []

@export_group("Logging")
@export var save_results_to_file: bool = true
@export var log_file_path: String = "user://dice_results.txt"
@export var include_timestamp: bool = true
@export var max_log_entries: int = 10000

signal all_dice_settled(results: Array[int])
signal dice_timeout_reroll()

var dice_array: Array[RigidBody3D] = []
var settled_dice: int = 0
var dice_results: Array[int] = []
var timeout_timer: Timer

func _ready():
	# Create timeout timer
	timeout_timer = Timer.new()
	timeout_timer.wait_time = settlement_timeout
	timeout_timer.timeout.connect(_on_settlement_timeout)
	timeout_timer.one_shot = true
	add_child(timeout_timer)
	
	create_dice()

func create_dice():
	# Clear existing dice
	for die in dice_array:
		if is_instance_valid(die):
			die.queue_free()
	dice_array.clear()
	
	# Wait a frame for cleanup
	await get_tree().process_frame
	
	if use_multi_die_mode and not die_scenes.is_empty():
		create_multi_type_dice()
	else:
		create_single_type_dice()

func create_single_type_dice():
	if not die_scene:
		print("Error: No die scene assigned!")
		return
	
	for i in range(number_of_dice):
		var die_instance = die_scene.instantiate() as RigidBody3D
		if not die_instance:
			print("Error: Failed to instantiate die")
			continue
			
		add_child(die_instance)
		
		if center_throws:
			# Position all dice at the center for throwing
			die_instance.global_position = global_position + Vector3(0, throw_height, 0)
		else:
			# Original spread positioning
			var angle = (2.0 * PI * i) / number_of_dice
			var offset = Vector3(
				cos(angle),
				throw_height,
				sin(angle)
			)
			die_instance.global_position = global_position + offset
		
		# Connect to settlement signal
		if die_instance.has_signal("die_settled"):
			die_instance.die_settled.connect(_on_die_settled)
		else:
			print("Warning: Die doesn't have die_settled signal")
		
		dice_array.append(die_instance)
	
	print("Created ", dice_array.size(), " dice")

func create_multi_type_dice():
	if die_type_counts.is_empty():
		for i in range(die_scenes.size()):
			die_type_counts.append(1)
	
	var total_dice = 0
	for count in die_type_counts:
		total_dice += count
	
	var current_index = 0
	
	# Create dice of each type
	for type_index in range(die_scenes.size()):
		var scene = die_scenes[type_index]
		var count = die_type_counts[type_index] if type_index < die_type_counts.size() else 1
		
		if not scene:
			print("Warning: Die scene at index ", type_index, " is null")
			continue
		
		for i in range(count):
			var die_instance = scene.instantiate() as RigidBody3D
			if not die_instance:
				print("Error: Failed to instantiate die from scene at index ", type_index)
				continue
			
			add_child(die_instance)
			
			if center_throws:
				# Position all dice at the center for throwing
				die_instance.global_position = global_position + Vector3(0, throw_height, 0)
			else:
				# Original spread positioning
				var angle = (2.0 * PI * current_index) / total_dice
				var offset = Vector3(
					cos(angle),
					throw_height,
					sin(angle)
				)
				die_instance.global_position = global_position + offset
			
			# Connect to settlement signal
			if die_instance.has_signal("die_settled"):
				die_instance.die_settled.connect(_on_die_settled)
			else:
				print("Warning: Die instance doesn't have die_settled signal")
			
			dice_array.append(die_instance)
			current_index += 1
	
	print("Created ", dice_array.size(), " dice of ", die_scenes.size(), " different types")

func roll_all_dice():
	settled_dice = 0
	dice_results.clear()
	
	# Stop any existing timeout timer and start fresh
	timeout_timer.stop()
	timeout_timer.start()
	
	# Initialize results array with correct size
	var total_dice_count = dice_array.size()
	for i in range(total_dice_count):
		dice_results.append(0)
	
	print("Rolling ", total_dice_count, " dice with ", settlement_timeout, "s timeout...")
	print("Results array initialized with size: ", dice_results.size())
	
	for i in range(dice_array.size()):
		var die = dice_array[i]
		
		# Reset dice position to center if center_throws is enabled
		if center_throws:
			die.global_position = global_position + Vector3(0, throw_height, 0)
			# Reset velocities to ensure clean throw
			die.linear_velocity = Vector3.ZERO
			die.angular_velocity = Vector3.ZERO
		
		# Generate throw parameters with reduced horizontal components
		var force_magnitude = randf_range(throw_force_range.x, throw_force_range.y)
		
		# Generate horizontal components with reduced influence
		var horizontal_x = randf_range(-max_horizontal_spread, max_horizontal_spread) * horizontal_force_multiplier
		var horizontal_z = randf_range(-max_horizontal_spread, max_horizontal_spread) * horizontal_force_multiplier
		
		# Generate vertical component with normal influence
		var vertical_y = randf_range(0.001, 0.0018) * vertical_force_multiplier
		
		var throw_direction = Vector3(horizontal_x, vertical_y, horizontal_z).normalized()
		var throw_force = throw_direction * force_magnitude
		
		# Reduce torque horizontal components too for more controlled spins
		var throw_torque = Vector3(
			randf_range(0, 0.10) * horizontal_force_multiplier,
			randf_range(0, 0.10),  # Keep Y torque normal for interesting spins
			randf_range(0, 0.10) * horizontal_force_multiplier
		)
		
		# Call roll_die if it exists
		if die.has_method("roll_die"):
			die.roll_die(throw_force, throw_torque)
		else:
			print("Warning: Die doesn't have roll_die method")

func _on_die_settled(value: int):
	# Find which die settled and record its value
	for i in range(dice_array.size()):
		var die = dice_array[i]
		# Handle both old and new die types
		var die_is_settled = false
		if "is_settled" in die:
			die_is_settled = die.is_settled
		elif die.has_method("is_settled"):
			die_is_settled = die.is_settled()
		else:
			# Fallback: assume this die just settled
			die_is_settled = true
		
		if die_is_settled and i < dice_results.size() and dice_results[i] == 0:  # Not yet recorded
			dice_results[i] = value
			break
	
	settled_dice += 1
	
	# Check if all dice have settled
	var total_dice_count = dice_array.size()
	if settled_dice >= total_dice_count:
		timeout_timer.stop()  # Stop timeout timer since all dice settled
		all_dice_settled.emit(dice_results)
		print("All dice settled. Results: ", dice_results)
		
		# Save results to file
		if save_results_to_file:
			save_dice_results(dice_results)

func _on_settlement_timeout():
	print("Dice settlement timeout! Rerolling after ", settlement_timeout, " seconds...")
	dice_timeout_reroll.emit()  # Notify UI about the timeout
	roll_all_dice()  # Automatically reroll

func force_settle_all_dice():
	"""Force all dice to settle immediately (useful for debugging)"""
	timeout_timer.stop()
	
	# Reset all dice settlement state
	for die in dice_array:
		if "is_settled" in die:
			die.is_settled = false
	
	# Wait a frame then force settlement
	await get_tree().process_frame
	
	settled_dice = 0
	dice_results.clear()
	var total_dice_count = dice_array.size()
	for i in range(total_dice_count):
		dice_results.append(0)
	
	# Force each die to settle
	for i in range(dice_array.size()):
		var die = dice_array[i]
		if die.has_method("settle_die"):
			die.settle_die()
		if i < dice_results.size():
			if die.has_method("get_top_face"):
				dice_results[i] = die.get_top_face()
			else:
				dice_results[i] = randi_range(1, 6)  # Fallback random value
	
	settled_dice = total_dice_count
	all_dice_settled.emit(dice_results)
	print("Force settled all dice. Results: ", dice_results)

# Helper functions for easier configuration
func add_die_type(scene: PackedScene, count: int = 1):
	"""Add a new die type to the multi-die setup"""
	if not use_multi_die_mode:
		use_multi_die_mode = true
	
	die_scenes.append(scene)
	die_type_counts.append(count)

func set_single_die_mode(scene: PackedScene, count: int = 3):
	"""Configure for single die type (backward compatibility)"""
	use_multi_die_mode = false
	die_scene = scene
	number_of_dice = count

func set_multi_die_mode(scenes_and_counts: Array):
	"""Configure for multiple die types. Pass array of [scene, count] pairs"""
	use_multi_die_mode = true
	die_scenes.clear()
	die_type_counts.clear()
	
	for pair in scenes_and_counts:
		if pair.size() >= 2:
			die_scenes.append(pair[0])
			die_type_counts.append(pair[1])

# New helper functions for throw behavior
func set_throw_behavior(centered: bool, horizontal_mult: float = 0.3, vertical_mult: float = 1.0):
	"""Configure throw behavior easily"""
	center_throws = centered
	horizontal_force_multiplier = horizontal_mult
	vertical_force_multiplier = vertical_mult

func set_horizontal_spread_limits(max_spread: float):
	"""Set the maximum horizontal force that can be applied"""
	max_horizontal_spread = max_spread

func save_dice_results(results: Array[int]):
	# Read existing content first
	var existing_content = ""
	if FileAccess.file_exists(log_file_path):
		var read_file = FileAccess.open(log_file_path, FileAccess.READ)
		if read_file:
			existing_content = read_file.get_as_text()
			read_file.close()
	
	# Prepare new entry
	var timestamp = ""
	if include_timestamp:
		var time = Time.get_datetime_dict_from_system()
		timestamp = "%04d-%02d-%02d %02d:%02d:%02d - " % [
			time.year, time.month, time.day,
			time.hour, time.minute, time.second
		]
	
	var new_entry = timestamp + "Dice Results: " + str(results) + "\n"
	
	# Combine existing content with new entry
	var final_content = existing_content + new_entry
	
	# Handle max entries limit (optional)
	if max_log_entries > 0:
		var lines = final_content.split("\n")
		if lines.size() > max_log_entries:
			# Keep only the most recent entries
			var start_index = lines.size() - max_log_entries
			lines = lines.slice(start_index)
			final_content = "\n".join(lines)
	
	# Write to file
	var file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if not file:
		print("Error: Could not open file for writing: ", log_file_path)
		return
	
	file.store_string(final_content)
	file.close()
	
	print("Dice results saved to: ", log_file_path)

# Alternative: Simpler true append method
func save_dice_results_simple_append(results: Array[int]):
	var file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if FileAccess.file_exists(log_file_path):
		file = FileAccess.open(log_file_path, FileAccess.READ_WRITE)
		file.seek_end()
	
	if not file:
		print("Error: Could not open file for writing: ", log_file_path)
		return
	
	# Prepare new entry
	var timestamp = ""
	if include_timestamp:
		var time = Time.get_datetime_dict_from_system()
		timestamp = "%04d-%02d-%02d %02d:%02d:%02d - " % [
			time.year, time.month, time.day,
			time.hour, time.minute, time.second
		]
	
	var new_entry = timestamp + "Dice Results: " + str(results) + "\n"
	
	file.store_string(new_entry)
	file.close()
	
	print("Dice results appended to: ", log_file_path)
