@tool
class_name AdResourceManager
extends Node

signal resource_ready(url: String, media_type: String, resource: Variant)
signal resource_failed(url: String, reason: String)

const CACHE_DIR := "user://admesh_cache"
const MAX_CONCURRENT_LOADS := 1
const MAX_DOWNLOAD_BYTES := 16 * 1024 * 1024
const LOCAL_MAX_CACHED_CREATIVES := 3
const SDK_VERSION := "0.2.4"

var _sdk_key := ""
var _ad_selector_url := "https://select.admesh.cloud"
var _event_collector_url := "https://events.admesh.cloud"
var _session_id := ""
var _enforce_https := true
var _allowed_hosts := PackedStringArray(["select.admesh.cloud", "events.admesh.cloud"])

var _cached_resources: Dictionary = {}
var _cache_order: Array[String] = []
var _loading_queue: Array[String] = []
var _callbacks_by_url: Dictionary = {}
var _cached_asset_keys: Dictionary = {}
var _asset_key_by_url: Dictionary = {}
var _http_requests: Array[HTTPRequest] = []
var _active_downloads: Dictionary = {}


func _ready() -> void:
	_ensure_cache_dir()
	_log("resource manager ready cache_dir=%s" % CACHE_DIR)
	if _http_requests.is_empty():
		for _idx in range(MAX_CONCURRENT_LOADS):
			var request := HTTPRequest.new()
			request.timeout = 10.0
			request.request_completed.connect(_on_cache_request_completed.bind(request))
			add_child(request)
			_http_requests.append(request)
	if not _loading_queue.is_empty():
		_log("processing queued media after resource manager startup")
		_process_queue()


func configure(sdk_key: String, ad_selector_url: String, event_collector_url: String, session_id: String = "") -> void:
	_sdk_key = sdk_key.strip_edges()
	_session_id = session_id.strip_edges()
	if ad_selector_url.strip_edges() != "":
		_ad_selector_url = ad_selector_url.strip_edges()
	if event_collector_url.strip_edges() != "":
		_event_collector_url = event_collector_url.strip_edges()
	_sync_allowed_hosts()
	_log("configured session=%s selector=%s collector=%s" % [_session_id, _ad_selector_url, _event_collector_url])


func has_resource(url: String) -> bool:
	return _cached_resources.has(url)


func get_resource(url: String) -> Variant:
	return _cached_resources.get(url, null)


func request_media(url: String, callback: Callable = Callable()) -> void:
	url = url.strip_edges()
	if url == "":
		return
	if not _is_media_url_allowed(url):
		_log("media blocked url=%s" % url)
		_emit_failed(url, "URL blocked by SDK policy")
		return
	if callback.is_valid():
		if not _callbacks_by_url.has(url):
			_callbacks_by_url[url] = []
		_callbacks_by_url[url].append(callback)
	if _cached_resources.has(url):
		var resource: Dictionary = _cached_resources[url]
		_touch_cached_resource(url)
		_log("media cache hit url=%s type=%s" % [url, str(resource.get("type", ""))])
		_notify_callbacks(url, str(resource.get("type", "")), resource.get("data"))
		return
	if not _loading_queue.has(url) and not _active_downloads.values().has(url):
		_loading_queue.append(url)
		_log("media queued url=%s" % url)
	_process_queue()


func preload_url(url: String) -> void:
	request_media(url)


func request_binary_asset(url: String, callback: Callable) -> void:
	url = url.strip_edges()
	if not _is_media_url_allowed(url):
		callback.call(false, PackedByteArray(), 0, "URL blocked by SDK policy")
		return
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(_on_binary_asset_completed.bind(http, callback))
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		callback.call(false, PackedByteArray(), 0, "Failed to start request")


