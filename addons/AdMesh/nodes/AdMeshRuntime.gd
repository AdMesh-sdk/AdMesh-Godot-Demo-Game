@tool
extends Node

const SDK_VERSION := "0.2.4"
const DEFAULT_AD_SELECTOR_URL := "https://select.admesh.cloud"
const DEFAULT_EVENT_COLLECTOR_URL := "https://events.admesh.cloud"
const PLAN_HORIZON_SECONDS := 180
const PLAN_REFRESH_MARGIN_SECONDS := 30.0
const ACTIVE_REVISION_CHECK_SECONDS := 35.0
const QUIET_REVISION_CHECK_SECONDS := 75.0
const PLAN_APPLY_STAGGER_SECONDS := 0.2

var _ad_selector_url: String = DEFAULT_AD_SELECTOR_URL
var _event_collector_url: String = DEFAULT_EVENT_COLLECTOR_URL
var _sdk_key: String = ""
var _session_id: String = ""
var _initialized := false
var _resource_manager: AdResourceManager
var _resource_manager_pending := false
var _registered_placements: Dictionary = {}
var _next_revision_check_unix := 0.0
var _plan_fetch_in_flight := 0
var _revision_check_in_flight := 0
var _tracker_position := Vector3.ZERO
var _tracker_available := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_sdk_key = ProjectSettings.get_setting("admesh/config/sdk_key", "")
	_ad_selector_url = ProjectSettings.get_setting("admesh/advanced/ad_selector_url", DEFAULT_AD_SELECTOR_URL)
	_event_collector_url = ProjectSettings.get_setting("admesh/advanced/event_collector_url", DEFAULT_EVENT_COLLECTOR_URL)
	_log("runtime boot sdk_present=%s selector=%s collector=%s" % [
		str(_sdk_key.strip_edges() != ""),
		_ad_selector_url,
		_event_collector_url,
	])

	if _sdk_key.strip_edges() != "":
		_session_id = "%s-%s" % [str(Time.get_unix_time_from_system()), str(randi())]
		_initialized = true
		await _ensure_resource_manager()
		if _resource_manager != null:
			_resource_manager.configure(_sdk_key, _ad_selector_url, _event_collector_url, _session_id)
			_log("runtime initialized session=%s" % _session_id)
	else:
		_log("runtime not initialized because sdk_key is missing")
	set_process(true)


func is_initialized() -> bool:
	return _initialized


func get_sdk_key() -> String:
	return _sdk_key


func get_session_id() -> String:
	return _session_id


func get_ad_selector_url() -> String:
	return _ad_selector_url


func get_event_collector_url() -> String:
	return _event_collector_url


func get_resource_manager() -> AdResourceManager:
	if _resource_manager == null or not is_instance_valid(_resource_manager):
		_resource_manager = get_node_or_null("AdMeshResourceManager")
	return _resource_manager


func get_runtime_summary() -> Dictionary:
	return {
		"sdk_key_present": _sdk_key.strip_edges() != "",
		"sdk_version": SDK_VERSION,
		"selector_host": _ad_selector_url,
		"collector_host": _event_collector_url,
		"initialized": _initialized,
	}


func fetch_ad(ad_unit_id: String, request_context: Dictionary = {}) -> Dictionary:
	if not _initialized:
		push_warning("[AdMesh] SDK Key missing. Set it in Project Settings > admesh/config/sdk_key")
		return {}
	await _ensure_resource_manager()
	if _resource_manager == null:
		_log("fetch_ad failed because resource manager is unavailable")
		return {}
	return await _resource_manager.fetch_ad(ad_unit_id, request_context)


func register_placement(placement: Node, test_mode: bool = false) -> void:
	if placement == null:
		return
	var ad_unit := str(placement.get("ad_unit_id")).strip_edges()
	if ad_unit == "":
		return
	_registered_placements[ad_unit] = {
		"node": placement,
		"test_mode": test_mode,
		"active": true,
	}
	request_immediate_sync()


func unregister_placement(placement: Node) -> void:
	if placement == null:
		return
	var ad_unit := str(placement.get("ad_unit_id")).strip_edges()
	if ad_unit == "":
		return
	_registered_placements.erase(ad_unit)


