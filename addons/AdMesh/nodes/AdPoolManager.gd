@tool
class_name AdPoolManager
extends Node

@export var placement_paths: Array[NodePath] = []
@export var auto_refresh_interval_seconds: float = 0.0

var _timer: Timer


func _ready() -> void:
	if auto_refresh_interval_seconds > 0.0:
		_timer = Timer.new()
		_timer.one_shot = false
		_timer.wait_time = auto_refresh_interval_seconds
		_timer.timeout.connect(refresh_all)
		add_child(_timer)
		_timer.start()


func refresh_all() -> void:
	for node_path in placement_paths:
		var node := get_node_or_null(node_path)
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("fetch_and_display_ad"):
			node.fetch_and_display_ad()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if placement_paths.is_empty():
		warnings.append("Add one or more AdMeshNode placements to coordinate refreshes.")
	return warnings