func fetch_ad(ad_unit_id: String, request_context: Dictionary = {}) -> Dictionary:
	if _sdk_key == "" or ad_unit_id.strip_edges() == "":
		return {}
	if not is_inside_tree():
		push_warning("[AdMesh] Resource manager is not ready in the scene tree yet")
		return {}
	if not _is_remote_url_allowed(_ad_selector_url):
		push_warning("[AdMesh] ad selector URL is blocked by SDK policy")
		return {}

	var payload := {
		"ad_unit_id": ad_unit_id,
		"ad_format": request_context.get("ad_format", "image"),
		"test_mode": request_context.get("test_mode", false),
		"session_id": request_context.get("session_id", _get_sdk_session_id()),
		"engine": "Godot",
		"sdk_version": SDK_VERSION,
		"platform": OS.get_name(),
		"app_version": ProjectSettings.get_setting("application/config/version", ""),
		"device_class": _resolve_device_class(),
		"sdk_capabilities": [
			"image",
			"video_ogv",
			"scheduled_dtl_delivery",
			"lease_bound_cache",
			"selection_token",
			"session_heartbeat",
			"proximity_analytics_v1"
		],
	}

	var body := JSON.stringify(payload)
	return await _post_selector_request(body, 10.0, ad_unit_id)


func fetch_serving_plan(ad_unit_ids: Array, request_context: Dictionary = {}) -> Dictionary:
	if _sdk_key == "" or ad_unit_ids.is_empty():
		return {}
	if not is_inside_tree():
		return {}
	if not _is_remote_url_allowed(_ad_selector_url):
		return {}

	var payload := {
		"request_mode": "serving_plan",
		"ad_unit_ids": ad_unit_ids,
		"ad_format": request_context.get("ad_format", "video"),
		"test_mode": request_context.get("test_mode", false),
		"session_id": request_context.get("session_id", _get_sdk_session_id()),
		"engine": "Godot",
		"sdk_version": SDK_VERSION,
		"platform": OS.get_name(),
		"app_version": ProjectSettings.get_setting("application/config/version", ""),
		"device_class": _resolve_device_class(),
		"sdk_capabilities": [
			"image",
			"video_ogv",
			"serving_plan_v1",
			"revision_check_v1",
			"scheduled_dtl_delivery",
			"lease_bound_cache",
			"selection_token",
			"session_heartbeat",
			"proximity_analytics_v1"
		],
		"plan_horizon_seconds": clampi(int(request_context.get("plan_horizon_seconds", 180)), 180, 300),
	}

	_log("serving plan request units=%s session=%s test_mode=%s" % [
		str(ad_unit_ids.size()),
		str(payload.get("session_id", "")),
		str(payload.get("test_mode", false)),
	])
	return await _post_selector_request(JSON.stringify(payload), 15.0, "plan")


func check_serving_revisions(ad_unit_ids: Array, known_revisions: Array, request_context: Dictionary = {}) -> Dictionary:
	if _sdk_key == "" or ad_unit_ids.is_empty():
		return {}
	if not is_inside_tree():
		return {}
	if not _is_remote_url_allowed(_ad_selector_url):
		return {}

	var payload := {
		"request_mode": "revision_check",
		"ad_unit_ids": ad_unit_ids,
		"ad_format": request_context.get("ad_format", "video"),
		"test_mode": request_context.get("test_mode", false),
		"session_id": request_context.get("session_id", _get_sdk_session_id()),
		"engine": "Godot",
		"sdk_version": SDK_VERSION,
		"platform": OS.get_name(),
		"app_version": ProjectSettings.get_setting("application/config/version", ""),
		"device_class": _resolve_device_class(),
		"sdk_capabilities": [
			"serving_plan_v1",
			"revision_check_v1"
		],
		"known_revisions": known_revisions,
	}

	_log("revision check request units=%s session=%s test_mode=%s" % [
		str(ad_unit_ids.size()),
		str(payload.get("session_id", "")),
		str(payload.get("test_mode", false)),
	])
	return await _post_selector_request(JSON.stringify(payload), 10.0, "revision")


