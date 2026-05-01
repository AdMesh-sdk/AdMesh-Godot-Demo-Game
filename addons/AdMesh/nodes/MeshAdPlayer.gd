@tool
@icon("res://addons/AdMesh/icon.jpeg")
class_name AdMeshNode
extends Node3D

const RETRY_AFTER_FAILURE_SECONDS := 60.0
const DEFAULT_PLACEHOLDER := preload("res://addons/AdMesh/AdMesh_Test_Poster_1.png")
const HOSTED_FALLBACK_IMAGE_URL := "https://assets.admesh.cloud/system/test-assets/admesh-test-image.png"

enum AspectRatioPreset {
	LANDSCAPE_16_9,
	SQUARE_1_1,
	PORTRAIT_9_16,
	CUSTOM,
}

enum PlacementState {
	IDLE,
	LOADING,
	ACTIVE,
	EXPIRED,
	FAILED,
}

@export_group("AdMesh Setup")
@export var sdk_key: String = "":
	get:
		return ProjectSettings.get_setting("admesh/config/sdk_key", "")
	set(value):
		ProjectSettings.set_setting("admesh/config/sdk_key", value)
		ProjectSettings.save()
@export var ad_unit_id: String = ""
@export var use_real_ads := false
@export var auto_load_on_ready := true
@export_enum("16:9 Landscape", "1:1 Square", "9:16 Portrait", "Custom") var aspect_ratio_preset: int = AspectRatioPreset.LANDSCAPE_16_9:
	set(value):
		aspect_ratio_preset = value
		if Engine.is_editor_hint():
			_apply_mesh_shape()
@export var custom_quad_size := Vector2(1.6, 0.9):
	set(value):
		custom_quad_size = Vector2(max(value.x, 0.1), max(value.y, 0.1))
		if Engine.is_editor_hint():
			_apply_mesh_shape()

@export_group("Display")
@export var placeholder_texture: Texture2D = DEFAULT_PLACEHOLDER
@export var force_unshaded_material := true:
	set(value):
		force_unshaded_material = value
		if Engine.is_editor_hint():
			_update_material_flags()
@export var double_sided := false:
	set(value):
		double_sided = value
		if Engine.is_editor_hint():
			_update_material_flags()

@export_group("Audio")
@export var enable_audio := false
@export_range(1.0, 250.0, 1.0, "suffix:m") var audio_max_distance := 24.0
@export_range(-40.0, 6.0, 0.5, "suffix:dB") var audio_volume_db := -8.0

@export_group("Delivery Proof")
@export var track_presence := true
@export_range(30.0, 900.0, 5.0, "suffix:s") var report_interval_seconds := 300.0

@export_group("Proximity Analytics")
@export var track_proximity := true
@export var use_audio_range_for_proximity := true
@export_range(1.0, 250.0, 1.0, "suffix:m") var proximity_radius := 24.0
@export_range(0.5, 30.0, 0.5, "suffix:s") var qualified_exposure_threshold_seconds := 3.0

@export_group("Advanced")
@export var refresh_while_online := true

@export_group("Debug")
@export var show_debug_overlay := false

signal ad_loaded(ad_data: Dictionary)
signal ad_failed(reason: String)

# Internal nodes — all owned, not exposed to the inspector
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _debug_label: Label3D
var _resource_manager: AdResourceManager
var _current_ad: Dictionary = {}
var _current_session_id := ""
var _video_player: VideoStreamPlayer
var _video_viewport: SubViewport
var _report_timer := 0.0
var _pending_visible_seconds := 0.0
var _current_valid_until_unix := 0.0
var _current_refresh_after_unix := 0.0
var _next_retry_unix := 0.0
var _state := PlacementState.IDLE
var _reported_creative_key := ""
var _uses_external_mesh := false
var _last_status_reason := ""
var _is_loading_hosted_fallback := false
var _serving_plan: Array = []
var _serving_revision := ""
var _plan_valid_until_unix := 0.0
var _current_slot_index := -1
var _pending_slot_asset_key := ""
var _pending_slot_index := -1
var _prefetched_asset_key := ""
var _prefetch_in_flight := false
var _proximity_inside_zone := false
var _current_proximity_dwell := 0.0
var _pending_proximity_entries := 0
var _pending_repeat_entries := 0
var _pending_qualified_exposures := 0
var _pending_proximity_dwell_seconds := 0.0
var _pending_proximity_active_duration_seconds := 0.0
var _proximity_report_timer := 0.0
var _lifetime_proximity_entries := 0


