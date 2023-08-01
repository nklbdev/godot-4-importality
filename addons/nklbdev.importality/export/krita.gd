@tool
extends "_.gd"

const _XML = preload("../xml.gd")

var __os_command_project_setting: _ProjectSetting = _ProjectSetting.new(
	"krita_command", "", TYPE_STRING, PROPERTY_HINT_NONE,
	"", true, func(v: String): return v.is_empty())

var __os_command_arguments_project_setting: _ProjectSetting = _ProjectSetting.new(
	"krita_command_arguments", PackedStringArray(), TYPE_PACKED_STRING_ARRAY, PROPERTY_HINT_NONE,
	"", true, func(v: PackedStringArray): return false)

func _init(editor_file_system: EditorFileSystem) -> void:
	var recognized_extensions: PackedStringArray = ["kra", "krita"]
	super("Krita", recognized_extensions, [], editor_file_system, [
		__os_command_project_setting,
		__os_command_arguments_project_setting,
	], CustomImageFormatLoaderExtension.new(recognized_extensions))

func __validate_image_name(image_name: String) -> _Common.Result:
	var result: _Common.Result = _Common.Result.new()
	var image_name_with_underscored_invalid_characters: String = image_name.validate_filename()
	var unsupported_characters: PackedStringArray
	for character_index in image_name.length():
		var validated_character = image_name_with_underscored_invalid_characters[character_index]
		if validated_character == "_":
			var original_character = image_name[character_index]
			if original_character != "_":
				if not unsupported_characters.has(original_character):
					unsupported_characters.push_back(original_character)
	if not unsupported_characters.is_empty():
		result.fail(ERR_FILE_BAD_PATH, "There are unsupported characters in Krita Document Title: \"%s\"" % ["".join(unsupported_characters)])
	return result

