@tool
# @tool надо писать, чтобы не только можно было инстанциировать этот скрипт,
# а еще чтобы инициализировалась статика в нем!
# И не важно, что в родительском классе эта директива уже есть!
extends "_.gd"

const __aseprite_sheet_types_by_sprite_sheet_layout: PackedStringArray = \
	[ "rows", "columns", "packed" ]
const __aseprite_animation_directions: PackedStringArray = \
	[ "forward", "reverse", "pingpong", "pingpong_reverse" ]

var __os_command_project_setting: _ProjectSetting = _ProjectSetting.new(
	"aseprite_command", "", TYPE_STRING, PROPERTY_HINT_NONE,
	"", true, func(v: String): return v.is_empty())

var __os_command_arguments_project_setting: _ProjectSetting = _ProjectSetting.new(
	"aseprite_command_arguments", PackedStringArray(), TYPE_PACKED_STRING_ARRAY, PROPERTY_HINT_NONE,
	"", true, func(v: PackedStringArray): return false)

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["ase", "aseprite"]
	super("Aseprite", recognized_extensions, [], editor_file_system,
		[__os_command_project_setting, __os_command_arguments_project_setting],
		CustomImageFormatLoaderExtension.new(recognized_extensions,
		__os_command_project_setting, __os_command_arguments_project_setting))

func _export(res_source_file_path: String, atlas_maker: AtlasMaker, options: Dictionary) -> _Common.ExportResult:
	var result: _Common.ExportResult = _Common.ExportResult.new()

	var os_command_result: _ProjectSetting.Result = __os_command_project_setting.get_value()
	if os_command_result.error:
		result.fail(ERR_UNCONFIGURED, "Unable to get Aseprite Command to export spritesheet", os_command_result)
		return result

	var os_command_arguments_result: _ProjectSetting.Result = __os_command_arguments_project_setting.get_value()
	if os_command_arguments_result.error:
		result.fail(ERR_UNCONFIGURED, "Unable to get Aseprite Command Arguments to export spritesheet", os_command_arguments_result)
		return result

	var temp_dir_path_result: _ProjectSetting.Result = _common_temporary_files_directory_path_project_setting.get_value()
	if temp_dir_path_result.error:
		result.fail(ERR_UNCONFIGURED, "Unable to get Temporary Files Directory Path to export spritesheet", temp_dir_path_result)
		return result

	var png_path: String = temp_dir_path_result.value.path_join("temp.png")
	var global_png_path: String = ProjectSettings.globalize_path(png_path)
	var sprite_sheet: _Common.SpriteSheetInfo = _Common.SpriteSheetInfo.new()
	result.sprite_sheet = sprite_sheet
	var sprite_sheet_layout: _Common.SpriteSheetLayout = options[_Options.SPRITE_SHEET_LAYOUT]

	var variable_options: Array
	if sprite_sheet_layout == _Common.SpriteSheetLayout.HORIZONTAL_STRIPS:
		variable_options += ["--sheet-columns", str(options[_Options.MAX_CELLS_IN_STRIP])]
	if sprite_sheet_layout == _Common.SpriteSheetLayout.VERTICAL_STRIPS:
		variable_options += ["--sheet-rows", str(options[_Options.MAX_CELLS_IN_STRIP])]
	match options[_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD]:
		_Common.EdgesArtifactsAvoidanceMethod.NONE:
			pass
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_SPACING:
			variable_options += ["--shape-padding", "1"]
		_Common.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
			variable_options += ["--shape-padding", "1", "--border-padding", "1"]
		_Common.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION:
			variable_options += ["--extrude"]
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION:
			variable_options += ["--inner-padding", "1"]
	if options[_Options.COLLAPSE_TRANSPARENT_SPRITES]: variable_options += ["--ignore-empty"]
	if options[_Options.MERGE_DUPLICATED_SPRITES]: variable_options += ["--merge-duplicates"]
	if options[_Options.TRIM_SPRITES_TO_OVERALL_MIN_SIZE]: variable_options += \
		["--trim" if sprite_sheet_layout == _Common.SpriteSheetLayout.PACKED else "--trim-sprite"]

	var output: Array = []
	var exit_code: int = OS.execute(
		os_command_result.value,
		os_command_arguments_result.value + PackedStringArray([
			"--batch",
			"--filename-format", "{tag}{tagframe}",
			"--format", "json-array",
			"--list-tags",
			"--trim" if sprite_sheet_layout == _Common.SpriteSheetLayout.PACKED else
				"--trim-sprite" if options[_Options.TRIM_SPRITES_TO_OVERALL_MIN_SIZE] else "",
			"--sheet-type", __aseprite_sheet_types_by_sprite_sheet_layout[sprite_sheet_layout],
			] + variable_options + [
			"--sheet", global_png_path,
			ProjectSettings.globalize_path(res_source_file_path)]),
		output, true, false)
	if exit_code:
		result.fail(ERR_QUERY_FAILED, "An error occurred while executing the Aseprite command. Process exited with code %s" % [exit_code])
		return result
	var json = JSON.new()
	json.parse(output[0])

	var source_size_data = json.data.frames[0].sourceSize
	sprite_sheet.source_image_size = Vector2i(source_size_data.w, source_size_data.h)

	var atlas_making_result: AtlasMaker.Result = atlas_maker \
		.make_atlas(Image.load_from_file(global_png_path))
	DirAccess.remove_absolute(global_png_path)
	if atlas_making_result.error:
		result.fail(ERR_SCRIPT_FAILED, "Unable to make atlas texture from image", atlas_making_result)
		return result
	sprite_sheet.atlas = atlas_making_result.atlas

	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges().strip_escapes()
	var sprites_by_rect_positions: Dictionary
	var frames: Array[_Common.FrameInfo]
	for frame_data in json.data.frames:
		var sprite_region: Rect2i = Rect2i(
			frame_data.frame.x, frame_data.frame.y,
			frame_data.frame.w, frame_data.frame.h)
		var sprite: _Common.SpriteInfo
		if sprites_by_rect_positions.has(sprite_region.position):
			sprite = sprites_by_rect_positions[sprite_region.position]
		else:
			sprite = _Common.SpriteInfo.new()
			sprites_by_rect_positions[sprite_region.position] = sprite
			sprite.region = sprite_region
			sprite.offset = Vector2i(
				frame_data.spriteSourceSize.x, frame_data.spriteSourceSize.y)
		var frame: _Common.FrameInfo = _Common.FrameInfo.new()
		frame.sprite = sprite
		frame.duration = frame_data.duration * 0.001
		frames.push_back(frame)

	var tags_data: Array = json.data.meta.frameTags
	var unique_names: Array[String] = []
	if tags_data.is_empty():
		var default_animation_name: String = options[_Options.DEFAULT_ANIMATION_NAME].strip_edges()
		if not default_animation_name.is_empty():
			# default animation
			var default_animation: _Common.AnimationInfo = _Common.AnimationInfo.new()
			default_animation.name = default_animation_name
			default_animation.repeat_count = options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT]
			default_animation.frames = frames
			result.animation_library.animations.append(default_animation)
	else:
		for tag_data in tags_data:
			var animation: _Common.AnimationInfo = _Common.AnimationInfo.new()
			animation.name = tag_data.name.strip_edges().strip_escapes()
			if animation.name.is_empty():
				result.fail(ERR_INVALID_DATA, "Found empty tag name")
				return result
			if unique_names.has(animation.name):
				result.fail(ERR_INVALID_DATA, "Found duplicated tag name")
				return result
			unique_names.append(animation.name)

			animation.direction = __aseprite_animation_directions.find(tag_data.direction)
			animation.repeat_count = int(tag_data.get("repeat", "0"))
			animation.frames = frames.slice(tag_data.from, tag_data.to + 1)
			if autoplay_animation_name and autoplay_animation_name == animation.name:
				animation_library.autoplay_index = animation_library.animations.size() - 1
			animation_library.animations.append(animation)

		if autoplay_animation_name and animation_library.autoplay_index < 0:
			result.fail(ERR_INVALID_DATA, "Autoplay animation not found by name: %s" % autoplay_animation_name)
			return result

	result.success(sprite_sheet, animation_library)
	return result