func _enter_tree() -> void:
	_ensure_mesh_ready()


func _ready() -> void:
	_ensure_mesh_ready()
	_setup_debug_overlay()
	_apply_placeholder_texture()
	_log("placement ready unit=%s live=%s auto_load=%s" % [ad_unit_id, str(use_real_ads), str(auto_load_on_ready)])
	var runtime: Node = _get_runtime()
	if runtime != null and runtime.has_method("register_placement"):
		runtime.register_placement(self, not use_real_ads)
	if not Engine.is_editor_hint() and use_real_ads and auto_load_on_ready and (runtime == null or not runtime.has_method("register_placement")):
		call_deferred("fetch_and_display_ad")


func _exit_tree() -> void:
	var runtime: Node = _get_runtime()
	if runtime != null and runtime.has_method("unregister_placement"):
		runtime.unregister_placement(self)


func fetch_and_display_ad() -> void:
	if ad_unit_id.strip_edges() == "":
		_fail_and_fallback("Ad Unit ID is required")
		return

	var runtime: Node = _get_runtime()
	if runtime == null or not runtime.is_initialized():
		_fail_and_fallback("Set your SDK key in Project Settings > AdMesh > Config before loading live ads")
		return

	_log("requesting ad unit=%s session=%s" % [ad_unit_id, str(runtime.get_session_id())])
	_state = PlacementState.LOADING
	if runtime.has_method("request_immediate_sync"):
		runtime.request_immediate_sync()
	else:
		_load_ad()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if not use_real_ads:
		_update_debug()
		return

	var now := Time.get_unix_time_from_system()
	if has_serving_plan():
		_handle_serving_plan_lifecycle(now)
	else:
		_handle_lease_lifecycle(now)
	_update_audio()

	if _state == PlacementState.LOADING:
		_update_debug()
		return

	if track_presence and _state == PlacementState.ACTIVE and not _current_ad.is_empty():
		var creative_key := _get_creative_key(_current_ad)
		if creative_key != "":
			if creative_key != _reported_creative_key:
				_reset_presence_window()
				_reported_creative_key = creative_key

			if is_visible_in_tree():
				_pending_visible_seconds += delta

			_report_timer += delta
			if _report_timer >= report_interval_seconds:
				_report_timer = 0.0
				var runtime: Node = _get_runtime()
				if runtime != null and runtime.is_initialized():
					runtime.report_presence(_current_ad, ad_unit_id, _pending_visible_seconds, _current_session_id, {
						"signal_mode": "session_heartbeat",
						"creative_type": _current_ad.get("media_type", ""),
						"creative_version": _get_creative_key(_current_ad),
						"state": PlacementState.keys()[_state],
						"override_id": _current_ad.get("override_id", ""),
					})
				_pending_visible_seconds = 0.0

	if track_proximity and _state == PlacementState.ACTIVE and not _current_ad.is_empty():
		_update_proximity(delta)

	_update_debug()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_flush_presence_report()
		_flush_proximity_report()


func _load_ad() -> void:
	_state = PlacementState.LOADING
	_last_status_reason = ""
	_update_debug()

	var runtime: Node = _get_runtime()
	if runtime == null:
		_fail_and_fallback("AdMesh runtime is unavailable")
		return

	var current_media_url := str(_current_ad.get("media_url", ""))
	var current_creative_key := _get_creative_key(_current_ad)
	var ad: Dictionary = await runtime.fetch_ad(ad_unit_id, {
		"ad_format": "video",
		"test_mode": not use_real_ads,
		"session_id": runtime.get_session_id(),
	})
	_log("selector response unit=%s empty=%s source=%s schedule=%s media=%s" % [
		ad_unit_id,
		str(ad.is_empty()),
		str(ad.get("delivery_mode", ad.get("source", ""))),
		str(ad.get("schedule_id", "")),
		str(ad.get("media_url", "")),
	])

	if ad.is_empty():
		if _has_active_lease(Time.get_unix_time_from_system()):
			_schedule_retry()
			_state = PlacementState.ACTIVE
			_log("selector empty, keeping cached creative within lease")
			return
		_fail_and_fallback("No ad fill available")
		return

	_apply_lease(ad)
	_current_session_id = runtime.get_session_id()
	var next_media_url := str(ad.get("media_url", "")).strip_edges()
	if next_media_url == "":
		_fail_and_fallback("Ad is missing media_url")
		return

	var next_creative_key := _get_creative_key(ad)
	if current_creative_key != "" and current_creative_key == next_creative_key and current_media_url == next_media_url:
		_current_ad = ad
		_state = PlacementState.ACTIVE
		_last_status_reason = ""
		_update_debug()
		return

	_current_ad = ad.duplicate(true)
	_reset_presence_window()
	_resource_manager = runtime.get_resource_manager()
	if _resource_manager == null:
		_fail_and_fallback("AdMesh resource manager is unavailable after ad selection")
		return
	_log("requesting media type=%s url=%s" % [str(_current_ad.get("media_type", "")), next_media_url])
	_resource_manager.request_media(next_media_url, Callable(self, "_on_media_ready"))