func _export(res_source_file_path: String, atlas_maker: AtlasMaker, options: Dictionary) -> _Common.ExportResult:
	var result: _Common.ExportResult = _Common.ExportResult.new()

	var os_command_result: _ProjectSetting.Result = __os_command_project_setting.get_value()
	if os_command_result.error:
		result.fail(ERR_UNCONFIGURED, "Unable to get Krita Command to export spritesheet", os_command_result)
		return result

	var os_command_arguments_result: _ProjectSetting.Result = __os_command_arguments_project_setting.get_value()
	if os_command_arguments_result.error:
		result.fail(ERR_UNCONFIGURED, "Unable to get Krita Command Arguments to export spritesheet", os_command_arguments_result)
		return result

	var temp_dir_path_result: _ProjectSetting.Result = _common_temporary_files_directory_path_project_setting.get_value()
	if temp_dir_path_result.error:
		result.fail(ERR_UNCONFIGURED, "Unable to get Temporary Files Directory Path to export spritesheet", temp_dir_path_result)
		return result

	var global_source_file_path: String = ProjectSettings.globalize_path(res_source_file_path)

	var zip_reader: ZIPReader = ZIPReader.new()
	var zip_error: Error = zip_reader.open(global_source_file_path)
	if zip_error:
		result.fail(zip_error, "Unable to open Krita file \"%s\" as ZIP archive with error: %s (%s)" % [res_source_file_path, zip_error, error_string(zip_error)])
		return result

	var files_names_in_zip: PackedStringArray = zip_reader.get_files()

	var maindoc_filename: String = "maindoc.xml"
	var maindoc_buffer: PackedByteArray = zip_reader.read_file(maindoc_filename)
	var maindoc_xml_root: _XML.XMLNodeRoot = _XML.parse_buffer(maindoc_buffer)
	var maindoc_doc_xml_element: _XML.XMLNodeElement = maindoc_xml_root.get_elements("DOC").front()

	var image_xml_element: _XML.XMLNodeElement = maindoc_doc_xml_element.get_elements("IMAGE").front()
	var image_name: String = image_xml_element.get_string("name")
	var image_size: Vector2i = image_xml_element.get_vector2i("width", "height")
	var image_name_validation_result: _Common.Result = __validate_image_name(image_name)
	if image_name_validation_result.error:
		result.fail(ERR_INVALID_DATA,
			"Krita Document Title have unsupported format",
			image_name_validation_result)
		return result

	var has_keyframes: bool
	for layer_xml_element in image_xml_element.get_elements("layers").front().get_elements("layer"):
		if layer_xml_element.attributes.has("keyframes"):
			has_keyframes = true
			break
	if not has_keyframes:
		result.fail(ERR_INVALID_DATA, "Source file has no keyframes")
		return result

	var animation_xml_element: _XML.XMLNodeElement = image_xml_element.get_elements("animation").front()
	var animation_framerate: int = max(1, animation_xml_element.get_elements("framerate").front().get_int("value"))
	var animation_range_xml_element: _XML.XMLNodeElement = animation_xml_element.get_elements("range").front()

	var animation_index_filename: String = "%s/animation/index.xml" % image_name
	var animation_index_buffer: PackedByteArray = zip_reader.read_file(animation_index_filename)
	var animation_index_xml_root: _XML.XMLNodeRoot = _XML.parse_buffer(animation_index_buffer)
	var animation_index_animation_metadata_xml_element: _XML.XMLNodeElement = animation_index_xml_root.get_elements("animation-metadata").front()
	var animation_index_animation_metadata_range_xml_element: _XML.XMLNodeElement = animation_index_animation_metadata_xml_element.get_elements("range").front()
	var export_settings_xml_element: _XML.XMLNodeElement = animation_index_animation_metadata_xml_element.get_elements("export-settings").front()
	var sequence_file_path_xml_element: _XML.XMLNodeElement = export_settings_xml_element.get_elements("sequenceFilePath").front()
	var sequence_base_name_xml_element: _XML.XMLNodeElement = export_settings_xml_element.get_elements("sequenceBaseName").front()

	var animations_parameters_parsing_results: Array[AnimationParamsParsingResult]
	var total_animations_frames_count: int
	var first_animations_frame_index: int = -1
	var last_animations_frame_index: int = -1
	var png_base_name: String = "img"
	var global_temp_kra_path: String
	var global_temp_png_path: String = temp_dir_path_result.value.path_join("%s.png" % png_base_name)
	DirAccess.make_dir_recursive_absolute(temp_dir_path_result.value)

	var storyboard_index_file_name: String = "%s/storyboard/index.xml" % image_name
	if storyboard_index_file_name in files_names_in_zip:
		var storyboard_index_xml_root: _XML.XMLNodeRoot = _XML.parse_buffer(zip_reader.read_file("%s/storyboard/index.xml" % image_name))
		var storyboard_info_xml_element: _XML.XMLNodeElement = storyboard_index_xml_root.get_elements("storyboard-info").front()
		var storyboard_item_list_xml_element: _XML.XMLNodeElement = storyboard_info_xml_element.get_elements("StoryboardItemList").front()
		var storyboard_item_xml_elements: Array[_XML.XMLNodeElement] = storyboard_item_list_xml_element.get_elements("storyboarditem")
		var unique_animations_names: PackedStringArray

		for animation_index in storyboard_item_xml_elements.size():
			var story_xml_element: _XML.XMLNodeElement = storyboard_item_xml_elements[animation_index]
			var animation_first_frame: int = story_xml_element.get_int("frame")
			var animation_params_parsing_result: AnimationParamsParsingResult = _parse_animation_params(
				story_xml_element.get_string("item-name").strip_edges(),
				AnimationOptions.Direction | AnimationOptions.RepeatCount,
				animation_first_frame,
				story_xml_element.get_int("duration-frame") + \
				animation_framerate * story_xml_element.get_int("duration-second"))
			if animation_params_parsing_result.error:
				result.fail(ERR_CANT_RESOLVE, "Unable to parse animation parameters",
					animation_params_parsing_result)
				return result
			if unique_animations_names.has(animation_params_parsing_result.name):
				result.fail(ERR_INVALID_DATA, "Duplicated animation name \"%s\" at index: %s" %
					[animation_params_parsing_result.name, animation_index])
				return result
			unique_animations_names.push_back(animation_params_parsing_result.name)
			animations_parameters_parsing_results.push_back(animation_params_parsing_result)
			total_animations_frames_count += animation_params_parsing_result.frames_count
			if first_animations_frame_index < 0 or animation_params_parsing_result.first_frame_index < first_animations_frame_index:
				first_animations_frame_index = animation_params_parsing_result.first_frame_index
			var animation_last_frame_index: int = animation_params_parsing_result.first_frame_index + animation_params_parsing_result.frames_count - 1
			if last_animations_frame_index < 0 or animation_last_frame_index > last_animations_frame_index:
				last_animations_frame_index = animation_last_frame_index

		animation_range_xml_element.attributes["from"] = str(first_animations_frame_index)
		animation_range_xml_element.attributes["to"] = str(last_animations_frame_index)

		var temp_kra_base_name: String = "img"
		var temp_kra_file_name: String = temp_kra_base_name + ".kra"
		global_temp_kra_path = temp_dir_path_result.value.path_join(temp_kra_file_name)

		animation_index_animation_metadata_range_xml_element.attributes["from"] = str(first_animations_frame_index)
		animation_index_animation_metadata_range_xml_element.attributes["to"] = str(last_animations_frame_index)

		var zip_writer = ZIPPacker.new()
		zip_writer.open(global_temp_kra_path, ZIPPacker.APPEND_CREATE)
		for filename in zip_reader.get_files():
			zip_writer.start_file(filename)
			match filename:
				maindoc_filename:
					zip_writer.write_file(maindoc_xml_root.dump_to_buffer())
				animation_index_filename:
					zip_writer.write_file(animation_index_xml_root.dump_to_buffer())
				_: zip_writer.write_file(zip_reader.read_file(filename))
			zip_writer.close_file()
		zip_writer.close()
	else:
		first_animations_frame_index = animation_range_xml_element.get_int("from")
		last_animations_frame_index = animation_range_xml_element.get_int("to")
		total_animations_frames_count = last_animations_frame_index - first_animations_frame_index + 1
		var default_animation_params_parsing_result: AnimationParamsParsingResult = AnimationParamsParsingResult.new()
		default_animation_params_parsing_result.name = options[_Options.DEFAULT_ANIMATION_NAME].strip_edges()
		if not default_animation_params_parsing_result.name:
			default_animation_params_parsing_result.name = "default"
		default_animation_params_parsing_result.first_frame_index = first_animations_frame_index
		default_animation_params_parsing_result.frames_count = last_animations_frame_index - first_animations_frame_index + 1
		default_animation_params_parsing_result.direction = options[_Options.DEFAULT_ANIMATION_DIRECTION]
		default_animation_params_parsing_result.repeat_count = options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT]
		animations_parameters_parsing_results.push_back(default_animation_params_parsing_result)
		global_temp_kra_path = global_source_file_path

	zip_reader.close()

	# Создать пользователя (например, KritaRunner) с паролем 111 с помощью Win+R -> netplwiz
	# Запустить Krita из-под этого пользователя с помощью утилиты PsExec
	# "C:\Program Files\WindowsApps\Microsoft.SysinternalsSuite_2023.6.0.0_x64__8wekyb3d8bbwe\Tools\PsExec.exe"
	# -u DEV-STATION\KritaRunner -p 111
	# "C:\Program Files\Krita (x64)\bin\krita.exe"
	# --export-sequence
	# --export-filename "R:\Temp\Godot\Krita Importers\img.png"
	# "D:\Godot 4.1\brave-mouse\project\tst2.kra"

	var output: Array
	var exit_code: int = OS.execute(
		os_command_result.value,
		os_command_arguments_result.value + PackedStringArray([
			"--export-sequence",
			"--export-filename", global_temp_png_path,
			global_temp_kra_path]),
		output, true, false)
	if exit_code:
		result.fail(ERR_QUERY_FAILED, "An error occurred while executing the Krita command. Process exited with code %s" % [exit_code])
		return result

	if global_temp_kra_path != global_source_file_path:
		DirAccess.remove_absolute(global_temp_kra_path)
		pass

	var unique_frames_count: int = last_animations_frame_index + 1 # - first_stories_frame
	var frames_images: Array[Image]
	for image_idx in unique_frames_count:
		var global_frame_png_path: String = temp_dir_path_result.value \
			.path_join("%s%04d.png" % [png_base_name, image_idx])
		if FileAccess.file_exists(global_frame_png_path):
			var image: Image = Image.load_from_file(global_frame_png_path)
			frames_images.push_back(image)
		else:
			frames_images.push_back(frames_images.back())
		DirAccess.remove_absolute(global_frame_png_path)

	var sprite_sheet_builder: _SpriteSheetBuilderBase = _create_sprite_sheet_builder(options)

	var sprite_sheet_building_result: _SpriteSheetBuilderBase.Result = sprite_sheet_builder.build_sprite_sheet(frames_images)
	if sprite_sheet_building_result.error:
		result.fail(ERR_BUG, "Sprite sheet building failed", sprite_sheet_building_result)
		return result
	var sprite_sheet: _Common.SpriteSheetInfo = sprite_sheet_building_result.sprite_sheet

	var atlas_making_result: AtlasMaker.Result = atlas_maker \
		.make_atlas(sprite_sheet_building_result.atlas_image)
	if atlas_making_result.error:
		result.fail(ERR_SCRIPT_FAILED, "Unable to make atlas texture from image", atlas_making_result)
		return result
	sprite_sheet.atlas = atlas_making_result.atlas

	var animation_library: _Common.AnimationLibraryInfo = _Common.AnimationLibraryInfo.new()
	var autoplay_animation_name: String = options[_Options.AUTOPLAY_ANIMATION_NAME].strip_edges()

	var frames_duration: float = 1.0 / animation_framerate
	var all_frames: Array[_Common.FrameInfo]
	all_frames.resize(unique_frames_count)
	for animation_index in animations_parameters_parsing_results.size():
		var animation_params_parsing_result: AnimationParamsParsingResult = animations_parameters_parsing_results[animation_index]
		var animation = _Common.AnimationInfo.new()
		animation.name = animation_params_parsing_result.name
		if animation.name == autoplay_animation_name:
			animation_library.autoplay_index = animation_index
		animation.direction = animation_params_parsing_result.direction
		animation.repeat_count = animation_params_parsing_result.repeat_count
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

	result.success(sprite_sheet, animation_library)
	return result

class CustomImageFormatLoaderExtension:
	extends ImageFormatLoaderExtension

	var __recognized_extensions: PackedStringArray

	func _init(recognized_extensions: PackedStringArray) -> void:
		__recognized_extensions = recognized_extensions

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
		var zip_reader := ZIPReader.new()
		zip_reader.open(file_access.get_path_absolute())
		image.load_png_from_buffer(zip_reader.read_file("mergedimage.png"))
		zip_reader.close()
		return OK
