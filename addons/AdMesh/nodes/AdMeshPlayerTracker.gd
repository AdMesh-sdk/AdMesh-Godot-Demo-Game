@tool
class_name AdMeshPlayerTracker
extends Node3D

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var runtime := get_node_or_null("/root/AdMeshRuntime")
	if runtime != null and runtime.has_method("set_tracker_position"):
		runtime.set_tracker_position(global_position)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	var runtime := get_node_or_null("/root/AdMeshRuntime")
	if runtime != null and runtime.has_method("clear_tracker_position"):
		runtime.clear_tracker_position()
