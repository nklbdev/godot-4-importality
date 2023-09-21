@tool
extends "_.gd"

const __ANIMATIONS_PARAMETERS_OPTION: StringName = "piskel/animations_parameters"

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["piskel"]
	super("Piskel", recognized_extensions, [
		_Options.create_option(__ANIMATIONS_PARAMETERS_OPTION, PackedStringArray(),
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT)],
		[],
		CustomImageFormatLoaderExtension.new(recognized_extensions))

func _export(res_source_file_path: String, options: Dictionary) -> ExportResult:
	var result: ExportResult = ExportResult.new()

	var raw_animations_params_list: PackedStringArray = options[__ANIMATIONS_PARAMETERS_OPTION]
	var animations_params_parsing_results: Array[AnimationParamsParsingResult]
	animations_params_parsing_results.resize(raw_animations_params_list.size())
	var unique_animations_names: PackedStringArray
	var frame_indices_to_export
	var unique_frames_count: int = 0
	var animation_first_frame_index: int = 0
	for animation_index in raw_animations_params_list.size():
		var raw_animation_params: String = raw_animations_params_list[animation_index]
		var animation_params_parsing_result: AnimationParamsParsingResult = _parse_animation_params(
			raw_animation_params,
			AnimationOptions.FramesCount | AnimationOptions.Direction | AnimationOptions.RepeatCount,
			animation_first_frame_index)
		if animation_params_parsing_result.error:
			result.fail(ERR_CANT_RESOLVE, "Failed to parse animation parameters", animation_params_parsing_result)
			return result
		if unique_animations_names.has(animation_params_parsing_result.name):
			result.fail(ERR_INVALID_DATA, "Duplicated animation name \"%s\" at index: %s" %
				[animation_params_parsing_result.name, animation_index])
			return result
		unique_animations_names.push_back(animation_params_parsing_result.name)
		unique_frames_count += animation_params_parsing_result.frames_count
		animation_first_frame_index += animation_params_parsing_result.frames_count
		animations_params_parsing_results[animation_index] = animation_params_parsing_result

	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(res_source_file_path))
	document.modelVersion #int 2
	var piskel: Dictionary = document.piskel
	piskel.name #string New Piskel
	piskel.description #string asdfasdfasdf
	piskel.fps #int 12,
	var image_size: Vector2i = Vector2i(piskel.width, piskel.height)
#	piskel.hiddenFrames#Array may absend
	var blended_layers: Image
	var layer_image: Image = Image.new()
	var frames_count: int
	var layer_image_size: Vector2i = image_size
	for layer_string in piskel.layers: #Array
		var layer: Dictionary = JSON.parse_string(layer_string)
		layer.name #string layer 1
		layer.opacity #float 1
		if frames_count == 0:
			frames_count = layer.frameCount
			layer_image_size.x = image_size.x * frames_count
		else:
			assert(frames_count == layer.frameCount)
		for chunk in layer.chunks:
			# chunk.layout # array [ [ 0 ], [ 1 ], [ 2 ] ]
			layer_image.load_png_from_buffer(Marshalls.base64_to_raw(chunk.base64PNG.trim_prefix("data:image/png;base64,")))
			assert(layer_image.get_size() == layer_image_size)
			if blended_layers == null:
				blended_layers = layer_image
				layer_image = Image.new()
			else:
				blended_layers.blend_rect(layer_image, Rect2i(Vector2i.ZERO, layer_image.get_size()), Vector2i.ZERO)

	var frames_images: Array[Image]
	frames_images.resize(frames_count)
	for frame_index in frames_count:
		frames_images[frame_index] = blended_layers.get_region(
			Rect2i(Vector2i(frame_index * image_size.x, 0), image_size))

	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)

	var sprite_sheet_building_result: _SpriteSheetBuilderBase.SpriteSheetBuildingResult = \
		sprite_sheet_builder.build_sprite_sheet(frames_images)
	if sprite_sheet_building_result.error:
		result.fail(ERR_BUG, "Sprite sheet building failed", sprite_sheet_building_result)
		return result
	var sprite_sheet: _Common.SpriteSheetInfo = sprite_sheet_building_result.sprite_sheet

	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()

	var frames_duration: float = 1.0 / piskel.fps
	var all_frames: Array[_Common.FrameInfo]
	all_frames.resize(unique_frames_count)
	for animation_index in animations_params_parsing_results.size():
		var animation_params_parsing_result: AnimationParamsParsingResult = animations_params_parsing_results[animation_index]
		var animation = _Common.AnimationInfo.new()
		animation.name = animation_params_parsing_result.name
		if animation.name == autoplay_animation_name:
			animation_library.autoplay_index = animation_index
		animation.direction = animation_params_parsing_result.direction
		if animation.direction < 0:
			animation.direction = _Common.AnimationDirection.FORWARD
		animation.repeat_count = animation_params_parsing_result.repeat_count
		if animation.repeat_count < 0:
			animation.repeat_count = 1
		for animation_frame_index in animation_params_parsing_result.frames_count:
			var global_frame_index: int = animation_params_parsing_result.first_frame_index + animation_frame_index
			var frame: _Common.FrameInfo = all_frames[global_frame_index]
			if frame == null:
				frame = _Common.FrameInfo.new()
				frame.sprite = sprite_sheet.sprites[global_frame_index]
				frame.duration = frames_duration
				all_frames[global_frame_index] = frame
			animation.frames.push_back(frame)
		animation_library.animations.push_back(animation)
	if not autoplay_animation_name.is_empty() and animation_library.autoplay_index < 0:
		push_warning("Autoplay animation name not found: \"%s\". Continuing..." % [autoplay_animation_name])

	result.success(sprite_sheet_building_result.atlas_image, sprite_sheet, animation_library)
	return result

class CustomImageFormatLoaderExtension:
	extends ImageFormatLoaderExtension

	var __recognized_extensions: PackedStringArray

	func _init(recognized_extensions: PackedStringArray) -> void:
		__recognized_extensions = recognized_extensions

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:

		var document: Dictionary = JSON.parse_string(file_access.get_as_text())
		var piskel: Dictionary = document.piskel
		var image_size: Vector2i = Vector2i(piskel.width, piskel.height)
		var image_rect: Rect2i = Rect2i(Vector2i.ZERO, image_size)
		image.set_data(1, 1, false, Image.FORMAT_RGBA8, [0, 0, 0, 0])
		image.resize(image_size.x, image_size.y)
		var layer_image: Image = Image.new()
		for layer_string in piskel.layers: #Array
			var layer: Dictionary = JSON.parse_string(layer_string)
			layer.opacity #float 1
			for chunk in layer.chunks:
				# chunk.layout # array [ [ 0 ], [ 1 ], [ 2 ] ]
				layer_image.load_png_from_buffer(Marshalls.base64_to_raw(chunk.base64PNG.trim_prefix("data:image/png;base64,")))
				image.blend_rect(layer_image, image_rect, Vector2i.ZERO)
		return OK
