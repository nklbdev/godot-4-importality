extends "_.gd"
# https://github.com/skarik/opengalefile/blob/master/src/galefile2.cpp#L110

const _XML = preload("../xml.gd")

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["gal"]
	super("GraphicsGale", recognized_extensions, [], editor_file_system, [],
	CustomImageFormatLoaderExtension.new(recognized_extensions))

static func int_2_bin(val: int) -> String:
	var str = ""
	for byte_index in 8:
		for bit_index in 8:
			str = str((val >> (byte_index * 8 + bit_index)) & 1) + str
		str = " " + str
		byte_index += 1
	return str

static func __print_chunk(chunk: PackedByteArray, line_length: int) -> void:
	return
	line_length = 8
	prints("chunk size: ", chunk.size())
	var byte_index: int = 0
	for offset in range(0, chunk.size(), line_length):
		var str = ""
		for byte_in_line_index in line_length:
			var val: int = chunk[byte_index]
			for c in 8:
				str = str(val >> c & 1) + str
			str = " " + str
			byte_index += 1
		print(str)
#		print(chunk.slice(offset, offset + line_length))

static func __print_chunk_(chunk: PackedByteArray, line_length: int) -> void:
	prints("chunk size: ", chunk.size())
	for offset in range(0, chunk.size(), line_length):
		print(chunk.slice(offset, offset + line_length).hex_encode())

static func ex(res_source_file_path: String) -> _Common.ExportResult:
	var result = _Common.ExportResult.new()
	var file = FileAccess.open(res_source_file_path, FileAccess.READ)
	var file_length: int = file.get_length()
	var prefix: PackedByteArray = file.get_buffer(8)
	if prefix.get_string_from_utf8() != "GaleX200":
		result.fail(ERR_INVALID_DATA, "Invalid file format: header prefix")
		return result
#	var metadata: Dictionary = __parse_metadata(__get_chunk(file))

	var chunk: PackedByteArray = __get_chunk(file)
	print(chunk.get_string_from_utf8())
	var xml_root: _XML.XMLNodeRoot = _XML.parse_buffer(chunk)
	var xml_frames: _XML.XMLNodeElement = xml_root.get_elements("Frames").front()
	var image_rect: Rect2i = Rect2i(Vector2i.ZERO, xml_frames.get_vector2i("Width", "Height"))
	var frames_count: int = xml_frames.get_int("Count")
	var bit_per_pixel: int = xml_frames.get_int("Bpp")
	var sync_pal: bool = xml_frames.get_bool("SyncPal")
	var randomized: bool = xml_frames.get_bool("Randomized")
	var compression_type: int = xml_frames.get_bool("CompType")
	var compression_level: int = xml_frames.get_bool("CompLevel")
	var background_color: Color = xml_frames.get_int_encoded_hex_color("BGColor", false)
	var block_size: Vector2i = xml_frames.get_vector2i("BlockWidth", "BlockHeight")
	var frames_images: Array[Image]
	frames_images.resize(frames_count)
	var frame_index: int
	for xml_frame in xml_frames.get_elements("Frame"):