func _handle_lease_lifecycle(now_unix: float) -> void:
	if _current_valid_until_unix > 0.0 and now_unix >= _current_valid_until_unix:
		_expire_current_creative("Creative lease expired")
		return

	if _next_retry_unix > 0.0 and now_unix >= _next_retry_unix:
		_next_retry_unix = 0.0
		if use_real_ads:
			_load_ad()
		return

	if refresh_while_online and _current_refresh_after_unix > 0.0 and now_unix >= _current_refresh_after_unix:
		_current_refresh_after_unix = 0.0
		if use_real_ads:
			_load_ad()


func apply_serving_plan(placement_plan: Dictionary) -> void:
	_serving_plan = placement_plan.get("slots", [])
	_serving_revision = str(placement_plan.get("serving_revision", ""))
	_plan_valid_until_unix = _parse_iso_unix(str(placement_plan.get("plan_valid_until", "")), Time.get_unix_time_from_system() + 180.0)
	_current_slot_index = -1
	_pending_slot_index = -1
	_prefetched_asset_key = ""
	_prefetch_in_flight = false
	_log("serving plan applied slots=%s revision=%s valid_until=%s" % [
		str(_serving_plan.size()),
		_serving_revision,
		str(placement_plan.get("plan_valid_until", "")),
	])
	_apply_current_plan_slot(Time.get_unix_time_from_system(), true)


func has_serving_plan() -> bool:
	return not _serving_plan.is_empty()


func get_plan_valid_until_unix() -> float:
	return _plan_valid_until_unix


func get_serving_revision() -> String:
	return _serving_revision


func is_likely_active() -> bool:
	return is_visible_in_tree()


func _handle_serving_plan_lifecycle(now_unix: float) -> void:
	_apply_current_plan_slot(now_unix, false)
	var next_slot := _get_next_plan_slot(now_unix)
	if next_slot.is_empty():
		return
	var seconds_until_next := _parse_iso_unix(str(next_slot.get("slot_start", "")), now_unix + 5.0) - now_unix
	if seconds_until_next >= 0.0 and seconds_until_next <= 3.0:
		_prefetch_plan_slot(next_slot)


func _apply_current_plan_slot(now_unix: float, force: bool) -> void:
	var next_slot_index := _get_slot_index_for_time(now_unix)
	if next_slot_index < 0:
		var runtime: Node = _get_runtime()
		if runtime != null and runtime.has_method("request_immediate_sync") and _plan_valid_until_unix > 0.0 and now_unix >= _plan_valid_until_unix:
			runtime.request_immediate_sync()
		return

	var slot: Dictionary = _serving_plan[next_slot_index]
	var slot_asset_key := _build_asset_key(str(slot.get("asset_id", "")), str(slot.get("asset_version", "")))
	var current_asset_key := _build_asset_key(str(_current_ad.get("id", "")), str(_current_ad.get("creative_version", "")))

	if _state == PlacementState.LOADING and _pending_slot_index == next_slot_index and _pending_slot_asset_key == slot_asset_key:
		return

	if not force and next_slot_index == _current_slot_index and slot_asset_key == current_asset_key:
		return

	_current_slot_index = next_slot_index
	_apply_plan_lease(slot)

	if not force and slot_asset_key == current_asset_key:
		_current_ad = _build_creative_from_plan_slot(slot)
		_state = PlacementState.ACTIVE
		_last_status_reason = ""
		_update_debug()
		_log("serving plan retained current asset=%s until=%s" % [str(slot.get("asset_name", "")), str(slot.get("slot_end", ""))])
		return

	_load_planned_slot(slot)


