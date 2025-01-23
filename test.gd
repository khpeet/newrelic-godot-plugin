extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	## Event Examples
	newrelic.send_event("button_event_1", "clicked_data", "TestButtonEvent2")
	# newrelic.send_event("button_event_2", "clicked_data", "TestButtonEvent2", true)

	## Metric Examples
	newrelic.send_metric("gauge_test_1", 1)
	# newrelic.send_metric("gauge_test_2", 2, "gauge", 0, {"key1": "value1", "key2": 12.3}, true)
	# newrelic.send_metric("count_test", 15, "count", 10000, {"key1": "value1", "key2": "value2"}, true)
	# newrelic.send_metric("summary_test", {"count": 5, "sum": 20, "min": 0.005, "max": 100}, "summary", 10000, {"key1": "value1", "key2": 12.3}, true)

	## Log Examples
	newrelic.send_log("test message 1")
	# newrelic.send_log("test message 2", {"key1": "value1", "key2": "value2"})
	# newrelic.send_log("test message 3", {"key1": "value1", "key2": "value2"}, true)

	## Call handle_exit() before SceneTree.quit() to make sure any final requests are sent
	await newrelic.handle_exit()
	get_tree().quit()
