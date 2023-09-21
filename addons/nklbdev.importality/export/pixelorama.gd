@tool
extends "_.gd"

enum PxoLayerType {
	PIXEL_LAYER = 0,
	GROUP_LAYER = 1,
	LAYER_3D = 2,
}

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["pxo"]
	super("Pixelorama", recognized_extensions, [
	], [
		# settings
	], CustomImageFormatLoaderExtension.new(recognized_extensions))

func _export(res_source_file_path: String, options: Dictionary) -> ExportResult:
	var result: ExportResult = ExportResult.new()

	var file: FileAccess = FileAccess.open_compressed(res_source_file_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null or file.get_open_error() == ERR_FILE_UNRECOGNIZED:
		file = FileAccess.open(res_source_file_path, FileAccess.READ)
	if file == null:
		result.fail(ERR_FILE_CANT_OPEN, "Failed to open file with unknown error")
		return result
	var open_error: Error = file.get_open_error()
	if open_error:
		result.fail(ERR_FILE_CANT_OPEN, "Failed to open file with error: %s \"%s\"" % [open_error, error_string(open_error)])
		return result

	var first_line: String = file.get_line()
	var images_data: PackedByteArray = file.get_buffer(file.get_length() - file.get_position())
	file.close()

	var pxo_project: Dictionary = JSON.parse_string(first_line)
	var image_size: Vector2i = Vector2i(pxo_project.size_x, pxo_project.size_y)
	var pxo_cel_image_buffer_size: int = image_size.x * image_size.y * 4
	var pxo_cel_image_buffer_offset: int
	var pxo_cel_image: Image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
	var pixel_layers_count: int
	for pxo_layer in pxo_project.layers:
		if pxo_layer.type == PxoLayerType.PIXEL_LAYER:
			pixel_layers_count += 1

	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()
	var unique_frames_indices_by_frame_index: Dictionary
	var unique_frames: Array[_Common.FrameInfo]
	var unique_frames_images: Array[Image]
	var unique_frames_count: int
	var pixel_layer_index: int
	var image_rect: Rect2i = Rect2i(Vector2i.ZERO, image_size)
	var frame: _Common.FrameInfo


	var is_animation_default: bool = pxo_project.tags.is_empty()
	if is_animation_default:
		var default_animation_name: String = options[_Options.DEFAULT_ANIMATION_NAME].strip_edges()
		if default_animation_name.is_empty():
			default_animation_name = "default"
		pxo_project.tags.push_back({
			name = default_animation_name,
			from = 1,
			to = pxo_project.frames.size()})
	var animations_count: int = pxo_project.tags.size()

	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	animation_library.animations.resize(animations_count)
	var pxo_cel_opacity: float
	var unique_animations_names: PackedStringArray
	for animation_index in animations_count:
		var pxo_tag: Dictionary = pxo_project.tags[animation_index]
		var animation: _Common.AnimationInfo = _Common.AnimationInfo.new()
		animation_library.animations[animation_index] = animation
		var animation_frames_count: int = pxo_tag.to + 1 - pxo_tag.from
		if is_animation_default:
			animation.name = pxo_tag.name
			if animation.name == autoplay_animation_name:
				animation_library.autoplay_index = animation_index
			animation.direction = options[_Options.DEFAULT_ANIMATION_DIRECTION]
			animation.repeat_count = options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT]
		else:
			var animation_params_parsing_result: AnimationParamsParsingResult = _parse_animation_params(
				pxo_tag.name, AnimationOptions.Direction | AnimationOptions.RepeatCount,
				pxo_tag.from, animation_frames_count)
			if animation_params_parsing_result.error:
				result.fail(ERR_CANT_RESOLVE, "Failed to parse animation parameters",
					animation_params_parsing_result)
				return result
			if unique_animations_names.has(animation_params_parsing_result.name):
				result.fail(ERR_INVALID_DATA, "Duplicated animation name \"%s\" at index: %s" %
					[animation_params_parsing_result.name, animation_index])
				return result
			unique_animations_names.push_back(animation_params_parsing_result.name)
			animation.name = animation_params_parsing_result.name
			if animation.name == autoplay_animation_name:
				animation_library.autoplay_index = animation_index
			animation.direction = animation_params_parsing_result.direction
			if animation.direction < 0:
				animation.direction = _Common.AnimationDirection.FORWARD
			animation.repeat_count = animation_params_parsing_result.repeat_count
			if animation.repeat_count < 0:
				animation.repeat_count = 1

		animation.frames.resize(animation_frames_count)

		var frame_image: Image
		for animation_frame_index in animation_frames_count:
			var frame_index: int = pxo_tag.from - 1 + animation_frame_index
			var unique_frame_index: int = unique_frames_indices_by_frame_index.get(frame_index, -1)
			if unique_frame_index >= 0:
				frame = unique_frames[unique_frame_index]
			else:
				frame = _Common.FrameInfo.new()
				unique_frames.push_back(frame)
				frame_image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
				unique_frames_images.push_back(frame_image)
				unique_frame_index = unique_frames_count
				unique_frames_count += 1
				pixel_layer_index = -1
				var pxo_frame: Dictionary = pxo_project.frames[frame_index]
				frame.duration = pxo_frame.duration / pxo_project.fps
				for cel_index in pxo_frame.cels.size():
					var pxo_cel = pxo_frame.cels[cel_index]
					var pxo_layer = pxo_project.layers[cel_index]
					if pxo_layer.type == PxoLayerType.PIXEL_LAYER:
						pixel_layer_index += 1
						var l: Dictionary = pxo_layer
						while l.parent >= 0 and pxo_layer.visible:
							if not l.visible:
								pxo_layer.visible = false
								break
							l = pxo_project.layers[l.parent]
						pxo_cel_opacity = pxo_cel.opacity
						if not pxo_layer.visible or pxo_cel_opacity == 0:
							continue
						pxo_cel_image_buffer_offset = pxo_cel_image_buffer_size * \
							(pixel_layers_count * frame_index + pixel_layer_index)
						var pxo_cel_image_buffer: PackedByteArray = images_data.slice(
							pxo_cel_image_buffer_offset,
							pxo_cel_image_buffer_offset + pxo_cel_image_buffer_size)
						for alpha_index in range(3, pxo_cel_image_buffer_size, 4):
							pxo_cel_image_buffer[alpha_index] = roundi(pxo_cel_image_buffer[alpha_index] * pxo_cel_opacity)
						pxo_cel_image.set_data(image_size.x, image_size.y, false, Image.FORMAT_RGBA8, pxo_cel_image_buffer)
						frame_image.blend_rect(pxo_cel_image, image_rect, Vector2i.ZERO)
				unique_frames_indices_by_frame_index[frame_index] = unique_frame_index
			animation.frames[animation_frame_index] = frame
	if not autoplay_animation_name.is_empty() and animation_library.autoplay_index < 0:
		push_warning("Autoplay animation name not found: \"%s\". Continuing..." % [autoplay_animation_name])

	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)

	var sprite_sheet_building_result: _SpriteSheetBuilderBase.SpriteSheetBuildingResult = \
		sprite_sheet_builder.build_sprite_sheet(unique_frames_images)
	if sprite_sheet_building_result.error:
		result.fail(ERR_BUG, "Sprite sheet building failed", sprite_sheet_building_result)
		return result
	var sprite_sheet: _Common.SpriteSheetInfo = sprite_sheet_building_result.sprite_sheet

	for unique_frame_index in unique_frames_count:
		var unique_frame: _Common.FrameInfo = unique_frames[unique_frame_index]
		unique_frame.sprite = sprite_sheet.sprites[unique_frame_index]

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
		var file: FileAccess = FileAccess.open_compressed(file_access.get_path(), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if file == null or file.get_open_error() == ERR_FILE_UNRECOGNIZED:
			file = FileAccess.open(file_access.get_path(), FileAccess.READ)
		if file == null:
			push_error("Failed to open file with unknown error")
			return ERR_FILE_CANT_OPEN
		var open_error: Error = file.get_open_error()
		if open_error:
			push_error("Failed to open file with error: %s \"%s\"" % [open_error, error_string(open_error)])
			return ERR_FILE_CANT_OPEN

		var first_line: String = file.get_line()

		var pxo_project: Dictionary = JSON.parse_string(first_line)
		var image_size: Vector2i = Vector2i(pxo_project.size_x, pxo_project.size_y)
		var pxo_cel_image_buffer_size: int = image_size.x * image_size.y * 4
		var pxo_cel_image_buffer_offset: int
		var pxo_cel_image: Image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
		var pixel_layer_index: int = -1
		image.set_data(1, 1, false, Image.FORMAT_RGBA8, [0, 0, 0, 0])
		image.resize(image_size.x, image_size.y)
		var image_rect: Rect2i = Rect2i(Vector2i.ZERO, image_size)
		for layer_index in pxo_project.layers.size():
			var pxo_layer: Dictionary = pxo_project.layers[layer_index]
			if pxo_layer.type != PxoLayerType.PIXEL_LAYER:
				continue
			pixel_layer_index += 1
			var l: Dictionary = pxo_layer
			while l.parent >= 0 and pxo_layer.visible:
				if not l.visible:
					pxo_layer.visible = false
					break
				l = pxo_project.layers[l.parent]
			if not pxo_layer.visible:
				continue
			var pxo_cel: Dictionary = pxo_project.frames[0].cels[layer_index]
			var pxo_cel_opacity = pxo_cel.opacity
			if pxo_cel_opacity == 0:
				continue
			pxo_cel_image_buffer_offset = pxo_cel_image_buffer_size * layer_index
			var pxo_cel_image_buffer: PackedByteArray = file.get_buffer(pxo_cel_image_buffer_size)
			for alpha_index in range(3, pxo_cel_image_buffer_size, 4):
				pxo_cel_image_buffer[alpha_index] = roundi(pxo_cel_image_buffer[alpha_index] * pxo_cel_opacity)
			pxo_cel_image.set_data(image_size.x, image_size.y, false, Image.FORMAT_RGBA8, pxo_cel_image_buffer)
			image.blend_rect(pxo_cel_image, image_rect, Vector2i.ZERO)
		file.close()
		return OK