func _get_slot_index_for_time(now_unix: float) -> int:
	for index in range(_serving_plan.size()):
		var slot: Dictionary = _serving_plan[index]
		var slot_start := _parse_iso_unix(str(slot.get("slot_start", "")), now_unix)
		var slot_end := _parse_iso_unix(str(slot.get("slot_end", "")), now_unix + 5.0)
		if now_unix >= slot_start and now_unix < slot_end:
			return index
	return _serving_plan.size() - 1 if not _serving_plan.is_empty() else -1


func _get_next_plan_slot(now_unix: float) -> Dictionary:
	var current_index := _get_slot_index_for_time(now_unix)
	if current_index >= 0 and current_index + 1 < _serving_plan.size():
		return _serving_plan[current_index + 1]
	return {}


func _apply_plan_lease(slot: Dictionary) -> void:
	var slot_end := _parse_iso_unix(str(slot.get("slot_end", "")), Time.get_unix_time_from_system() + 5.0)
	var slot_start := _parse_iso_unix(str(slot.get("slot_start", "")), Time.get_unix_time_from_system())
	_current_valid_until_unix = slot_end
	_current_refresh_after_unix = slot_end
	_next_retry_unix = 0.0
	_log("plan slot active asset=%s start=%s end=%s loop=%s" % [
		str(slot.get("asset_name", "")),
		str(slot.get("slot_start", "")),
		str(slot.get("slot_end", "")),
		str(slot.get("loop_flag", true)),
	])


func _load_planned_slot(slot: Dictionary) -> void:
	if _resource_manager == null:
		var runtime: Node = _get_runtime()
		if runtime != null:
			_resource_manager = runtime.get_resource_manager()
	if _resource_manager == null:
		_fail_and_fallback("AdMesh resource manager is unavailable for serving plan slot")
		return

	var pending_asset_key := _build_asset_key(str(slot.get("asset_id", "")), str(slot.get("asset_version", "")))
	var pending_slot_index := _get_slot_index_for_time(Time.get_unix_time_from_system())
	if _state == PlacementState.LOADING and _pending_slot_asset_key == pending_asset_key and _pending_slot_index == pending_slot_index:
		return

	_state = PlacementState.LOADING
	_last_status_reason = ""
	_pending_slot_asset_key = pending_asset_key
	_pending_slot_index = pending_slot_index
	_resource_manager.request_plan_asset(
		str(slot.get("asset_id", "")),
		str(slot.get("asset_version", "")),
		str(slot.get("media_type", "")),
		str(slot.get("media_url", "")),
		Callable(self, "_on_plan_media_ready").bind(_pending_slot_asset_key, slot)
	)
	_update_debug()


func _on_plan_media_ready(url: String, media_type: String, resource: Variant, requested_asset_key: String, slot: Dictionary) -> void:
	if _pending_slot_asset_key != requested_asset_key:
		return
	_pending_slot_asset_key = ""
	_pending_slot_index = -1
	if media_type == "":
		_fail_and_fallback("Failed to load planned asset %s" % str(slot.get("asset_name", "")))
		return

	_current_ad = _build_creative_from_plan_slot(slot)
	_reset_presence_window()

	match media_type:
		"image":
			_material.albedo_texture = resource
			_apply_material_to_target()
			_stop_video_if_needed()
		"video":
			if not url.to_lower().ends_with(".ogv"):
				_fail_and_fallback("Godot currently supports .ogv videos only")
				return
			_setup_video_player(str(resource), bool(slot.get("loop_flag", true)))
		_:
			_fail_and_fallback("Unsupported planned media type")
			return

	_state = PlacementState.ACTIVE
	_last_status_reason = ""
	_is_loading_hosted_fallback = false
	_log("plan render success unit=%s asset=%s source=%s url=%s" % [
		ad_unit_id,
		str(slot.get("asset_name", "")),
		str(slot.get("source", "")),
		str(slot.get("media_url", "")),
	])
	_update_debug()


func _prefetch_plan_slot(slot: Dictionary) -> void:
	if _prefetch_in_flight or _resource_manager == null:
		return
	var asset_key := _build_asset_key(str(slot.get("asset_id", "")), str(slot.get("asset_version", "")))
	if asset_key == _prefetched_asset_key:
		return
	var current_asset_key := _build_asset_key(str(_current_ad.get("id", "")), str(_current_ad.get("creative_version", "")))
	if asset_key == current_asset_key:
		return
	_prefetch_in_flight = true
	_resource_manager.request_plan_asset(
		str(slot.get("asset_id", "")),
		str(slot.get("asset_version", "")),
		str(slot.get("media_type", "")),
		str(slot.get("media_url", "")),
		Callable(self, "_on_prefetch_plan_asset_ready").bind(asset_key, slot)
	)


