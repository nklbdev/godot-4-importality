@tool
extends EditorImportPlugin

const _Common = preload("common.gd")
const _Options = preload("options.gd")
const _Exporter = preload("export/_.gd")
const _Importer = preload("import/_.gd")
const _AtlasMaker = preload("atlas_maker.gd")
const _MiddleImportScript = preload("external_scripts/middle_import_script_base.gd")
const _PostImportScript = preload("external_scripts/post_import_script_base.gd")

const __empty_callable: Callable = Callable()

var __exporter: _Exporter
var __importer: _Importer
var __import_order: int = 0
var __importer_name: String
var __priority: float = 1
var __resource_type: StringName
var __save_extension: String
var __visible_name: String
var __options: Array[Dictionary]
var __options_visibility_checkers: Dictionary
var __atlas_maker: _AtlasMaker
var __editor_file_system: EditorFileSystem

func _init(exporter: _Exporter, importer: _Importer, atlas_maker: _AtlasMaker, editor_file_system: EditorFileSystem) -> void:
	__importer = importer
	__exporter = exporter
	__atlas_maker = atlas_maker
	__import_order = 1
	__importer_name = "%s %s" % [exporter.get_name(), importer.get_name()]
	__priority = 1
	__resource_type = importer.get_resource_type()
	__save_extension = importer.get_save_extension()
	__visible_name = "%s -> %s" % [exporter.get_name(), importer.get_name()]
	__editor_file_system = editor_file_system
	var options: Array[Dictionary]
	__options.append_array(importer.get_options())
	__options.append(_Options.create_option(
		_Options.MIDDLE_IMPORT_SCRIPT_PATH, "", PROPERTY_HINT_FILE, "*.gd", PROPERTY_USAGE_DEFAULT))
	__options.append(_Options.create_option(
		_Options.POST_IMPORT_SCRIPT_PATH, "", PROPERTY_HINT_FILE, "*.gd", PROPERTY_USAGE_DEFAULT))
	__options.append_array(exporter.get_options())
	for option in __options:
		if option.has("get_is_visible"):
			__options_visibility_checkers[option.name] = option.get_is_visible

