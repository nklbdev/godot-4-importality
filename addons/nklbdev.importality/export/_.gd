@tool
extends RefCounted

const _Result = preload("../result.gd").Class
const _Common = preload("../common.gd")
const _Options = preload("../options.gd")
const _Setting = preload("../setting.gd")
const _DirAccessExtensions = preload("../dir_access_ext.gd")

const _SpriteSheetBuilderBase = preload("../sprite_sheet_builder/_.gd")
const _GridBasedSpriteSheetBuilder = preload("../sprite_sheet_builder/grid_based.gd")
const _PackedSpriteSheetBuilder = preload("../sprite_sheet_builder/packed.gd")

const ATLAS_TEXTURE_RESOURCE_TYPE_NAMES: PackedStringArray = [
	"Embedded PortableCompressedTexture2D (compact)",
	"Embedded ImageTexture (large)",
	"Separated image (custom)",
]
enum AtlasResourceType {
	EMBEDDED_PORTABLE_COMPRESSED_TEXTURE_2D = 0,
	EMBEDDED_IMAGE_TEXTURE = 1,
	SEPARATED_IMAGE = 2,
}

class ExportResult:
	extends _Result
	var atlas_image: Image
	var sprite_sheet: _Common.SpriteSheetInfo
	var animation_library: _Common.AnimationLibraryInfo
	func _get_result_type_description() -> String:
		return "Export"
	func success(
		atlas_image: Image,
		sprite_sheet: _Common.SpriteSheetInfo,
		animation_library: _Common.AnimationLibraryInfo
		) -> void:
		_success()
		self.atlas_image = atlas_image
		self.sprite_sheet = sprite_sheet
		self.animation_library = animation_library

var __name: String
var __recognized_extensions: PackedStringArray
var __settings: Array[_Setting] = [_Common.common_temporary_files_directory_path_setting]
var __options: Array[Dictionary] = [
	_Options.create_option(_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD, _Common.EdgesArtifactsAvoidanceMethod.NONE,
		PROPERTY_HINT_ENUM, ",".join(_Common.EDGES_ARTIFACTS_AVOIDANCE_METHODS_NAMES),
		PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED),
	_Options.create_option(_Options.SPRITES_SURROUNDING_COLOR, Color.TRANSPARENT,
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT,
		func(o): return o[_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD] == \
			_Common.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING),
	_Options.create_option(_Options.SPRITE_SHEET_LAYOUT, _Common.SpriteSheetLayout.PACKED,
		PROPERTY_HINT_ENUM, ",".join(_Common.SPRITE_SHEET_LAYOUTS_NAMES),
		PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED),
	_Options.create_option(_Options.MAX_CELLS_IN_STRIP, 0,
		PROPERTY_HINT_RANGE, "0,,1,or_greater", PROPERTY_USAGE_DEFAULT,
		func(o): return o[_Options.SPRITE_SHEET_LAYOUT] != \
			_Common.SpriteSheetLayout.PACKED),
	_Options.create_option(_Options.TRIM_SPRITES_TO_OVERALL_MIN_SIZE, true,
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT,
		func(o): return o[_Options.SPRITE_SHEET_LAYOUT] != \
			_Common.SpriteSheetLayout.PACKED),
	_Options.create_option(_Options.COLLAPSE_TRANSPARENT_SPRITES, true,
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT,
		func(o): return o[_Options.SPRITE_SHEET_LAYOUT] != \
			_Common.SpriteSheetLayout.PACKED),
	_Options.create_option(_Options.MERGE_DUPLICATED_SPRITES, true,
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT,
		func(o): return o[_Options.SPRITE_SHEET_LAYOUT] != \
			_Common.SpriteSheetLayout.PACKED),
]
var __image_format_loader_extension: ImageFormatLoaderExtension

func _init(
	name: String,
	recognized_extensions: PackedStringArray,
	options: Array[Dictionary],
	settings: Array[_Setting],
	image_format_loader_extension: ImageFormatLoaderExtension = null
	) -> void:
	__name = name
	__recognized_extensions = recognized_extensions
	__options.append_array(options)
	__settings.append_array(settings)
	__image_format_loader_extension = image_format_loader_extension

func get_recognized_extensions() -> PackedStringArray:
	return __recognized_extensions

func get_options() -> Array[Dictionary]:
	return __options

func get_name() -> String:
	return __name

func get_settings() -> Array[_Setting]:
	return __settings

func get_image_format_loader_extension() -> ImageFormatLoaderExtension:
	return __image_format_loader_extension

func export(
	res_source_file_path: String,
	options: Dictionary,
	editor_import_plugin: EditorImportPlugin
	) -> ExportResult:
	return _export(
		res_source_file_path,
		options)

