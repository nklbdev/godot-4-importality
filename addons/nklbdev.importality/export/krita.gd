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

func __validate_image_name(image_name: String) -> bool:
	return true

func _export(res_source_file_path: String, options: Dictionary) -> _Models.ExportResultModel:
	var os_command_result: _ProjectSetting.Result = __os_command_project_setting.get_value()
	if os_command_result.error:
		return _Models.ExportResultModel.fail(os_command_result.error, os_command_result.error_message)

	var os_command_arguments_result: _ProjectSetting.Result = __os_command_arguments_project_setting.get_value()
	if os_command_arguments_result.error:
		return _Models.ExportResultModel.fail(os_command_arguments_result.error, os_command_arguments_result.error_message)

	var temp_dir_path_result: _ProjectSetting.Result = _common_temporary_files_directory_path_project_setting.get_value()
	if temp_dir_path_result.error:
		return _Models.ExportResultModel.fail(temp_dir_path_result.error, temp_dir_path_result.error_message)

	var global_source_file_path: String = ProjectSettings.globalize_path(res_source_file_path)

	var zip_reader: ZIPReader = ZIPReader.new()
	var zip_error: Error = zip_reader.open(global_source_file_path)
	if zip_error: return _Models.ExportResultModel.fail(zip_error, "Unable to open Krita file as ZIP archive")
	var files_names_in_zip: PackedStringArray = zip_reader.get_files()

	var maindoc_filename: String = "maindoc.xml"
	var buf: PackedByteArray = zip_reader.read_file(maindoc_filename)
	var maindoc_xml_root: _XML.XMLNodeRoot = _XML.parse_buffer(buf)
	var maindoc_doc_xml_element: _XML.XMLNodeElement = maindoc_xml_root.get_elements("DOC").front()

	var image_xml_element: _XML.XMLNodeElement = maindoc_doc_xml_element.get_elements("IMAGE").front()
	var image_name: String = image_xml_element.get_string("name")
	var image_size: Vector2i = image_xml_element.get_vector2i("width", "height")
	if not __validate_image_name(image_name):
		var result = _Models.ExportResultModel.new()
		result.status = ERR_INVALID_DATA
		result.error_description = "Image name have unsupported format"
		return result

	var has_keyframes: bool
	for layer_xml_element in image_xml_element.get_elements("layers").front().get_elements("layer"):
		if layer_xml_element.attributes.has("keyframes"):
			has_keyframes = true
			break
	if not has_keyframes:
		var sh: _Models.SpriteSheetModel = _Models.SpriteSheetModel.new()
		sh.edges_artifacts_avoidance_method = options[_Options.EDGES_ARTIFACTS_AVOIDANCE_METHOD]
		sh.atlas_image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		sh.layout = options[_Options.SPRITE_SHEET_LAYOUT]
		sh.source_image_size = image_size
		sh.strips_count = 0
		sh.cells_in_strip_count = 0

		var al: _Models.AnimationLibraryModel = _Models.AnimationLibraryModel.new()
		var an: _Models.AnimationModel = _Models.AnimationModel.new()
		an.name = options[_Options.DEFAULT_ANIMATION_NAME].strip_edges()
		if not an.name:
			an.name = "default"
		an.direction = options[_Options.DEFAULT_ANIMATION_DIRECTION]
		an.repeat_count = options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT]
		al.animations.push_back(an)
		return _Models.ExportResultModel.success(sh, al)


	var animation_xml_element: _XML.XMLNodeElement = image_xml_element.get_elements("animation").front()
	var animation_framerate: int = max(1, animation_xml_element.get_elements("framerate").front().get_int("value"))
	var animation_range_xml_element: _XML.XMLNodeElement = animation_xml_element.get_elements("range").front()

	var animation_index_filename: String = "%s/animation/index.xml" % image_name
	buf = zip_reader.read_file(animation_index_filename)
	var animation_index_xml_root: _XML.XMLNodeRoot = _XML.parse_buffer(buf)
	var animation_index_animation_metadata_xml_element: _XML.XMLNodeElement = animation_index_xml_root.get_elements("animation-metadata").front()
	var animation_index_animation_metadata_range_xml_element: _XML.XMLNodeElement = animation_index_animation_metadata_xml_element.get_elements("range").front()
	var export_settings_xml_element: _XML.XMLNodeElement = animation_index_animation_metadata_xml_element.get_elements("export-settings").front()
	var sequence_file_path_xml_element: _XML.XMLNodeElement = export_settings_xml_element.get_elements("sequenceFilePath").front()
	var sequence_base_name_xml_element: _XML.XMLNodeElement = export_settings_xml_element.get_elements("sequenceBaseName").front()

	var animations_infos: Array[_AnimationInfo]
	var total_animations_frames_count: int
	var first_animations_frame: int = -1
	var last_animations_frame: int = -1
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

		for story_xml_element in storyboard_item_xml_elements:
			var animation_first_frame: int = story_xml_element.get_int("frame")
			var animation_info: _AnimationInfo = _parse_animation_info(
				story_xml_element.get_string("item-name").strip_edges(),
				AnimationOption.Direction | AnimationOption.RepeatCount,
				animation_first_frame,
				animation_first_frame + story_xml_element.get_int("duration-frame") + \
				animation_framerate * story_xml_element.get_int("duration-second") - 1)
			animations_infos.push_back(animation_info)
			total_animations_frames_count += animation_info.last_frame - animation_info.first_frame + 1
			if first_animations_frame < 0 or animation_info.first_frame < first_animations_frame:
				first_animations_frame = animation_info.first_frame
			if last_animations_frame < 0 or animation_info.last_frame > last_animations_frame:
				last_animations_frame = animation_info.last_frame

		animation_range_xml_element.attributes["from"] = str(first_animations_frame)
		animation_range_xml_element.attributes["to"] = str(last_animations_frame)

		var temp_kra_base_name: String = "img"
		var temp_kra_file_name: String = temp_kra_base_name + ".kra"
		global_temp_kra_path = temp_dir_path_result.value.path_join(temp_kra_file_name)

		animation_index_animation_metadata_range_xml_element.attributes["from"] = str(first_animations_frame)
		animation_index_animation_metadata_range_xml_element.attributes["to"] = str(last_animations_frame)

		var zip_writer = ZIPPacker.new()
		zip_writer.open(global_temp_kra_path, ZIPPacker.APPEND_CREATE)
		for filename in zip_reader.get_files():
			zip_writer.start_file(filename)
			match filename:
				maindoc_filename:
					buf = maindoc_xml_root.dump_to_buffer()
					zip_writer.write_file(buf)
				animation_index_filename:
					buf = animation_index_xml_root.dump_to_buffer()
					zip_writer.write_file(buf)
				_: zip_writer.write_file(zip_reader.read_file(filename))
			zip_writer.close_file()
		zip_writer.close()
	else:
		first_animations_frame = animation_range_xml_element.get_int("from")
		last_animations_frame = animation_range_xml_element.get_int("to")
		total_animations_frames_count = last_animations_frame - first_animations_frame + 1
		var default_animation_info: _AnimationInfo = _AnimationInfo.new()
		default_animation_info.name = options[_Options.DEFAULT_ANIMATION_NAME].strip_edges()
		if not default_animation_info.name:
			default_animation_info.name = "default"
		default_animation_info.first_frame = first_animations_frame
		default_animation_info.last_frame = last_animations_frame
		default_animation_info.direction = options[_Options.DEFAULT_ANIMATION_DIRECTION]
		default_animation_info.repeat_count = options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT]
		animations_infos.push_back(default_animation_info)
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
		return _Models.ExportResultModel.fail(exit_code, "An error occurred while executing the Krita command")

	if global_temp_kra_path != global_source_file_path:
		DirAccess.remove_absolute(global_temp_kra_path)
		pass

	var unique_frames_count: int = last_animations_frame + 1 # - first_stories_frame
	var frames_images: Array[Image]
	for image_idx in unique_frames_count:
		var global_frame_png_path: String = temp_dir_path_result.value \
			.path_join("%s%04d.png" % [png_base_name, image_idx])
		if FileAccess.file_exists(global_frame_png_path):
			frames_images.push_back(Image.load_from_file(global_frame_png_path))
		else:
			frames_images.push_back(frames_images.back())
		DirAccess.remove_absolute(global_frame_png_path)

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
