extends Node3D

@export_group("Weapon Parameters")
@export var max_ammo: int = 30
@export var current_ammo: int = 30
@export var reload_time: float = 2.0
@export var damage: int = 25
@export var fire_rate: float = 0.15
@export var ray_length: float = 100.0

@export_group("References")
@export var ray_cast: RayCast3D
@export var muzzle_flash: GPUParticles3D
@export var shot_sound: AudioStreamPlayer3D
@export var hit_marker: Sprite3D

var can_shoot: bool = true
var is_reloading: bool = false
var shoot_timer: Timer
var is_firing: bool = false

# Sound cooldown: prevents sound from being retriggered faster than it can play
const MIN_SOUND_INTERVAL: float = 0.12
var _sound_timer: float = 0.0

signal on_empty_trigger
signal on_ammo_changed(current: int, max: int)
signal ammo_changed(current: int, total: int)
func _ready():
	shoot_timer = Timer.new()
	add_child(shoot_timer)
	shoot_timer.one_shot = true
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	
	# Enable overlapping shots to prevent the "mosquito racket" cutoff
	if shot_sound:
		shot_sound.max_polyphony = 8

func _physics_process(delta: float):
	_sound_timer = max(0.0, _sound_timer - delta)
	if is_firing and can_shoot and !is_reloading:
		if current_ammo <= 0:
			on_empty_trigger.emit()
			stop_firing()
		else:
			shoot.call_deferred()  # Use call_deferred for coroutine

func start_firing():
	is_firing = true
	if current_ammo <= 0:
		on_empty_trigger.emit()
		return false
	if can_shoot:
		shoot.call_deferred()  # Use call_deferred for coroutine
	return false

func stop_firing():
	is_firing = false

func shoot():
	if !can_shoot or current_ammo <= 0 or is_reloading:
		return false

	current_ammo -= 1
	can_shoot = false
	shoot_timer.start(fire_rate)
	
	if muzzle_flash:
		muzzle_flash.restart()
	if shot_sound and _sound_timer <= 0.0:
		# Don't stop the previous shot; let max_polyphony handle the overlap gracefully
		shot_sound.play()
		_sound_timer = MIN_SOUND_INTERVAL

	# Handle hit marker separately to avoid coroutine issues
	if ray_cast.is_colliding():
		var hit = ray_cast.get_collision_point()
		var body = ray_cast.get_collider()
		
		if hit_marker:
			hit_marker.global_position = hit
			hit_marker.visible = true
			create_hit_marker_timer()
		
		if body.has_method("take_damage_enemy"):
			body.take_damage_enemy(damage)
		
	
	on_ammo_changed.emit(current_ammo, max_ammo)
	ammo_changed.emit(current_ammo, max_ammo)
	return true

# Separate function to handle hit marker timing
func create_hit_marker_timer():
	var timer = get_tree().create_timer(0.1)
	timer.timeout.connect(func(): hit_marker.visible = false)

func start_reload():
	if is_reloading or current_ammo == max_ammo:
		return false
		
	is_reloading = true
	is_firing = false
	var timer = get_tree().create_timer(reload_time)
	timer.timeout.connect(complete_reload)
	return true

func complete_reload():
	current_ammo = max_ammo
	is_reloading = false
	on_ammo_changed.emit(current_ammo, max_ammo)

func _on_shoot_timer_timeout():
	can_shoot = true

func has_ammo() -> bool:
	return current_ammo > 0

func is_ready_to_fire() -> bool:
	return can_shoot and !is_reloading and has_ammo()
	
func _process(_delta: float) -> void:
	pass  # ammo_changed is emitted directly when ammo changes