func set_placement_active(placement: Node, active: bool) -> void:
	if placement == null:
		return
	var ad_unit := str(placement.get("ad_unit_id")).strip_edges()
	if ad_unit == "":
		return
	if _registered_placements.has(ad_unit):
		_registered_placements[ad_unit]["active"] = active
		if active:
			request_immediate_sync()


func request_immediate_sync() -> void:
	_next_revision_check_unix = 0.0


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _initialized or _resource_manager == null:
		return
	if _plan_fetch_in_flight > 0 or _revision_check_in_flight > 0:
		return

	var active_bindings := _get_active_bindings()
	if active_bindings.is_empty():
		return

	var now := Time.get_unix_time_from_system()
	if _needs_plan_refresh(active_bindings, now):
		_fetch_full_plans(active_bindings)
		return

	if _next_revision_check_unix <= 0.0 or now >= _next_revision_check_unix:
		_check_revisions(active_bindings)


func report_impression(ad_data: Dictionary, ad_unit_id: String, session_id: String = "") -> void:
	if not _initialized:
		return
	if _resource_manager == null or not is_instance_valid(_resource_manager):
		_resource_manager = get_node_or_null("AdMeshResourceManager")
	if _resource_manager == null:
		return
	_resource_manager.send_impression_event(ad_data, ad_unit_id, session_id)


func report_presence(
	ad_data: Dictionary,
	ad_unit_id: String,
	elapsed_seconds: float,
	session_id: String = "",
	meta_data: Dictionary = {}
) -> void:
	if not _initialized:
		return
	if _resource_manager == null or not is_instance_valid(_resource_manager):
		_resource_manager = get_node_or_null("AdMeshResourceManager")
	if _resource_manager == null:
		return
	_resource_manager.send_presence_signal(
		ad_data,
		ad_unit_id,
		elapsed_seconds,
		session_id,
		meta_data
	)


func report_proximity(
	ad_data: Dictionary,
	ad_unit_id: String,
	proximity_payload: Dictionary,
	session_id: String = "",
	meta_data: Dictionary = {}
) -> void:
	if not _initialized:
		return
	if _resource_manager == null or not is_instance_valid(_resource_manager):
		_resource_manager = get_node_or_null("AdMeshResourceManager")
	if _resource_manager == null:
		return
	_resource_manager.send_proximity_signal(
		ad_data,
		ad_unit_id,
		proximity_payload,
		session_id,
		meta_data
	)


func set_tracker_position(position: Vector3) -> void:
	_tracker_position = position
	_tracker_available = true


func clear_tracker_position() -> void:
	_tracker_available = false


func has_tracker_position() -> bool:
	return _tracker_available


func get_tracker_position() -> Vector3:
	return _tracker_position


func _ensure_resource_manager() -> void:
	if _resource_manager != null and is_instance_valid(_resource_manager):
		return

	_resource_manager = get_node_or_null("AdMeshResourceManager")
	if _resource_manager != null:
		return

	if _resource_manager_pending:
		await get_tree().process_frame
		if _resource_manager != null and is_instance_valid(_resource_manager):
			return

	_resource_manager = AdResourceManager.new()
	_resource_manager.name = "AdMeshResourceManager"
	_resource_manager_pending = true
	_log("creating resource manager")
	add_child.call_deferred(_resource_manager)
	await get_tree().process_frame
	_resource_manager_pending = false
	if _initialized:
		_resource_manager.configure(_sdk_key, _ad_selector_url, _event_collector_url, _session_id)
		_log("resource manager configured")


func _get_active_bindings() -> Array:
	var bindings: Array = []
	for ad_unit in _registered_placements.keys():
		var binding: Dictionary = _registered_placements[ad_unit]
		var node: Node = binding.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		if not bool(binding.get("active", true)):
			continue
		bindings.append({
			"ad_unit_id": ad_unit,
			"node": node,
			"test_mode": bool(binding.get("test_mode", false)),
		})
	return bindings


func _needs_plan_refresh(bindings: Array, now_unix: float) -> bool:
	for binding in bindings:
		var node: Node = binding.get("node", null)
		if node == null:
			return true
		if not node.has_method("has_serving_plan") or not node.has_serving_plan():
			return true
		if not node.has_method("get_plan_valid_until_unix"):
			return true
		var plan_valid_until := float(node.get_plan_valid_until_unix())
		if plan_valid_until <= 0.0 or (plan_valid_until - now_unix) <= PLAN_REFRESH_MARGIN_SECONDS:
			return true
	return false


