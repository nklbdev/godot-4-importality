extends "_.gd"

class Context:
	extends RefCounted
	var atlas_image: Image
	var sprite_sheet: SpriteSheetInfo
	var animation_library: AnimationLibraryInfo
	var gen_files_to_add: PackedStringArray
	var middle_import_data: Variant

static func modify_context(
	res_source_file_path: String,
	res_save_file_path: String,
	editor_import_plugin: EditorImportPlugin,
	editor_file_system: EditorFileSystem,
	options: Dictionary,
	context: Context) -> Error:
	return OK
