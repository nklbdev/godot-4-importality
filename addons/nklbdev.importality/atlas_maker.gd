@tool
extends RefCounted

const _Result = preload("result.gd").Class

class AtlasMakingResult:
	extends _Result
	var atlas: Texture2D
	func success(atlas: Texture2D) -> void:
		super._success()
		self.atlas = atlas

var __editor_file_system: EditorFileSystem

func _init(editor_file_system: EditorFileSystem) -> void:
	__editor_file_system = editor_file_system

func make_atlas(
	atlas_image: Image,
	res_source_file_path: String,
	editor_import_plugin: EditorImportPlugin,
	) -> AtlasMakingResult:
	var result: AtlasMakingResult = AtlasMakingResult.new()
	var res_png_path: String = res_source_file_path + ".png"
	if not (res_png_path.is_absolute_path() and res_png_path.begins_with("res://")):
		result.fail(ERR_FILE_BAD_PATH, "Path to PNG-file is not valid: %s" % [res_png_path])
		return result
	var error: Error
	error = atlas_image.save_png(res_png_path)
	if error:
		result.fail(error, "An error occured while saving atlas-image to png-file: %s" % [res_png_path])
		return result
	__editor_file_system.update_file(res_png_path)
	error = editor_import_plugin.append_import_external_resource(res_png_path)
	if error:
		result.fail(error, "An error occured while appending import external resource (atlas texture)")
		return result
	result.success(ResourceLoader.load(res_png_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE))
	return result
