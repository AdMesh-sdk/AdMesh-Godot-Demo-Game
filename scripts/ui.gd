# HUD.gd
extends Control

# Duplicate the enum from player script to maintain type safety
enum WeaponState { UNARMED, RIFLE }

@onready var health_bar = $HealthBar/ProgressBar
@onready var health_label = $HealthBar/Label
@onready var weapon_label = $WeaponIndicator/Label
@onready var weapon_texture = $WeaponIndicator/TextureRect

var current_health: float = 100.0
var max_health: float = 100.0

func _ready():
	update_health_display(current_health)
	# Get reference to the player node and connect to its signal
	# Adjust the player node path to match your scene structure
	var player = get_node("..")  # or however you need to reference your player
	player.weapon_changed.connect(update_weapon_display)
	update_health_display(current_health)
	update_weapon_display(WeaponState.UNARMED)

func update_health_display(value: float):
	current_health = value
	health_bar.value = value
	health_label.text = str(floor(value)) + "%"

func update_weapon_display(weapon_state: WeaponState):
	match weapon_state:
		WeaponState.UNARMED:
			weapon_label.text = "UNARMED"
			weapon_texture.texture = preload("res://ui/palm-of-hand.png")
		WeaponState.RIFLE:
			weapon_label.text = "RIFLE"
			weapon_texture.texture = preload("res://ui/ak.png")
