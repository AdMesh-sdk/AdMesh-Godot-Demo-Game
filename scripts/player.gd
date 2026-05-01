extends CharacterBody3D
enum WeaponState { UNARMED, RIFLE }
const WEAPON_SWITCH_TIME: float = 0.3
const CROUCH_TRANSITION_TIME: float = 0.4

@export_group("Animation References")
@export var animation_tree: AnimationTree
@export var locomotion_state_playback_path: String
@export var rifle_state_playback_path: String
@export var locomotion_blend_path: String
@export var blend2_path: String

@export_group("State Names")
# Locomotion States
@export var jump_state: String = "JUMP"
@export var falling_state: String = "LANDING"
@export var walking_state: String = "Locomotion"
@export var sprinting_state: String = "RUNNING"
@export var equip_state: String = "EQUIP_WEAPON"

# Rifle States
@export var rifle_fire_state: String = "RIFLE_FIRE"
@export var rifle_reload_state: String = "RIFLE_RELOAD"
@export var rifle_aim_state: String = "RIFLE_AIM"
@export var rifle_idle_state: String = "RIFLE_IDLE"
@export var rifle_walk_state: String = "RIFLE_WALK"
@export var rifle_run_state: String = "RIFLE_RUN"
@export var rifle_unequip_state: String = "WEAPON_UNEQUIP"
@export var enter_vehicle_state: String = "ENTER_VEHICLE"
@export var exit_vehicle_state: String = "EXIT_VEHICLE"

# Crouch States
@export var stand_to_crouch_state: String = "STAND_TO_CROUCH"
@export var crouch_idle_state: String = "CROUCH_IDLE"
@export var crouch_walking_state: String = "CROUCHED_WALKING"
@export var crouch_to_stand_state: String = "CROUCH_TO_STAND"


@export_group("Movement Parameters")
@export var speed: float = 5.0
@export var acceleration: float = 10.0
@export var jump_velocity: float = 4.5
@export var rotation_speed: float = 10.0
@export var sprint_multiplier: float = 1.5
@export var crouched_speed_multiplier: float = 0.5



@export_group("Camera and IK")
@export var camera_controller: Node3D
@export var player_mesh: Node3D
@export var skeleton_ik: SkeletonIK3D
@export var aim_position_node: Node3D
@export var weapon_system: Node3D
@export var camera_aim_position: Vector3
@export var default_camera_aim_position: Vector3
@export var standing_camera_height: float = 1.8
@export var crouching_camera_height: float = 0.9
@export var ik_blend_speed: float = 5.0


@export_group("Weapon System")
@export var max_ammo_per_mag: int = 30
@export var starting_total_ammo: int = 90
@export var weapon_model: Node3D
@export var MUZZLE_FLASH_DURATION = 0.05
@export var MUZZLE_FLASH_SIZE = Vector3(0.2, 0.2, 0.2)
@export var MUZZLE_FLASH_INTENSITY = 5.0

var input_dir = Vector2.ZERO
var current_blend_position = Vector2.ZERO
var is_sprinting = false
var gravity = 9.8
var jump_queued: bool
var falling: bool
var can_jump = true
var can_move = true
var can_switch_weapon = true
var transition_speed: float = 10.0

var current_weapon_state: WeaponState = WeaponState.UNARMED
var is_switching_weapon: bool = false
var weapon_switch_timer: float = 0.0
var current_ammo: int = max_ammo_per_mag
var total_ammo: int = starting_total_ammo
var is_firing: bool = false
var can_fire: bool = true
var fire_rate: float = 0.1
var fire_timer: float = 0.0
var is_reloading: bool = false
var is_aiming: bool = false

var camera_position: Vector3
var camera_rotation: Vector3
var camera_fov: float = 75.0
var base_fov: float = 75.0
var sprint_fov_multiplier: float = 1.15
var aim_fov: float = 30.0
var current_fov: float = base_fov
var fov_lerp_speed: float = 5.0
var camera_shake_amount: float = 0.0
var base_fire_shake: float = 0.2
var aim_fire_shake: float = 0.05
var shake_decay: float = 10.0
var shake_roughness: float = 20.0


var current_vehicle: VehicleBody3D = null
var is_in_vehicle: bool = false
var can_exit_car = false
var original_transform: Transform3D


var is_crouching: bool = false
var is_transitioning_crouch: bool = false


var current_health: int = 100
var current_ik_interpolation: float = 0.0
var target_ik_interpolation: float = 0.0


