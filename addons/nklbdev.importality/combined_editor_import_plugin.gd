@tool
extends EditorImportPlugin

const _Common = preload("common.gd")
const _Options = preload("options.gd")
const _Exporter = preload("export/_.gd")
const _Importer = preload("import/_.gd")
const _AtlasMaker = preload("atlas_maker.gd")
const _MiddleImportScript = preload("middle_import.gd")

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

func _init(exporter: _Exporter, importer: _Importer, atlas_maker: _AtlasMaker) -> void:
	__importer = importer
	__exporter = exporter
	__atlas_maker = atlas_maker
	__import_order = 1
	__importer_name = "%s %s" % [exporter.get_name(), importer.get_name()]
	__priority = 1
	__resource_type = importer.get_resource_type()
	__save_extension = importer.get_save_extension()
	__visible_name = "%s -> %s" % [exporter.get_name(), importer.get_name()]
	var options: Array[Dictionary]
	__options.append_array(importer.get_options())
	__options.append(_Options.create_option(
		_Options.MIDDLE_IMPORT_SCRIPT_PATH, "", PROPERTY_HINT_FILE, "*.gd", PROPERTY_USAGE_DEFAULT))
	__options.append_array(exporter.get_options())
	for option in __options:
		if option.has("get_is_visible"):
			__options_visibility_checkers[option.name] = option.get_is_visible

func _import(
	source_file: String,
	save_path: String,
	options: Dictionary,
	platform_variants: Array[String],
	gen_files: Array[String]
	) -> Error:
	var export_result: _Exporter.ExportResult = \
		__exporter.export(source_file, options, self)
	if export_result.error:
		push_error("Export is failed. Errors chain:\n%s" % [export_result])
		return export_result.error
	var middle_import_script_path: String = options[_Options.MIDDLE_IMPORT_SCRIPT_PATH].strip_edges()
	if middle_import_script_path:
		if not (middle_import_script_path.is_absolute_path() and middle_import_script_path.begins_with("res://")):
			push_error("Middle import script path is not valid: %s" % [middle_import_script_path])
			return ERR_FILE_BAD_PATH
		var middle_import_script: Script = ResourceLoader \
			.load(middle_import_script_path, "Script") as Script
		if middle_import_script == null:
			push_error("Unable to load middle import script: %s" % [middle_import_script_path])
			return ERR_FILE_CORRUPT
		if not __is_script_inherited_from(middle_import_script, _MiddleImportScript):
			push_error("The script specified as middle import script is not inherited from middle_import_script.gd: %s" % [middle_import_script_path])
			return ERR_INVALID_DECLARATION
		middle_import_script.modify(
			export_result.atlas_image,
			export_result.sprite_sheet,
			export_result.animation_library)

	var atlas_making_result: _AtlasMaker.AtlasMakingResult = \
		__atlas_maker.make_atlas(export_result.atlas_image, source_file, self)
	if atlas_making_result.error:
		push_error("Atlas texture making is failed. Errors chain:\n%s" % [atlas_making_result])
		return atlas_making_result.error
	var import_result: _Importer.ImportResult = __importer.import(
		source_file,
		atlas_making_result.atlas,
		export_result.sprite_sheet,
		export_result.animation_library,
		options,
		save_path)
	if import_result.error:
		push_error("Import is failed. Errors chain:\n%s" % [import_result])
		return import_result.error
	return ResourceSaver.save(
		import_result.resource,
		"%s.%s" % [save_path, _get_save_extension()],
		import_result.resource_saver_flags)

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