func request_plan_asset(asset_id: String, asset_version: String, media_type: String, url: String, callback: Callable = Callable()) -> void:
	var asset_key := _build_asset_key(asset_id, asset_version)
	var cached_url := str(_cached_asset_keys.get(asset_key, ""))
	if cached_url != "" and _cached_resources.has(cached_url):
		var resource: Dictionary = _cached_resources[cached_url]
		_touch_cached_resource(cached_url)
		if callback.is_valid():
			callback.call(cached_url, str(resource.get("type", "")), resource.get("data"))
		return

	var wrapped_callback := Callable()
	if callback.is_valid():
		wrapped_callback = Callable(self, "_on_plan_asset_ready").bind(asset_key, callback)
	request_media(url, wrapped_callback)


func _on_plan_asset_ready(url: String, media_type: String, resource: Variant, asset_key: String, callback: Callable) -> void:
	if media_type != "" and asset_key != "":
		_cached_asset_keys[asset_key] = url
		_asset_key_by_url[url] = asset_key
	if callback.is_valid():
		callback.call(url, media_type, resource)


func _post_selector_request(body: String, timeout_seconds: float, log_context: String) -> Dictionary:
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-sdk-key: " + _sdk_key,
	])

	var http := HTTPRequest.new()
	http.timeout = timeout_seconds
	add_child(http)
	var err := http.request(_ad_selector_url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {}

	var result = await http.request_completed
	http.queue_free()

	var status_code: int = result[1]
	var response_body: PackedByteArray = result[3]
	_log("selector response status=%s context=%s" % [str(status_code), log_context])
	if status_code != 200:
		return {}

	var parsed := _parse_json_dict(response_body)
	if str(parsed.get("request_mode", "")) == "serving_plan":
		return parsed
	if str(parsed.get("request_mode", "")) == "revision_check":
		return parsed
	if parsed.has("placements") and typeof(parsed["placements"]) == TYPE_ARRAY:
		return parsed
	if parsed.has("ad") and typeof(parsed["ad"]) == TYPE_DICTIONARY:
		_log("selector ad source=%s schedule=%s media=%s" % [
			str(parsed["ad"].get("delivery_mode", parsed.get("source", ""))),
			str(parsed["ad"].get("schedule_id", "")),
			str(parsed["ad"].get("media_url", "")),
		])
		return parsed["ad"]
	if parsed.has("ads") and typeof(parsed["ads"]) == TYPE_ARRAY and not parsed["ads"].is_empty():
		var first_ad = parsed["ads"][0]
		if typeof(first_ad) == TYPE_DICTIONARY:
			_log("selector ads[0] source=%s schedule=%s media=%s" % [
				str(first_ad.get("delivery_mode", parsed.get("source", ""))),
				str(first_ad.get("schedule_id", "")),
				str(first_ad.get("media_url", "")),
			])
			return first_ad
	_log("selector returned no usable ad for context=%s body=%s" % [log_context, response_body.get_string_from_utf8()])
	return {}


func send_impression_event(ad_data: Dictionary, ad_unit_id: String, session_id: String = "") -> void:
	var payload := {
		"event_type": "impression",
		"ad_id": ad_data.get("id", ""),
		"campaign_id": ad_data.get("campaign_id", ""),
		"ad_unit_id": ad_unit_id,
		"schedule_id": ad_data.get("schedule_id", ""),
		"package_type": "DTL",
		"session_id": session_id if session_id != "" else _get_sdk_session_id(),
		"device_class": _resolve_device_class(),
		"meta_data": {
			"engine": "Godot",
			"sdk_version": SDK_VERSION,
			"platform": OS.get_name(),
			"app_version": ProjectSettings.get_setting("application/config/version", ""),
			"signal_mode": "delivery_start",
			"creative_type": ad_data.get("media_type", ""),
			"creative_version": ad_data.get("creative_version", ad_data.get("override_id", ad_data.get("schedule_id", ""))),
			"cache_status": ad_data.get("cache_status", "fresh"),
			"render_status": "rendering",
			"delivery_mode": ad_data.get("delivery_mode", "scheduled"),
			"override_id": ad_data.get("override_id", ""),
		}
	}
	_apply_selection_token(payload, ad_data)
	_post_event(payload)


func send_presence_signal(
	ad_data: Dictionary,
	ad_unit_id: String,
	elapsed_seconds: float,
	session_id: String = "",
	meta_data: Dictionary = {}
) -> void:
	var merged_meta := {
		"engine": "Godot",
		"sdk_version": SDK_VERSION,
		"platform": OS.get_name(),
		"app_version": ProjectSettings.get_setting("application/config/version", ""),
		"signal_mode": "session_heartbeat",
		"creative_type": ad_data.get("media_type", ""),
		"creative_version": ad_data.get("creative_version", ad_data.get("override_id", ad_data.get("schedule_id", ""))),
		"cache_status": ad_data.get("cache_status", "fresh"),
		"render_status": ad_data.get("render_status", "rendering"),
		"delivery_mode": ad_data.get("delivery_mode", "scheduled"),
		"override_id": ad_data.get("override_id", ""),
	}
	for key in meta_data.keys():
		merged_meta[key] = meta_data[key]

	var payload := {
		"event_type": "view",
		"ad_id": ad_data.get("id", ""),
		"campaign_id": ad_data.get("campaign_id", ""),
		"ad_unit_id": ad_unit_id,
		"schedule_id": ad_data.get("schedule_id", ""),
		"package_type": "DTL",
		"lit_seconds": snappedf(max(elapsed_seconds, 0.0), 0.01),
		"session_id": session_id if session_id != "" else _get_sdk_session_id(),
		"device_class": _resolve_device_class(),
		"meta_data": merged_meta,
	}
	_apply_selection_token(payload, ad_data)
	_post_event(payload)


func send_proximity_signal(
	ad_data: Dictionary,
	ad_unit_id: String,
	proximity_payload: Dictionary,
	session_id: String = "",
	meta_data: Dictionary = {}
) -> void:
	var merged_meta := {
		"engine": "Godot",
		"sdk_version": SDK_VERSION,
		"signal_mode": "proximity_heartbeat",
		"creative_type": ad_data.get("media_type", ""),
		"creative_version": ad_data.get("creative_version", ad_data.get("override_id", ad_data.get("schedule_id", ""))),
		"cache_status": ad_data.get("cache_status", "fresh"),
		"render_status": ad_data.get("render_status", "rendering"),
		"delivery_mode": ad_data.get("delivery_mode", "scheduled"),
		"override_id": ad_data.get("override_id", ""),
		"platform": OS.get_name(),
		"app_version": ProjectSettings.get_setting("application/config/version", ""),
	}
	for key in meta_data.keys():
		merged_meta[key] = meta_data[key]

	var payload := {
		"event_type": "proximity",
		"ad_id": ad_data.get("id", ""),
		"campaign_id": ad_data.get("campaign_id", ""),
		"ad_unit_id": ad_unit_id,
		"schedule_id": ad_data.get("schedule_id", ""),
		"package_type": "DTL",
		"session_id": session_id if session_id != "" else _get_sdk_session_id(),
		"device_class": _resolve_device_class(),
		"proximity": proximity_payload,
		"meta_data": merged_meta,
	}
	_apply_selection_token(payload, ad_data)
	_post_event(payload)


func _post_event(payload: Dictionary) -> void:
	if _sdk_key == "":
		return
	if not _is_remote_url_allowed(_event_collector_url):
		return
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"x-sdk-key: " + _sdk_key,
	])
	var err := http.request(_event_collector_url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_log("collector request failed to start type=%s unit=%s" % [str(payload.get("event_type", "")), str(payload.get("ad_unit_id", ""))])
		http.queue_free()
		return
	http.request_completed.connect(func(_result: int, _status: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_log("collector response status=%s type=%s unit=%s" % [str(_status), str(payload.get("event_type", "")), str(payload.get("ad_unit_id", ""))])
		http.queue_free()
	)


func _apply_selection_token(payload: Dictionary, ad_data: Dictionary) -> void:
	var selection_token := str(ad_data.get("selection_token", "")).strip_edges()
	if selection_token != "":
		payload["selection_token"] = selection_token


func _ensure_cache_dir() -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_absolute(CACHE_DIR)


func _process_queue() -> void:
	while not _loading_queue.is_empty() and _active_downloads.size() < MAX_CONCURRENT_LOADS:
		var request := _find_available_request()
		if request == null:
			return
		var url := _loading_queue.pop_front()
		var cache_path := _get_cache_path(url)
		if FileAccess.file_exists(cache_path):
			_load_cached_resource(url, cache_path)
			continue
		_active_downloads[request] = url
		var err := request.request(url)
		if err != OK:
			_active_downloads.erase(request)
			_emit_failed(url, "Failed to start media request")


func _find_available_request() -> HTTPRequest:
	for request in _http_requests:
		if not _active_downloads.has(request):
			return request
	return null


func _on_cache_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	var url := str(_active_downloads.get(request, ""))
	_active_downloads.erase(request)
	if url == "":
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_log("media download failed url=%s status=%s result=%s" % [url, str(response_code), str(result)])
		_emit_failed(url, "Media download failed")
		_process_queue()
		return
	if body.is_empty() or body.size() > MAX_DOWNLOAD_BYTES:
		_emit_failed(url, "Media exceeded SDK size limits")
		_process_queue()
		return

	var cache_path := _get_cache_path(url)
	var file := FileAccess.open(cache_path, FileAccess.WRITE)
	if file == null:
		_emit_failed(url, "Failed to write media cache file")
		_process_queue()
		return
	file.store_buffer(body)
	file.close()
	_log("media downloaded url=%s bytes=%s" % [url, str(body.size())])
	_load_cached_resource(url, cache_path)
	_process_queue()


func _load_cached_resource(url: String, cache_path: String) -> void:
	var media_type := _detect_media_type(url)
	var resource: Dictionary = {}
	match media_type:
		"image":
			var image := Image.new()
			if image.load(cache_path) != OK:
				_emit_failed(url, "Failed to decode cached image")
				return
			resource = {
				"type": "image",
				"data": ImageTexture.create_from_image(image),
				"path": cache_path,
			}
			_log("media decoded image url=%s" % url)
		"video":
			resource = {
				"type": "video",
				"data": cache_path,
				"path": cache_path,
			}
			_log("media prepared video url=%s path=%s" % [url, cache_path])
		_:
			_emit_failed(url, "Unsupported media type")
			return

	_cached_resources[url] = resource
	_remember_cached_resource(url, cache_path)
	resource_ready.emit(url, media_type, resource["data"])
	_notify_callbacks(url, media_type, resource["data"])


func _notify_callbacks(url: String, media_type: String, resource: Variant) -> void:
	var callbacks: Array = _callbacks_by_url.get(url, [])
	for callback in callbacks:
		if callback is Callable and callback.is_valid():
			callback.call(url, media_type, resource)
	_callbacks_by_url.erase(url)


func _emit_failed(url: String, reason: String) -> void:
	_log("media failure url=%s reason=%s" % [url, reason])
	resource_failed.emit(url, reason)
	var callbacks: Array = _callbacks_by_url.get(url, [])
	for callback in callbacks:
		if callback is Callable and callback.is_valid():
			callback.call(url, "", null)
	_callbacks_by_url.erase(url)


func _on_binary_asset_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, callback: Callable) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		callback.call(false, PackedByteArray(), response_code, "Network request failed")
		return
	if response_code != 200:
		callback.call(false, PackedByteArray(), response_code, "Unexpected status code")
		return
	if body.is_empty():
		callback.call(false, PackedByteArray(), response_code, "Empty response body")
		return
	if body.size() > MAX_DOWNLOAD_BYTES:
		callback.call(false, PackedByteArray(), response_code, "Asset exceeds SDK size limit")
		return
	callback.call(true, body, response_code, "")


func _detect_media_type(url: String) -> String:
	var lower := url.to_lower()
	if lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".webp"):
		return "image"
	if lower.ends_with(".ogv"):
		return "video"
	return ""