@onready var camera_root: Node3D = $CamRoot
@onready var interaction_area = $InteractionArea
@onready var muzzle_flash_light = $Player_model_base/Player_model/Skeleton/gun/AK/ak_light
@onready var muzzle_flash_mesh = $Player_model_base/Player_model/Skeleton/gun/AK/ak_muzzle_flash



signal health_changed(value: float)
signal weapon_changed(weapon_state: WeaponState)


func _ready():
	
	
	switch_weapon()
	weapon_model.visible = true
	aim_position_node.position = camera_aim_position
	var locomotion_playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
	var rifle_playback = animation_tree.get(rifle_state_playback_path) as AnimationNodeStateMachinePlayback


	locomotion_playback.travel(walking_state)
	rifle_playback.travel(rifle_idle_state)

	

func _input(event):
	if is_switching_weapon:
		return
			
	elif event.is_action_pressed("jump") and is_on_floor():
		trigger_jump()
	if event.is_action_pressed("switch_weapon") and !is_aiming and can_switch_weapon:
		switch_weapon()
	elif current_weapon_state == WeaponState.RIFLE:
		handle_rifle_input(event)
	
	if event.is_action_pressed("jump") and is_on_floor():
		trigger_jump()
		
	if is_in_vehicle:
		if event.is_action_pressed("interact") and can_exit_car:
			current_vehicle.exit_vehicle()
			is_in_vehicle = false
		return
		
	if event.is_action_pressed("interact") and is_near_vehicle():
		enter_nearest_vehicle()
	if event.is_action_pressed("crouch") and !is_transitioning_crouch and !is_in_vehicle and !is_switching_weapon:
		toggle_crouch()
	
func is_near_vehicle():
	for body in interaction_area.get_overlapping_bodies():
		if body is VehicleBody3D and body.has_method("enter_vehicle"):
			current_vehicle = body
			return true
	return false
	
func enter_nearest_vehicle():
	if current_vehicle == null or is_in_vehicle:
		return

	# Single authoritative check - if can_enter() fails, tell the player why
	if !current_vehicle.can_enter(global_position):
		print("Move closer to the driver's door or wait for car to stop")
		return

	# Unequip weapon before entering
	if current_weapon_state == WeaponState.RIFLE:
		switch_weapon()
		await get_tree().create_timer(WEAPON_SWITCH_TIME).timeout

	var entered = await current_vehicle.enter_vehicle(self)
	if not entered:
		return

	# Lock down player state
	can_switch_weapon = false
	can_jump = false
	can_exit_car = false
	is_in_vehicle = true
	original_transform = global_transform
	$CamRoot/CamYaw/CamPitch/SpringArm3D/Camera3D.current = false
	$col.disabled = true

	# Play entry animation
	var locomotion_playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
	locomotion_playback.travel(enter_vehicle_state)
	self.rotation.y = current_vehicle.rotation.y + 1.5 * PI

	await get_tree().create_timer(2.3).timeout

	# Snap to driver seat
	self.global_position = current_vehicle.driver_seat.global_position
	self.rotation.y = current_vehicle.rotation.y + 1.5 * PI

	await get_tree().create_timer(1.5).timeout
	$Player_model_base.visible = false

	# Allow driving
	can_exit_car = true
	current_vehicle.can_accelerate = true
	can_move = false

			
			
func exit_vehicle(exit_transform: Transform3D):
	if !is_in_vehicle:
		return

	is_in_vehicle = false
	var vehicle_rotation = current_vehicle.rotation.y
	can_move = false
	can_jump = false
	can_exit_car = false
	gravity = 0

	# Play exit animation while briefly visible
	$Player_model_base.visible = true
	rotation.y = vehicle_rotation + PI / 3.0
	var locomotion_playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
	locomotion_playback.travel(exit_vehicle_state)

	await get_tree().create_timer(2.0).timeout

	# Snap player to the exit point position now that animation is mostly done
	global_position = exit_transform.origin + Vector3(0, 0.2, 0)
	rotation.y = vehicle_rotation + PI / 3.0

	await get_tree().create_timer(0.5).timeout

	# Restore camera
	$CamRoot/CamYaw/CamPitch/SpringArm3D/Camera3D.current = true

	# Fully restore player controls
	$col.disabled = false
	gravity = 9.8
	can_jump = true
	can_move = true
	can_switch_weapon = true

	# Clear vehicle reference so next interaction works fresh
	current_vehicle = null


