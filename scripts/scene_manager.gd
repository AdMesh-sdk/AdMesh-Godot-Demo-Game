extends Node

## Scene Manager Singleton
## Handles scene transitions, loading screens, and game state management

signal scene_changed(scene_name: String)
signal fade_started(direction: String)
signal fade_completed(direction: String)

# Scene paths
const MAIN_MENU_SCENE = "res://Scenes/main_menu.tscn"
const GAME_SCENE = "res://Scenes/test_scene.tscn"

# Fade transition settings
@export var fade_duration: float = 0.5
@export var fade_color: Color = Color.BLACK

# Current state
var current_scene: String = ""
var is_transitioning: bool = false

# Fade overlay
var fade_overlay: ColorRect = null
var fade_tween: Tween = null

func _ready():
	# Create fade overlay
	_setup_fade_overlay()
	
	# AdMesh SDK initializes automatically via the AdMeshRuntime autoload
	# SDK key is set in Project Settings > admesh/config/sdk_key
	
	# Get current scene name
	var root = get_tree().root
	var scene = root.get_child(root.get_child_count() - 1)
	if scene:
		current_scene = scene.scene_file_path

func _setup_fade_overlay():
	"""Create the fade overlay that covers the screen during transitions"""
	fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.color = fade_color
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.visible = false
	fade_overlay.modulate.a = 0.0
	
	# Add to autoload so it persists across scenes
	add_child(fade_overlay)

func change_scene(scene_path: String, with_fade: bool = true) -> void:
	"""
	Change to a new scene with optional fade transition
	"""
	if is_transitioning:
		push_warning("Scene transition already in progress!")
		return
	
	if scene_path == current_scene:
		push_warning("Already on scene: " + scene_path)
		return
	
	is_transitioning = true
	
	if with_fade:
		await _fade_transition(scene_path)
	else:
		await _instant_scene_change(scene_path)
	
	is_transitioning = false

func _fade_transition(scene_path: String) -> void:
	"""
	Perform a fade out, change scene, then fade in
	"""
	fade_started.emit("out")
	
	# Show overlay and fade to black
	fade_overlay.visible = true
	fade_overlay.modulate.a = 0.0
	
	fade_tween = create_tween()
	fade_tween.set_ease(Tween.EASE_IN_OUT)
	fade_tween.set_trans(Tween.TRANS_QUAD)
	fade_tween.tween_property(fade_overlay, "modulate:a", 1.0, fade_duration)
	await fade_tween.finished
	
	# Change scene while faded
	await _instant_scene_change(scene_path)
	
	# Fade back in
	fade_started.emit("in")
	fade_tween = create_tween()
	fade_tween.set_ease(Tween.EASE_IN_OUT)
	fade_tween.set_trans(Tween.TRANS_QUAD)
	fade_tween.tween_property(fade_overlay, "modulate:a", 0.0, fade_duration)
	await fade_tween.finished
	
	fade_overlay.visible = false
	fade_completed.emit("in")

func _instant_scene_change(scene_path: String) -> void:
	"""
	Instantly change to a new scene
	"""
	if get_tree().change_scene_to_file(scene_path) == OK:
		current_scene = scene_path
		var scene_name = scene_path.get_file().get_basename()
		scene_changed.emit(scene_name)
	else:
		push_error("Failed to load scene: " + scene_path)

func start_game() -> void:
	"""
	Start the game from the main menu
	"""
	await change_scene(GAME_SCENE, true)

func return_to_main_menu() -> void:
	"""
	Return to the main menu from gameplay
	"""
	# Unpause the game if it was paused
	get_tree().paused = false
	await change_scene(MAIN_MENU_SCENE, true)

func quit_game() -> void:
	"""
	Quit the game application
	"""
	print("Quitting game...")
	get_tree().quit()

func is_game_paused() -> bool:
	"""
	Check if the game is currently paused
	"""
	return get_tree().paused

func set_game_paused(paused: bool) -> void:
	"""
	Set the game pause state
	"""
	get_tree().paused = paused

func toggle_pause() -> bool:
	"""
	Toggle the game pause state. Returns the new pause state.
	"""
	var new_state = !get_tree().paused
	get_tree().paused = new_state
	return new_state

func restart_current_scene() -> void:
	"""
	Restart the current scene
	"""
	if current_scene.is_empty():
		push_warning("No current scene to restart")
		return
	
	await change_scene(current_scene, true)

func get_current_scene_name() -> String:
	"""
	Get the name of the current scene
	"""
	return current_scene.get_file().get_basename() if !current_scene.is_empty() else ""

func is_in_game() -> bool:
	"""
	Check if currently in the game scene
	"""
	return current_scene == GAME_SCENE

func is_in_main_menu() -> bool:
	"""
	Check if currently in the main menu scene
	"""
	return current_scene == MAIN_MENU_SCENE
