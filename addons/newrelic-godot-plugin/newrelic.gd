extends Node
## Exposes methods to send events, metrics, or logs to New Relic
##
## This class manages a HTTPRequest queue that handles sending data to New Relic.
## Compression is used to speed up requests

## Max size of queue - data will be dropped if limit is exceeded, and queue will be reset.
## increase/decrease as needed for performance
const MAX_Q_SIZE = 100

var ingest_key = ProjectSettings.get_setting("newrelic/general/ingest_key", null)
var account_id = ProjectSettings.get_setting("newrelic/general/account_id", null)
var region = ProjectSettings.get_setting("newrelic/general/region", "US")

var can_send_data: bool = false

var http_request: HTTPRequest
var request_in_progress: bool = false
var should_drain_q = false
var request_q: Array[Dictionary] = []
var current_q_size = 0

signal exit_handled


## Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if ingest_key && account_id:
		can_send_data = true
		http_request = HTTPRequest.new()
		add_child(http_request)
		http_request.request_completed.connect(_on_request_complete)


## Used to send events to New Relic's event API
# @param: key - Key of event - Accepts string only [Required]
# @param: value - Value of event - Accepts string, int, or bool types [Required]
# @param: table - Table to post key-value pair to - Accepts string only [Required]
# @param: includeDeviceInfo - Send device metadata associated with metric - Default: false
func send_event(key: String, value, table: String, includeDeviceInfo: bool = false) -> void:
	if not can_send_data:
		push_error("[NEWRELIC] Event collection skipped - validate configuration under Project Settings -> New Relic")
		return
	
	if key.length() > 255:
		push_error("[NEWRELIC] Event collection skipped - Key longer than 255 characters")
		return
	
	if typeof(value) == TYPE_STRING:
		if value.length() > 4096:
			push_error("[NEWRELIC] Event collection skipped - Value longer than 4096 characters")
			return
	
	current_q_size += 1
	if current_q_size > MAX_Q_SIZE:
		push_error("[NEWRELIC] Request queue size exceeded - data temporarily dropped - resetting queue")
		_reset_queue()
		return

	var EVENT_ENDPOINT = "https://insights-collector.newrelic.com/v1/accounts/{0}/events".format([account_id])
	if region == "EU":
		EVENT_ENDPOINT = "https://insights-collector.eu01.newrelic.com/v1/accounts/{0}/events".format([account_id])

	var event_payload = [{
		"eventType": table
	}]
	var headers = [
		"Content-Type: application/json",
		"Content-Encoding: gzip",
		"Api-Key: " + ingest_key
	]
		
	event_payload[0][key] = value
	if includeDeviceInfo:
		event_payload[0]["os_type"] = OS.get_name()
		event_payload[0]["os_version"] = OS.get_version()
		event_payload[0]["isDebugBuild"] = OS.is_debug_build()
		event_payload[0]["cpu"] = OS.get_processor_name()
		var graphics_info = OS.get_video_adapter_driver_info()
		if graphics_info.size() > 0:
			event_payload[0]["gpu_type"] = graphics_info[0]
			event_payload[0]["gpu_version"] = graphics_info[1]
	
	var compressed_payload = _compress_payload(JSON.stringify(event_payload))
	
	var request = {
		"url": EVENT_ENDPOINT,
		"headers": headers,
		"body": compressed_payload
	}
	request_q.append(request)
	_handle_requests()


## Used to send metrics to New Relic's metric API
# @param: name - Name of metric [Required] - Default: null
# @param: value - Value of metric [Required] - number|map - Default: null
# @param: type - Type of metric - count|gauge|summary - Default: gauge
# @param: interval - Length of metric time window in milliseconds [Required for count/summary only] - Default: 0
# @param: attributes - Map of key-value pairs associated with metric - Default: {}
# @param: includeDeviceInfo - Send device metadata associated with metric - Default: false
func send_metric(name: String, value, type: String = "gauge", interval: int = 0, attributes: Dictionary = {}, includeDeviceInfo: bool = false) -> void:
	if not can_send_data:
		push_error("[NEWRELIC] Metric collection skipped - validate configuration under Project Settings -> New Relic")
		return
	
	var metric_payload = [{
		"metrics": [
			{
				"name": name,
				"type": type,
				"value": value,
				"timestamp": Time.get_unix_time_from_system()
			}
		]
	}]
	if type in ["count", "summary"]:
		if interval > 0:
			metric_payload[0]["metrics"][0]["interval.ms"] = interval
		else:
			push_error("[NEWRELIC] interval in milliseconds required for count or summary metrics - skipping metric")
			return
	
	if attributes.size() > 0:
		metric_payload[0]["metrics"][0]["attributes"] = attributes
	
	if includeDeviceInfo:
		metric_payload[0]["common"] = {}
		metric_payload[0]["common"]["attributes"] = {
			"os_type": OS.get_name(),
			"os_version": OS.get_version(),
			"isDebugBuild": OS.is_debug_build(),
			"cpu": OS.get_processor_name()
		}
		var graphics_info = OS.get_video_adapter_driver_info()
		if graphics_info.size() > 0:
			metric_payload[0]["common"]["attributes"]["gpu_type"] = graphics_info[0]
			metric_payload[0]["common"]["attributes"]["gpu_version"] = graphics_info[1]
	
	current_q_size += 1
	if current_q_size > MAX_Q_SIZE:
		push_error("[NEWRELIC] Request queue size exceeded - data temporarily dropped - resetting queue")
		_reset_queue()
		return
	
	var METRIC_ENDPOINT = "https://metric-api.newrelic.com/metric/v1"
	if region == "EU":
		METRIC_ENDPOINT = "https://metric-api.eu.newrelic.com/metric/v1"

	var headers = [
		"Content-Type: application/json",
		"Content-Encoding: gzip",
		"Api-Key: " + ingest_key
	]
	
	var compressed_payload = _compress_payload(JSON.stringify(metric_payload))
	var request = {
		"url": METRIC_ENDPOINT,
		"headers": headers,
		"body": compressed_payload
	}
	
	request_q.append(request)
	_handle_requests()