func apply_gravity_and_jump(delta):
	if !is_on_floor():
		velocity.y -= gravity * delta
		if !falling:
			falling = true
			var playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
			playback.travel(jump_state)
	else:
		falling = false
		
	if jump_queued and can_jump:
		velocity.y = jump_velocity
		jump_queued = false
				
	# Only trigger landing animation if falling (not during jump)
	if falling and velocity.y < -4.0:  # Add a threshold to detect actual falling
			falling = true
			var playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
			playback.travel(falling_state)
	else:
		falling = false
		

		
func _physics_process(delta):
	if is_in_vehicle:
		can_move = false
		return  # Stop processing player movement when in vehicle

	if is_switching_weapon:
		if weapon_switch_timer > 0:
			weapon_switch_timer -= delta
	if can_move:
		handle_movement(delta)
	
	if current_weapon_state == WeaponState.RIFLE:
		handle_aiming(delta)
		handle_continuous_fire(delta)
	update_ik_interpolation(delta)
	handle_animations(delta)
	apply_gravity_and_jump(delta)
	move_and_slide()
	update_camera_effects(delta)
	


	# When health changes
	health_changed.emit(current_health)

	# When weapon state changes
	weapon_changed.emit(current_weapon_state)


func handle_aiming(delta):
	if Input.is_action_just_pressed("aim"):
		start_aiming()
	elif Input.is_action_just_released("aim"):
		stop_aiming()
		
	if is_aiming:
		speed = 4
		update_aim_rotation(delta)
		update_camera_transitions(delta)
	if !is_aiming:
		speed = 5.0


func trigger_jump():
	if !is_in_vehicle:
		var playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
		playback.travel(jump_state)
		jump_queued = true


func update_camera_transitions(delta):
	var camera = $CamRoot/CamYaw/CamPitch/SpringArm3D/Camera3D
	
	# Calculate target camera height
	var target_camera_height = crouching_camera_height if is_crouching else standing_camera_height
	
	# Smoothly interpolate camera root position
	camera_root.position.y = lerp(
		camera_root.position.y,
		target_camera_height,
		delta * transition_speed
	)
	
	# Smoothly interpolate camera position
	aim_position_node.position = aim_position_node.position.lerp(
		camera_aim_position if is_aiming else default_camera_aim_position,
		delta * transition_speed
	)
	
	# Smoothly interpolate camera properties
	camera.rotation_degrees.x = lerp(
		camera.rotation_degrees.x,
		11.0 if is_aiming else 0.0,
		delta * transition_speed
	)
	
	camera.fov = lerp(
		camera.fov,
		30.0 if is_aiming else 75.0,
		delta * transition_speed
	)
	
	

func start_aiming():
	if current_weapon_state != WeaponState.RIFLE or is_reloading:
		return

	is_aiming = true
	var rifle_playback = animation_tree.get(rifle_state_playback_path) as AnimationNodeStateMachinePlayback
	rifle_playback.travel(rifle_aim_state)
	
	# Set target interpolation to 1 and start IK
	target_ik_interpolation = 1.0
	skeleton_ik.start()

func update_aim_rotation(delta):
	var camera_direction = -$CamRoot/CamYaw.global_transform.basis.z
	var flat_direction = camera_direction
	flat_direction.y = 0
	flat_direction = flat_direction.normalized()
	
	var target_rotation = atan2(flat_direction.x, flat_direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)
	
func handle_continuous_fire(delta):
	if !is_firing or !is_aiming or is_reloading:
		return
		
	var rifle_playback = animation_tree.get(rifle_state_playback_path) as AnimationNodeStateMachinePlayback
	
	fire_timer -= delta
	if fire_timer <= 0 and can_fire and weapon_system.is_ready_to_fire():
		fire_timer = fire_rate
		show_muzzle_flash()
		$Player_model_base/Player_model/Skeleton/gun/AK/ak_muzzle.emitting = true
		$Player_model_base/Player_model/Skeleton/gun/AK/gun/AnimationPlayer.play("Armature_003|shooting")
		rifle_playback.start(rifle_fire_state, -1.0)  # Only pass the state name and optional blend time

		weapon_system.start_firing()
		
	if is_aiming:
		add_camera_shake(aim_fire_shake)
	else:
		add_camera_shake(base_fire_shake)
		await get_tree().create_timer(fire_rate * 0.5).timeout
		if is_aiming and is_firing and !is_reloading:
			rifle_playback.travel(rifle_aim_state)
			
