@tool
extends RefCounted

const _Result = preload("../result.gd").Class
const _Common = preload("../common.gd")
const _Options = preload("../options.gd")

class ImportResult:
	extends _Result
	var resource: Resource
	var resource_saver_flags: ResourceSaver.SaverFlags
	func _get_result_type_description() -> String:
		return "Import"
	func success(
		resource: Resource,
		resource_saver_flags: ResourceSaver.SaverFlags = ResourceSaver.FLAG_NONE
		) -> void:
		_success()
		self.resource = resource
		self.resource_saver_flags = resource_saver_flags

var __options: Array[Dictionary] = [
	_Options.create_option(_Options.DEFAULT_ANIMATION_NAME, "default",
	PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	_Options.create_option(_Options.DEFAULT_ANIMATION_DIRECTION, _Common.AnimationDirection.FORWARD,
	PROPERTY_HINT_ENUM, ",".join(_Common.ANIMATION_DIRECTIONS_NAMES), PROPERTY_USAGE_DEFAULT),
	_Options.create_option(_Options.DEFAULT_ANIMATION_REPEAT_COUNT, 0,
	PROPERTY_HINT_RANGE, "0,,1,or_greater", PROPERTY_USAGE_DEFAULT),
	_Options.create_option(_Options.AUTOPLAY_ANIMATION_NAME, "",
	PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	_Options.create_option(_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED, false,
	PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
]
var __name: String
var __resource_type: StringName
var __save_extension: String

func _init(
	name: String,
	resource_type: String,
	save_extension: String,
	options: Array[Dictionary] = []) -> void:
	__name = name
	__resource_type = resource_type
	__save_extension = save_extension
	__options.append_array(options)

func get_name() -> String:
	return __name

func get_resource_type() -> StringName:
	return __resource_type

func get_save_extension() -> String:
	return __save_extension

func get_options() -> Array[Dictionary]:
	return __options

func import(
	source_file_path: String,
	atlas: Texture2D,
	sprite_sheet: _Common.SpriteSheetInfo,
	animation_library: _Common.AnimationLibraryInfo,
	options: Dictionary,
	save_path: String) -> ImportResult:
	assert(false, "This method is abstract and must be overriden.")
	var result: ImportResult = ImportResult.new()
	result.fail(ERR_UNCONFIGURED, "This method is abstract and must be overriden.")
	return result
