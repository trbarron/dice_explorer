extends RigidBody3D

@export var die_mesh: Mesh  # Assign extracted mesh (.tres file) - REQUIRED
@export var face_values: Array[int] = []  # Values for each face (auto-detected if empty)
@export var settle_threshold: float = 0.1
@export var settle_time: float = 1.0
@export var auto_detect_faces: bool = true
@export var face_detection_method: FaceDetectionMethod = FaceDetectionMethod.RAYCAST_DOWN
@export var die_mass: float = 0.008  # 8 grams default

# Material/Texture options (much cleaner now)
@export_group("Appearance")
@export var die_texture: Texture2D  # Main texture for the die
@export var die_material: Material  # Pre-made material (takes priority over texture)
@export var texture_scale: Vector2 = Vector2(1.0, 1.0)  # UV scaling
@export var texture_offset: Vector2 = Vector2(0.0, 0.0)  # UV offset

enum FaceDetectionMethod {
	RAYCAST_DOWN,      # Cast rays down to find bottom face
	NORMAL_ANALYSIS,   # Analyze face normals (requires face data)
	PHYSICS_CONTACTS   # Use physics contact points (most accurate)
}

signal die_settled(value: int)

var is_settled: bool = false
var settle_timer: float = 0.0
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var face_data: Array[Dictionary] = []  # Stores face centers and normals
var last_contact_point: Vector3

func _ready():
	setup_die_components()
	if auto_detect_faces:
		analyze_mesh_faces()
	setup_physics_properties()
	set_physics_process(true)

func setup_die_components():
	# Find or create MeshInstance3D
	mesh_instance = get_node("MeshInstance3D") if get_node_or_null("MeshInstance3D") else null
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "MeshInstance3D"
		add_child(mesh_instance)
	
	# Find or create CollisionShape3D
	collision_shape = get_node("CollisionShape3D") if get_node_or_null("CollisionShape3D") else null
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
	
	# Apply the mesh if provided
	if die_mesh:
		apply_mesh()
	else:
		print("Error: No die_mesh assigned! Please assign a mesh resource.")

func apply_mesh():
	if not die_mesh:
		print("Error: No mesh assigned")
		return
	
	# Set the visual mesh
	mesh_instance.mesh = die_mesh
	
	# Apply materials/textures AFTER setting mesh
	apply_material_and_texture()
	
	# Create collision shape from mesh
	var shape = die_mesh.create_convex_shape()  # Use convex first for dice
	if not shape:
		# Fallback to trimesh if convex fails
		shape = die_mesh.create_trimesh_shape()
	
	if shape:
		collision_shape.shape = shape
		print("Created collision shape: ", shape.get_class())
	else:
		print("Error: Could not create collision shape from mesh")

func analyze_mesh_faces():
	if not die_mesh:
		print("Warning: No mesh available for face analysis")
		return
	
	face_data.clear()
	
	# Get mesh surface data
	if die_mesh.get_surface_count() == 0:
		print("Warning: Mesh has no surfaces")
		return
	
	var arrays = die_mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		print("Warning: Mesh has no vertex data")
		return
	
	var vertices = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	
	if not vertices or vertices.size() == 0:
		print("Warning: No vertices found in mesh")
		return
	
	# Group vertices into faces and calculate face properties
	var faces = group_vertices_into_faces(vertices, indices)
	
	for i in range(faces.size()):
		var face = faces[i]
		var face_info = {
			"center": calculate_face_center(face),
			"normal": calculate_face_normal(face),
			"vertices": face,
			"value": i + 1  # Default numbering
		}
		face_data.append(face_info)
	
	# Auto-generate face values if not provided
	if face_values.is_empty():
		for i in range(face_data.size()):
			face_values.append(i + 1)
	
	print("Detected ", face_data.size(), " faces on die")


