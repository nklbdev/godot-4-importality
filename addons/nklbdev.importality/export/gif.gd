extends "_.gd"

# best!!! https://commandlinefanatic.com/cgi-bin/showarticle.cgi?article=art011
# https://www.fileformat.info/format/gif/egff.htm

#const _XML = preload("../xml.gd")
#const _SpriteSheetBuilderBase = preload("../sprite_sheet_builder/_.gd")
#const _GridBasedSpriteSheetBuilder = preload("../sprite_sheet_builder/grid_based.gd")
#const _PackedSpriteSheetBuilder = preload("../sprite_sheet_builder/packed.gd")

#const __FRAMES_RANGES_OPTION: StringName = "importers/pencil2d/frames_ranges"

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["gif"]
	super("GIF", recognized_extensions, [
	#	_Options.create_option(__FRAMES_RANGES_OPTION, [],# PackedStringArray(),
	#	PROPERTY_HINT_ARRAY_TYPE, "a:%s,b:%s" % [TYPE_INT, TYPE_STRING], PROPERTY_USAGE_DEFAULT),
	], editor_file_system, [
	], CustomImageFormatLoaderExtension.new(recognized_extensions))

func _export(res_source_file_path: String, options: Dictionary) -> _Models.ExportResultModel:
	var sprite_sheet_model: _Models.SpriteSheetModel = _Models.SpriteSheetModel.new()
	var animation_library_model: _Models.AnimationLibraryModel = _Models.AnimationLibraryModel.new()
	return _Models.ExportResultModel.success(sprite_sheet_model, animation_library_model)

class CustomImageFormatLoaderExtension:
	extends ImageFormatLoaderExtension

	var __recognized_extensions: PackedStringArray

	func _init(recognized_extensions: PackedStringArray) -> void:
		__recognized_extensions = recognized_extensions

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
		image.set_data(1, 1, false, Image.FORMAT_RGBA8, [0x00, 0x00, 0x00, 0xFF])
		image.resize(64, 64)
		image.fill(Color.RED)
		return OK