func _export(source_file: String, options: Dictionary) -> ExportResult:
	assert(false, "This method is abstract and must be overriden.")
	var result: ExportResult = ExportResult.new()
	result.fail(ERR_UNCONFIGURED)
	return result

enum AnimationOptions {
	FramesCount = 1,
	Direction = 2,
	RepeatCount = 4,
}

static var __option_regex: RegEx = RegEx.create_from_string("\\s-\\p{L}:\\s*\\S+")
static var __natural_number_regex: RegEx = RegEx.create_from_string("\\A\\d+\\z")

class AnimationParamsParsingResult:
	extends _Result
	var name: String
	var first_frame_index: int
	var frames_count: int
	var direction: _Common.AnimationDirection
	var repeat_count: int
	func _get_result_type_description() -> String:
		return "Animation parameters parsing"

static func _parse_animation_params(
	raw_animation_params: String,
	animation_options: AnimationOptions,
	first_frame_index: int,
	frames_count: int = 0
	) -> AnimationParamsParsingResult:
	var result = AnimationParamsParsingResult.new()
	if first_frame_index < 0:
		result.fail(ERR_INVALID_DATA, "Wrong value for animation first frame index. Expected natural number, got: %s" % [first_frame_index])
		return result
	result.first_frame_index = first_frame_index
	result.frames_count = frames_count
	result.direction = -1
	result.repeat_count = -1
	raw_animation_params = raw_animation_params.strip_edges()
	var options_matches: Array[RegExMatch] = __option_regex.search_all(raw_animation_params)
	var first_match_position: int = raw_animation_params.length()
	for option_match in options_matches:
		var match_position: int = option_match.get_start()
		assert(match_position >= 0)
		if match_position < first_match_position:
			first_match_position = match_position
		var raw_option: String = option_match.get_string().strip_edges()
		var raw_value = raw_option.substr(3).strip_edges()
		match raw_option.substr(0, 3):
			"-f:":
				if animation_options & AnimationOptions.FramesCount:
					if result.frames_count == 0:
						if __natural_number_regex.search(raw_value):
							result.frames_count = raw_value.to_int()
						if result.frames_count <= 0:
							result.fail(ERR_INVALID_DATA, "Wrong value format for frames count. Expected positive integer number, got: \"%s\"" % [raw_value])
							return result
			"-d:":
				if animation_options & AnimationOptions.Direction:
					if  result.direction < 0:
						match raw_value:
							"f": result.direction = _Common.AnimationDirection.FORWARD
							"r": result.direction = _Common.AnimationDirection.REVERSE
							"pp": result.direction = _Common.AnimationDirection.PING_PONG
							"ppr": result.direction = _Common.AnimationDirection.PING_PONG_REVERSE
							_:
								result.fail(ERR_INVALID_DATA, "Wrong value format for animation direction. Expected one of: [\"f\", \"r\", \"pp\", \"ppr\"], got: \"%s\"" % [raw_value])
								return result
			"-r:":
				if animation_options & AnimationOptions.RepeatCount:
					if result.repeat_count < 0:
						if __natural_number_regex.search(raw_value):
							result.repeat_count = raw_value.to_int()
						else:
							result.fail(ERR_INVALID_DATA, "Wrong value format for repeat count. Expected positive integer number or zero, got: \"%s\"" % [raw_value])
							return result
			_: pass # Ignore unknown parameter
	result.name = raw_animation_params.left(first_match_position).strip_edges()
	if result.frames_count <= 0:
		result.fail(ERR_UNCONFIGURED, "Animation frames count is required but not specified")
		return result
	return result

func _create_sprite_sheet_builder(options: Dictionary) -> _SpriteSheetBuilderBase:
	var sprite_sheet_layout: _Common.SpriteSheetLayout = options[_Options.SPRITE_SHEET_LAYOUT]
	return \
	_PackedSpriteSheetBuilder.new(
		options[_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD],
		options[_Options.SPRITES_SURROUNDING_COLOR]) \
	if sprite_sheet_layout == _Common.SpriteSheetLayout.PACKED else \
	_GridBasedSpriteSheetBuilder.new(
		options[_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD],
			_GridBasedSpriteSheetBuilder.StripDirection.HORIZONTAL
			if sprite_sheet_layout == _Common.SpriteSheetLayout.HORIZONTAL_STRIPS else
			_GridBasedSpriteSheetBuilder.StripDirection.HORIZONTAL,
		options[_Options.MAX_CELLS_IN_STRIP],
		options[_Options.TRIM_SPRITES_TO_OVERALL_MIN_SIZE],
		options[_Options.COLLAPSE_TRANSPARENT_SPRITES],
		options[_Options.MERGE_DUPLICATED_SPRITES],
		options[_Options.SPRITES_SURROUNDING_COLOR])
