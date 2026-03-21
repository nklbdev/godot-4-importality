@tool
extends "_.gd"

const __ANIMATIONS_PARAMETERS_OPTION: StringName = &"piskel/animations_parameters"

func _init() -> void:
	var recognized_extensions: PackedStringArray = ["piskel"]
	super("Piskel", recognized_extensions, [
		_Options.create_option(__ANIMATIONS_PARAMETERS_OPTION, PackedStringArray(),
			PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
		_Options.create_option(_Options.SPLIT_LAYERS, false,
			PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_UPDATE_ALL_IF_MODIFIED),
		_Options.create_option(_Options.LAYERS_ANIMATION_NAME_FORMAT, 0,
			PROPERTY_HINT_ENUM, "layer_name/tag_name,tag_name/layer_name", PROPERTY_USAGE_DEFAULT,
			func(o): return o.get(_Options.SPLIT_LAYERS, false)),
		],
		[],
		CustomImageFormatLoaderExtension.new(recognized_extensions))

func _export(res_source_file_path: String, options: Dictionary) -> ExportResult:
	var result: ExportResult = ExportResult.new()

	var raw_animations_params_list: PackedStringArray = options[__ANIMATIONS_PARAMETERS_OPTION]
	var animations_params_parsing_results: Array[AnimationParamsParsingResult]
	animations_params_parsing_results.resize(raw_animations_params_list.size())
	var unique_animations_names: PackedStringArray
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
	var piskel: Dictionary = document.piskel
	var image_size: Vector2i = Vector2i(piskel.width, piskel.height)
	var split_layers: bool = options.get(_Options.SPLIT_LAYERS, false)
	var layer_name_first: bool = options.get(_Options.LAYERS_ANIMATION_NAME_FORMAT, 0) == 0
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()

	# Parse all Piskel layers and load their strip images.
	# Each entry: {strip: Image, display_name: String, canvas_offset: Vector2i}
	var parsed_layers: Array = []
	for layer_string in piskel.layers:
		var layer: Dictionary = JSON.parse_string(layer_string)
		var layer_strip: Image = null
		for chunk in layer.chunks:
			layer_strip = Image.new()
			layer_strip.load_png_from_buffer(Marshalls.base64_to_raw(
				chunk.base64PNG.trim_prefix("data:image/png;base64,")))
		if layer_strip == null:
			continue
		var name_params := _parse_layer_params(layer.name)
		if name_params.error:
			result.fail(ERR_INVALID_DATA, "Failed to parse layer name params for \"%s\"" % layer.name, name_params)
			return result
		parsed_layers.push_back({
			strip = layer_strip,
			display_name = name_params.name,
			canvas_offset = name_params.canvas_offset,
		})

	if parsed_layers.is_empty():
		result.fail(ERR_INVALID_DATA, "Piskel file has no layers")
		return result

	# Build layer_infos.
	# Non-split: one info with layer_index = -1 (composite all layers).
	# Split: one info per layer.
	# Each info: {layer_index, name_prefix, name_suffix, canvas_offset}
	var layer_infos: Array = []
	if not split_layers:
		layer_infos.push_back({
			layer_index = -1, name_prefix = "", name_suffix = "", canvas_offset = Vector2i.ZERO})
	else:
		for li in parsed_layers.size():
			var pl: Dictionary = parsed_layers[li]
			layer_infos.push_back({
				layer_index = li,
				name_prefix = pl.display_name + "/" if layer_name_first else "",
				name_suffix = "" if layer_name_first else "/" + pl.display_name,
				canvas_offset = pl.canvas_offset,
			})

	# Collect all frame images, applying canvas offsets where needed
	var all_frame_images: Array[Image] = []
	var sprite_indices: Array = []  # Array of Dict[fi -> sprite_sheet_index]

	for info in layer_infos:
		var sidx: Dictionary = {}
		for fi in unique_frames_count:
			var img: Image
			if info.layer_index < 0:
				# Composite all layers for this frame
				img = Image.create_empty(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
				for pl in parsed_layers:
					var layer_frame: Image = pl.strip.get_region(
						Rect2i(Vector2i(fi * image_size.x, 0), image_size))
					img.blend_rect(layer_frame, Rect2i(Vector2i.ZERO, image_size), Vector2i.ZERO)
			else:
				var pl: Dictionary = parsed_layers[info.layer_index]
				img = pl.strip.get_region(Rect2i(Vector2i(fi * image_size.x, 0), image_size))
			if info.canvas_offset != Vector2i.ZERO:
				var shifted := Image.create_empty(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
				shifted.blit_rect(img,
					Rect2i(info.canvas_offset.x, info.canvas_offset.y, image_size.x, image_size.y),
					Vector2i.ZERO)
				img = shifted
			sidx[fi] = all_frame_images.size()
			all_frame_images.push_back(img)
		sprite_indices.push_back(sidx)

	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)
	var sprite_sheet_building_result: _SpriteSheetBuilderBase.SpriteSheetBuildingResult = \
		sprite_sheet_builder.build_sprite_sheet(all_frame_images)
	if sprite_sheet_building_result.error:
		result.fail(ERR_BUG, "Sprite sheet building failed", sprite_sheet_building_result)
		return result
	var sprite_sheet: _Common.SpriteSheetInfo = sprite_sheet_building_result.sprite_sheet

	# Create animations — identical loop for both split and non-split
	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	var frames_duration: float = 1.0 / piskel.fps
	for di in layer_infos.size():
		var info: Dictionary = layer_infos[di]
		var sidx: Dictionary = sprite_indices[di]
		var unqualified: bool = info.name_prefix.is_empty() and info.name_suffix.is_empty()
		for animation_index in animations_params_parsing_results.size():
			var apr: AnimationParamsParsingResult = animations_params_parsing_results[animation_index]
			var anim_name: String = info.name_prefix + apr.name + info.name_suffix
			var animation = _Common.AnimationInfo.new()
			animation.name = anim_name
			animation.direction = apr.direction
			if animation.direction < 0:
				animation.direction = _Common.AnimationDirection.FORWARD
			animation.repeat_count = apr.repeat_count
			if animation.repeat_count < 0:
				animation.repeat_count = 1
			for animation_frame_index in apr.frames_count:
				var fi: int = apr.first_frame_index + animation_frame_index
				var frame := _Common.FrameInfo.new()
				frame.sprite = sprite_sheet.sprites[sidx[fi]]
				frame.duration = frames_duration
				animation.frames.push_back(frame)
			if unqualified and anim_name == autoplay_animation_name:
				animation_library.autoplay_index = animation_library.animations.size()
			animation_library.animations.push_back(animation)
	if not split_layers and not autoplay_animation_name.is_empty() \
			and animation_library.autoplay_index < 0:
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
