@tool

const _Common = preload("../common.gd")
const _Export = preload("_.gd")
const _Options = preload("../options.gd")

enum PxoLayerType {
	PIXEL_LAYER = 0,
	GROUP_LAYER = 1,
	LAYER_3D = 2,
}

static func _open_pxo_file(res_source_file_path: String) -> FileAccess:
	var file: FileAccess = FileAccess.open_compressed(res_source_file_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null or file.get_open_error() == ERR_FILE_UNRECOGNIZED:
		file = FileAccess.open(res_source_file_path, FileAccess.READ)
	return file

static func export(res_source_file_path: String, options: Dictionary) -> _Export.ExportResult:
	var result := _Export.ExportResult.new()

	var file: FileAccess = _open_pxo_file(res_source_file_path)
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

	var pxo_project = JSON.parse_string(first_line)
	if not pxo_project is Dictionary:
		result.fail(ERR_PARSE_ERROR, "Failed to parse pxo file: expected JSON object on first line")
		return result

	var image_size: Vector2i = Vector2i(pxo_project.size_x, pxo_project.size_y)
	var pxo_cel_image_buffer_size: int = image_size.x * image_size.y * 4
	var image_rect: Rect2i = Rect2i(Vector2i.ZERO, image_size)
	var split_layers: bool = options.get(_Options.SPLIT_LAYERS, false)
	var layer_name_first: bool = options.get(_Options.LAYERS_ANIMATION_NAME_FORMAT, 0) == 0
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()

	# Count pixel layers (needed for buffer offset calculation)
	var pixel_layers_count: int = 0
	for pxo_layer in pxo_project.layers:
		if pxo_layer.type == PxoLayerType.PIXEL_LAYER:
			pixel_layers_count += 1

	# Resolve tags with default fallback
	var use_default_tag: bool = pxo_project.tags.is_empty()
	if use_default_tag:
		var default_animation_name: String = options[_Options.DEFAULT_ANIMATION_NAME].strip_edges()
		if default_animation_name.is_empty():
			default_animation_name = "default"
		pxo_project.tags.push_back({
			name = default_animation_name,
			from = 1,
			to = pxo_project.frames.size()})

	# Parse all tags
	var parsed_tags: Array = []
	for pxo_tag in pxo_project.tags:
		var animation_frames_count: int = pxo_tag.to + 1 - pxo_tag.from
		var params := _Export._parse_animation_params(
			pxo_tag.name,
			_Export.AnimationOptions.Direction | _Export.AnimationOptions.RepeatCount,
			pxo_tag.from - 1, animation_frames_count)
		if params.error:
			result.fail(ERR_CANT_RESOLVE, "Failed to parse animation parameters", params)
			return result
		var direction: _Common.AnimationDirection = params.direction
		var repeat_count: int = params.repeat_count
		if not use_default_tag:
			var tag_ud: String = pxo_tag.get("user_data", "")
			if not tag_ud.is_empty() and (direction < 0 or repeat_count < 0):
				var ud := _Export._parse_animation_params(tag_ud,
					_Export.AnimationOptions.Direction | _Export.AnimationOptions.RepeatCount,
					pxo_tag.from - 1, animation_frames_count)
				if direction < 0: direction = ud.direction
				if repeat_count < 0: repeat_count = ud.repeat_count
		if direction < 0:
			direction = options[_Options.DEFAULT_ANIMATION_DIRECTION] as _Common.AnimationDirection
		if repeat_count < 0:
			repeat_count = options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT] as int
		parsed_tags.push_back({
			name = params.name,
			direction = direction,
			repeat_count = repeat_count,
			from = pxo_tag.from - 1,
			to = pxo_tag.to - 1,
		})

	# Collect the set of frame indices needed across all tags
	var needed_fi_set: Dictionary = {}
	for pt in parsed_tags:
		for fi in range(pt.from, pt.to + 1):
			needed_fi_set[fi] = true
	var needed_fi: PackedInt32Array = PackedInt32Array(needed_fi_set.keys())
	needed_fi.sort()

	# Build layer_infos.
	# Non-split: one info with pixel_layer_index = -1 (composite all visible layers).
	# Split: one info per visible pixel layer.
	# Each info: {pixel_layer_index, name_prefix, name_suffix, canvas_offset}
	var layer_infos: Array = []

	if not split_layers:
		layer_infos.push_back({
			pixel_layer_index = -1, name_prefix = "", name_suffix = "", canvas_offset = Vector2i.ZERO})
	else:
		var pli: int = 0
		for li in pxo_project.layers.size():
			var pxo_layer: Dictionary = pxo_project.layers[li]
			if pxo_layer.type != PxoLayerType.PIXEL_LAYER:
				continue
			var cur_pli: int = pli
			pli += 1
			# Check effective visibility
			var visible: bool = true
			var l: Dictionary = pxo_layer
			while true:
				if not l.visible:
					visible = false
					break
				if l.parent < 0:
					break
				l = pxo_project.layers[l.parent]
			if not visible:
				continue
			var name_params := _Export._parse_layer_params(pxo_layer.name)
			if name_params.error:
				result.fail(ERR_INVALID_DATA, "Failed to parse layer name params for \"%s\"" % pxo_layer.name, name_params)
				return result
			var display_name: String = name_params.name
			var canvas_offset: Vector2i = name_params.canvas_offset
			var layer_ud: String = pxo_layer.get("user_data", "")
			if not layer_ud.is_empty() and canvas_offset == Vector2i.ZERO:
				var ud := _Export._parse_layer_params(layer_ud)
				if not ud.error: canvas_offset = ud.canvas_offset
			layer_infos.push_back({
				pixel_layer_index = cur_pli,
				name_prefix = display_name + "/" if layer_name_first else "",
				name_suffix = "" if layer_name_first else "/" + display_name,
				canvas_offset = canvas_offset,
			})

		if layer_infos.is_empty():
			result.fail(ERR_INVALID_DATA, "No visible pixel layers found in Pixelorama project.")
			return result

	# Collect all frame images, applying canvas offsets where needed
	var all_frame_images: Array[Image] = []
	var sprite_indices: Array = []  # Array of Dict[fi -> sprite_sheet_index]
	var pxo_cel_image: Image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)

	for info in layer_infos:
		var sidx: Dictionary = {}
		for fi in needed_fi:
			var img: Image
			if info.pixel_layer_index < 0:
				# Composite all visible pixel layers for this frame
				img = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
				var pli2: int = 0
				var pxo_frame: Dictionary = pxo_project.frames[fi]
				for cel_index in pxo_frame.cels.size():
					var pxo_cel = pxo_frame.cels[cel_index]
					var pxo_layer = pxo_project.layers[cel_index]
					if pxo_layer.type != PxoLayerType.PIXEL_LAYER:
						continue
					var cur_pli2: int = pli2
					pli2 += 1
					var l: Dictionary = pxo_layer
					while l.parent >= 0 and pxo_layer.visible:
						if not l.visible:
							pxo_layer.visible = false
							break
						l = pxo_project.layers[l.parent]
					var pxo_cel_opacity: float = pxo_cel.opacity
					if not pxo_layer.visible or pxo_cel_opacity == 0:
						continue
					var offset: int = pxo_cel_image_buffer_size * (pixel_layers_count * fi + cur_pli2)
					var pxo_cel_image_buffer: PackedByteArray = images_data.slice(offset, offset + pxo_cel_image_buffer_size)
					for alpha_index in range(3, pxo_cel_image_buffer_size, 4):
						pxo_cel_image_buffer[alpha_index] = roundi(pxo_cel_image_buffer[alpha_index] * pxo_cel_opacity)
					pxo_cel_image.set_data(image_size.x, image_size.y, false, Image.FORMAT_RGBA8, pxo_cel_image_buffer)
					img.blend_rect(pxo_cel_image, image_rect, Vector2i.ZERO)
			else:
				# Single layer raw data
				var offset: int = pxo_cel_image_buffer_size * (pixel_layers_count * fi + info.pixel_layer_index)
				var cel_data: PackedByteArray = images_data.slice(offset, offset + pxo_cel_image_buffer_size)
				img = Image.create_from_data(image_size.x, image_size.y, false, Image.FORMAT_RGBA8, cel_data)
			if info.canvas_offset != Vector2i.ZERO:
				var shifted := Image.create_empty(image_size.x, image_size.y, false, Image.FORMAT_RGBA8)
				shifted.blit_rect(img,
					Rect2i(info.canvas_offset.x, info.canvas_offset.y, image_size.x, image_size.y),
					Vector2i.ZERO)
				img = shifted
			sidx[fi] = all_frame_images.size()
			all_frame_images.push_back(img)
		sprite_indices.push_back(sidx)

	# Build sprite sheet
	var sprite_sheet_builder := _Export._create_sprite_sheet_builder(options)
	var build_result := sprite_sheet_builder.build_sprite_sheet(all_frame_images)
	if build_result.error:
		result.fail(ERR_BUG, "Sprite sheet building failed", build_result)
		return result
	var sprite_sheet: _Common.SpriteSheetInfo = build_result.sprite_sheet

	# Create animations — identical loop for both split and non-split
	var animation_library := _Common.AnimationLibraryInfo.new()
	for di in layer_infos.size():
		var info: Dictionary = layer_infos[di]
		var sidx: Dictionary = sprite_indices[di]
		var unqualified: bool = info.name_prefix.is_empty() and info.name_suffix.is_empty()
		for pt in parsed_tags:
			var anim_name: String = info.name_prefix + pt.name + info.name_suffix
			var animation := _Common.AnimationInfo.new()
			animation.name = anim_name
			animation.direction = pt.direction
			animation.repeat_count = pt.repeat_count
			for fi in range(pt.from, pt.to + 1):
				var frame := _Common.FrameInfo.new()
				frame.duration = pxo_project.frames[fi].duration / pxo_project.fps
				frame.sprite = sprite_sheet.sprites[sidx[fi]]
				animation.frames.push_back(frame)
			if unqualified and anim_name == autoplay_animation_name:
				animation_library.autoplay_index = animation_library.animations.size()
			animation_library.animations.push_back(animation)
	if not split_layers and not autoplay_animation_name.is_empty() \
			and animation_library.autoplay_index < 0:
		push_warning("Autoplay animation name not found: \"%s\". Continuing..." % [autoplay_animation_name])

	result.success(build_result.atlas_image, sprite_sheet, animation_library)
	return result

static func load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
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

	var pxo_project = JSON.parse_string(first_line)
	if not pxo_project is Dictionary:
		push_error("Failed to parse pxo file: expected JSON object on first line")
		return ERR_PARSE_ERROR
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
