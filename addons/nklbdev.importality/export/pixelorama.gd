extends "_.gd"

enum PxoLayerType {
	PIXEL_LAYER = 0,
	GROUP_LAYER = 1,
	LAYER_3D = 2,
}

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["pxo"]
	super("Pixelorama", recognized_extensions, [
	], editor_file_system, [
		# settings
	], CustomImageFormatLoaderExtension.new(recognized_extensions))

func _export(res_source_file_path: String, options: Dictionary) -> _Models.ExportResultModel:
	var file: FileAccess = FileAccess.open_compressed(res_source_file_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null and file.get_open_error() == ERR_FILE_UNRECOGNIZED:
		file.open(res_source_file_path, FileAccess.READ)
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

	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME]
	var unique_frames_models_indices_by_frame_index: Dictionary
	var unique_frames_models: Array[_Models.FrameModel]
	var unique_frames_images: Array[Image]
	var unique_frames_count: int
	var pixel_layer_index: int
	var image_rect: Rect2i = Rect2i(Vector2i.ZERO, image_size)
	var frame_model: _Models.FrameModel
	var animations_count: int = pxo_project.tags.size()
	var animation_library_model: _Models.AnimationLibraryModel = _Models.AnimationLibraryModel.new()
	animation_library_model.animations.resize(animations_count)
	var pxo_cel_opacity: float
	var unique_animation_names: PackedStringArray
	for animation_index in animations_count:
		var pxo_tag: Dictionary = pxo_project.tags[animation_index]
		var animation_model: _Models.AnimationModel = _Models.AnimationModel.new()
		animation_library_model.animations[animation_index] = animation_model
		animation_model.name = pxo_tag.name
		if animation_model.name == autoplay_animation_name:
			animation_library_model.autoplay_animation_index = animation_index
		animation_model.direction = _Models.AnimationModel.Direction.FORWARD
		animation_model.repeat_count = 1
		var animation_frames_count: int = pxo_tag.to + 1 - pxo_tag.from
		animation_model.frames.resize(animation_frames_count)

		var frame_image: Image
		for animation_frame_index in animation_frames_count:
			var frame_index: int = pxo_tag.from - 1 + animation_frame_index
			var unique_frame_index: int = unique_frames_models_indices_by_frame_index.get(frame_index, -1)
			if unique_frame_index >= 0:
				frame_model = unique_frames_models[unique_frame_index]
			else:
				frame_model = _Models.FrameModel.new()
				unique_frames_models.push_back(frame_model)
				frame_image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
				unique_frames_images.push_back(frame_image)
				unique_frame_index = unique_frames_count
				unique_frames_count += 1
				pixel_layer_index = -1
				var pxo_frame: Dictionary = pxo_project.frames[frame_index]
				frame_model.duration = pxo_frame.duration / pxo_project.fps
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
				unique_frames_models_indices_by_frame_index[frame_index] = unique_frame_index
			animation_model.frames[animation_frame_index] = frame_model
	if not autoplay_animation_name.is_empty() and animation_library_model.autoplay_animation_index < 0:
		push_warning("Autoplay animation name not found: \"%s\". Continuing..." % [autoplay_animation_name])

	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)

	var sprite_sheet_building_result: _SpriteSheetBuilderBase.Result = \
		sprite_sheet_builder.build_sprite_sheet(unique_frames_images)
	if sprite_sheet_building_result.error:
		return _Models.ExportResultModel.fail(sprite_sheet_building_result.error,
			"Sprite sheet building failed: " + sprite_sheet_building_result.error_message)
	var sprite_sheet_model: _Models.SpriteSheetModel = sprite_sheet_building_result.sprite_sheet

	for unique_frame_index in unique_frames_count:
		var unique_frame_model: _Models.FrameModel = unique_frames_models[unique_frame_index]
		unique_frame_model.sprite = sprite_sheet_model.sprites[unique_frame_index]

	return _Models.ExportResultModel.success(sprite_sheet_model, animation_library_model)

class CustomImageFormatLoaderExtension:
	extends ImageFormatLoaderExtension

	var __recognized_extensions: PackedStringArray

	func _init(recognized_extensions: PackedStringArray) -> void:
		__recognized_extensions = recognized_extensions

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
		var file: FileAccess = FileAccess.open_compressed(file_access.get_path(), FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if file == null and file.get_open_error() == ERR_FILE_UNRECOGNIZED:
			file.open(file_access.get_path(), FileAccess.READ)
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

