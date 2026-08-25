class_name FrontendTheme
extends RefCounted

## Stable loading entry for the shared temporary front-end Theme.

const RESOURCE_PATH := "res://UI/Frontend/frontend_theme.tres"


static func get_shared() -> Theme:
	return load(RESOURCE_PATH) as Theme


static func create() -> Theme:
	var shared := get_shared()
	return shared.duplicate(true) as Theme if shared != null else Theme.new()
