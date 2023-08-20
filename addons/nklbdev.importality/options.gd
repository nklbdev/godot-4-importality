@tool

const _Common = preload("common.gd")
const __empty_callable: Callable = Callable()

const SPRITE_SHEET_LAYOUT: StringName = "sprite_sheet/layout"
const MAX_CELLS_IN_STRIP: StringName = "sprite_sheet/max_cells_in_strip"
const EDGES_ARTIFACTS_AVOIDANCE_METHOD: StringName = "sprite_sheet/edges_artifacts_avoidance_method"
const SPRITES_SURROUNDING_COLOR: StringName = "sprite_sheet/sprites_surrounding_color"
const TRIM_SPRITES_TO_OVERALL_MIN_SIZE: StringName = "sprite_sheet/trim_sprites_to_overall_min_size"
const COLLAPSE_TRANSPARENT_SPRITES: StringName = "sprite_sheet/collapse_transparent_sprites"
const MERGE_DUPLICATED_SPRITES: StringName = "sprite_sheet/merge_duplicated_sprites"
const DEFAULT_ANIMATION_NAME: StringName = "animation/default/name"
const DEFAULT_ANIMATION_DIRECTION: StringName = "animation/default/direction"
const DEFAULT_ANIMATION_REPEAT_COUNT: StringName = "animation/default/repeat_count"
const AUTOPLAY_ANIMATION_NAME: StringName = "animation/autoplay_name"
const ROOT_NODE_NAME: StringName = "root_node_name"
const ANIMATION_STRATEGY: StringName = "animation/strategy"
const SPRITE_CENTERED: StringName = "sprite/centered"
const ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED: StringName = "atlas_textures/region_filter_clip_enabled"
const MIDDLE_IMPORT_SCRIPT_PATH: StringName = "middle_import_script"
const POST_IMPORT_SCRIPT_PATH: StringName = "post_import_script"

static func create_option(
	name: StringName,
	default_value: Variant,
	property_hint: PropertyHint = PROPERTY_HINT_NONE,
	hint_string: String = "",
	usage: PropertyUsageFlags = PROPERTY_USAGE_NONE,
	get_is_visible: Callable = __empty_callable
	) -> Dictionary:
	var option_data: Dictionary = {
		name = name,
		default_value = default_value,
	}
	if hint_string: option_data["hint_string"] = hint_string
	if property_hint: option_data["property_hint"] = property_hint
	if usage: option_data["usage"] = usage
	if get_is_visible != __empty_callable:
		option_data["get_is_visible"] = get_is_visible
	return option_data
