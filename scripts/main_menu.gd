extends Control

## Main Menu Controller
## Handles the main menu UI interactions

@onready var title_label = $Background/VBoxContainer/TitleLabel
@onready var start_button = $Background/VBoxContainer/MenuButtons/StartButton
@onready var settings_button = $Background/VBoxContainer/MenuButtons/SettingsButton
@onready var quit_button = $Background/VBoxContainer/MenuButtons/QuitButton
@onready var settings_panel = $SettingsPanel
@onready var close_settings_button = $SettingsPanel/VBoxContainer/CloseSettingsButton

func _ready():
	# Connect button signals
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Connect close settings button
	if close_settings_button:
		close_settings_button.pressed.connect(_on_close_settings_pressed)
	
	# Hide settings panel initially
	if settings_panel:
		settings_panel.visible = false
	
	# Animation: Fade in title
	_title_animation()
	
	# Make sure game is not paused in menu
	SceneManager.set_game_paused(false)
	
	print("Main Menu ready")

func _title_animation():
	"""Animate the title label on entry"""
	if title_label:
		# Start with scale 0 and fade in
		title_label.modulate.a = 0.0
		title_label.scale = Vector2(0.8, 0.8)
		
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_BACK)
		tween.tween_property(title_label, "modulate:a", 1.0, 0.5)
		tween.parallel().tween_property(title_label, "scale", Vector2(1.0, 1.0), 0.5)

func _on_start_pressed():
	"""Start the game"""
	print("Start button pressed - Starting game...")
	
	# Disable buttons during transition
	_set_buttons_enabled(false)
	
	# Add a small delay for button press effect
	await get_tree().create_timer(0.1).timeout
	
	# Start the game via SceneManager
	SceneManager.start_game()

func _on_settings_pressed():
	"""Open settings panel"""
	print("Settings button pressed")
	
	if settings_panel:
		settings_panel.visible = true
		
		# Animate settings panel opening
		settings_panel.modulate.a = 0.0
		settings_panel.scale = Vector2(0.9, 0.9)
		
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(settings_panel, "modulate:a", 1.0, 0.2)
		tween.parallel().tween_property(settings_panel, "scale", Vector2(1.0, 1.0), 0.2)

func _on_quit_pressed():
	"""Quit the game"""
	print("Quit button pressed")
	
	# Disable buttons
	_set_buttons_enabled(false)
	
	# Add a small delay for button press effect
	await get_tree().create_timer(0.1).timeout
	
	# Quit via SceneManager
	SceneManager.quit_game()

func _on_close_settings_pressed():
	"""Close the settings panel"""
	print("Close settings pressed")
	
	if settings_panel:
		# Animate settings panel closing
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(settings_panel, "modulate:a", 0.0, 0.15)
		tween.parallel().tween_property(settings_panel, "scale", Vector2(0.9, 0.9), 0.15)
		
		await tween.finished
		settings_panel.visible = false

func _set_buttons_enabled(enabled: bool):
	"""Enable or disable all menu buttons"""
	if start_button:
		start_button.disabled = !enabled
	if settings_button:
		settings_button.disabled = !enabled
	if quit_button:
		quit_button.disabled = !enabled

func _input(event):
	# Handle ESC key to close settings or quit from main menu
	if event.is_action_pressed("esc"):
		if settings_panel and settings_panel.visible:
			_on_close_settings_pressed()
		else:
			SceneManager.quit_game()