func _on_prefetch_plan_asset_ready(_url: String, media_type: String, _resource: Variant, asset_key: String, slot: Dictionary) -> void:
	_prefetch_in_flight = false
	if media_type == "":
		return
	_prefetched_asset_key = asset_key
	_log("prefetched next asset=%s" % str(slot.get("asset_name", "")))


func _build_creative_from_plan_slot(slot: Dictionary) -> Dictionary:
	return {
		"id": str(slot.get("asset_id", "")),
		"name": str(slot.get("asset_name", "")),
		"media_url": str(slot.get("media_url", "")),
		"media_type": str(slot.get("media_type", "")),
		"type": str(slot.get("media_type", "")),
		"delivery_mode": "fallback",
		"source": str(slot.get("source", "")),
		"valid_until": str(slot.get("slot_end", "")),
		"refresh_after": str(slot.get("slot_end", "")),
		"creative_version": str(slot.get("asset_version", "")),
		"current_asset_id": str(slot.get("asset_id", "")),
		"current_asset_name": str(slot.get("asset_name", "")),
		"next_change_at": str(slot.get("slot_end", "")),
		"video_loop_enabled": bool(slot.get("loop_flag", true)),
		"serving_enabled": true,
	}


func _build_asset_key(asset_id: String, asset_version: String) -> String:
	var normalized_id := asset_id.strip_edges()
	if normalized_id == "":
		normalized_id = "asset"
	var normalized_version := asset_version.strip_edges()
	if normalized_version == "":
		normalized_version = "v1"
	return "%s__%s" % [normalized_id, normalized_version]


func _apply_lease(ad: Dictionary) -> void:
	_current_valid_until_unix = _parse_iso_unix(str(ad.get("valid_until", "")), Time.get_unix_time_from_system() + 600.0)
	_current_refresh_after_unix = _parse_iso_unix(str(ad.get("refresh_after", "")), min(_current_valid_until_unix, Time.get_unix_time_from_system() + 300.0))
	_next_retry_unix = 0.0


func _has_active_lease(now_unix: float) -> bool:
	return not _current_ad.is_empty() and _current_valid_until_unix > now_unix


func _schedule_retry() -> void:
	if not use_real_ads:
		return
	_next_retry_unix = Time.get_unix_time_from_system() + RETRY_AFTER_FAILURE_SECONDS


func _on_media_ready(url: String, media_type: String, resource: Variant) -> void:
	var expected_url := str(_current_ad.get("media_url", ""))
	if url != expected_url:
		return

	if media_type == "":
		_log("media load failed for url=%s" % url)
		if _has_active_lease(Time.get_unix_time_from_system()):
			_schedule_retry()
			_state = PlacementState.ACTIVE
			_log("media failed, keeping cached creative within lease")
			return
		_fail_and_fallback("Failed to load creative media")
		return

	match media_type:
		"image":
			_material.albedo_texture = resource
			_apply_material_to_target()
			_stop_video_if_needed()
		"video":
			if not url.to_lower().ends_with(".ogv"):
				_fail_and_fallback("Godot currently supports .ogv videos only")
				return
			_setup_video_player(str(resource))
		_:
			_fail_and_fallback("Unsupported media type")
			return

	_state = PlacementState.ACTIVE
	_last_status_reason = ""
	_is_loading_hosted_fallback = false
	_log("render success unit=%s source=%s schedule=%s url=%s" % [
		ad_unit_id,
		str(_current_ad.get("delivery_mode", _current_ad.get("source", ""))),
		str(_current_ad.get("schedule_id", "")),
		str(_current_ad.get("media_url", "")),
	])
	_send_impression_if_needed()
	_update_debug()
	ad_loaded.emit(_current_ad)


