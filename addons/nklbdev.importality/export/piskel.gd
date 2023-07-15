extends "_.gd"

const __ANIMATIONS_INFOS_OPTION: StringName = "piskel/animations_infos"

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["piskel"]
	super("Piskel", recognized_extensions, [
		_Options.create_option(__ANIMATIONS_INFOS_OPTION, PackedStringArray(),
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	], editor_file_system, [
	], CustomImageFormatLoaderExtension.new(recognized_extensions))

func _export(res_source_file_path: String, options: Dictionary) -> _Models.ExportResultModel:
	var raw_animations_infos: PackedStringArray = options[__ANIMATIONS_INFOS_OPTION]
	var animations_infos: Array[_AnimationInfo]
	animations_infos.resize(raw_animations_infos.size())
	var unique_animations_names: PackedStringArray
	var frame_indices_to_export
	var unique_frames_count: int = 0
	var animation_first_frame: int = 0
	for raw_animation_info_index in raw_animations_infos.size():
		var raw_animation_info: String = raw_animations_infos[raw_animation_info_index]
		var animation_info: _AnimationInfo = _parse_animation_info(
			raw_animation_info,
			AnimationOption.FramesCount | AnimationOption.Direction | AnimationOption.RepeatCount,
			animation_first_frame)
		if animation_info == null:
			return _Models.ExportResultModel.fail(ERR_INVALID_DATA, "Invalid animation info format at element %s. Use \"name -f:frames_count [-d: direction] [-r: repeat_count]\" where direction can be: f(forward - default), r(reverse), pp(ping-pong), ppr(ping-pong reverse) and repeat_count is positive integer or 0 (default) for infinite loop" % raw_animation_info_index)
		if unique_animations_names.has(animation_info.name):
			return _Models.ExportResultModel.fail(ERR_INVALID_DATA, "Duplicated animation name at index: %s" % raw_animation_info_index)
		unique_animations_names.push_back(animation_info.name)
		unique_frames_count += animation_info.last_frame - animation_info.first_frame + 1
		animation_first_frame = animation_info.last_frame + 1
		animations_infos[raw_animation_info_index] = animation_info

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

	var sprite_sheet_building_result: _SpriteSheetBuilderBase.Result = \
		sprite_sheet_builder.build_sprite_sheet(frames_images)
	if sprite_sheet_building_result.error:
		return _Models.ExportResultModel.fail(sprite_sheet_building_result.error,
			"Sprite sheet building failed: " + sprite_sheet_building_result.error_message)
	var sprite_sheet_model: _Models.SpriteSheetModel = sprite_sheet_building_result.sprite_sheet

	var animation_library_model: _Models.AnimationLibraryModel = _Models.AnimationLibraryModel.new()
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()

	var frames_duration: float = 1.0 / piskel.fps
	var all_frames: Array[_Models.FrameModel]
	all_frames.resize(unique_frames_count)
	for animation_index in animations_infos.size():
		var animation_info: _AnimationInfo = animations_infos[animation_index]
		var animation_model = _Models.AnimationModel.new()
		animation_model.name = animation_info.name
		if animation_info.name == autoplay_animation_name:
			animation_library_model.autoplay_animation_index = animation_index
		animation_model.direction = animation_info.direction
		animation_model.repeat_count = animation_info.repeat_count
		for global_frame_index in range(animation_info.first_frame, animation_info.last_frame + 1):
			var frame_model: _Models.FrameModel = all_frames[global_frame_index]
			if frame_model == null:
				frame_model = _Models.FrameModel.new()
				frame_model.sprite = sprite_sheet_model.sprites[global_frame_index]
				frame_model.duration = frames_duration
				all_frames[global_frame_index] = frame_model
			animation_model.frames.push_back(frame_model)
		animation_library_model.animations.push_back(animation_model)
	if not autoplay_animation_name.is_empty() and animation_library_model.autoplay_animation_index < 0:
		push_warning("Autoplay animation name not found: \"%s\". Continuing..." % [autoplay_animation_name])

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
