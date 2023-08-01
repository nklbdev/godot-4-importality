@tool
extends EditorImportPlugin

const _Common = preload("common.gd")
const _Exporter = preload("export/_.gd")
const _Importer = preload("import/_.gd")

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

func _init(exporter: _Exporter, importer: _Importer) -> void:
	__importer = importer
	__exporter = exporter
	__import_order = 1
	__importer_name = "%s %s" % [exporter.get_name(), importer.get_name()]
	__priority = 1
	__resource_type = importer.get_resource_type()
	__save_extension = importer.get_save_extension()
	__visible_name = "%s -> %s" % [exporter.get_name(), importer.get_name()]
	var options: Array[Dictionary]
	__options.append_array(importer.get_options())
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
	var export_result: _Common.ExportResult = \
		__exporter.export(source_file, options, self)
	if export_result.error:
		push_error("Export is failed. Errors chain:\n%s" % [export_result])
		return export_result.error
	var import_result: _Common.ImportResult = \
		__importer.import(source_file, export_result.sprite_sheet, export_result.animation_library, options, save_path)
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
