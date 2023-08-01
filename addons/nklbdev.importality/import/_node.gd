@tool
extends "_.gd"

func _init(
	name: String,
	resource_type: String,
	save_extension: String,
	options: Array[Dictionary] = []
	) -> void:
	options.append_array([
		_Options.create_option(_Options.ROOT_NODE_NAME, "",
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	])
	super(name, resource_type, save_extension, options)