func _flush_presence_report() -> void:
	if _current_ad.is_empty() or _pending_visible_seconds <= 0.0:
		_report_timer = 0.0
		_pending_visible_seconds = 0.0
		return

	var runtime: Node = _get_runtime()
	if runtime == null:
		return

	runtime.report_presence(_current_ad, ad_unit_id, _pending_visible_seconds, _current_session_id, {
		"signal_mode": "session_heartbeat",
		"creative_type": _current_ad.get("media_type", ""),
		"creative_version": _get_creative_key(_current_ad),
		"state": PlacementState.keys()[_state],
		"override_id": _current_ad.get("override_id", ""),
	})
	_log("heartbeat sent unit=%s seconds=%s schedule=%s" % [
		ad_unit_id,
		str(snappedf(_pending_visible_seconds, 0.01)),
		str(_current_ad.get("schedule_id", "")),
	])
	_report_timer = 0.0
	_pending_visible_seconds = 0.0


func _update_proximity(delta: float) -> void:
	var runtime: Node = _get_runtime()
	if runtime == null or not runtime.has_method("has_tracker_position") or not runtime.has_tracker_position():
		_exit_proximity_zone_if_needed()
		return

	var radius := audio_max_distance if use_audio_range_for_proximity else proximity_radius
	var tracker_position: Vector3 = runtime.get_tracker_position()
	var inside_zone := global_position.distance_to(tracker_position) <= max(radius, 0.1)

	if inside_zone:
		if not _proximity_inside_zone:
			_proximity_inside_zone = true
			_pending_proximity_entries += 1
			if _lifetime_proximity_entries > 0:
				_pending_repeat_entries += 1
			_lifetime_proximity_entries += 1
		_current_proximity_dwell += delta
		_pending_proximity_dwell_seconds += delta
		_pending_proximity_active_duration_seconds += delta
	else:
		_exit_proximity_zone_if_needed()

	_proximity_report_timer += delta
	if _proximity_report_timer >= report_interval_seconds:
		_flush_proximity_report()


func _exit_proximity_zone_if_needed() -> void:
	if not _proximity_inside_zone:
		return
	if _current_proximity_dwell >= qualified_exposure_threshold_seconds:
		_pending_qualified_exposures += 1
	_proximity_inside_zone = false
	_current_proximity_dwell = 0.0


func _flush_proximity_report() -> void:
	_exit_proximity_zone_if_needed()
	if _current_ad.is_empty():
		_reset_proximity_window()
		return
	if _pending_proximity_entries <= 0 and _pending_repeat_entries <= 0 and _pending_qualified_exposures <= 0 and _pending_proximity_dwell_seconds <= 0.0:
		_proximity_report_timer = 0.0
		return

	var runtime: Node = _get_runtime()
	if runtime != null and runtime.has_method("report_proximity"):
		runtime.report_proximity(_current_ad, ad_unit_id, {
			"radius_meters": audio_max_distance if use_audio_range_for_proximity else proximity_radius,
			"qualified_dwell_threshold_seconds": qualified_exposure_threshold_seconds,
			"entries": _pending_proximity_entries,
			"repeat_entries": _pending_repeat_entries,
			"total_dwell_seconds": snappedf(_pending_proximity_dwell_seconds, 0.01),
			"qualified_exposure_count": _pending_qualified_exposures,
			"active_duration_seconds": snappedf(_pending_proximity_active_duration_seconds, 0.01),
		}, _current_session_id, {
			"state": PlacementState.keys()[_state],
		})

	_reset_proximity_window()


func _reset_proximity_window() -> void:
	_proximity_report_timer = 0.0
	_pending_proximity_entries = 0
	_pending_repeat_entries = 0
	_pending_qualified_exposures = 0
	_pending_proximity_dwell_seconds = 0.0
	_pending_proximity_active_duration_seconds = 0.0


func _send_impression_if_needed() -> void:
	var creative_key := _get_creative_key(_current_ad)
	if creative_key == "":
		return
	var runtime: Node = _get_runtime()
	if runtime == null:
		return
	_log("impression sent unit=%s schedule=%s source=%s" % [
		ad_unit_id,
		str(_current_ad.get("schedule_id", "")),
		str(_current_ad.get("delivery_mode", _current_ad.get("source", ""))),
	])
	runtime.report_impression(_current_ad, ad_unit_id, _current_session_id)


func _expire_current_creative(reason: String) -> void:
	_flush_presence_report()
	_flush_proximity_report()
	_current_ad = {}
	_current_valid_until_unix = 0.0
	_current_refresh_after_unix = 0.0
	_reported_creative_key = ""
	_last_status_reason = reason
	_proximity_inside_zone = false
	_current_proximity_dwell = 0.0
	_stop_video_if_needed()
	_apply_placeholder_texture()
	_state = PlacementState.EXPIRED
	_log("creative expired unit=%s reason=%s" % [ad_unit_id, reason])
	_update_debug()
	ad_failed.emit(reason)