class CustomImageFormatLoaderExtension:
	extends ImageFormatLoaderExtension

	var __recognized_extensions: PackedStringArray
	var __os_command_project_setting: _ProjectSetting
	var __os_command_arguments_project_setting: _ProjectSetting
	var __common_temporary_files_directory_path_project_setting: _ProjectSetting

	func _init(recognized_extensions: PackedStringArray,
		os_command_project_setting: _ProjectSetting,
		os_command_arguments_project_setting: _ProjectSetting
		) -> void:
		__recognized_extensions = recognized_extensions
		__os_command_project_setting = os_command_project_setting
		__os_command_arguments_project_setting = os_command_arguments_project_setting

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
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

		flags = flags as ImageFormatLoader.LoaderFlags

		var source_file_path: String = ProjectSettings.globalize_path(file_access.get_path_absolute())
		var png_path: String = temp_dir_path_result.value.path_join("temp.png")
		var global_png_path: String = ProjectSettings.globalize_path(png_path)

		var output: Array = []
		var exit_code: int = OS.execute(
			os_command_result.value,
			os_command_arguments_result.value + PackedStringArray([
				"--batch",
				source_file_path,
				"--frame-range", "0,0",
				"--save-as",
				global_png_path]),
			output, true, false)
		if exit_code:
			push_error("An error occurred while executing the Aseprite command: %s" % error_string(exit_code))
			return exit_code

		image.load_png_from_buffer(FileAccess.get_file_as_bytes(global_png_path))
		DirAccess.remove_absolute(global_png_path)

		return OK

