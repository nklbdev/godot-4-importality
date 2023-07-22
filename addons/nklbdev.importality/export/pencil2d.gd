extends "_.gd"

const _XML = preload("../xml.gd")

var __os_command_project_setting: _ProjectSetting = _ProjectSetting.new(
	"pencil2d_command", "", TYPE_STRING, PROPERTY_HINT_NONE,
	"", true, func(v: String): return v.is_empty())

var __os_command_arguments_project_setting: _ProjectSetting = _ProjectSetting.new(
	"pencil2d_command_arguments", PackedStringArray(), TYPE_PACKED_STRING_ARRAY, PROPERTY_HINT_NONE,
	"", true, func(v: PackedStringArray): return false)

const __ANIMATIONS_INFOS_OPTION: StringName = "importers/pencil2d/animations_infos"

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["pclx"]
	super("Pencil2D", recognized_extensions, [
		_Options.create_option(__ANIMATIONS_INFOS_OPTION, PackedStringArray(),
		PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
	], editor_file_system,
	[ __os_command_project_setting, __os_command_arguments_project_setting ],
	CustomImageFormatLoaderExtension.new(
		recognized_extensions,
		__os_command_project_setting,
		__os_command_arguments_project_setting,
		_common_temporary_files_directory_path_project_setting))

func _export(res_source_file_path: String, options: Dictionary) -> _Models.ExportResultModel:
	var err: Error
	var global_source_file_path: String = ProjectSettings.globalize_path(res_source_file_path)

	var os_command_result: _ProjectSetting.Result = __os_command_project_setting.get_value()
	if os_command_result.error:
		return _Models.ExportResultModel.fail(os_command_result.error, os_command_result.error_message)

	var os_command_arguments_result: _ProjectSetting.Result = __os_command_arguments_project_setting.get_value()
	if os_command_arguments_result.error:
		return _Models.ExportResultModel.fail(os_command_arguments_result.error, os_command_arguments_result.error_message)

	var temp_dir_path_result: _ProjectSetting.Result = _common_temporary_files_directory_path_project_setting.get_value()
	if temp_dir_path_result.error:
		return _Models.ExportResultModel.fail(temp_dir_path_result.error, temp_dir_path_result.error_message)

	var zip_reader: ZIPReader = ZIPReader.new()
	var zip_error: Error = zip_reader.open(global_source_file_path)
	if zip_error: return _Models.ExportResultModel.fail(zip_error, "Unable to open Pencil2D file as ZIP archive")
	var buffer: PackedByteArray = zip_reader.read_file("main.xml")
	var main_xml_root: _XML.XMLNodeRoot = _XML.parse_buffer(buffer)
	zip_reader.close()
	var animation_framerate: int = main_xml_root \
		.get_elements("document").front() \
		.get_elements("projectdata").front() \
		.get_elements("fps").front() \
		.get_int("value")

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

	# -o --export <output_path> Render the file to <output_path>
	# --camera <layer_name> Name of the camera layer to use
	# --width <integer> Width of the output frames
	# --height <integer> Height of the output frames
	# --start <frame> The first frame you want to include in the exported movie
	# --end <frame> The last frame you want to include in the exported movie. Can also be last or last-sound to automatically use the last frame containing animation or sound respectively
	# --transparency Render transparency when possible
	# input Path to input pencil file
	var global_temp_dir_path: String = ProjectSettings.globalize_path(temp_dir_path_result.value)
	if not DirAccess.dir_exists_absolute(global_temp_dir_path):
		err = DirAccess.make_dir_recursive_absolute(global_temp_dir_path)
		if err: return _Models.ExportResultModel.fail(err, "An error occured while make temp directory: %s" % [temp_dir_path_result.value])
	var png_base_name: String = "img"
	var global_temp_png_path: String = temp_dir_path_result.value.path_join("%s.png" % png_base_name)
	var command_line_params: PackedStringArray = PackedStringArray([
		"--export", global_temp_png_path,
		"--start", 1,
		"--end", unique_frames_count,
		"--transparency",
		global_source_file_path,
	])

	var output: Array
	err = OS.execute(
		os_command_result.value,
		os_command_arguments_result.value + PackedStringArray([
			"--export", global_temp_png_path,
			"--start", 1,
			"--end", unique_frames_count,
			"--transparency",
			global_source_file_path]),
		output, true, false)
	if err: return _Models.ExportResultModel.fail(err, "An error occurred while executing the Pencil2D command")

	var frames_images: Array[Image]
	for image_idx in unique_frames_count:
		var global_frame_png_path: String = temp_dir_path_result.value \
			.path_join("%s%04d.png" % [png_base_name, image_idx + 1])
		frames_images.push_back(Image.load_from_file(global_frame_png_path))
		err = DirAccess.remove_absolute(global_frame_png_path)
		if err: push_error("Unable to remove temp file: \"%s\" with error: %s, continuing..." %
			[global_frame_png_path, error_string(err)])

	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)

	var sprite_sheet_building_result: _SpriteSheetBuilderBase.Result = sprite_sheet_builder.build_sprite_sheet(frames_images)
	if sprite_sheet_building_result.error:
		return _Models.ExportResultModel.fail(sprite_sheet_building_result.error,
			"Sprite sheet building failed: " + sprite_sheet_building_result.error_message)
	var sprite_sheet_model: _Models.SpriteSheetModel = sprite_sheet_building_result.sprite_sheet

	var animation_library_model: _Models.AnimationLibraryModel = _Models.AnimationLibraryModel.new()
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()

	var frames_duration: float = 1.0 / animation_framerate
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
	var __os_command_project_setting: _ProjectSetting
	var __os_command_arguments_project_setting: _ProjectSetting
	var __common_temporary_files_directory_path_project_setting: _ProjectSetting

	func _init(recognized_extensions: PackedStringArray,
		os_command_project_setting: _ProjectSetting,
		os_command_arguments_project_setting: _ProjectSetting,
		common_temporary_files_directory_path: _ProjectSetting,
		) -> void:
		__recognized_extensions = recognized_extensions
		__os_command_project_setting = os_command_project_setting
		__os_command_arguments_project_setting = os_command_arguments_project_setting
		__common_temporary_files_directory_path_project_setting = common_temporary_files_directory_path

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
		var err: Error

		var os_command_result: _ProjectSetting.Result = __os_command_project_setting.get_value()
		if os_command_result.error:
			push_error(os_command_result.error_message)
			return os_command_result.error

		var os_command_arguments_result: _ProjectSetting.Result = __os_command_arguments_project_setting.get_value()
		if os_command_arguments_result.error:
			push_error(os_command_arguments_result.error_message)
			return os_command_arguments_result.error

		var temp_dir_path_result: _ProjectSetting.Result = __common_temporary_files_directory_path_project_setting.get_value()
		if temp_dir_path_result.error:
			push_error(temp_dir_path_result.error_message)
			return temp_dir_path_result.error

		var global_source_file_path: String = ProjectSettings.globalize_path(file_access.get_path())
		var global_temp_dir_path: String = ProjectSettings.globalize_path(temp_dir_path_result.value)
		if not DirAccess.dir_exists_absolute(global_temp_dir_path):
			err = DirAccess.make_dir_recursive_absolute(global_temp_dir_path)
			if err:
				push_error("An error occured while make temp directory: %s" % [temp_dir_path_result.value])
				return err
		var png_base_name: String = "img"
		var global_temp_png_path: String = temp_dir_path_result.value.path_join("%s.png" % png_base_name)

		var output: Array
		err = OS.execute(
			os_command_result.value,
			os_command_arguments_result.value + PackedStringArray([
				"--export", global_temp_png_path,
				"--start", 1,
				"--end", 1,
				"--transparency",
				global_source_file_path]),
			output, true, false)
		if err:
			push_error("An error occurred while executing the Pencil2D command")
			return err

		var global_frame_png_path: String = temp_dir_path_result.value \
			.path_join("%s0001.png" % [png_base_name])
		err = image.load_png_from_buffer(FileAccess.get_file_as_bytes(global_frame_png_path))
		if err:
			push_error("An error occurred while image loading")
			return err
		return OK

