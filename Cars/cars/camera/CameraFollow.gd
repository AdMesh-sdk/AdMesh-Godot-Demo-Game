extends SpringArm3D

@export var target_distance = 5
@export var min_distance = 2
@export var max_distance = 10
@export var mouse_sensitivity := 0.2

var follow_this: Node3D = null
var pitch: float = 20.0  # Initial pitch angle
var yaw: float = 0.0

func _ready():
	follow_this = get_parent() as Node3D
	adjust_camera_position(target_distance)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event.is_action_pressed("esc"):
		_toggle_mouse_capture()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_mouse_capture()

	if event is InputEventMouseMotion:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			return
		# Adjust yaw (horizontal) and pitch (vertical) based on mouse movement
		yaw -= event.relative.x * mouse_sensitivity
		pitch += event.relative.y * mouse_sensitivity

		# Clamp pitch to avoid flipping
		pitch = clamp(pitch, -80, 80)

		adjust_camera_position(target_distance)

func _toggle_mouse_capture() -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _process(delta):
	# Calculate rotation for yaw and pitch
	var rotation = Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	transform.basis = rotation

	# Ensure SpringArm3D is positioned at the car's center
	global_transform.origin = follow_this.global_transform.origin

func adjust_camera_position(distance: float):
	# Adjust the position of the Camera3D node relative to the SpringArm3D
	if $Camera3D:
		$Camera3D.transform.origin = Vector3(0, 0, -distance)
