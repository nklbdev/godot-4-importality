@tool
extends "_node_with_animation_player.gd"

const ANIMATION_STRATEGIES_NAMES: PackedStringArray = [
	"Animate sprite's region and offset",
	"Animate single atlas texture's region and margin",
	"Animate multiple atlas textures instances",
]
enum AnimationStrategy {
	SPRITE_REGION_AND_OFFSET = 0,
	SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN = 1,
	MULTIPLE_ATLAS_TEXTURES_INSTANCES = 2,
}

func _init(
	name: String,
	resource_type: String,
	save_extension: String,
	options: Array[Dictionary] = []
	) -> void:
	options.append_array([
		_Options.create_option(_Options.ANIMATION_STRATEGY, AnimationStrategy.SPRITE_REGION_AND_OFFSET,
		PROPERTY_HINT_ENUM, ",".join(ANIMATION_STRATEGIES_NAMES), PROPERTY_USAGE_DEFAULT),
		_Options.create_option(_Options.SPRITE_CENTERED, false,
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	])
	super(name, resource_type, save_extension, options)