func _import(
	res_source_file_path: String,
	res_save_file_path: String,
	options: Dictionary,
	platform_variants: Array[String],
	gen_files: Array[String]
	) -> Error:
	var error: Error

	var export_result: _Exporter.ExportResult = \
		__exporter.export(res_source_file_path, options, self)
	if export_result.error:
		push_error("Export is failed. Errors chain:\n%s" % [export_result])
		return export_result.error

	var middle_import_script_context: _MiddleImportScript.Context = _MiddleImportScript.Context.new()
	middle_import_script_context.atlas_image = export_result.atlas_image
	middle_import_script_context.sprite_sheet = export_result.sprite_sheet
	middle_import_script_context.animation_library = export_result.animation_library


	# -------- MIDDLE IMPORT BEGIN --------
	var middle_import_script_path: String = options[_Options.MIDDLE_IMPORT_SCRIPT_PATH].strip_edges()
	if middle_import_script_path:
		if not (middle_import_script_path.is_absolute_path() and middle_import_script_path.begins_with("res://")):
			push_error("Middle import script path is not valid: %s" % [middle_import_script_path])
			return ERR_FILE_BAD_PATH
		var middle_import_script: Script = ResourceLoader \
			.load(middle_import_script_path, "Script") as Script
		if middle_import_script == null:
			push_error("Failed to load middle import script: %s" % [middle_import_script_path])
			return ERR_FILE_CORRUPT
		if not __is_script_inherited_from(middle_import_script, _MiddleImportScript):
			push_error("The script specified as middle import script is not inherited from external_scripts/middle_import_script_base.gd: %s" % [middle_import_script_path])
			return ERR_INVALID_DECLARATION
		error = middle_import_script.modify_context(
			res_source_file_path,
			res_save_file_path,
			self,
			__editor_file_system,
			options,
			middle_import_script_context)
		if error:
			push_error("Failed to perform middle-import-script")
			return error
		error = __append_gen_files(gen_files, middle_import_script_context.gen_files_to_add)
		if error:
			push_error("Failed to add gen files from middle-import-script context")
			return error
	# -------- MIDDLE IMPORT END --------



	var atlas_making_result: _AtlasMaker.AtlasMakingResult = \
		__atlas_maker.make_atlas(middle_import_script_context.atlas_image, res_source_file_path, self)
	if atlas_making_result.error:
		push_error("Atlas texture making is failed. Errors chain:\n%s" % [atlas_making_result])
		return atlas_making_result.error
	var import_result: _Importer.ImportResult = __importer.import(
		res_source_file_path,
		atlas_making_result.atlas,
		middle_import_script_context.sprite_sheet,
		middle_import_script_context.animation_library,
		options,
		res_save_file_path)
	if import_result.error:
		push_error("Import is failed. Errors chain:\n%s" % [import_result])
		return import_result.error

	var post_import_script_context: _PostImportScript.Context = _PostImportScript.Context.new()
	post_import_script_context.resource = import_result.resource
	post_import_script_context.resource_saver_flags = import_result.resource_saver_flags
	post_import_script_context.save_extension = _get_save_extension()



	# -------- POST IMPORT BEGIN --------
	var post_import_script_path: String = options[_Options.POST_IMPORT_SCRIPT_PATH].strip_edges()
	if post_import_script_path:
		if not (post_import_script_path.is_absolute_path() and post_import_script_path.begins_with("res://")):
			push_error("Post import script path is not valid: %s" % [post_import_script_path])
			return ERR_FILE_BAD_PATH
		var post_import_script: Script = ResourceLoader \
			.load(post_import_script_path, "Script") as Script
		if post_import_script == null:
			push_error("Failed to load post import script: %s" % [post_import_script_path])
			return ERR_FILE_CORRUPT
		if not __is_script_inherited_from(post_import_script, _PostImportScript):
			push_error("The script specified as post import script is not inherited from external_scripts/post_import_script_base.gd: %s" % [post_import_script_path])
			return ERR_INVALID_DECLARATION
		error = post_import_script.modify_context(
			res_source_file_path,
			res_save_file_path,
			self,
			__editor_file_system,
			options,
			middle_import_script_context.middle_import_data,
			post_import_script_context)
		if error:
			push_error("Failed to perform post-import-script")
			return error
		error = __append_gen_files(gen_files, post_import_script_context.gen_files_to_add)
		if error:
			push_error("Failed to add gen files from post-import-script context")
			return error
	# -------- POST IMPORT END --------


	error = ResourceSaver.save(
		post_import_script_context.resource,
		"%s.%s" % [res_save_file_path, post_import_script_context.save_extension],
		post_import_script_context.resource_saver_flags)
	if error:
		push_error("Failed to save the new resource via ResourceSaver")
	return error

func _get_import_options(path: String, preset_index: int) -> Array[Dictionary]:
	return __options

func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	if __options_visibility_checkers.has(option_name):
		return __options_visibility_checkers[option_name].call(options)
	return true

func _get_import_order() -> int:
	return __import_order

func _get_importer_name() -> String:
	return __importer_name

func _get_preset_count() -> int:
	return 1

func _get_preset_name(preset_index: int) -> String:
	return "Default"

func _get_priority() -> float:
	return __priority

func _get_recognized_extensions() -> PackedStringArray:
	return __exporter.get_recognized_extensions()

func _get_resource_type() -> String:
	return __importer.get_resource_type()

func _get_save_extension() -> String:
	return __importer.get_save_extension()

func _get_visible_name() -> String:
	return __visible_name

func __is_script_inherited_from(script: Script, base_script: Script) -> bool:
	while script != null:
		if script == base_script:
			return true
		script = script.get_base_script()
	return false

func __append_gen_files(gen_files: PackedStringArray, gen_files_to_add: PackedStringArray) -> Error:
	for gen_file_path in gen_files_to_add:
		gen_file_path = gen_file_path.strip_edges()
		if gen_files.has(gen_file_path):
			continue
		if not gen_file_path.is_absolute_path():
			push_error("Gen-file-path is not valid path: %s" % [gen_file_path])
			return ERR_FILE_BAD_PATH
		if not gen_file_path.begins_with("res://"):
			push_error("Gen-file-path is not a resource file system path (res://): %s" % [gen_file_path])
			return ERR_FILE_BAD_PATH
		if not FileAccess.file_exists(gen_file_path):
			push_error("The file at the gen-file-path was not found: %s" % [gen_file_path])
			return ERR_FILE_NOT_FOUND
		gen_files.push_back(gen_file_path)
	return OK