func _get_cache_path(url: String) -> String:
	var sanitized_url := url.split("?", false, 1)[0]
	var extension := sanitized_url.get_extension().to_lower()
	if extension == "":
		extension = "bin"
	var file_hash := str(hash(url))
	return CACHE_DIR.path_join(file_hash + "." + extension)


func _parse_json_dict(body: Variant) -> Dictionary:
	var text := ""
	if body is PackedByteArray:
		text = body.get_string_from_utf8()
	else:
		text = str(body)
	text = text.strip_edges()
	if text == "":
		return {}

	var parsed_variant: Variant = JSON.parse_string(text)
	if typeof(parsed_variant) == TYPE_DICTIONARY:
		return parsed_variant

	var json := JSON.new()
	if json.parse(text) == OK:
		var data := json.get_data()
		if typeof(data) == TYPE_DICTIONARY:
			return data

	_log("selector parse failed context text=%s" % [text.substr(0, mini(text.length(), 256))])
	return {}


func _resolve_device_class() -> String:
	var name := OS.get_name().to_lower()
	if name.contains("android") or name.contains("ios"):
		return "mobile"
	if name.contains("web"):
		return "web"
	if name.contains("switch") or name.contains("xbox") or name.contains("playstation"):
		return "console"
	return "desktop"


