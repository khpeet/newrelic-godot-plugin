extends Node
## Exposes methods to send events, metrics, or logs to New Relic
##
## This class manages a HTTPRequest queue that handles sending data to New Relic.
## Compression is used to speed up requests

## Max size of queue - data will be dropped if limit is exceeded, and queue will be reset.
## Increase/decrease as needed for performance
const MAX_Q_SIZE = 100

const RESERVED_LOG_KEYS: Array[String] = ["message", "timestamp"]

var _ingest_key: String
var _account_id: String
var _region: String

var _can_send_data: bool = false

var _http_request: HTTPRequest
var _request_in_progress: bool = false
var _should_drain_q: bool = false
var _request_q: Array[Dictionary] = []

var _event_endpoint: String
var _metric_endpoint: String
var _log_endpoint: String
var _headers: PackedStringArray

signal exit_handled


func _ready() -> void:
	_ingest_key = ProjectSettings.get_setting("newrelic/general/ingest_key", "")
	_account_id = ProjectSettings.get_setting("newrelic/general/account_id", "")
	_region     = ProjectSettings.get_setting("newrelic/general/region", "US")

	if _ingest_key and _account_id:
		_can_send_data = true
		_http_request = HTTPRequest.new()
		_http_request.use_threads = true
		add_child(_http_request)
		_http_request.request_completed.connect(_on_request_complete)

		var eu := _region == "EU"
		_event_endpoint  = "https://insights-collector%s.newrelic.com/v1/accounts/%s/events" \
				% [(".eu01" if eu else ""), _account_id]
		_metric_endpoint = "https://metric-api%s.newrelic.com/metric/v1" \
				% [(".eu" if eu else "")]
		_log_endpoint    = "https://log-api%s.newrelic.com/log/v1" \
				% [(".eu" if eu else "")]
		_headers = PackedStringArray([
			"Content-Type: application/json",
			"Content-Encoding: gzip",
			"Api-Key: " + _ingest_key,
		])


## Used to send events to New Relic's event API
# @param: key - Key of event - Accepts string only [Required]
# @param: value - Value of event - Accepts string, int, or bool types [Required]
# @param: table - Table to post key-value pair to - Accepts string only [Required]
# @param: includeDeviceInfo - Send device metadata associated with event - Default: false
func send_event(key: String, value: Variant, table: String, includeDeviceInfo: bool = false) -> void:
	if not _can_send_data:
		push_error("[NEWRELIC] Event collection skipped - validate configuration under Project Settings -> New Relic")
		return

	if key.length() > 255:
		push_error("[NEWRELIC] Event collection skipped - Key longer than 255 characters")
		return

	if typeof(value) == TYPE_STRING:
		if (value as String).length() > 4096:
			push_error("[NEWRELIC] Event collection skipped - Value longer than 4096 characters")
			return

	if _request_q.size() >= MAX_Q_SIZE:
		push_error("[NEWRELIC] Request queue size exceeded - data temporarily dropped - resetting queue")
		_reset_queue()
		return

	var event_payload: Array[Dictionary] = [{
		"eventType": table
	}]
	event_payload[0][key] = value
	if includeDeviceInfo:
		_add_device_info(event_payload[0])

	_enqueue(_event_endpoint, JSON.stringify(event_payload))


