@tool
extends "_.gd"

const __aseprite_sheet_types_by_sprite_sheet_layout: PackedStringArray = \
	[ "packed", "rows", "columns" ]
const __aseprite_animation_directions: PackedStringArray = \
	[ "forward", "reverse", "pingpong", "pingpong_reverse" ]

var __os_command_setting: _Setting = _Setting.new(
	"aseprite_or_libre_sprite_command", "", TYPE_STRING, PROPERTY_HINT_NONE,
	"", true, func(v: String): return v.is_empty())

var __os_command_arguments_setting: _Setting = _Setting.new(
	"aseprite_or_libre_sprite_command_arguments", PackedStringArray(), TYPE_PACKED_STRING_ARRAY, PROPERTY_HINT_NONE,
	"", true, func(v: PackedStringArray): return false)

func _init() -> void:
	var recognized_extensions: PackedStringArray = ["ase", "aseprite"]
	super("Aseprite", recognized_extensions, [],
		[__os_command_setting, __os_command_arguments_setting],
		CustomImageFormatLoaderExtension.new(
			recognized_extensions,
			__os_command_setting,
			__os_command_arguments_setting,
			_Common.common_temporary_files_directory_path_setting))

func _export(res_source_file_path: String, options: Dictionary) -> ExportResult:
	var result: ExportResult = ExportResult.new()
	var err: Error

	var os_command_result: _Setting.GettingValueResult = __os_command_setting.get_value()
	if os_command_result.error:
		result.fail(ERR_UNCONFIGURED, "Failed to get Aseprite Command to export spritesheet", os_command_result)
		return result

	var os_command_arguments_result: _Setting.GettingValueResult = __os_command_arguments_setting.get_value()
	if os_command_arguments_result.error:
		result.fail(ERR_UNCONFIGURED, "Failed to get Aseprite Command Arguments to export spritesheet", os_command_arguments_result)
		return result

	var temp_dir_path_result: _Setting.GettingValueResult = _Common.common_temporary_files_directory_path_setting.get_value()
	if temp_dir_path_result.error:
		result.fail(ERR_UNCONFIGURED, "Failed to get Temporary Files Directory Path to export spritesheet", temp_dir_path_result)
		return result
	var global_temp_dir_path: String = ProjectSettings.globalize_path(
		temp_dir_path_result.value.strip_edges())
	var unique_temp_dir_creation_result: _DirAccessExtensions.CreationResult = \
		_DirAccessExtensions.create_directory_with_unique_name(global_temp_dir_path)
	if unique_temp_dir_creation_result.error:
		result.fail(ERR_QUERY_FAILED, "Failed to create unique temporary directory to export spritesheet", unique_temp_dir_creation_result)
		return result
	var unique_temp_dir_path: String = unique_temp_dir_creation_result.path

	var global_source_file_path: String = ProjectSettings.globalize_path(res_source_file_path)
	var global_png_path: String = unique_temp_dir_path.path_join("temp.png")
	var global_json_path: String = unique_temp_dir_path.path_join("temp.json")

	var split_layers: bool = options.get(_Options.SPLIT_LAYERS, false)

	var command: String = os_command_result.value.strip_edges()
	# Base args for ALL CLI calls (composite and per-layer)
	var per_layer_base_args: PackedStringArray = \
		os_command_arguments_result.value + \
		PackedStringArray(["--batch", "--format", "json-array", "--list-tags"])
	# Initial call also needs --list-layers when splitting
	var initial_args: PackedStringArray = per_layer_base_args.duplicate()
	if split_layers:
		initial_args.append("--list-layers")
	initial_args.append_array(PackedStringArray(["--sheet", global_png_path, "--data", global_json_path, global_source_file_path]))

	var output: Array = []
	var exit_code: int = OS.execute(command, initial_args, output, true, false)
	if exit_code:
		for arg_index in initial_args.size():
			initial_args[arg_index] = "\nArgument: " + initial_args[arg_index]
		result.fail(ERR_QUERY_FAILED, " ".join([
			"An error occurred while executing the Aseprite command.",
			"Process exited with code %s:\nCommand: %s%s"
			]) % [exit_code, command, "".join(initial_args)])
		return result
	var raw_atlas_image: Image = Image.load_from_file(global_png_path)
	var json := JSON.new()
	err = json.parse(FileAccess.get_file_as_string(global_json_path))
	if err:
		result.fail(ERR_INVALID_DATA, "Failed to parse sprite sheet json data with error %s \"%s\"" % [err, error_string(err)])
		return result
	var raw_sprite_sheet_data: Dictionary = json.data

	var source_image_size: Vector2i = _Common.get_vector2i(
		raw_sprite_sheet_data.frames[0].sourceSize, "w", "h")
	var frames_data: Array = raw_sprite_sheet_data.frames
	var frames_count: int = frames_data.size()

	var tags_data: Array = raw_sprite_sheet_data.meta.frameTags
	if tags_data.is_empty():
		var default_animation_name: String = options[_Options.DEFAULT_ANIMATION_NAME].strip_edges()
		if default_animation_name.is_empty():
			default_animation_name = "default"
		tags_data.push_back({
			name = default_animation_name,
			from = 0,
			to = frames_count - 1,
			direction = __aseprite_animation_directions[options[_Options.DEFAULT_ANIMATION_DIRECTION]],
			repeat = options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT]
		})

	# Pre-parse all tags — used identically for both split and non-split paths
	var parsed_tags: Array = []
	var unique_tag_names: PackedStringArray
	for animation_index in tags_data.size():
		var tag_data: Dictionary = tags_data[animation_index]
		var params: AnimationParamsParsingResult = _parse_animation_params(
			tag_data.name.strip_edges(),
			AnimationOptions.Direction | AnimationOptions.RepeatCount,
			tag_data.from,
			tag_data.to - tag_data.from + 1)
		if params.error:
			if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
				push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
			result.fail(ERR_CANT_RESOLVE, "Failed to parse animation parameters", params)
			return result
		if params.name.is_empty():
			if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
				push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
			result.fail(ERR_INVALID_DATA, "A tag with empty name found")
			return result
		if unique_tag_names.has(params.name):
			if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
				push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
			result.fail(ERR_INVALID_DATA, "Duplicated animation name \"%s\" at index: %s" %
				[params.name, animation_index])
			return result
		unique_tag_names.push_back(params.name)
		var tag_ud: String = tag_data.get("data", "")
		var ud_params: AnimationParamsParsingResult
		if not tag_ud.is_empty():
			ud_params = _parse_animation_params(tag_ud,
				AnimationOptions.Direction | AnimationOptions.RepeatCount,
				tag_data.from, tag_data.to - tag_data.from + 1)
		var direction: int = __aseprite_animation_directions.find(tag_data.direction)
		if ud_params and ud_params.direction >= 0: direction = ud_params.direction
		if params.direction >= 0: direction = params.direction
		var repeat_count: int = int(tag_data.get("repeat", "0"))
		if ud_params and ud_params.repeat_count >= 0: repeat_count = ud_params.repeat_count
		if params.repeat_count >= 0: repeat_count = params.repeat_count
		parsed_tags.push_back({
			name = params.name,
			direction = direction,
			repeat_count = repeat_count,
			from = tag_data.from,
			to = tag_data.to,
		})

	# Build layer descriptors.
	# Non-split: one descriptor representing the composited image (no name affix, no canvas offset).
	# Split: one descriptor per layer in meta.layers, with per-layer PNG, name affix, and canvas offset.
	# Each descriptor: {frames_images: Dict[fi->Image], name_prefix: String, name_suffix: String, canvas_offset: Vector2i}
	var layer_descriptors: Array = []

	if not split_layers:
		var frames_images: Dictionary = {}
		for pt in parsed_tags:
			for fi in range(pt.from, pt.to + 1):
				if not frames_images.has(fi):
					var fd: Dictionary = frames_data[fi]
					frames_images[fi] = raw_atlas_image.get_region(Rect2i(
						_Common.get_vector2i(fd.frame, "x", "y"), source_image_size))
		layer_descriptors.push_back({
			frames_images = frames_images,
			name_prefix = "",
			name_suffix = "",
			canvas_offset = Vector2i.ZERO,
		})
	else:
		var layers_data: Array = raw_sprite_sheet_data.meta.get("layers", [])
		if layers_data.is_empty():
			if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
				push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
			result.fail(ERR_INVALID_DATA, "No layers found in Aseprite file. Make sure --list-layers is supported by your Aseprite version.")
			return result
		var layer_name_first: bool = options.get(_Options.LAYERS_ANIMATION_NAME_FORMAT, 0) == 0
		for layer_data in layers_data:
			# Parse canvas offset from layer name, then fall back to user data
			var name_params: LayerParamsParsingResult = _parse_layer_params(layer_data.name)
			if name_params.error:
				if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
					push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
				result.fail(ERR_INVALID_DATA, "Failed to parse layer name params for \"%s\"" % layer_data.name, name_params)
				return result
			var display_name: String = name_params.name
			var canvas_offset: Vector2i = name_params.canvas_offset
			var layer_ud: String = layer_data.get("data", "")
			if not layer_ud.is_empty() and canvas_offset == Vector2i.ZERO:
				var ud_params: LayerParamsParsingResult = _parse_layer_params(layer_ud)
				if not ud_params.error:
					canvas_offset = ud_params.canvas_offset
			var name_prefix: String = display_name + "/" if layer_name_first else ""
			var name_suffix: String = "" if layer_name_first else "/" + display_name
			# Run per-layer export
			var layer_idx: int = layers_data.find(layer_data)
			var layer_png_path: String = unique_temp_dir_path.path_join("layer_%d.png" % layer_idx)
			var layer_json_path: String = unique_temp_dir_path.path_join("layer_%d.json" % layer_idx)
			var layer_args: PackedStringArray = per_layer_base_args + \
				PackedStringArray(["--layer", layer_data.name,
					"--sheet", layer_png_path, "--data", layer_json_path,
					global_source_file_path])
			var layer_output: Array = []
			var layer_exit: int = OS.execute(command, layer_args, layer_output, true, false)
			if layer_exit:
				if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
					push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
				result.fail(ERR_QUERY_FAILED, "Failed to export layer \"%s\" (exit code %d)" % [layer_data.name, layer_exit])
				return result
			var layer_atlas: Image = Image.load_from_file(layer_png_path)
			var layer_json := JSON.new()
			err = layer_json.parse(FileAccess.get_file_as_string(layer_json_path))
			if err:
				if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
					push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
				result.fail(ERR_INVALID_DATA, "Failed to parse layer json for layer \"%s\"" % layer_data.name)
				return result
			var layer_frames_data: Array = layer_json.data.frames
			var frames_images: Dictionary = {}
			for pt in parsed_tags:
				for fi in range(pt.from, pt.to + 1):
					if not frames_images.has(fi):
						var fd: Dictionary = layer_frames_data[fi]
						frames_images[fi] = layer_atlas.get_region(Rect2i(
							_Common.get_vector2i(fd.frame, "x", "y"), source_image_size))
			layer_descriptors.push_back({
				frames_images = frames_images,
				name_prefix = name_prefix,
				name_suffix = name_suffix,
				canvas_offset = canvas_offset,
			})

	# Collect all frame images into a single list, applying canvas offsets
	var all_frame_images: Array[Image] = []
	var sprite_indices: Array = []  # Array of Dict[fi -> sprite_sheet_index]
	for desc in layer_descriptors:
		var sidx: Dictionary = {}
		var sorted_fi: PackedInt32Array = PackedInt32Array(desc.frames_images.keys())
		sorted_fi.sort()
		for fi in sorted_fi:
			var img: Image = desc.frames_images[fi]
			if desc.canvas_offset != Vector2i.ZERO:
				var shifted := Image.create_empty(source_image_size.x, source_image_size.y, false, Image.FORMAT_RGBA8)
				shifted.blit_rect(img,
					Rect2i(desc.canvas_offset.x, desc.canvas_offset.y, source_image_size.x, source_image_size.y),
					Vector2i.ZERO)
				img = shifted
			sidx[fi] = all_frame_images.size()
			all_frame_images.push_back(img)
		sprite_indices.push_back(sidx)

	# Build the unified sprite sheet
	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)
	var build_result: _SpriteSheetBuilderBase.SpriteSheetBuildingResult = \
		sprite_sheet_builder.build_sprite_sheet(all_frame_images)
	if build_result.error:
		if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
			push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
		result.fail(ERR_BUG, "Sprite sheet building failed", build_result)
		return result
	var sprite_sheet: _Common.SpriteSheetInfo = build_result.sprite_sheet

	# Create animations — identical loop for both split and non-split
	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()
	for di in layer_descriptors.size():
		var desc: Dictionary = layer_descriptors[di]
		var sidx: Dictionary = sprite_indices[di]
		var unqualified: bool = desc.name_prefix.is_empty() and desc.name_suffix.is_empty()
		for pt in parsed_tags:
			var anim_name: String = desc.name_prefix + pt.name + desc.name_suffix
			var animation := _Common.AnimationInfo.new()
			animation.name = anim_name
			animation.direction = pt.direction
			animation.repeat_count = pt.repeat_count
			for fi in range(pt.from, pt.to + 1):
				var frame := _Common.FrameInfo.new()
				frame.sprite = sprite_sheet.sprites[sidx[fi]]
				frame.duration = frames_data[fi].duration * 0.001
				animation.frames.push_back(frame)
			if unqualified and anim_name == autoplay_animation_name:
				animation_library.autoplay_index = animation_library.animations.size()
			animation_library.animations.push_back(animation)

	if not split_layers and not autoplay_animation_name.is_empty() and animation_library.autoplay_index < 0:
		push_warning("Autoplay animation name not found: \"%s\". Continuing..." % [autoplay_animation_name])

	if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
		push_warning("Failed to remove unique temporary directory: \"%s\"" % [unique_temp_dir_path])
	result.success(build_result.atlas_image, sprite_sheet, animation_library)
	return result

