extends Camera3D

@export var dice_manager_path: NodePath = "../DiceManager"
@export var follow_speed: float = 2.0
@export var rotation_speed: float = 1
@export var height_offset: float = 5.0
@export var distance_offset: float = 5.0
@export var look_ahead_factor: float = 0.3
@export var min_distance: float = 4.0
@export var max_distance: float = 8.0

var dice_manager: Node3D
var target_position: Vector3
var target_rotation: Vector3
var dice_center: Vector3
var dice_bounds_size: float

func _ready():
	dice_manager = get_node(dice_manager_path) if get_node_or_null(dice_manager_path) else null
	if not dice_manager:
		print("Camera: DiceManager not found at path: ", dice_manager_path)
		return
	
	# Connect to dice manager signals if available
	if dice_manager.has_signal("all_dice_settled"):
		dice_manager.all_dice_settled.connect(_on_dice_settled)

func _process(delta):
	if not dice_manager:
		return
	
	update_dice_tracking()
	smooth_camera_movement(delta)

func update_dice_tracking():
	if not dice_manager.has_method("get_children"):
		return
	
	var dice_positions: Array[Vector3] = []
	var dice_velocities: Array[Vector3] = []
	var total_velocity := Vector3.ZERO
	var moving_dice := 0
	
	# Collect dice positions and velocities
	for child in dice_manager.get_children():
		if child is RigidBody3D:
			dice_positions.append(child.global_position)
			var velocity = child.linear_velocity
			dice_velocities.append(velocity)
			total_velocity += velocity
			if velocity.length() > 0.1:
				moving_dice += 1
	
	if dice_positions.is_empty():
		return
	
	# Calculate center of dice
	dice_center = Vector3.ZERO
	for pos in dice_positions:
		dice_center += pos
	dice_center /= dice_positions.size()
	
	# Calculate bounds of dice area
	dice_bounds_size = 0.0
	for pos in dice_positions:
		var distance = dice_center.distance_to(pos)
		dice_bounds_size = max(dice_bounds_size, distance)
	
	# Add some padding to bounds
	dice_bounds_size = max(dice_bounds_size + 2.0, min_distance)
	dice_bounds_size = min(dice_bounds_size, max_distance)
	
	# Predict where dice will be (look ahead for moving dice)
	var predicted_center = dice_center
	if moving_dice > 0:
		var avg_velocity = total_velocity / moving_dice
		predicted_center += avg_velocity * look_ahead_factor
	
	# Calculate target camera position
	var camera_distance = dice_bounds_size + distance_offset
	var camera_angle = -45.0  # Look down at 45 degrees
	
	target_position = predicted_center + Vector3(
		camera_distance * cos(deg_to_rad(camera_angle)),
		height_offset + dice_bounds_size * 0.5,
		camera_distance * sin(deg_to_rad(camera_angle))
	)
	
	# Calculate target rotation to look at dice center
	var look_target = predicted_center + Vector3(0, 0.5, 0)  # Look slightly above dice
	target_rotation = global_position.direction_to(look_target)

func smooth_camera_movement(delta):
	# Smooth position movement
	global_position = global_position.lerp(target_position, follow_speed * delta)
	
	# Smooth rotation to look at dice
	var look_target = dice_center + Vector3(0, 0.5, 0)
	var current_transform = global_transform
	var target_transform = current_transform.looking_at(look_target, Vector3.UP)
	global_transform = current_transform.interpolate_with(target_transform, rotation_speed * delta)

func _on_dice_settled(results: Array):
	# Optional: Zoom in slightly when dice have settled
	distance_offset = max(distance_offset - 1.0, 2.0)
	
	# Create a slight delay then zoom back out for next roll
	await get_tree().create_timer(2.0).timeout
	distance_offset = 5.0

# Optional: Call this to focus on dice immediately (useful for debugging)
func focus_on_dice():
	if not dice_manager:
		return
		
	update_dice_tracking()
	global_position = target_position
	look_at(dice_center + Vector3(0, 0.5, 0), Vector3.UP)

# Optional: Call this to set a specific camera angle
func set_camera_angle(angle_degrees: float, distance: float = -1):
	if distance > 0:
		distance_offset = distance
	
	var camera_distance = dice_bounds_size + distance_offset
	target_position = dice_center + Vector3(
		camera_distance * cos(deg_to_rad(angle_degrees)),
		height_offset,
		camera_distance * sin(deg_to_rad(angle_degrees))
	)
