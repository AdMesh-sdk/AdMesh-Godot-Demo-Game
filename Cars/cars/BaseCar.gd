# Vehicle.gd
extends VehicleBody3D

@export var STEER_SPEED = 1.5
@export var STEER_LIMIT = 0.6
@export var engine_force_value = 40
@export var max_exit_speed: float = 100
@export var max_entry_speed: float = 5.0

var steer_target = 0
var driver = null
var door_open = false
var door_angle = 0.0
const DOOR_SPEED = 2.0
const MAX_DOOR_ANGLE = 75.0  # degrees

@onready var exit_point = $ExitPoint
@onready var enter_point = $EnterPoint
@onready var driver_seat = $DriverSeat
@onready var door = $Door  # Add a Node3D for the door
@onready var vehicle_camera = $CamRoot/CamYaw/CamPitch/SpringArm3D/Camera3D

@onready var driver_door = $DriverDoor  # Add an empty Node3D to mark driver's door position
const ENTRY_DISTANCE = 2.0  # Maximum distance for entering vehicle
var can_accelerate = false
var exiting = false
var keep_pos = false

# --- Engine audio ---
var _engine_audio: AudioStreamPlayer3D = null
const ENGINE_PITCH_IDLE: float   = 0.8
const ENGINE_PITCH_MAX: float    = 2.0
const ENGINE_SPEED_MAX: float    = 30.0  # m/s where pitch is at max

func _ready():
	vehicle_camera.current = false
	_setup_engine_audio()

func _setup_engine_audio() -> void:
	_engine_audio = AudioStreamPlayer3D.new()
	_engine_audio.stream = load("res://Sounds/car_engine.wav")
	_engine_audio.volume_db  = 4.0   # a little boost – adjust as needed
	_engine_audio.max_distance = 30.0
	_engine_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_engine_audio.autoplay = false
	add_child(_engine_audio)



func _physics_process(delta):
	if !driver and !can_accelerate:
		return  # Stop processing vehicle movement when empty

	handle_driving_controls(delta)
	handle_camera(delta)
	update_door(delta)
	update_hud()

	# Update engine audio pitch based on speed (simulates RPM)
	if _engine_audio and _engine_audio.playing:
		var speed_ratio = clamp(linear_velocity.length() / ENGINE_SPEED_MAX, 0.0, 1.0)
		_engine_audio.pitch_scale = lerp(ENGINE_PITCH_IDLE, ENGINE_PITCH_MAX, speed_ratio)


func can_enter(player_position: Vector3) -> bool:
	if linear_velocity.length() > max_entry_speed:
		return false
	# Looser constraint: just be relatively close to the door. Removes strict dot_product checks.
	var door_pos = driver_door.global_position
	var distance = player_position.distance_to(door_pos)
	
	# Allow entry if player is within 4 meters of the driver door
	return distance < (ENTRY_DISTANCE * 2.0)
	

func handle_driving_controls(delta):
	if can_accelerate:
		var speed = linear_velocity.length() * Engine.get_frames_per_second() * delta
		var fwd_mps = transform.basis.x.x
		
		# Steering
		steer_target = Input.get_action_strength("left") - Input.get_action_strength("right")
		steer_target *= STEER_LIMIT
		steering = move_toward(steering, steer_target, STEER_SPEED * delta)
		
		# Acceleration/Braking
		if Input.is_action_pressed("backward"):
			engine_force = calculate_engine_force(speed, true)
		elif Input.is_action_pressed("forward"):
			if fwd_mps >= -1:
				engine_force = calculate_engine_force(speed, false)
			else:
				brake = 1
		else:
			engine_force = 0
			brake = 0.0
		
		# Handbrake
		if Input.is_action_pressed("ui_select"):
			apply_handbrake()
		else:
			release_handbrake()
		if keep_pos:
			var exit_transform = exit_point.global_transform
	 
	
	
	

func calculate_engine_force(speed: float, is_reverse: bool) -> float:
	if speed < 20 and speed != 0:
		return clamp(engine_force_value * (3 if is_reverse else 10) / speed, 0, 300) * (-1 if !is_reverse else 1)
	return engine_force_value * (-1 if !is_reverse else 1)

func apply_handbrake():
	brake = 3
	$wheal2.wheel_friction_slip = 0.8
	$wheal3.wheel_friction_slip = 0.8

func release_handbrake():
	$wheal2.wheel_friction_slip = 3
	$wheal3.wheel_friction_slip = 3

func update_door(delta):
	var target_angle = MAX_DOOR_ANGLE if door_open else 0.0
	door_angle = move_toward(door_angle, target_angle, DOOR_SPEED * delta)
	door.rotation_degrees.y = door_angle

func handle_camera(delta):
	# Add vehicle camera behavior here
	pass

func update_hud():
	var speed = linear_velocity.length()  # Convert to km/h
	$Hud/speed.text = str(round(speed)) + " KMPH"


func apply_traction(speed):
	apply_central_force(Vector3.DOWN * speed)

func enter_vehicle(player):
	if !can_enter(player.global_position):
		return false
		
	driver = player
	$"doge-body/door_open_close".play("Door_open")
	vehicle_camera.current = true
	driver.global_position = $EnterPoint.global_position
	driver.rotation_degrees.x = 0
	driver.rotation_degrees.z = 0

	# Start engine audio
	if _engine_audio and not _engine_audio.playing:
		_engine_audio.pitch_scale = ENGINE_PITCH_IDLE
		_engine_audio.play()

	return true



func exit_vehicle():
	if not driver or not can_exit():
		return

	engine_force = 0
	brake = 500000
	can_accelerate = false
	vehicle_camera.current = false

	var exit_transform = exit_point.global_transform
	var exiting_driver = driver
	driver = null  # Clear reference immediately to prevent stale calls

	# Tell the player to play the exit animation and restore themselves
	exiting_driver.exit_vehicle(exit_transform)

	# Stop engine audio gradually
	if _engine_audio and _engine_audio.playing:
		_engine_audio.stop()

	# Play door animation after a short delay
	await get_tree().create_timer(1.5).timeout
	$"doge-body/door_open_close".play("Door_close")

	# Unfreeze the car
	brake = 0
	engine_force = 0



func can_exit() -> bool:
	return linear_velocity.length() <= max_exit_speed
