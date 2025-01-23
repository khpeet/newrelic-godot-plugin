@tool
extends EditorPlugin

const AUTOLOAD_NAME := "newrelic"
const AUTOLOAD_PATH := "res://addons/newrelic-godot-plugin/newrelic.gd"
const PLUGIN_PROPERTIES := [
	{"name": "newrelic/general/ingest_key", "default": "", "type": TYPE_STRING, "hint": PROPERTY_HINT_PASSWORD, "hint_string": ""},
	{"name": "newrelic/general/account_id", "default": "", "type": TYPE_STRING,  "hint": PROPERTY_HINT_NONE, "hint_string": ""},
	{"name": "newrelic/general/region", "default": "US", "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string":"US,EU"},
]


func _enter_tree() -> void:	
	#Init configuration
	for prop in PLUGIN_PROPERTIES:
		if not ProjectSettings.has_setting(prop["name"]):
			ProjectSettings.set_setting(prop["name"], prop["default"])
			ProjectSettings.add_property_info({
				"name": prop["name"],
				"type": prop["type"],
				"hint": prop["hint"],
				"hint_string": prop["hint_string"]
			})
			ProjectSettings.set_as_basic(prop["name"], true)
	
	if ProjectSettings.get_setting("newrelic/general/ingest_key") == "" or not ProjectSettings.get_setting("newrelic/general/ingest_key"):
		printerr("Ingest key has not been set for New Relic.")
	
	if ProjectSettings.get_setting("newrelic/general/account_id") == "" or not ProjectSettings.get_setting("newrelic/general/account_id"):
		printerr("Account ID has not been set for New Relic.")
		
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