func _fail_and_fallback(reason: String) -> void:
	_schedule_retry()
	_last_status_reason = reason
	_log("failure unit=%s reason=%s" % [ad_unit_id, reason])
	if _try_load_hosted_fallback(reason):
		_state = PlacementState.LOADING
	else:
		_apply_placeholder_texture()
		_state = PlacementState.ACTIVE
	_update_debug()
	ad_failed.emit(reason)


func _reset_presence_window() -> void:
	_report_timer = 0.0
	_pending_visible_seconds = 0.0
	_reset_proximity_window()


func _get_creative_key(ad_data: Dictionary) -> String:
	if ad_data.is_empty():
		return ""
	var creative_version := str(ad_data.get("creative_version", "")).strip_edges()
	if creative_version != "":
		return creative_version
	var override_id := str(ad_data.get("override_id", "")).strip_edges()
	if override_id != "":
		return override_id
	var schedule_id := str(ad_data.get("schedule_id", "")).strip_edges()
	if schedule_id != "":
		return schedule_id
	return str(ad_data.get("id", "")).strip_edges()


func _parse_iso_unix(value: String, fallback_unix: float) -> float:
	if value.strip_edges() == "":
		return fallback_unix
	var parsed := Time.get_unix_time_from_datetime_string(value)
	return parsed if parsed > 0.0 else fallback_unix


# ── Mesh / Material Setup ──────────────────────────────────────────────────────

func _ensure_mesh_ready() -> void:
	var self_candidate: Object = self
	var parent := get_parent()
	_uses_external_mesh = false

	var self_mesh := _try_as_mesh_instance(self_candidate)
	var parent_mesh := _try_as_mesh_instance(parent)

	if self_mesh != null:
		_mesh_instance = self_mesh
	elif parent_mesh != null and parent_mesh != _mesh_instance:
		_mesh_instance = parent_mesh
		_uses_external_mesh = true
	elif _mesh_instance == null or not is_instance_valid(_mesh_instance):
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "AdMeshQuad"
		add_child(_mesh_instance)

	if _material == null:
		_material = StandardMaterial3D.new()

	_update_material_flags()
	if _mesh_instance.mesh == null and not _uses_external_mesh:
		_apply_mesh_shape()
	_apply_material_to_target()


func _apply_mesh_shape() -> void:
	if _mesh_instance == null or _uses_external_mesh:
		return
	var quad := QuadMesh.new()
	quad.size = _resolve_quad_size()
	_mesh_instance.mesh = quad


func _resolve_quad_size() -> Vector2:
	match aspect_ratio_preset:
		AspectRatioPreset.SQUARE_1_1:
			return Vector2(1.0, 1.0)
		AspectRatioPreset.PORTRAIT_9_16:
			return Vector2(0.9, 1.6)
		AspectRatioPreset.CUSTOM:
			return Vector2(max(custom_quad_size.x, 0.1), max(custom_quad_size.y, 0.1))
		_:
			return Vector2(1.6, 0.9)


func _update_material_flags() -> void:
	if _material == null:
		return
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if force_unshaded_material else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED if double_sided else BaseMaterial3D.CULL_BACK
	_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


func _apply_placeholder_texture() -> void:
	if _material == null:
		_ensure_mesh_ready()
	if placeholder_texture != null:
		_material.albedo_texture = placeholder_texture
	else:
		_material.albedo_texture = DEFAULT_PLACEHOLDER
	_apply_material_to_target()
	_log("rendering bundled placeholder unit=%s" % ad_unit_id)


func _apply_material_to_target() -> void:
	if _mesh_instance == null or _material == null:
		return

	if _mesh_instance.mesh != null and _mesh_instance.mesh.get_surface_count() > 0:
		_mesh_instance.set_surface_override_material(0, _material)
	else:
		_mesh_instance.material_override = _material


func _try_as_mesh_instance(node: Object) -> Variant:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node
	return null