## Used to send metrics to New Relic's metric API
# @param: name - Name of metric [Required]
# @param: value - Value of metric [Required] - number|map
# @param: type - Type of metric - count|gauge|summary - Default: gauge
# @param: interval - Length of metric time window in milliseconds [Required for count/summary only] - Default: 0
# @param: attributes - Map of key-value pairs associated with metric - Default: {}
# @param: includeDeviceInfo - Send device metadata associated with metric - Default: false
func send_metric(name: String, value: Variant, type: String = "gauge", interval: int = 0, attributes: Dictionary = {}, includeDeviceInfo: bool = false) -> void:
	if not _can_send_data:
		push_error("[NEWRELIC] Metric collection skipped - validate configuration under Project Settings -> New Relic")
		return

	if type in ["count", "summary"]:
		if interval <= 0:
			push_error("[NEWRELIC] interval in milliseconds required for count or summary metrics - skipping metric")
			return

	if _request_q.size() >= MAX_Q_SIZE:
		push_error("[NEWRELIC] Request queue size exceeded - data temporarily dropped - resetting queue")
		_reset_queue()
		return

	var metric: Dictionary = {
		"name": name,
		"type": type,
		"value": value,
		"timestamp": Time.get_unix_time_from_system()
	}
	if type in ["count", "summary"]:
		metric["interval.ms"] = interval
	if attributes.size() > 0:
		metric["attributes"] = attributes

	var metric_payload: Array[Dictionary] = [{"metrics": [metric]}]

	if includeDeviceInfo:
		var common_attrs: Dictionary = {}
		_add_device_info(common_attrs)
		metric_payload[0]["common"] = {"attributes": common_attrs}

	_enqueue(_metric_endpoint, JSON.stringify(metric_payload))


## Used to send logs to New Relic's log API
# @param: message - Log message to send [Required]
# @param: attributes - Map of key-value pairs associated with log - Default: {}
# @param: includeDeviceInfo - Send device metadata associated with log - Default: false
func send_log(message: String, attributes: Dictionary = {}, includeDeviceInfo: bool = false) -> void:
	if not _can_send_data:
		push_error("[NEWRELIC] Log collection skipped - validate configuration under Project Settings -> New Relic")
		return

	if _request_q.size() >= MAX_Q_SIZE:
		push_error("[NEWRELIC] Request queue size exceeded - data temporarily dropped - resetting queue")
		_reset_queue()
		return

	var log_payload: Dictionary = {
		"message": message,
		"timestamp": Time.get_unix_time_from_system()
	}

	for key in attributes:
		if key in RESERVED_LOG_KEYS:
			push_warning("[NEWRELIC] send_log attribute key '%s' is reserved and will be skipped" % key)
			continue
		log_payload[key] = attributes[key]

	if includeDeviceInfo:
		_add_device_info(log_payload)

	_enqueue(_log_endpoint, JSON.stringify(log_payload))


## Must be awaited before SceneTree.quit() to ensure any queued requests are sent
func handle_exit() -> void:
	_should_drain_q = true
	_handle_requests()
	await exit_handled


## Compress any request body
func _compress_payload(payload: String) -> PackedByteArray:
	return payload.to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)


func _enqueue(url: String, body: String) -> void:
	_request_q.append({
		"url": url,
		"headers": _headers,
		"body": _compress_payload(body)
	})
	_handle_requests()


func _reset_queue() -> void:
	_request_q.clear()


func _add_device_info(target: Dictionary) -> void:
	target["os_type"]      = OS.get_name()
	target["os_version"]   = OS.get_version()
	target["isDebugBuild"] = OS.is_debug_build()
	target["cpu"]          = OS.get_processor_name()
	var graphics_info: PackedStringArray = OS.get_video_adapter_driver_info()
	if graphics_info.size() > 0:
		target["gpu_type"]    = graphics_info[0]
		target["gpu_version"] = graphics_info[1]


## Main request queue handler
func _handle_requests() -> void:
	if not _request_q.is_empty() and not _request_in_progress:
		_request_in_progress = true
		var req: Dictionary = _request_q.front()
		var err: int = _http_request.request_raw(
			req["url"],
			req["headers"],
			HTTPClient.METHOD_POST,
			req["body"]
		)
		if err != OK:
			push_error("[NEWRELIC] Failed to send HTTP request. Error: %d" % err)
			_request_in_progress = false
			_request_q.pop_front()
			_handle_requests()
			return

	if _should_drain_q and _request_q.is_empty():
		_should_drain_q = false
		await get_tree().process_frame
		exit_handled.emit()


## Handles New Relic response
func _on_request_complete(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_in_progress = false

	if not _request_q.is_empty():
		_request_q.pop_front()

	if response_code < 200 or response_code > 299:
		push_error("[NEWRELIC] HTTP request failed. Response code: %d" % response_code)

	_handle_requests()
