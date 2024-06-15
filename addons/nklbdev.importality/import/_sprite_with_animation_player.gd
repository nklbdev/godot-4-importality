@tool
extends "_node_with_animation_player.gd"

func _init(
	name: String,
	resource_type: String,
	save_extension: String,
	options: Array[Dictionary] = []
	) -> void:
	options.append_array([
		_Options.create_option(_Options.ANIMATION_STRATEGY, _Common.AnimationStrategy.SPRITE_REGION_AND_OFFSET,
		PROPERTY_HINT_ENUM, ",".join(_Common.ANIMATION_STRATEGIES_NAMES), PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED),
		_Options.create_option(_Options.SPRITE_CENTERED, false,
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	])
	super(name, resource_type, save_extension, options)
