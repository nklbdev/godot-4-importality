@tool
extends "_.gd"

const _XML = preload("../xml.gd")

var __os_command_setting: _Setting = _Setting.new(
	"pencil2d_command", "", TYPE_STRING, PROPERTY_HINT_NONE,
	"", true, func(v: String): return v.is_empty())

var __os_command_arguments_setting: _Setting = _Setting.new(
	"pencil2d_command_arguments", PackedStringArray(), TYPE_PACKED_STRING_ARRAY, PROPERTY_HINT_NONE,
	"", true, func(v: PackedStringArray): return false)

const __ANIMATIONS_PARAMETERS_OPTION: StringName = "pencil2d/animations_parameters"

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["pclx"]
	super("Pencil2D", recognized_extensions, [
		_Options.create_option(__ANIMATIONS_PARAMETERS_OPTION, PackedStringArray(),
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT)],
	[ __os_command_setting, __os_command_arguments_setting ],
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
		result.fail(ERR_UNCONFIGURED, "Failed to get Pencil2D Command to export spritesheet", os_command_result)
		return result

	var os_command_arguments_result: _Setting.GettingValueResult = __os_command_arguments_setting.get_value()
	if os_command_arguments_result.error:
		result.fail(ERR_UNCONFIGURED, "Failed to get Pencil2D Command Arguments to export spritesheet", os_command_arguments_result)
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

	var zip_reader: ZIPReader = ZIPReader.new()
	var zip_error: Error = zip_reader.open(global_source_file_path)
	if zip_error:
		result.fail(zip_error, "Failed to open Pencil2D file \"%s\" as ZIP archive with error: %s (%s)" % [res_source_file_path, zip_error, error_string(zip_error)])
		return result
	var buffer: PackedByteArray = zip_reader.read_file("main.xml")
	var main_xml_root: _XML.XMLNodeRoot = _XML.parse_buffer(buffer)
	zip_reader.close()
	var animation_framerate: int = main_xml_root \
		.get_elements("document").front() \
		.get_elements("projectdata").front() \
		.get_elements("fps").front() \
		.get_int("value")

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

	# -o --export <output_path> Render the file to <output_path>
	# --camera <layer_name> Name of the camera layer to use
	# --width <integer> Width of the output frames
	# --height <integer> Height of the output frames
	# --start <frame> The first frame you want to include in the exported movie
	# --end <frame> The last frame you want to include in the exported movie. Can also be last or last-sound to automatically use the last frame containing animation or sound respectively
	# --transparency Render transparency when possible
	# input Path to input pencil file
	var png_base_name: String = "temp"
	var global_temp_png_path: String = unique_temp_dir_path.path_join("%s.png" % png_base_name)

	var command: String = os_command_result.value.strip_edges()
	var arguments: PackedStringArray = \
		os_command_arguments_result.value + \
		PackedStringArray([
			"--export", global_temp_png_path,
			"--start", 1,
			"--end", unique_frames_count,
			"--transparency",
			global_source_file_path])

	var output: Array
	var exit_code: int = OS.execute(command, arguments, output, true, false)
	if exit_code:
		for arg_index in arguments.size():
			arguments[arg_index] = "\nArgument: " + arguments[arg_index]
		result.fail(ERR_QUERY_FAILED, " ".join([
			"An error occurred while executing the Pencil2D command.",
			"Process exited with code %s:\nCommand: %s%s"
			]) % [exit_code, command, "".join(arguments)])
		return result

	var frames_images: Array[Image]
	for image_idx in unique_frames_count:
		var global_frame_png_path: String = unique_temp_dir_path \
			.path_join("%s%04d.png" % [png_base_name, image_idx + 1])
		frames_images.push_back(Image.load_from_file(global_frame_png_path))

	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)

	var sprite_sheet_building_result: _SpriteSheetBuilderBase.SpriteSheetBuildingResult = sprite_sheet_builder.build_sprite_sheet(frames_images)
	if sprite_sheet_building_result.error:
		result.fail(ERR_BUG, "Sprite sheet building failed", sprite_sheet_building_result)
		return result
	var sprite_sheet: _Common.SpriteSheetInfo = sprite_sheet_building_result.sprite_sheet

	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()

	var frames_duration: float = 1.0 / animation_framerate
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
		common_temporary_files_directory_path: _Setting,
		) -> void:
		__recognized_extensions = recognized_extensions
		__os_command_setting = os_command_setting
		__os_command_arguments_setting = os_command_arguments_setting
		__common_temporary_files_directory_path_setting = common_temporary_files_directory_path

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
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

		var global_source_file_path: String = ProjectSettings.globalize_path(file_access.get_path())

		const png_base_name: String = "img"
		var global_temp_png_path: String = unique_temp_dir_path.path_join("%s.png" % png_base_name)

		var command: String = os_command_result.value.strip_edges()
		var arguments: PackedStringArray = \
			os_command_arguments_result.value + \
			PackedStringArray([
				"--export", global_temp_png_path,
				"--start", 1,
				"--end", 1,
				"--transparency",
				global_source_file_path])

		var output: Array
		var exit_code: int = OS.execute(command, arguments, output, true, false)
		if exit_code:
			for arg_index in arguments.size():
				arguments[arg_index] = "\nArgument: " + arguments[arg_index]
			push_error(" ".join([
				"An error occurred while executing the Pencil2D command.",
				"Process exited with code %s:\nCommand: %s%s"
				]) % [exit_code, command, "".join(arguments)])
			return ERR_QUERY_FAILED

		var global_frame_png_path: String = unique_temp_dir_path \
			.path_join("%s0001.png" % [png_base_name])
		err = image.load_png_from_buffer(FileAccess.get_file_as_bytes(global_frame_png_path))
		if err:
			push_error("An error occurred while image loading")
			return err

		if _DirAccessExtensions.remove_dir_recursive(unique_temp_dir_path).error:
			push_warning(
				"Failed to remove unique temporary directory: \"%s\"" %
				[unique_temp_dir_path])

		return OK