func handle_rifle_input(event):
	if current_weapon_state != WeaponState.RIFLE:
		return
		
	var rifle_playback = animation_tree.get(rifle_state_playback_path) as AnimationNodeStateMachinePlayback
	
	# Reload check: Ensure reload cannot be interrupted by firing
	if event.is_action_pressed("reload") and !is_switching_weapon and !is_reloading:
		if weapon_system.start_reload():
			is_reloading = true
			is_firing = false
			can_fire = false
			$Player_model_base/Player_model/Skeleton/gun/AK/gun/AnimationPlayer.play("Armature_003|idle action 2")
			stop_aiming()
			
			rifle_playback.travel(rifle_reload_state)

			await get_tree().create_timer(2.9).timeout
			
			is_reloading = false
			can_fire = true
			
			# Blend back to appropriate state based on current movement
			if is_aiming:
				rifle_playback.travel(rifle_aim_state)
			elif is_sprinting:
				rifle_playback.travel(rifle_run_state)
			elif velocity.length() > 0.1:
				rifle_playback.travel(rifle_walk_state)
			else:
				rifle_playback.travel(rifle_idle_state)
				
	elif event.is_action_pressed("fire") and !is_switching_weapon and is_aiming and !is_reloading:
		
		is_firing = true
		
		fire_timer = 0
		
		# Only fire if not reloading
		if !is_reloading:
			rifle_playback.start(rifle_fire_state, -1.0)  # Only pass the state name and optional blend time

		weapon_system.start_firing()
				
	elif event.is_action_released("fire"):
		is_firing = false
		weapon_system.stop_firing()
		if is_aiming:
			rifle_playback.travel(rifle_aim_state)
		else:
			rifle_playback.travel(rifle_idle_state)
func switch_weapon():
	if is_switching_weapon:
		return
		
	is_switching_weapon = true
	weapon_switch_timer = WEAPON_SWITCH_TIME
	
	var locomotion_playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
	var rifle_playback = animation_tree.get(rifle_state_playback_path) as AnimationNodeStateMachinePlayback
	
	if current_weapon_state == WeaponState.UNARMED:
		# Switching to Rifle
		locomotion_playback.travel(equip_state)  # Play equip animation in locomotion state
		weapon_model.visible = true
		
		# Wait for equip animation to finish before transitioning to rifle idle
		await get_tree().create_timer(WEAPON_SWITCH_TIME).timeout
		current_weapon_state = WeaponState.RIFLE
		animation_tree.set(blend2_path, 1.0)  # Ensure upper body blend is set
		rifle_playback.travel(rifle_idle_state)
		is_switching_weapon = false
	else:
		# Switching to Unarmed
		animation_tree.set(blend2_path, 1.0)  # Ensure upper body blend is active for unequip
		rifle_playback.travel(rifle_unequip_state)  # Play unequip in rifle state
		
		# Wait for unequip animation to finish before hiding weapon
		await get_tree().create_timer(WEAPON_SWITCH_TIME).timeout
		weapon_model.visible = false
		animation_tree.set(blend2_path, 0.0)  # Reset upper body blend
		locomotion_playback.travel(walking_state)
		current_weapon_state = WeaponState.UNARMED
		is_switching_weapon = false
		stop_aiming()
		
		