func _fetch_full_plans(bindings: Array) -> void:
	var grouped: Dictionary = {}
	for binding in bindings:
		var test_mode := bool(binding.get("test_mode", false))
		if not grouped.has(test_mode):
			grouped[test_mode] = []
		grouped[test_mode].append(binding)

	_plan_fetch_in_flight += grouped.size()
	for test_mode in grouped.keys():
		var group_bindings: Array = grouped[test_mode]
		var ad_unit_ids: Array = []
		for binding in group_bindings:
			ad_unit_ids.append(binding.get("ad_unit_id", ""))
		_fetch_full_plan_group(ad_unit_ids, bool(test_mode))


func _fetch_full_plan_group(ad_unit_ids: Array, test_mode: bool) -> void:
	var response := await _resource_manager.fetch_serving_plan(ad_unit_ids, {
		"ad_format": "video",
		"test_mode": test_mode,
		"session_id": _session_id,
		"plan_horizon_seconds": PLAN_HORIZON_SECONDS,
	})
	if typeof(response.get("placements", [])) == TYPE_ARRAY:
		var apply_index := 0
		for placement_plan in response.get("placements", []):
			if typeof(placement_plan) != TYPE_DICTIONARY:
				continue
			var ad_unit_id := str(placement_plan.get("ad_unit_id", "")).strip_edges()
			if ad_unit_id == "" or not _registered_placements.has(ad_unit_id):
				continue
			var binding: Dictionary = _registered_placements[ad_unit_id]
			var node: Node = binding.get("node", null)
			if node != null and is_instance_valid(node) and node.has_method("apply_serving_plan"):
				if apply_index > 0:
					await get_tree().create_timer(PLAN_APPLY_STAGGER_SECONDS * apply_index).timeout
				node.apply_serving_plan(placement_plan)
				apply_index += 1
	_schedule_next_revision_check(_has_visible_activity())
	_plan_fetch_in_flight = maxi(0, _plan_fetch_in_flight - 1)


func _check_revisions(bindings: Array) -> void:
	var grouped: Dictionary = {}
	for binding in bindings:
		var test_mode := bool(binding.get("test_mode", false))
		if not grouped.has(test_mode):
			grouped[test_mode] = []
		grouped[test_mode].append(binding)

	_revision_check_in_flight += grouped.size()
	for test_mode in grouped.keys():
		var group_bindings: Array = grouped[test_mode]
		var ad_unit_ids: Array = []
		var known_revisions: Array = []
		for binding in group_bindings:
			var node: Node = binding.get("node", null)
			if node == null:
				continue
			ad_unit_ids.append(binding.get("ad_unit_id", ""))
			known_revisions.append({
				"ad_unit_id": binding.get("ad_unit_id", ""),
				"serving_revision": node.get_serving_revision() if node.has_method("get_serving_revision") else "",
			})
		_check_revision_group(ad_unit_ids, known_revisions, bool(test_mode))


func _check_revision_group(ad_unit_ids: Array, known_revisions: Array, test_mode: bool) -> void:
	var response := await _resource_manager.check_serving_revisions(ad_unit_ids, known_revisions, {
		"ad_format": "video",
		"test_mode": test_mode,
		"session_id": _session_id,
	})
	if bool(response.get("changed", false)):
		_revision_check_in_flight = maxi(0, _revision_check_in_flight - 1)
		_fetch_full_plans(_get_active_bindings())
		return
	_schedule_next_revision_check(_has_visible_activity())
	_revision_check_in_flight = maxi(0, _revision_check_in_flight - 1)


func _schedule_next_revision_check(has_visible_activity: bool) -> void:
	_next_revision_check_unix = Time.get_unix_time_from_system() + (ACTIVE_REVISION_CHECK_SECONDS if has_visible_activity else QUIET_REVISION_CHECK_SECONDS)


func _has_visible_activity() -> bool:
	for ad_unit in _registered_placements.keys():
		var binding: Dictionary = _registered_placements[ad_unit]
		var node: Node = binding.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		if not bool(binding.get("active", true)):
			continue
		if node.has_method("is_likely_active") and node.is_likely_active():
			return true
	return false


func _log(message: String) -> void:
	print("[AdMesh] %s" % message)
