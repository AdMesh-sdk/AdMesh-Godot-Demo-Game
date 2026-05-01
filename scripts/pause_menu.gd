extends Control

## Pause Menu Controller
## Handles the in-game pause menu

@onready var resume_button = $Panel/VBoxContainer/ResumeButton
@onready var settings_button = $Panel/VBoxContainer/SettingsButton
@onready var quit_to_menu_button = $Panel/VBoxContainer/QuitToMenuButton
@onready var quit_game_button = $Panel/VBoxContainer/QuitGameButton

var is_paused: bool = false

func _ready():
	# Connect button signals
	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	quit_game_button.pressed.connect(_on_quit_game_pressed)
	
	# Hide pause menu initially
	visible = false
	is_paused = false
	
	print("Pause Menu ready")

func _input(event):
	# Handle ESC key for pause toggle
	if event.is_action_pressed("esc"):
		# Don't toggle if SceneManager is transitioning
		if SceneManager.is_transitioning:
			return
		toggle_pause()

func toggle_pause() -> void:
	"""Toggle the pause state"""
	is_paused = !is_paused
	
	if is_paused:
		_show_pause_menu()
	else:
		_hide_pause_menu()

func _show_pause_menu() -> void:
	"""Show the pause menu and pause the game"""
	# Pause the game
	SceneManager.set_game_paused(true)
	
	# Show pause menu with animation
	visible = true
	
	# Reset and animate
	modulate.a = 0.0
	$Panel.scale = Vector2(0.9, 0.9)
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property($Panel, "scale", Vector2(1.0, 1.0), 0.15)
	
	print("Game paused")

func _hide_pause_menu() -> void:
	"""Hide the pause menu and unpause the game"""
	# Animate out
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	
	await tween.finished
	
	# Hide and unpause
	visible = false
	SceneManager.set_game_paused(false)
	
	print("Game resumed")

func _on_resume_pressed():
	"""Resume the game"""
	print("Resume button pressed")
	toggle_pause()

func _on_settings_pressed():
	"""Open settings (placeholder)"""
	print("Settings button pressed")
	# TODO: Implement settings panel
	# For now, show a simple message or popup

func _on_quit_to_menu_pressed():
	"""Quit to main menu"""
	print("Quit to menu button pressed")
	
	# Disable buttons during transition
	_set_buttons_enabled(false)
	
	# First unpause, then transition
	SceneManager.set_game_paused(false)
	is_paused = false
	visible = false
	
	# Return to main menu
	await SceneManager.return_to_main_menu()

func _on_quit_game_pressed():
	"""Quit the game entirely"""
	print("Quit game button pressed")
	
	# Disable buttons
	_set_buttons_enabled(false)
	
	# Unpause and quit
	SceneManager.set_game_paused(false)
	
	# Small delay for button press effect
	await get_tree().create_timer(0.1).timeout
	
	SceneManager.quit_game()

func _set_buttons_enabled(enabled: bool):
	"""Enable or disable all menu buttons"""
	resume_button.disabled = !enabled
	settings_button.disabled = !enabled
	quit_to_menu_button.disabled = !enabled
	quit_game_button.disabled = !enabled

func force_unpause() -> void:
	"""Force the game to unpause (used when returning to menu)"""
	if is_paused:
		is_paused = false
		visible = false
		SceneManager.set_game_paused(false)
