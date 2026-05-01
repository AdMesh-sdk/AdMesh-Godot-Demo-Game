extends CharacterBody3D

# Export variables for each enemy instance
@export var MAX_HEALTH: float = 100
@export var MOVE_SPEED: float = 3.0
@export var DAMAGE_MULTIPLIER: float = 1.0
@export var DAMAGE_AMOUNT: float = 10
@export var ATTACK_RANGE: float = 2.0
@export var FOLLOW_DISTANCE: float = 1.0


var is_attacking: bool = false
var is_alive: bool = true
var is_staggered: bool = false

@onready var player: Node3D = get_node("/root/Test_scene/Player")  # Use a global path
@onready var animation_player: AnimationPlayer = $Enemy_2Legs/AnimationPlayer
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	# Add NavigationAgent3D as child if not already present
	if !has_node("NavigationAgent3D"):
		var nav = NavigationAgent3D.new()
		add_child(nav)
		nav_agent = nav
	
	# Configure NavigationAgent3D
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.path_max_distance = 50.0
	
	# Set initial path
	if player:
		nav_agent.target_position = player.global_position
	
	animation_player.connect("animation_finished", Callable(self, "_on_animation_finished"))

func _physics_process(delta: float) -> void:
	if !is_alive:
		return
		
	if !player:
		die()
		return
		
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if !is_attacking and !is_staggered:
		follow_player(delta)
	
	# Update navigation target
	nav_agent.target_position = player.global_position

func follow_player(delta: float) -> void:
	var distance_to_player = global_position.distance_to(player.global_position)
	
	# If within attack range, stop and attack
	if distance_to_player <= ATTACK_RANGE:
		velocity.x = 0
		velocity.z = 0
		stop_walk_animation()
		start_attack()
		return
	
	# Get next path position
	var next_path_position: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_path_position - global_position).normalized()
	
	# Set velocity (maintain y velocity for gravity)
	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED
	
	# Rotate to face movement direction
	look_at(Vector3(next_path_position.x, global_position.y, next_path_position.z), Vector3.UP)
	
	# Play walk animation
	if !is_attacking and !is_staggered:
		play_walk_animation()
	
	move_and_slide()

func take_damage_enemy(amount: float) -> void:
	if !is_alive:
		return
	
	$Animation.play("Damage_Label")
	$Damage_label.text = str("-")
	MAX_HEALTH -= amount
	play_hit_animation()
	
	if MAX_HEALTH <= 0:
		die()

func play_hit_animation() -> void:
	is_staggered = true
	$BloodParticles.emitting = true
	animation_player.play("CharacterArmature|Hit")

func start_attack() -> void:
	if !is_alive or is_attacking or is_staggered:
		return
	
	is_attacking = true
	animation_player.play("CharacterArmature|Attack")

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "CharacterArmature|Attack":
		is_attacking = false
		stop_walk_animation()
		if player and global_position.distance_to(player.global_position) <= ATTACK_RANGE:
			player.take_damage(DAMAGE_AMOUNT * DAMAGE_MULTIPLIER)
	elif anim_name == "CharacterArmature|Hit":
		is_staggered = false

func play_walk_animation() -> void:
	if animation_player.current_animation != "CharacterArmature|Run":
		animation_player.play("CharacterArmature|Run")

func stop_walk_animation() -> void:
	if animation_player.current_animation == "CharacterArmature|Run":
		animation_player.play("CharacterArmature|Idle")

func die() -> void:
	is_alive = false
	animation_player.play("CharacterArmature|Death")
	await get_tree().create_timer(0.6667).timeout
	queue_free()
