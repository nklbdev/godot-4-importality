extends Object

const _Models = preload("../models.gd")
const _Options = preload("../options.gd")
const _ProjectSetting = preload("../project_setting.gd")

const _SpriteSheetBuilderBase = preload("../sprite_sheet_builder/_.gd")
const _GridBasedSpriteSheetBuilder = preload("../sprite_sheet_builder/grid_based.gd")
const _PackedSpriteSheetBuilder = preload("../sprite_sheet_builder/packed.gd")

const ATLAS_TEXTURE_RESOURCE_TYPE_NAMES: PackedStringArray = [
	"Embedded PortableCompressedTexture2D (compact)",
	"Embedded ImageTexture (large)",
	"Separated image as CompressedTexture2D (compact)",
]
enum AtlasResourceType {
	EMBEDDED_PORTABLE_COMPRESSED_TEXTURE_2D = 0,
	EMBEDDED_IMAGE_TEXTURE = 1,
	SEPARATED_IMAGE_AS_COMPRESSED_TEXTURE_2D = 2,
}

class _AnimationInfo:
	var name: String
	var first_frame: int
	var last_frame: int
	var direction: _Models.AnimationModel.Direction
	var repeat_count: int
	func _to_string() -> String:
		return "AnimationInfo(name: %s, first_frame: %s, last_frame: %s, direction: %s, repeat_count: %s)" % [name, first_frame, last_frame, direction, repeat_count]

var _common_temporary_files_directory_path: _ProjectSetting = _ProjectSetting.new(
	"common/temporary_files_directory_path", "", TYPE_STRING, PROPERTY_HINT_GLOBAL_DIR,
	"", true, func(v: String): return v.is_empty())

