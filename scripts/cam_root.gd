extends Node3D

@export var player : Node3D
@onready var yaw_node = $CamYaw
@onready var pitch_node = $CamYaw/CamPitch
@onready var spring_arm = $CamYaw/CamPitch/SpringArm3D
@onready var camera = $CamYaw/CamPitch/SpringArm3D/Camera3D
var yaw : float = 0
var pitch : float = 0
var yaw_sensitivity : float = 0.07
var pitch_sensitivity : float = 0.07
var yaw_acceleration : float = 15
var pitch_acceleration : float = 15
var pitch_max : float = 75
var pitch_min : float = -55
var tween : Tween
var position_offset : Vector3 = Vector3(0, 1.3, 0)
var position_offset_target : Vector3 = Vector3(0, 1.3, 0)

# Track if mouse was just toggled to prevent double-toggling
var _mouse_toggle_cooldown: float = 0.0
const TOGGLE_COOLDOWN: float = 0.2

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	spring_arm.add_excluded_object(player.get_rid())
	top_level = true

func _process(delta):
	# Cooldown timer for mouse toggle
	if _mouse_toggle_cooldown > 0:
		_mouse_toggle_cooldown -= delta

func _input(event):
	# Handle ESC key to release mouse - check both action and direct key
	if event.is_action_pressed("esc") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
		if _mouse_toggle_cooldown <= 0:
			_toggle_mouse_capture()
			_mouse_toggle_cooldown = TOGGLE_COOLDOWN
			get_viewport().set_input_as_handled()
			return

	# Only process mouse movement when captured
	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			return
		yaw += -event.relative.x * yaw_sensitivity
		pitch += event.relative.y * pitch_sensitivity

func _toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		print("Mouse released - press ESC again to recapture")
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		print("Mouse captured")


func _physics_process(delta):
	position_offset = lerp(position_offset, position_offset_target, 4 * delta)
	global_position = lerp(global_position, player.global_position + position_offset, 18 * delta)
	
	pitch = clamp(pitch, pitch_min, pitch_max)
	
	yaw_node.rotation_degrees.y = lerp(yaw_node.rotation_degrees.y, yaw, yaw_acceleration * delta)
	pitch_node.rotation_degrees.x = lerp(pitch_node.rotation_degrees.x, pitch, pitch_acceleration * delta)