func _get_sdk_session_id() -> String:
	return _session_id


func _is_remote_url_allowed(url: String) -> bool:
	if url.strip_edges() == "":
		return false
	var lower := url.to_lower()
	if not lower.begins_with("http://") and not lower.begins_with("https://"):
		return false
	if _enforce_https and not lower.begins_with("https://"):
		return false
	if _allowed_hosts.is_empty():
		return true
	var host := _extract_host(lower)
	if host == "":
		return false
	for allowed in _allowed_hosts:
		if host == allowed or host.ends_with("." + allowed):
			return true
	return false


func _is_media_url_allowed(url: String) -> bool:
	if url.strip_edges() == "":
		return false
	var lower := url.to_lower()
	return lower.begins_with("https://")


func _extract_host(url: String) -> String:
	var scheme_split := url.split("://", false, 2)
	if scheme_split.size() < 2:
		return ""
	var remainder: String = scheme_split[1]
	var slash_index := remainder.find("/")
	var host_port := remainder.substr(0, slash_index) if slash_index != -1 else remainder
	var colon_index := host_port.find(":")
	return host_port.substr(0, colon_index) if colon_index != -1 else host_port


func _sync_allowed_hosts() -> void:
	var hosts := PackedStringArray()
	var selector_host := _extract_host(_ad_selector_url.to_lower())
	var collector_host := _extract_host(_event_collector_url.to_lower())
	if selector_host != "":
		hosts.append(selector_host)
	if collector_host != "" and not hosts.has(collector_host):
		hosts.append(collector_host)
	_allowed_hosts = hosts
	_log("allowed hosts=%s" % [", ".join(_allowed_hosts)])