func group_vertices_into_faces(vertices: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var faces = []
	var face_tolerance = 0.01  # How close vertices need to be to be considered on same face
	
	# If we have indices, use them to group triangles into faces
	if indices and indices.size() > 0:
		# Group triangles that are coplanar
		var triangle_faces = []
		for i in range(0, indices.size(), 3):
			if i + 2 < indices.size():
				var tri = [
					vertices[indices[i]],
					vertices[indices[i + 1]], 
					vertices[indices[i + 2]]
				]
				triangle_faces.append(tri)
		
		# Merge coplanar triangles into faces
		faces = merge_coplanar_triangles(triangle_faces, face_tolerance)
	else:
		# Fallback: treat every 3 vertices as a triangle
		for i in range(0, vertices.size(), 3):
			if i + 2 < vertices.size():
				faces.append([vertices[i], vertices[i + 1], vertices[i + 2]])
	
	return faces

func merge_coplanar_triangles(triangles: Array, tolerance: float) -> Array:
	var merged_faces = []
	var used_triangles = []
	
	for i in range(triangles.size()):
		if i in used_triangles:
			continue
		
		var base_triangle = triangles[i]
		var base_normal = calculate_face_normal(base_triangle)
		var base_center = calculate_face_center(base_triangle)
		
		var current_face = base_triangle.duplicate()
		used_triangles.append(i)
		
		# Find other triangles that are coplanar
		for j in range(i + 1, triangles.size()):
			if j in used_triangles:
				continue
			
			var test_triangle = triangles[j]
			var test_normal = calculate_face_normal(test_triangle)
			var test_center = calculate_face_center(test_triangle)
			
			# Check if normals are similar and centers are on same plane
			if (base_normal.dot(test_normal) > 0.95 and 
				abs(base_normal.dot(test_center - base_center)) < tolerance):
				# Merge vertices (remove duplicates)
				for vertex in test_triangle:
					var is_duplicate = false
					for existing_vertex in current_face:
						if vertex.distance_to(existing_vertex) < tolerance:
							is_duplicate = true
							break
					if not is_duplicate:
						current_face.append(vertex)
				used_triangles.append(j)
		
		merged_faces.append(current_face)
	
	return merged_faces

func calculate_face_center(face_vertices: Array) -> Vector3:
	if face_vertices.is_empty():
		return Vector3.ZERO
	
	var center = Vector3.ZERO
	for vertex in face_vertices:
		center += vertex
	return center / face_vertices.size()

func calculate_face_normal(face_vertices: Array) -> Vector3:
	if face_vertices.size() < 3:
		return Vector3.UP
	
	var v1 = face_vertices[1] - face_vertices[0]
	var v2 = face_vertices[2] - face_vertices[0]
	return v1.cross(v2).normalized()

func setup_physics_properties():
	mass = die_mass
	
	var physics_mat = PhysicsMaterial.new()
	physics_mat.friction = 0.8
	physics_mat.bounce = 0.2
	physics_material_override = physics_mat
	
	linear_damp = 0.1
	angular_damp = 0.2
	
	# Set collision layers for dice-to-dice collisions
	collision_layer = 1  # Layer 1 for dice
	collision_mask = 1   # Collide with other dice (layer 1) and environment
	
	# Enable contact monitoring for physics-based face detection
	if face_detection_method == FaceDetectionMethod.PHYSICS_CONTACTS:
		contact_monitor = true
		max_contacts_reported = 10
	
	print("Die physics setup complete - Mass: ", mass, " Layer: ", collision_layer)

func _physics_process(delta):
	if not is_settled:
		check_if_settled(delta)

func check_if_settled(delta: float):
	var current_velocity = linear_velocity
	var current_angular_velocity = angular_velocity
	
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
	var face_value = get_face_value()
	die_settled.emit(face_value)
	print("Die settled with value: ", face_value)

func get_face_value() -> int:
	match face_detection_method:
		FaceDetectionMethod.RAYCAST_DOWN:
			return get_face_value_raycast()
		FaceDetectionMethod.NORMAL_ANALYSIS:
			return get_face_value_normal_analysis()
		FaceDetectionMethod.PHYSICS_CONTACTS:
			return get_face_value_physics_contacts()
		_:
			return get_face_value_raycast()

func get_face_value_raycast() -> int:
	# Cast a ray downward to find which face is touching the ground
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.new()
	
	# Ray from die center downward
	query.from = global_position
	query.to = global_position + Vector3.DOWN * 10
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	if result:
		# Find the closest face to the contact point
		var contact_point = to_local(result.position)
		return get_closest_face_to_point(contact_point)
	
	# Fallback: find the face pointing most downward
	return get_most_downward_face()

func get_face_value_normal_analysis() -> int:
	if face_data.is_empty():
		return 1
	
	# Find the face whose normal points most downward
	var down_direction = Vector3.DOWN
	var best_dot = 2.0  # Start with impossible value
	var best_face_index = 0
	
	for i in range(face_data.size()):
		var world_normal = global_transform.basis * face_data[i].normal
		var dot_product = world_normal.dot(down_direction)
		
		if dot_product < best_dot:  # Most downward (most negative dot product)
			best_dot = dot_product
			best_face_index = i
	
	return get_face_value_for_index(best_face_index)

func get_face_value_physics_contacts() -> int:
	# This would use the last contact point recorded during physics simulation
	if last_contact_point != Vector3.ZERO:
		return get_closest_face_to_point(last_contact_point)
	else:
		return get_face_value_raycast()  # Fallback

func get_closest_face_to_point(point: Vector3) -> int:
	if face_data.is_empty():
		return 1
	
	var closest_distance = INF
	var closest_face_index = 0
	
	for i in range(face_data.size()):
		var distance = face_data[i].center.distance_to(point)
		if distance < closest_distance:
			closest_distance = distance
			closest_face_index = i
	
	return get_face_value_for_index(closest_face_index)

func get_most_downward_face() -> int:
	if face_data.is_empty():
		return 1
	
	var lowest_y = INF
	var lowest_face_index = 0
	
	for i in range(face_data.size()):
		var world_center = global_transform * face_data[i].center
		if world_center.y < lowest_y:
			lowest_y = world_center.y
			lowest_face_index = i
	
	return get_face_value_for_index(lowest_face_index)

func get_face_value_for_index(face_index: int) -> int:
	if face_index >= 0 and face_index < face_values.size():
		return face_values[face_index]
	else:
		return face_index + 1  # Fallback numbering

func roll_die(throw_force: Vector3, throw_torque: Vector3):
	is_settled = false
	settle_timer = 0.0
	last_contact_point = Vector3.ZERO
	
	apply_central_impulse(throw_force)
	apply_torque_impulse(throw_torque)

# Called when the die contacts another body (if contact monitoring is enabled)
func _on_body_entered(body):
	pass

# Optional: Override this to set custom face values
func set_custom_face_values(values: Array[int]):
	face_values = values

# Optional: Call this to re-analyze the mesh if it changes
func refresh_face_analysis():
	if auto_detect_faces:
		analyze_mesh_faces()

func apply_material_and_texture():
	if not mesh_instance or not mesh_instance.mesh:
		print("Error: No MeshInstance3D or mesh found for applying material")
		return
	
	var material_to_apply: Material = null
	
	# Priority: use die_material if provided, otherwise create from texture
	if die_material:
		material_to_apply = die_material
		print("Using provided die_material")
	elif die_texture:
		material_to_apply = create_material_from_texture()
		print("Created material from die_texture")
	
	if material_to_apply:
		# Apply material to all surfaces of the mesh
		var surface_count = mesh_instance.mesh.get_surface_count()
		print("Applying material to ", surface_count, " surfaces")
		
		for i in range(surface_count):
			mesh_instance.set_surface_override_material(i, material_to_apply)
			print("Set material for surface ", i)
		
		print("Material application complete")
	else:
		print("No material or texture provided for die")

func create_material_from_texture() -> StandardMaterial3D:
	if not die_texture:
		return null
	
	var material = StandardMaterial3D.new()
	material.resource_name = "DieM_" + str(get_instance_id()) # Make it unique
	
	# Basic texture setup
	material.albedo_texture = die_texture
	material.uv1_scale = Vector3(texture_scale.x, texture_scale.y, 1.0)
	material.uv1_offset = Vector3(texture_offset.x, texture_offset.y, 0.0)
	
	# Good defaults for dice
	material.roughness = 0.01
	material.metallic = 0.3
	
	# Enable features that work well for dice
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.flags_unshaded = false  # Keep lighting
	
	return material
