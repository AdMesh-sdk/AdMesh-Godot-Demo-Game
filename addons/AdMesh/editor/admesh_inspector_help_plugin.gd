@tool
extends EditorInspectorPlugin

const HELP_BY_SCRIPT := {
	"nodes/MeshAdPlayer.gd": {
		"title": "AdMesh Node Guide",
		"summary": "This is the shipped Godot surface-placement node. The main setup path is: SDK key -> ad_unit_id -> live/test mode -> mesh shape -> serving plan -> fallback display -> delivery proof.",
		"sections": [
			{
				"title": "Core setup",
				"lines": [
					"`sdk_key`: Project-wide live key, stored into Project Settings by this inspector.",
					"`ad_unit_id`: Placement identifier from the AdMesh portal. Live loads fail without it.",
					"`use_real_ads`: Leave off while scene-blocking or testing placeholders; turn on for production serving.",
					"`auto_load_on_ready`: Register and fetch automatically when the node enters a live scene."
				]
			},
			{
				"title": "Visual setup",
				"lines": [
					"`aspect_ratio_preset`: Keeps the generated quad aligned to the intended creative format.",
					"`custom_quad_size`: Only matters when the preset is `Custom`.",
					"`placeholder_texture`: Safe fallback shown before a live creative arrives or after failures.",
					"`force_unshaded_material`: Keeps the ad surface readable instead of being darkened by scene lighting.",
					"`double_sided`: Lets the same surface render from both front and back."
				]
			},
			{
				"title": "Audio and proof",
				"lines": [
					"`enable_audio`: Lets video creatives output positional sound from this placement.",
					"`audio_max_distance`: Distance after which the video audio is effectively muted.",
					"`audio_volume_db`: Base Godot video volume before distance attenuation.",
					"`track_presence`: Enables session heartbeat and presence reporting.",
					"`report_interval_seconds`: Lower values increase reporting frequency but cost more network traffic.",
					"`refresh_while_online`: Keeps the placement refreshing while the runtime remains connected.",
					"`show_debug_overlay`: Shows runtime state, visibility, and serving diagnostics above the mesh."
				]
			},
			{
				"title": "Runtime model",
				"lines": [
					"This package uses batched serving plans plus revision checks.",
					"Rotation and next-asset changes come from the server plan, not from a hidden local playlist.",
					"Godot video delivery requires a safe `.ogv` media variant."
				]
			}
		]
	},
	"nodes/AdMeshRuntime.gd": {
		"title": "AdMesh Runtime Guide",
		"summary": "This runtime is the placement coordinator for the Godot SDK. It batches active placements, requests serving plans, runs revision checks, and reduces redundant worker traffic.",
		"sections": [
			{
				"title": "What it owns",
				"lines": [
					"Registers and unregisters active placements.",
					"Fetches serving plans for the active ad-unit set.",
					"Runs batched revision checks instead of per-placement polling."
				]
			},
			{
				"title": "Developer guidance",
				"lines": [
					"Only active instantiated placements participate in runtime sync.",
					"Plan horizon and revision cadence are runtime-level behavior, not per-node overrides.",
					"If no SDK key is configured, the runtime remains inactive and placements stay on safe fallback behavior."
				]
			}
		]
	},
	"nodes/AdResourceManager.gd": {
		"title": "AdMesh Resource Manager Guide",
		"summary": "This manager is the runtime network and cache boundary for the Godot SDK. It owns creative downloads, cache policy, selector calls, and collector posts.",
		"sections": [
			{
				"title": "What it controls",
				"lines": [
					"`configure(...)` injects the SDK key, selector URL, collector URL, and runtime session.",
					"`request_plan_asset(...)` is the cached media path for images and supported videos.",
					"`fetch_serving_plan(...)` and `check_serving_revisions(...)` are the live worker coordination paths."
				]
			},
			{
				"title": "Developer guidance",
				"lines": [
					"Only override worker URLs when explicitly testing staging or a local contract change.",
					"Keep download limits conservative because oversized creatives hit startup time and memory first in Godot builds.",
					"Godot video delivery should use OGV-safe assets."
				]
			}
		]
	},
	"nodes/AdPoolManager.gd": {
		"title": "Ad Pool Manager Guide",
		"summary": "Use this helper when you want a managed local pool of fallback or curated assets rather than a single live placement node.",
		"sections": [
			{
				"title": "When to use it",
				"lines": [
					"Use a pool for controlled fallback loops, demo scenes, or curated placements that should keep rotating even without live fill.",
					"Use `MeshAdPlayer` directly when each surface should fetch its own live server plan."
				]
			}
		]
	},
	"nodes/AdMeshSDK.gd": {
		"title": "AdMesh SDK Entry Guide",
		"summary": "This is the high-level public entry point used to initialize or query the Godot SDK from game code.",
		"sections": [
			{
				"title": "What to keep in mind",
				"lines": [
					"Prefer a single project-wide initialization path.",
					"Use the same SDK key across placements that belong to the same app.",
					"Do not treat this layer as the place to hardcode billing or serving decisions; the worker remains authoritative."
				]
			}
		]
	}
}

func _can_handle(object: Object) -> bool:
	return HELP_BY_SCRIPT.has(_get_script_path(object))


func _parse_begin(object: Object) -> void:
	var script_path := _get_script_path(object)
	if not HELP_BY_SCRIPT.has(script_path):
		return

	var help_data: Dictionary = HELP_BY_SCRIPT[script_path]
	var panel := PanelContainer.new()
	panel.tooltip_text = "AdMesh inspector guidance for this SDK object."

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	margin.add_child(layout)

	var title := Label.new()
	title.text = str(help_data.get("title", "AdMesh Guide"))
	title.add_theme_font_size_override("font_size", 15)
	layout.add_child(title)

	var summary := RichTextLabel.new()
	summary.bbcode_enabled = true
	summary.fit_content = true
	summary.scroll_active = false
	summary.text = str(help_data.get("summary", ""))
	layout.add_child(summary)

	for section in help_data.get("sections", []):
		var section_title := Label.new()
		section_title.text = str(section.get("title", ""))
		section_title.add_theme_font_size_override("font_size", 13)
		layout.add_child(section_title)

		var body := RichTextLabel.new()
		body.bbcode_enabled = true
		body.fit_content = true
		body.scroll_active = false
		body.text = _format_lines(section.get("lines", []))
		layout.add_child(body)

	add_custom_control(panel)


func _get_script_path(object: Object) -> String:
	if object == null or object.get_script() == null:
		return ""
	var script: Script = object.get_script()
	return script.resource_path.trim_prefix("res://addons/AdMesh/")


func _format_lines(lines: Array) -> String:
	var formatted: PackedStringArray = []
	for line in lines:
		formatted.append("- %s" % str(line))
	return "\n".join(formatted)