## Used to send logs to New Relic's log API
# @param: message - Log message to send [Required] - Default: ""
# @param: attributes - Map of key-value pairs associated with log - Default: {}
# @param: includeDeviceInfo - Send device metadata associated with metric - Default: false
func send_log(message: String, attributes: Dictionary = {}, includeDeviceInfo: bool = false) -> void:
	if not can_send_data:
		push_error("[NEWRELIC] Log collection skipped - validate configuration under Project Settings -> New Relic")
		return
	
	var log_payload = {
		"message": message,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if attributes.size() > 0:
		for key in attributes.keys():
			log_payload[key] = attributes[key]
	
	if includeDeviceInfo:
		log_payload["os_type"] = OS.get_name()
		log_payload["os_version"] = OS.get_version()
		log_payload["isDebugBuild"] = OS.is_debug_build()
		log_payload["cpu"] = OS.get_processor_name()
		var graphics_info = OS.get_video_adapter_driver_info()
		if graphics_info.size() > 0:
			log_payload["gpu_type"] = graphics_info[0]
			log_payload["gpu_version"] = graphics_info[1]

	current_q_size += 1
	if current_q_size > MAX_Q_SIZE:
		push_error("[NEWRELIC] Request queue size exceeded - data temporarily dropped - resetting queue")
		_reset_queue()
		return
	
	var LOG_ENDPOINT = "https://log-api.newrelic.com/log/v1"
	if region == "EU":
		LOG_ENDPOINT = "https://log-api.eu.newrelic.com/log/v1"

	var headers = [
		"Content-Type: application/json",
		"Content-Encoding: gzip",
		"Api-Key: " + ingest_key
	]
	
	var compressed_payload = _compress_payload(JSON.stringify(log_payload))
	var request = {
		"url": LOG_ENDPOINT,
		"headers": headers,
		"body": compressed_payload
	}
	
	request_q.append(request)
	_handle_requests()


## Should be called to send final events to New Relic before any game close events
func handle_exit():
	should_drain_q = true
	_handle_requests()
	return exit_handled


## Main request queue handler
func _handle_requests() -> void:
	if not request_q.is_empty() and not request_in_progress:
		request_in_progress = true
		var req: Dictionary = request_q.front()
		var result = http_request.request_raw(
			req["url"],
			req["headers"],
			HTTPClient.METHOD_POST,
			req["body"]
		)
		if result != OK:
			_handle_request_failure(result)

	# emit exit signal if q drained successfully
	if should_drain_q and request_q.is_empty():
		await get_tree().process_frame
		exit_handled.emit()


## Compress any request body
func _compress_payload(payload: String) -> PackedByteArray:
	return PackedByteArray(payload.to_utf8_buffer()).compress(FileAccess.COMPRESSION_GZIP)


func _reset_queue() -> void:
	request_q.clear()
	current_q_size = 0


## Handles any HTTP failures
func _handle_request_failure(response_code: int) -> void:
	if not request_q.is_empty():
		request_q.pop_front()
		current_q_size = max(current_q_size - 1, 0)
	
	if response_code >= 400:
		push_error("[NEWRELIC] http request failed. result: %d" % response_code)
	
	request_in_progress = false
	_handle_requests()


## Handles New Relic response
func _on_request_complete(result, response_code, headers, body) -> void:
	if response_code >= 200 and response_code <= 299:
		if not request_q.is_empty():
			request_q.pop_front()
			current_q_size = max(current_q_size - 1, 0)
		if should_drain_q:
			_handle_requests()
	else:
		_handle_request_failure(response_code)
	
	request_in_progress = false
	_handle_requests()
