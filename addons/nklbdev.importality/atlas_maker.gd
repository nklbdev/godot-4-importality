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

	var portableCompressedTexture: PortableCompressedTexture2D = PortableCompressedTexture2D.new()
	portableCompressedTexture.create_from_image(atlas_image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)

	result.success(portableCompressedTexture)
	return result
