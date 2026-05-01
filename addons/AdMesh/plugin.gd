@tool
extends EditorPlugin

const ADMESH_SCRIPT := "res://addons/AdMesh/nodes/MeshAdPlayer.gd"
const ADMESH_TRACKER_SCRIPT := "res://addons/AdMesh/nodes/AdMeshPlayerTracker.gd"
const ADMESH_ICON := "res://addons/AdMesh/icon.jpeg"

var _inspector_help_plugin: EditorInspectorPlugin

func _enter_tree() -> void:
	_add_custom_project_setting("admesh/config/sdk_key", "", TYPE_STRING)
	_add_custom_project_setting("admesh/advanced/ad_selector_url", "https://select.admesh.cloud", TYPE_STRING)
	_add_custom_project_setting("admesh/advanced/event_collector_url", "https://events.admesh.cloud", TYPE_STRING)

	add_autoload_singleton("AdMeshRuntime", "res://addons/AdMesh/nodes/AdMeshRuntime.gd")
	add_custom_type("AdMeshNode", "Node3D", load(ADMESH_SCRIPT), load(ADMESH_ICON))
	add_custom_type("AdMeshPlayerTracker", "Node3D", load(ADMESH_TRACKER_SCRIPT), load(ADMESH_ICON))
	_inspector_help_plugin = load("res://addons/AdMesh/editor/admesh_inspector_help_plugin.gd").new()
	add_inspector_plugin(_inspector_help_plugin)

func _exit_tree() -> void:
	remove_custom_type("AdMeshNode")
	remove_custom_type("AdMeshPlayerTracker")
	if _inspector_help_plugin != null:
		remove_inspector_plugin(_inspector_help_plugin)
		_inspector_help_plugin = null
	remove_autoload_singleton("AdMeshRuntime")

func _add_custom_project_setting(name: String, default_value: Variant, type: int) -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)
	ProjectSettings.set_initial_value(name, default_value)
	var property_info = {
		"name": name,
		"type": type
	}
	ProjectSettings.add_property_info(property_info)
