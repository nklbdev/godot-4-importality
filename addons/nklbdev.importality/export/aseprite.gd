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

func _init(editor_file_system: EditorFileSystem) -> void:
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

	var command: String = os_command_result.value.strip_edges()
	var arguments: PackedStringArray = \
		os_command_arguments_result.value + \
		PackedStringArray([
			"--batch",
			"--format", "json-array",
			"--list-tags",
			"--sheet", global_png_path,
			"--data", global_json_path,
			global_source_file_path])

	var output: Array = []
	var exit_code: int = OS.execute(command, arguments, output, true, false)
	if exit_code:
		for arg_index in arguments.size():
			arguments[arg_index] = "\nArgument: " + arguments[arg_index]
		result.fail(ERR_QUERY_FAILED, " ".join([
			"An error occurred while executing the Aseprite command.",
			"Process exited with code %s:\nCommand: %s%s"
			]) % [exit_code, command, "".join(arguments)])
		return result
	var raw_atlas_image: Image = Image.load_from_file(global_png_path)
	var json = JSON.new()
	err = json.parse(FileAccess.get_file_as_string(global_json_path))
	if err:
		result.fail(ERR_INVALID_DATA, "Failed to parse sprite sheet json data with error %s \"%s\"" % [err, error_string(err)])
		return result
	var raw_sprite_sheet_data: Dictionary = json.data

	var sprite_sheet_layout: _Common.SpriteSheetLayout = options[_Options.SPRITE_SHEET_LAYOUT]
	var source_image_size: Vector2i = _Common.get_vector2i(
		raw_sprite_sheet_data.frames[0].sourceSize, "w", "h")

	var frames_images_by_indices: Dictionary
	var tags_data: Array = raw_sprite_sheet_data.meta.frameTags
	var frames_data: Array = raw_sprite_sheet_data.frames
	var frames_count: int = frames_data.size()
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
	var animations_count: int = tags_data.size()
	for tag_data in tags_data:
		for frame_index in range(tag_data.from, tag_data.to + 1):
			if frames_images_by_indices.has(frame_index):
				continue
			var frame_data: Dictionary = frames_data[frame_index]
			frames_images_by_indices[frame_index] = raw_atlas_image.get_region(Rect2i(
				_Common.get_vector2i(frame_data.frame, "x", "y"),
				source_image_size))
	var used_frames_indices: PackedInt32Array = PackedInt32Array(frames_images_by_indices.keys())
	used_frames_indices.sort()
	var used_frames_count: int = used_frames_indices.size()
	var sprite_sheet_frames_indices_by_global_frame_indices: Dictionary
	for sprite_sheet_frame_index in used_frames_indices.size():
		sprite_sheet_frames_indices_by_global_frame_indices[
			used_frames_indices[sprite_sheet_frame_index]] = \
			sprite_sheet_frame_index
	var used_frames_images: Array[Image]
	used_frames_images.resize(used_frames_count)
	for i in used_frames_count:
		used_frames_images[i] = frames_images_by_indices[used_frames_indices[i]]

	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)

	var sprite_sheet_building_result: _SpriteSheetBuilderBase.SpriteSheetBuildingResult = sprite_sheet_builder.build_sprite_sheet(used_frames_images)
	if sprite_sheet_building_result.error:
		result.fail(ERR_BUG, "Sprite sheet building failed", sprite_sheet_building_result)
		return result
	var sprite_sheet: _Common.SpriteSheetInfo = sprite_sheet_building_result.sprite_sheet

	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()

	var all_frames: Array[_Common.FrameInfo]
	all_frames.resize(used_frames_count)
	var unique_animations_names: PackedStringArray
	for animation_index in animations_count:
		var tag_data: Dictionary = tags_data[animation_index]

		var animation_params_parsing_result: AnimationParamsParsingResult = _parse_animation_params(
			tag_data.name.strip_edges(),
			AnimationOptions.Direction | AnimationOptions.RepeatCount,
			tag_data.from,
			tag_data.to - tag_data.from + 1)
		if animation_params_parsing_result.error:
			result.fail(ERR_CANT_RESOLVE, "Failed to parse animation parameters",
				animation_params_parsing_result)
			return result
		if unique_animations_names.has(animation_params_parsing_result.name):
			result.fail(ERR_INVALID_DATA, "Duplicated animation name \"%s\" at index: %s" %
				[animation_params_parsing_result.name, animation_index])
			return result
		unique_animations_names.push_back(animation_params_parsing_result.name)
		var animation = _Common.AnimationInfo.new()
		animation.name = animation_params_parsing_result.name
		if animation.name.is_empty():
			result.fail(ERR_INVALID_DATA, "A tag with empty name found")
			return result
		if animation.name == autoplay_animation_name:
			animation_library.autoplay_index = animation_index
		animation.direction = __aseprite_animation_directions.find(tag_data.direction)
		if animation_params_parsing_result.direction >= 0:
			animation.direction = animation_params_parsing_result.direction
		animation.repeat_count = int(tag_data.get("repeat", "0"))
		if animation_params_parsing_result.repeat_count >= 0:
			animation.repeat_count = animation_params_parsing_result.repeat_count
		for global_frame_index in range(tag_data.from, tag_data.to + 1):
			var sprite_sheet_frame_index: int = \
				sprite_sheet_frames_indices_by_global_frame_indices[global_frame_index]
			var frame: _Common.FrameInfo = all_frames[sprite_sheet_frame_index]
			if frame == null:
				frame = _Common.FrameInfo.new()
				frame.sprite = sprite_sheet.sprites[sprite_sheet_frame_index]
				frame.duration = frames_data[global_frame_index].duration * 0.001
				all_frames[sprite_sheet_frame_index] = frame
			animation.frames.push_back(frame)
		animation_library.animations.push_back(animation)

	if not autoplay_animation_name.is_empty() and animation_library.autoplay_index < 0:
		push_warning("Autoplay animation name not found: \"%s\". Continuing..." % [autoplay_animation_name])

	if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
		push_warning(
			"Failed to remove unique temporary directory: \"%s\"" %
			[unique_temp_dir_path])

	result.success(sprite_sheet_building_result.atlas_image, sprite_sheet, animation_library)
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