#		print("frame")
		var frame_image: Image = Image.create(image_rect.size.x, image_rect.size.y, false, Image.FORMAT_RGBA8)
		var is_frame_has_transparent_color: bool = xml_frame.get_int("TransColor") > -1
		var frame_transparent_color: Color
		if is_frame_has_transparent_color:
			frame_transparent_color = xml_frame.get_int_encoded_hex_color("TransColor", false)
		var frame_duration_ms: int = xml_frame.get_int("Delay")
		var frame_disposal_WHAT_IS_IT: int = xml_frame.get_int("Disposal")
		var xml_layers: _XML.XMLNodeElement = xml_frame.get_elements("Layers").front()
		var layers_size: Vector2i = xml_layers.get_vector2i("Width", "Height")
		var layers_bit_per_pixel: int = xml_layers.get_int("Bpp")
		var palette: PackedColorArray
		if bit_per_pixel < 15:
			var palette_string: String = xml_layers.get_elements("RGB").front().children[0].text
			var palette_size: int = 1 << bit_per_pixel
			palette.resize(palette_size)
			for color_index in palette_size:
				var color_parts: PackedByteArray = palette_string.substr(color_index * 6, 6).hex_decode()
				palette[color_index] = Color(
					color_parts[2] / 255.0,
					color_parts[1] / 255.0,
					color_parts[0] / 255.0)
		print(palette)
		var bytes_per_row: int
		match layers_bit_per_pixel:
			1: bytes_per_row = layers_size.x / 8 + signi(layers_size.x % 8)
			4: bytes_per_row = layers_size.x / 2 + signi(layers_size.x % 2)
			8: bytes_per_row = layers_size.x
			15: pass
			16: bytes_per_row = layers_size.x * 2
			24, 32: bytes_per_row = layers_size.x * 3
		# stepify rows by 4 bytes
		bytes_per_row += signi(bytes_per_row % 4) * 4
		for xml_layer in xml_layers.get_elements("Layer"):
			if not xml_layer.get_bool("Visible"):
				continue
			var layer_rect: Rect2i = Rect2i(xml_layer.get_vector2i("Left", "Top"), layers_size)
			var layer_opacity: float = xml_layer.get_int("Alpha") / 255.0
			var is_layer_has_alpha: bool = xml_layer.get_bool("AlphaOn")
			var color_bytes: PackedByteArray = __get_chunk(file)
			__print_chunk_(color_bytes, 8)
			var alpha_bytes: PackedByteArray = __get_chunk(file)
			__print_chunk_(alpha_bytes, 8 * 1)
			if layer_opacity == 0:
				continue
			var intersection_rect: Rect2i = image_rect.intersection(layer_rect)
			var source_x: int
			var source_y: int
			var color: Color
			for target_y in range(intersection_rect.position.y, intersection_rect.end.y):
				source_y = target_y - layer_rect.position.y
				for target_x in range(intersection_rect.position.x, intersection_rect.end.x):
					source_x = target_x - layer_rect.position.x
					var row_start: int = bytes_per_row * target_y
					match layers_bit_per_pixel:
						1: color = palette[(color_bytes[row_start + target_x / 8] >> (7 - target_x % 8) * 1) & 1]
						4: color = palette[(color_bytes[row_start + target_x / 2] >> (1 - target_x % 2) * 4) & 15]
						8: color = palette[color_bytes[row_start + target_x]]
						15:
							var val: int = color_bytes.decode_u16(row_start + target_x * 2)
							print(int_2_bin(val))
							color = Color(
								((val >> 10) & 0b01_1111) / 31.0, # red - 5 bits
								((val >>  5) & 0b01_1111) / 31.0, # green - 6 bits
								((val >>  0) & 0b01_1111) / 31.0) # blue - 5 bits
						16:
							var val: int = color_bytes.decode_u16(row_start + target_x * 2)
							color = Color(
								((val >> 11) & 0b01_1111) / 31.0, # red - 5 bits
								((val >>  5) & 0b11_1111) / 63.0, # green - 6 bits
								((val >>  0) & 0b01_1111) / 31.0) # blue - 5 bits
						24: color = Color(
							color_bytes[row_start + target_x * 3 + 2] / 255.0,
							color_bytes[row_start + target_x * 3 + 1] / 255.0,
							color_bytes[row_start + target_x * 3 + 0] / 255.0)
						32: color = Color(
							color_bytes[row_start + target_x * 3 + 2] / 255.0,
							color_bytes[row_start + target_x * 3 + 1] / 255.0,
							color_bytes[row_start + target_x * 3 + 0] / 255.0,
							alpha_bytes[row_start + target_x] / 255.0)
					if is_frame_has_transparent_color and color == frame_transparent_color:
						print("transparent")
						continue
					color.a *= layer_opacity
					frame_image.set_pixel(target_x, target_y,
						frame_image.get_pixel(target_x, target_y).blend(color))
		frames_images[frame_index] = frame_image
		frame_index += 1
	var sprite_sheet_builder: _SpriteSheetBuilderBase = _GridBasedSpriteSheetBuilder.new(
		_Common.EdgesArtifactsAvoidanceMethod.NONE,
		_GridBasedSpriteSheetBuilder.StripDirection.HORIZONTAL,
		2, # max cells in strip
		false, #trim_sprites_to_overall_min_size: bool,
		false, #collapse_transparent: bool,
		false#, #merge_duplicates: bool,
		#sprites_surrounding_color: Color = Color.TRANSPARENT
	)
	var sprite_sheet_building_result: _SpriteSheetBuilderBase.Result = \
		sprite_sheet_builder.build_sprite_sheet(frames_images)


	var sprite_sheet: _Common.SpriteSheetInfo = sprite_sheet_building_result.sprite_sheet
	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	result.success(sprite_sheet, animation_library)
	return result

func _export(res_source_file_path: String, options: Dictionary) -> _Common.ExportResult:
	var result: _Common.ExportResult = _Common.ExportResult.new()
	var sprite_sheet: _Common.SpriteSheetInfo = _Common.SpriteSheetInfo.new()

	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(res_source_file_path)
	var offset: int = 8
	var buffer_size: int = bytes.decode_u32(offset)
#	print(buffer_size)
	offset += 4
	var buffer: PackedByteArray = bytes.slice(offset, offset + buffer_size)
	var data: PackedByteArray = buffer.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP) #1024 * 1024
	var root: _XML.XMLNodeRoot = _XML.parse_buffer(data)
	var d: String = root.dump_to_string()
#	print(d)

	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	result.success(sprite_sheet, animation_library)
	return result

static func __get_chunk(file: FileAccess) -> PackedByteArray:
	var buffer_size: int = file.get_32()
	if buffer_size > 0:
		var chunk: PackedByteArray = file.get_buffer(buffer_size) \
			.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
#		prints("chunk:", buffer_size, chunk.size())
		return chunk
	else:
#		print("chunk: empty")
		return PackedByteArray()

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
