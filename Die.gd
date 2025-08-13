# Die.gd - Script for individual die
extends RigidBody3D

@export var die_faces: Array[int] = [1, 2, 3, 4, 5, 6]
@export var settle_threshold: float = 0.1
@export var settle_time: float = 0.75

signal die_settled(value: int)

var is_settled: bool = false
var settle_timer: float = 0.0
var last_velocity: Vector3
var face_normals: Array[Vector3] = [
	Vector3.UP,      # Face 1 (top)
	Vector3.DOWN,    # Face 6 (bottom)  
	Vector3.FORWARD, # Face 2
	Vector3.BACK,    # Face 5
	Vector3.RIGHT,   # Face 3
	Vector3.LEFT     # Face 4
]

func _ready():
	# Set up physics properties for realistic dice behavior
	mass = 0.008  # 8 grams in kg
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.8
	physics_material_override.bounce = 0.2
	
	# Set damping for more realistic settling
	linear_damp = 0.1
	angular_damp = 0.2
	
	# Connect to physics process
	set_physics_process(true)

func _physics_process(delta):
	if not is_settled:
		check_if_settled(delta)

func check_if_settled(delta: float):
	var current_velocity = linear_velocity
	var current_angular_velocity = angular_velocity
	
	# Check if the die is moving slowly enough to be considered settled
	if (current_velocity.length() < settle_threshold and 
		current_angular_velocity.length() < settle_threshold):
		settle_timer += delta
		
		if settle_timer >= settle_time:
			settle_die()
	else:
		settle_timer = 0.0

func settle_die():
	if is_settled:
		return
		
	is_settled = true
	var face_value = get_top_face()
	die_settled.emit(face_value)

func get_top_face() -> int:
	# Get the global up direction
	var up_direction = Vector3.UP
	var best_dot = -2.0
	var top_face_index = 0
	
	# Find which face normal is most aligned with the up direction
	for i in range(face_normals.size()):
		var world_normal = global_transform.basis * face_normals[i]
		var dot_product = world_normal.dot(up_direction)
		
		if dot_product > best_dot:
			best_dot = dot_product
			top_face_index = i
	
	# Return the corresponding face value
	return die_faces[top_face_index]

func roll_die(throw_force: Vector3, throw_torque: Vector3):
	# Reset settlement state
	is_settled = false
	settle_timer = 0.0
	
	# Apply forces to simulate throwing
	apply_central_impulse(throw_force)
	apply_torque_impulse(throw_torque)