var __name: String
var __recognized_extensions: PackedStringArray
var __project_settings: Array[_ProjectSetting] = [_common_temporary_files_directory_path]
var __editor_file_system: EditorFileSystem
var __options: Array[Dictionary] = [
	_Options.create_option(_Options.ATLAS_RESOURCE_TYPE, AtlasResourceType.EMBEDDED_PORTABLE_COMPRESSED_TEXTURE_2D,
	PROPERTY_HINT_ENUM, ",".join(ATLAS_TEXTURE_RESOURCE_TYPE_NAMES), PROPERTY_USAGE_DEFAULT),
	_Options.create_option(_Options.SPRITE_SHEET_LAYOUT, _Models.SpriteSheetModel.Layout.PACKED,
	PROPERTY_HINT_ENUM, ",".join(_Models.SpriteSheetModel.LAYOUTS_NAMES),
	PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED),
	_Options.create_option(_Options.MAX_CELLS_IN_STRIP, 0,
	PROPERTY_HINT_RANGE, "0,,1,or_greater", PROPERTY_USAGE_DEFAULT,
	func(o): return o[_Options.SPRITE_SHEET_LAYOUT] != \
		_Models.SpriteSheetModel.Layout.PACKED),
	_Options.create_option(_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD, _Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.NONE,
	PROPERTY_HINT_ENUM, ",".join(_Models.SpriteSheetModel.EDGES_ARTIFACTS_AVOIDANCE_METHODS_NAMES),
	PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED),
	_Options.create_option(_Options.SPRITES_SURROUNDING_COLOR, Color.TRANSPARENT,
	PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT,
	func(o): return o[_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD] == \
		_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING),
	_Options.create_option(_Options.TRIM_SPRITES_TO_OVERALL_MIN_SIZE, true,
	PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	_Options.create_option(_Options.COLLAPSE_TRANSPARENT_SPRITES, true,
	PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	_Options.create_option(_Options.MERGE_DUPLICATED_SPRITES, true,
	PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
]
var __image_format_loader_extension: ImageFormatLoaderExtension

func _is_layout_grid_based(options: Dictionary) -> bool:
	return options[_Options.SPRITE_SHEET_LAYOUT] != _Models.SpriteSheetModel.Layout.PACKED

func _init(
	name: String,
	recognized_extensions: PackedStringArray,
	options: Array[Dictionary],
	editor_file_system: EditorFileSystem,
	project_settings: Array[_ProjectSetting],
	image_format_loader_extension: ImageFormatLoaderExtension = null
	) -> void:
	__name = name
	__recognized_extensions = recognized_extensions
	__options.append_array(options)
	__editor_file_system = editor_file_system
	__project_settings.append_array(project_settings)
	__image_format_loader_extension = image_format_loader_extension

func get_recognized_extensions() -> PackedStringArray:
	return __recognized_extensions

func get_options() -> Array[Dictionary]:
	return __options

func get_name() -> String:
	return __name

func get_project_settings() -> Array[_ProjectSetting]:
	return __project_settings

func get_image_format_loader_extension() -> ImageFormatLoaderExtension:
	return __image_format_loader_extension

func export(
	res_source_file_path: String,
	options: Dictionary,
	editor_import_plugin: EditorImportPlugin
	) -> _Models.ExportResultModel:

	var export_result_model: _Models.ExportResultModel = _export(res_source_file_path, options)
	if export_result_model.status: return export_result_model
	var atlas_resource_type: AtlasResourceType = options[_Options.ATLAS_RESOURCE_TYPE]
	match atlas_resource_type:
		AtlasResourceType.EMBEDDED_PORTABLE_COMPRESSED_TEXTURE_2D:
			var atlas: PortableCompressedTexture2D = PortableCompressedTexture2D.new()
			atlas.keep_compressed_buffer = true
			atlas.create_from_image(export_result_model.sprite_sheet.atlas_image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
			export_result_model.sprite_sheet.atlas = atlas
		AtlasResourceType.EMBEDDED_IMAGE_TEXTURE:
			export_result_model.sprite_sheet.atlas = \
				ImageTexture.create_from_image(export_result_model.sprite_sheet.atlas_image)
		AtlasResourceType.SEPARATED_IMAGE_AS_COMPRESSED_TEXTURE_2D:
			var png_path = res_source_file_path + ".png"
			export_result_model.sprite_sheet.atlas_image.save_png(png_path)
			__editor_file_system.update_file(png_path)
			var err: Error = editor_import_plugin.append_import_external_resource(png_path)
			if err: return _Models.ExportResultModel.fail(err, "An error occured while appending import external resource (atlas texture)")
			export_result_model.sprite_sheet.atlas = \
				ResourceLoader.load(png_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
		_: return _Models.ExportResultModel.fail(ERR_INVALID_DATA, "Unexpected atlas resource type: %s" % [atlas_resource_type])
	return export_result_model

func _export(source_file: String, options: Dictionary) -> _Models.ExportResultModel:
	assert(false, "This method is abstract and must be overriden.")
	return _Models.ExportResultModel.fail(ERR_UNCONFIGURED)

enum AnimationOption {
	FramesCount = 1,
	Direction = 2,
	RepeatCount = 4,
}

static func _parse_animation_info(
	raw_animation_info: String,
	animation_options: AnimationOption,
	first_frame: int,
	default_last_frame: int = -1
	) -> _AnimationInfo:
	var __option_regex: RegEx = RegEx.create_from_string("\\s-\\p{L}:\\s*\\S+")
	var __natural_number_regex: RegEx = RegEx.create_from_string("\\A\\d+\\z")

	var animation_info = _AnimationInfo.new()
	animation_info.first_frame = first_frame
	animation_info.last_frame = default_last_frame
	animation_info.direction = -1
	animation_info.repeat_count = -1
	raw_animation_info = raw_animation_info.strip_edges()
	var options_matches: Array[RegExMatch] = __option_regex.search_all(raw_animation_info)
	var first_match_position: int = raw_animation_info.length()
	for option_match in options_matches:
		var match_position: int = option_match.get_start()
		assert(match_position >= 0)
		if match_position < first_match_position:
			first_match_position = match_position
		var raw_option: String = option_match.get_string().strip_edges()
		var raw_value = raw_option.substr(3).strip_edges()
		match raw_option.substr(0, 3):
			"-f:":
				if animation_options & AnimationOption.FramesCount:
					if animation_info.last_frame < 0 and __natural_number_regex.search(raw_value):
						animation_info.last_frame = first_frame + raw_value.to_int() - 1
					else: return null
			"-d:":
				if animation_options & AnimationOption.Direction:
					if  animation_info.direction >= 0: return null
					match raw_value:
						"f": animation_info.direction = _Models.AnimationModel.Direction.FORWARD
						"r": animation_info.direction = _Models.AnimationModel.Direction.REVERSE
						"pp": animation_info.direction = _Models.AnimationModel.Direction.PING_PONG
						"ppr": animation_info.direction = _Models.AnimationModel.Direction.PING_PONG_REVERSE
						_: return null
			"-r:":
				if animation_options & AnimationOption.RepeatCount:
					if animation_info.repeat_count < 0 and __natural_number_regex.search(raw_value):
						var rc: int = raw_value.to_int()
						animation_info.repeat_count = rc
					else: return null
			_: return null
	animation_info.name = raw_animation_info.left(first_match_position)
	if animation_info.first_frame < 0: return null
	if animation_info.last_frame < animation_info.first_frame: return null
	if animation_info.repeat_count < 0: animation_info.repeat_count = 1
	if animation_info.direction < 0: animation_info.direction = _Models.AnimationModel.Direction.FORWARD
	return animation_info

func _create_sprite_sheet_builder(options: Dictionary) -> _SpriteSheetBuilderBase:
	var sprite_sheet_layout: _Models.SpriteSheetModel.Layout = options[_Options.SPRITE_SHEET_LAYOUT]
	return \
	_PackedSpriteSheetBuilder.new(
		options[_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD],
		options[_Options.SPRITES_SURROUNDING_COLOR]) \
	if sprite_sheet_layout == _Models.SpriteSheetModel.Layout.PACKED else \
	_GridBasedSpriteSheetBuilder.new(
		options[_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD],
			_GridBasedSpriteSheetBuilder.StripDirection.HORIZONTAL
			if sprite_sheet_layout == _Models.SpriteSheetModel.Layout.HORIZONTAL_STRIPS else
			_GridBasedSpriteSheetBuilder.StripDirection.HORIZONTAL,
		options[_Options.MAX_CELLS_IN_STRIP],
		options[_Options.TRIM_SPRITES_TO_OVERALL_MIN_SIZE],
		options[_Options.COLLAPSE_TRANSPARENT_SPRITES],
		options[_Options.MERGE_DUPLICATED_SPRITES],
		options[_Options.SPRITES_SURROUNDING_COLOR])
