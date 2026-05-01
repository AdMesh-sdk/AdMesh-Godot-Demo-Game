extends Node3D

## Script to generate trimesh collision from the city mesh.
## Attach this to the Sketchfab_Scene node in test_scene.tscn

@export var auto_generate_on_ready: bool = true
@export var wait_frames: int = 2
@export var use_convex_collision: bool = false  ## Set to true for convex decomposition, false for trimesh

func _ready() -> void:
	if auto_generate_on_ready:
		# Wait for the scene to fully load all children
		# This is necessary because the GLB is loaded as a PackedScene
		for i in range(wait_frames):
			await get_tree().process_frame
		generate_collision()

## Generate collision from all MeshInstance3D children
func generate_collision() -> void:
	# Remove existing collision nodes if any
	_remove_existing_collision()
	
	# Find all MeshInstance3D nodes in this scene
	var mesh_instances = _find_all_mesh_instances(self)
	
	if mesh_instances.size() == 0:
		push_warning("CityCollision: No MeshInstance3D nodes found in scene")
		return
	
	print("CityCollision: Found ", mesh_instances.size(), " mesh instance(s)")
	
	# Create a single StaticBody3D to hold all collision shapes
	var static_body = StaticBody3D.new()
	static_body.name = "CityTrimeshCollision"
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	add_child(static_body)
	
	# Create collision shapes for each mesh
	var collision_count = 0
	for mesh_instance in mesh_instances:
		var mesh = mesh_instance.mesh
		if mesh == null:
			continue
		
		# Skip empty meshes
		if mesh.get_surface_count() == 0:
			continue
		
		# Create collision shape based on settings
		var collision_shape = _create_collision_shape(mesh_instance, use_convex_collision)
		if collision_shape:
			static_body.add_child(collision_shape)
			collision_count += 1
			print("CityCollision: Created collision for mesh: ", mesh_instance.name)
	
	print("CityCollision: Generated collision for ", collision_count, " mesh(es)")

## Create collision shape for a mesh instance
func _create_collision_shape(mesh_instance: MeshInstance3D, use_convex: bool) -> CollisionShape3D:
	var mesh = mesh_instance.mesh
	if mesh == null:
		return null
	
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape_" + mesh_instance.name
	
	if use_convex:
		# Use convex decomposition for better performance but less accuracy
		var convex_shape = mesh.create_convex_shape(true, true)
		if convex_shape:
			collision_shape.shape = convex_shape
		else:
			push_warning("CityCollision: Failed to create convex shape for " + mesh_instance.name)
			return null
	else:
		# Use trimesh collision for accuracy
		var trimesh_shape = mesh.create_trimesh_shape()
		if trimesh_shape:
			collision_shape.shape = trimesh_shape
		else:
			push_warning("CityCollision: Failed to create trimesh shape for " + mesh_instance.name)
			return null
	
	# Copy the global transform from the mesh instance
	collision_shape.transform = mesh_instance.transform
	
	return collision_shape

## Find all MeshInstance3D nodes recursively
func _find_all_mesh_instances(node: Node) -> Array:
	var mesh_instances: Array = []
	
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			# Skip meshes with no surfaces
			if child.mesh.get_surface_count() > 0:
				mesh_instances.append(child)
		# Recursively search children
		mesh_instances.append_array(_find_all_mesh_instances(child))
	
	return mesh_instances

## Remove existing collision nodes
func _remove_existing_collision() -> void:
	var collision_nodes = []
	
	for child in get_children():
		if child.name == "CityCollision" or child.name == "CityTrimeshCollision":
			collision_nodes.append(child)
	
	for node in collision_nodes:
		node.queue_free()

## Public function to regenerate collision (can be called from editor or other scripts)
func regenerate_collision() -> void:
	generate_collision()
