extends "_.gd"

class Context:
	extends RefCounted
	var resource: Resource
	var resource_saver_flags: ResourceSaver.SaverFlags
	var save_extension: String
	var gen_files_to_add: PackedStringArray

static func modify_context(
	res_source_file_path: String,
	res_save_file_path: String,
	editor_import_plugin: EditorImportPlugin,
	editor_file_system: EditorFileSystem,
	options: Dictionary,
	middle_import_data: Variant,
	context: Context,
	) -> Error:
	return OK