func _try_load_hosted_fallback(reason: String) -> bool:
	if _is_loading_hosted_fallback:
		return false
	var runtime: Node = _get_runtime()
	if runtime == null or not runtime.is_initialized():
		return false
	_resource_manager = runtime.get_resource_manager()
	if _resource_manager == null:
		return false
	_is_loading_hosted_fallback = true
	_current_ad = {
		"id": "system-test-image",
		"name": "AdMesh Hosted Fallback",
		"media_url": HOSTED_FALLBACK_IMAGE_URL,
		"media_type": "image",
		"type": "image",
		"campaign_id": "system-test-fill",
		"package_type": "DTL",
		"delivery_mode": "fallback",
		"schedule_id": "",
		"creative_version": "system-test-image-v1",
	}
	_log("rendering hosted fallback unit=%s reason=%s url=%s" % [ad_unit_id, reason, HOSTED_FALLBACK_IMAGE_URL])
	_resource_manager.request_media(HOSTED_FALLBACK_IMAGE_URL, Callable(self, "_on_media_ready"))
	return true


func _log(message: String) -> void:
	print("[AdMesh] %s" % message)


# ── Video ──────────────────────────────────────────────────────────────────────

func _setup_video_player(video_path: String, should_loop: bool = true) -> void:
	if _video_player != null:
		_video_player.queue_free()
		_video_player = null
	if _video_viewport != null:
		_video_viewport.queue_free()
		_video_viewport = null

	_video_viewport = SubViewport.new()
	_video_viewport.size = Vector2i(1280, 720)
	add_child(_video_viewport)

	_video_player = VideoStreamPlayer.new()
	_video_player.expand = true
	_video_player.custom_minimum_size = Vector2(1280, 720)
	_video_player.volume_db = audio_volume_db if enable_audio else -80.0
	_video_viewport.add_child(_video_player)

	var stream := VideoStreamTheora.new()
	stream.file = video_path
	_video_player.stream = stream
	_video_player.loop = should_loop
	_video_player.play()
	_material.albedo_texture = _video_viewport.get_texture()


func _stop_video_if_needed() -> void:
	if _video_player != null:
		_video_player.stop()
		_video_player.volume_db = -80.0


# ── Audio ──────────────────────────────────────────────────────────────────────

func _update_audio() -> void:
	if _video_player == null:
		return

	if not enable_audio:
		_video_player.volume_db = -80.0
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_video_player.volume_db = -80.0
		return

	var distance := global_position.distance_to(camera.global_position)
	if distance >= audio_max_distance:
		_video_player.volume_db = -80.0
		return

	var normalized := clampf(distance / max(audio_max_distance, 0.001), 0.0, 1.0)
	_video_player.volume_db = lerpf(audio_volume_db, -24.0, normalized)


# ── Debug Overlay ──────────────────────────────────────────────────────────────

func _update_debug() -> void:
	if _debug_label == null:
		return

	var runtime: Node = _get_runtime()
	var runtime_ready: bool = runtime != null and runtime.is_initialized()
	_debug_label.text = "AdMesh\nstate: %s\nunit: %s\nlive: %s\nsdk: %s" % [
		PlacementState.keys()[_state],
		ad_unit_id if ad_unit_id != "" else "(unset)",
		"yes" if use_real_ads else "no",
		"ready" if runtime_ready else "missing",
	]
	var source := str(_current_ad.get("delivery_mode", _current_ad.get("source", ""))).strip_edges()
	if source != "":
		_debug_label.text += "\nsource: %s" % source
	if _last_status_reason != "":
		_debug_label.text += "\nreason: %s" % _last_status_reason


func _setup_debug_overlay() -> void:
	if not show_debug_overlay:
		if _debug_label != null:
			_debug_label.queue_free()
			_debug_label = null
		return

	if _debug_label == null:
		_debug_label = Label3D.new()
		_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_debug_label.position = Vector3(0, 0.7, 0)
		_debug_label.font_size = 22
		add_child(_debug_label)

	_update_debug()


# ── Runtime Access ─────────────────────────────────────────────────────────────

func _get_runtime() -> Node:
	return get_node_or_null("/root/AdMeshRuntime")


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if sdk_key.strip_edges() == "":
		warnings.append("SDK Key is required. Paste your key into the 'Sdk Key' field above.")
	if ad_unit_id.strip_edges() == "":
		warnings.append("Set Ad Unit ID before expecting live delivery.")
	var runtime: Node = _get_runtime()
	if use_real_ads and (runtime == null or not runtime.is_initialized()):
		warnings.append("Live ads enabled but SDK key not applied yet. Enter your SDK Key in the inspector.")
	return warnings