# Modify your handle_movement function
func handle_movement(delta):
	var was_sprinting = is_sprinting
	# Prevent sprinting while crouching
	is_sprinting = Input.is_action_pressed("sprint") and input_dir != Vector2.ZERO and !is_aiming and !is_crouching
	
	var speed_modifier = speed
	if is_sprinting:
		speed_modifier *= sprint_multiplier
	elif is_crouching:
		speed_modifier *= crouched_speed_multiplier
	
	input_dir = -Input.get_vector("left", "right", "up", "down")
	var camera_basis = camera_controller.get_node("CamYaw").global_transform.basis
	var direction = (camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		var target_velocity = direction * speed_modifier
		velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
		
		if !is_aiming:
			var target_rotation = atan2(-direction.x, -direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0, acceleration * delta)

# Modified handle_animations function
func handle_animations(delta):
	var locomotion_playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
	var rifle_playback = animation_tree.get(rifle_state_playback_path) as AnimationNodeStateMachinePlayback
	
	# Update movement blend for locomotion BlendSpace2D
	var forward_speed = velocity.length() / speed
	current_blend_position = current_blend_position.lerp(Vector2(0, forward_speed), delta * acceleration)
	animation_tree.set(locomotion_blend_path, current_blend_position)
	
	# Get current state name
	var current_state = locomotion_playback.get_current_node()
	
	# Handle locomotion states
	if is_on_floor() and !falling and !is_transitioning_crouch:
		# Only update animation state if we're not in a transition state
		if current_state != stand_to_crouch_state and current_state != crouch_to_stand_state:
			if is_crouching:
				update_crouch_state()
			else:
				if current_state != equip_state:
					update_movement_state()
	
	# Handle rifle states
	if current_weapon_state == WeaponState.RIFLE and !is_reloading and !is_switching_weapon:
		if is_aiming:
			rifle_playback.travel(rifle_aim_state)
		elif is_sprinting:
			rifle_playback.travel(rifle_run_state)
		elif velocity.length() > 0.1:
			rifle_playback.travel(rifle_walk_state)
		else:
			rifle_playback.travel(rifle_idle_state)
			

func _on_weapon_empty():
	if is_aiming:
		var rifle_playback = animation_tree.get(rifle_state_playback_path) as AnimationNodeStateMachinePlayback
		rifle_playback.travel(rifle_aim_state)

func stop_aiming():
	if !is_aiming:
		return
		
	is_aiming = false
	if current_weapon_state == WeaponState.RIFLE:
		var rifle_playback = animation_tree.get(rifle_state_playback_path) as AnimationNodeStateMachinePlayback
		rifle_playback.travel(rifle_idle_state)
	
	# Set target interpolation to 0
	target_ik_interpolation = 0.0


func update_ik_interpolation(delta):
	if current_ik_interpolation != target_ik_interpolation:
		current_ik_interpolation = lerp(current_ik_interpolation, target_ik_interpolation, delta * ik_blend_speed)
		skeleton_ik.interpolation = current_ik_interpolation




func update_camera_effects(delta):
	var camera = $CamRoot/CamYaw/CamPitch/SpringArm3D/Camera3D
	
	# Update FOV based on state
	var target_fov = base_fov
	if is_sprinting and velocity.length() > 0.1:
		target_fov = base_fov * sprint_fov_multiplier
	elif is_aiming:
		target_fov = aim_fov
	
	current_fov = lerp(current_fov, target_fov, delta * fov_lerp_speed)
	camera.fov = current_fov
	
	# Handle camera shake
	camera_shake_amount = max(0, camera_shake_amount - shake_decay * delta)
	if camera_shake_amount > 0:
		var shake_offset = Vector3(
			randf_range(-1, 1) * camera_shake_amount,
			randf_range(-1, 1) * camera_shake_amount,
			0
		)
		camera.position = shake_offset
	else:
		camera.position = Vector3.ZERO

func add_camera_shake(amount: float):
	camera_shake_amount = min(camera_shake_amount + amount, 1.0)



func show_muzzle_flash():
	# Random rotation for variety
	muzzle_flash_mesh.rotation = Vector3(
		randf_range(0, PI),
		randf_range(0, PI),
		randf_range(0, PI)
	)
	
	# Random scale variation
	var scale_var = randf_range(0.8, 1.2)
	muzzle_flash_mesh.scale = MUZZLE_FLASH_SIZE * scale_var
	
	# Show effects
	muzzle_flash_mesh.visible = true
	muzzle_flash_light.visible = true
	muzzle_flash_light.light_energy = MUZZLE_FLASH_INTENSITY
	
	# Hide after duration
	await get_tree().create_timer(MUZZLE_FLASH_DURATION).timeout
	muzzle_flash_mesh.visible = false
	muzzle_flash_light.visible = false
	
# Update your toggle_crouch function
func toggle_crouch():
	is_transitioning_crouch = true
	var locomotion_playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
	
	if !is_crouching:
		# Transition to crouch
		locomotion_playback.travel(stand_to_crouch_state)
		await get_tree().create_timer(CROUCH_TRANSITION_TIME).timeout
		is_crouching = true
		update_crouch_state()
	else:
		# Transition to stand
		locomotion_playback.travel(crouch_to_stand_state)
		await get_tree().create_timer(CROUCH_TRANSITION_TIME).timeout
		is_crouching = false
		update_movement_state()
	
	is_transitioning_crouch = false
	
	is_transitioning_crouch = false

# New function to update crouch state based on movement
func update_crouch_state():
	var locomotion_playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
	var current_state = locomotion_playback.get_current_node()
	
	# Only update if we're not in a transition state
	if current_state != stand_to_crouch_state and current_state != crouch_to_stand_state:
		if velocity.length() > 0.1:
			locomotion_playback.travel(crouch_walking_state)
		else:
			locomotion_playback.travel(crouch_idle_state)
			

# New function to update regular movement state
func update_movement_state():
	var locomotion_playback = animation_tree.get(locomotion_state_playback_path) as AnimationNodeStateMachinePlayback
	if is_sprinting:
		locomotion_playback.travel(sprinting_state)
	else:
		locomotion_playback.travel(walking_state)