class CustomImageFormatLoaderExtension:
	extends ImageFormatLoaderExtension

	var __recognized_extensions: PackedStringArray
	var __os_command_setting: _Setting
	var __os_command_arguments_setting: _Setting
	var __common_temporary_files_directory_path_setting: _Setting

	func _init(recognized_extensions: PackedStringArray,
		os_command_setting: _Setting,
		os_command_arguments_setting: _Setting,
		common_temporary_files_directory_path_setting: _Setting
		) -> void:
		__recognized_extensions = recognized_extensions
		__os_command_setting = os_command_setting
		__os_command_arguments_setting = os_command_arguments_setting
		__common_temporary_files_directory_path_setting = \
			common_temporary_files_directory_path_setting

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
		var global_source_file_path: String = file_access.get_path_absolute()
		var err: Error

		var os_command_result: _Setting.GettingValueResult = __os_command_setting.get_value()
		if os_command_result.error:
			push_error(os_command_result.error_description)
			return os_command_result.error

		var os_command_arguments_result: _Setting.GettingValueResult = __os_command_arguments_setting.get_value()
		if os_command_arguments_result.error:
			push_error(os_command_arguments_result.error_description)
			return os_command_arguments_result.error

		var temp_dir_path_result: _Setting.GettingValueResult = _Common.common_temporary_files_directory_path_setting.get_value()
		if temp_dir_path_result.error:
			push_error("Failed to get Temporary Files Directory Path to export spritesheet")
			return temp_dir_path_result.error
		var global_temp_dir_path: String = ProjectSettings.globalize_path(
			temp_dir_path_result.value.strip_edges())
		var unique_temp_dir_creation_result: _DirAccessExtensions.CreationResult = \
			_DirAccessExtensions.create_directory_with_unique_name(global_temp_dir_path)
		if unique_temp_dir_creation_result.error:
			push_error("Failed to create unique temporary directory to export spritesheet")
			return unique_temp_dir_creation_result.error
		var unique_temp_dir_path: String = unique_temp_dir_creation_result.path

		var global_png_path: String = unique_temp_dir_path.path_join("temp.png")
		var global_json_path: String = unique_temp_dir_path.path_join("temp.json")

		var command: String = os_command_result.value.strip_edges()
		var arguments: PackedStringArray = \
			os_command_arguments_result.value + \
			PackedStringArray([
				"--batch",
				"--format", "json-array",
				"--list-tags",
				"--sheet", global_png_path,
				"--data", global_json_path,
				global_source_file_path,
			])

		var output: Array = []
		var exit_code: int = OS.execute(command, arguments, output, true, false)
		if exit_code:
			for arg_index in arguments.size():
				arguments[arg_index] = "\nArgument: " + arguments[arg_index]
			push_error(" ".join([
				"An error occurred while executing the Aseprite command.",
				"Process exited with code %s:\nCommand: %s%s"
				]) % [exit_code, command, "".join(arguments)])
			return ERR_QUERY_FAILED

		var raw_atlas_image: Image = Image.load_from_file(global_png_path)
		var json = JSON.new()
		err = json.parse(FileAccess.get_file_as_string(global_json_path))
		if err:
			push_error("Failed to parse sprite sheet json data with error %s \"%s\"" % [err, error_string(err)])
			return ERR_INVALID_DATA
		var raw_sprite_sheet_data: Dictionary = json.data

		var source_image_size: Vector2i = _Common.get_vector2i(
			raw_sprite_sheet_data.frames[0].sourceSize, "w", "h")

		if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
			push_warning(
				"Failed to remove unique temporary directory: \"%s\"" %
				[unique_temp_dir_path])

		image.copy_from(raw_atlas_image.get_region(Rect2i(Vector2i.ZERO, source_image_size)))
		return OK