func _log(message: String) -> void:
	print("[AdMesh] %s" % message)


func _touch_cached_resource(url: String) -> void:
	if _cache_order.has(url):
		_cache_order.erase(url)
	_cache_order.append(url)


func _remember_cached_resource(url: String, cache_path: String) -> void:
	_touch_cached_resource(url)
	while _cache_order.size() > LOCAL_MAX_CACHED_CREATIVES:
		var evicted_url := _cache_order.pop_front()
		if evicted_url == url:
			continue
		var evicted: Dictionary = _cached_resources.get(evicted_url, {})
		_cached_resources.erase(evicted_url)
		var evicted_path := str(evicted.get("path", ""))
		if evicted_path == "":
			evicted_path = _get_cache_path(evicted_url)
		var evicted_asset_key := str(_asset_key_by_url.get(evicted_url, ""))
		if evicted_asset_key != "":
			_cached_asset_keys.erase(evicted_asset_key)
			_asset_key_by_url.erase(evicted_url)
		if evicted_path != "" and FileAccess.file_exists(evicted_path):
			DirAccess.remove_absolute(evicted_path)


func _build_asset_key(asset_id: String, asset_version: String) -> String:
	var normalized_id := asset_id.strip_edges()
	if normalized_id == "":
		normalized_id = "asset"
	var normalized_version := asset_version.strip_edges()
	if normalized_version == "":
		normalized_version = "v1"
	return "%s__%s" % [normalized_id, normalized_version]
