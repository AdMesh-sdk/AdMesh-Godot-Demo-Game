extends CanvasLayer

## Touch Input Controller for Android
## This script handles virtual joystick and button inputs for mobile devices

# Set layer to be above game UI (higher = on top)
@export var ui_layer: int = 100

@onready var left_joystick = $LeftJoystick
@onready var joystick_knob = $LeftJoystick/JoystickBg/JoystickKnob
@onready var jump_button = $RightButtons/JumpButton
@onready var crouch_button = $RightButtons/CrouchButton
@onready var sprint_button = $RightButtons/SprintButton
@onready var fire_button = $BottomButtons/FireButton
@onready var aim_button = $BottomButtons/AimButton

# Joystick state
var joystick_center: Vector2 = Vector2.ZERO
var joystick_vector: Vector2 = Vector2.ZERO
var joystick_active: bool = false
var joystick_deadzone: float = 0.2

# Button state tracking
var button_states = {
	"jump": false,
	"crouch": false,
	"sprint": false,
	"fire": false,
	"aim": false
}

func _ready():
	# Set the layer for proper z-ordering (above game)
	layer = ui_layer
	
	# Connect button signals using button_down and button_up
	_connect_button_signals()
	
	# Determine visibility based on platform/device type
	_update_visibility()

func _connect_button_signals():
	# Connect all button signals safely
	if jump_button:
		jump_button.button_down.connect(_on_jump_pressed)
		jump_button.button_up.connect(_on_jump_released)
	if crouch_button:
		crouch_button.button_down.connect(_on_crouch_pressed)
		crouch_button.button_up.connect(_on_crouch_released)
	if sprint_button:
		sprint_button.button_down.connect(_on_sprint_pressed)
		sprint_button.button_up.connect(_on_sprint_released)
	if fire_button:
		fire_button.button_down.connect(_on_fire_pressed)
		fire_button.button_up.connect(_on_fire_released)
	if aim_button:
		aim_button.button_down.connect(_on_aim_pressed)
		aim_button.button_up.connect(_on_aim_released)

func _update_visibility():
	# Check if we should show touch controls
	var should_show = _is_mobile_device()
	
	# Set visibility
	visible = should_show
	
	# Also enable/disable input processing based on visibility
	process_mode = PROCESS_MODE_INHERIT if should_show else PROCESS_MODE_DISABLED

func _is_mobile_device() -> bool:
	# Check for Android
	if OS.get_name() == "Android":
		return true
	
	# Check for iOS
	if OS.get_name() == "iOS":
		return true
	
	# Check for HTML5/Web build (often used on mobile)
	if OS.get_name() == "Web":
		# Check if running on a touch device via JavaScript
		if _is_touch_device_detected():
			return true
		# Also check viewport size for mobile-like screens
		var screen_size = DisplayServer.screen_get_size()
		if screen_size.x <= 1024 or screen_size.y <= 1024:
			return true
	
	# Check for touch screen capability on desktop
	if DisplayServer.is_touchscreen_available():
		return true
	
	# Check for specific handheld consoles (using model property)
	var model = OS.get_model_name().to_lower()
	if "nintendo" in model or "playstation" in model or "steam" in model:
		return true
	
	return false

func _is_touch_device_detected() -> bool:
	# Try to detect touch via JavaScript in Web builds
	# This is a placeholder - in actual Godot web exports,
	# you could use JavaScript bridge to check navigator.maxTouchPoints
	return false

func _input(event):
	# Only process touch events if visible
	if not visible:
		return
	
	if event is InputEventScreenTouch:
		if event.pressed:
			_handle_touch_start(event)
		else:
			_handle_touch_end(event)
	elif event is InputEventScreenDrag:
		_handle_touch_drag(event)

func _handle_touch_start(event: InputEventScreenTouch):
	var touch_pos = event.position
	
	# Check if touch is in the left joystick area
	if touch_pos.x < 300 and touch_pos.y > 400:
		joystick_center = Vector2(150, 500)  # Center of left joystick
		joystick_active = true
		_update_joystick(touch_pos)

func _handle_touch_end(event: InputEventScreenTouch):
	if joystick_active:
		joystick_vector = Vector2.ZERO
		joystick_knob.position = Vector2.ZERO
		joystick_active = false

func _handle_touch_drag(event: InputEventScreenDrag):
	if joystick_active:
		_update_joystick(event.position)

func _update_joystick(touch_pos: Vector2):
	var direction = touch_pos - joystick_center
	var distance = direction.length()
	var max_distance = 60.0
	
	# Clamp to max distance
	if distance > max_distance:
		direction = direction.normalized() * max_distance
		distance = max_distance
	
	# Update knob position
	joystick_knob.position = direction
	
	# Calculate normalized vector
	if distance > joystick_deadzone * max_distance:
		joystick_vector = direction / max_distance
	else:
		joystick_vector = Vector2.ZERO
	
	# Map joystick to input actions
	_update_movement_input()

func _update_movement_input():
	# Forward/Backward (up/down on joystick)
	if joystick_vector.y < -joystick_deadzone:
		Input.action_press("forward", -joystick_vector.y)
		Input.action_release("backward")
	elif joystick_vector.y > joystick_deadzone:
		Input.action_press("backward", joystick_vector.y)
		Input.action_release("forward")
	else:
		Input.action_release("forward")
		Input.action_release("backward")
	
	# Left/Right (left/right on joystick)
	if joystick_vector.x < -joystick_deadzone:
		Input.action_press("left", -joystick_vector.x)
		Input.action_release("right")
	elif joystick_vector.x > joystick_deadzone:
		Input.action_press("right", joystick_vector.x)
		Input.action_release("left")
	else:
		Input.action_release("left")
		Input.action_release("right")

# Button handlers
func _on_jump_pressed():
	Input.action_press("jump")
	button_states["jump"] = true

func _on_jump_released():
	Input.action_release("jump")
	button_states["jump"] = false

func _on_crouch_pressed():
	Input.action_press("crouch")
	button_states["crouch"] = true

func _on_crouch_released():
	Input.action_release("crouch")
	button_states["crouch"] = false

func _on_sprint_pressed():
	Input.action_press("sprint")
	button_states["sprint"] = true

func _on_sprint_released():
	Input.action_release("sprint")
	button_states["sprint"] = false

func _on_fire_pressed():
	Input.action_press("fire")
	button_states["fire"] = true

func _on_fire_released():
	Input.action_release("fire")
	button_states["fire"] = false

func _on_aim_pressed():
	Input.action_press("aim")
	button_states["aim"] = true

func _on_aim_released():
	Input.action_release("aim")
	button_states["aim"] = false
