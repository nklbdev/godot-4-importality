@tool
extends EditorPlugin

const ExporterBase = preload("export/_.gd")
const _AtlasMaker = preload("atlas_maker.gd")

const EXPORTERS_SCRIPTS: Array[GDScript] = [
	preload("export/aseprite.gd"),
	preload("export/krita.gd"),
	preload("export/pencil2d.gd"),
	preload("export/piskel.gd"),
	preload("export/pixelorama.gd"),
]

const ImporterBase = preload("import/_.gd")
const IMPORTERS_SCRIPTS: Array[GDScript] = [
	preload("import/animated_sprite_2d.gd"),
	preload("import/animated_sprite_3d.gd"),
	preload("import/sprite_2d_with_animation_player.gd"),
	preload("import/sprite_3d_with_animation_player.gd"),
	preload("import/sprite_frames.gd"),
	preload("import/texture_rect_with_animation_player.gd"),
	preload("import/sprite_sheet.gd"),
]

const StandaloneImageFormatLoaderExtension = preload("standalone_image_format_loader_extension.gd")
const STANDALONE_IMAGE_FORMAT_LOADER_EXTENSIONS: Array[GDScript] = [
	preload("command_line_image_format_loader_extension.gd")
]

const CombinedEditorImportPlugin = preload("combined_editor_import_plugin.gd")

var __editor_import_plugins: Array[EditorImportPlugin]
var __image_format_loader_extensions: Array[ImageFormatLoaderExtension]

func _enter_tree() -> void:
	var editor_interface: EditorInterface = get_editor_interface()
	var editor_file_system: EditorFileSystem = editor_interface.get_resource_filesystem()
	var editor_settings: EditorSettings = editor_interface.get_editor_settings()

	var exporters: Array[ExporterBase]
	for Exporter in EXPORTERS_SCRIPTS:
		var exporter: ExporterBase = Exporter.new(editor_file_system)
		for setting in exporter.get_settings():
			setting.register(editor_settings)
		exporters.push_back(exporter)
		var image_format_loader_extension: ImageFormatLoaderExtension = \
			exporter.get_image_format_loader_extension()
		if image_format_loader_extension:
			__image_format_loader_extensions.push_back(image_format_loader_extension)
			image_format_loader_extension.add_format_loader()
	var importers: Array[ImporterBase]
	for Importer in IMPORTERS_SCRIPTS:
		importers.push_back(Importer.new())
	var atlas_maker: _AtlasMaker = _AtlasMaker.new(editor_file_system)
	for exporter in exporters:
		for importer in importers:
			var editor_import_plugin: EditorImportPlugin = \
				CombinedEditorImportPlugin.new(exporter, importer, atlas_maker, editor_file_system)
			__editor_import_plugins.push_back(editor_import_plugin)
			add_import_plugin(editor_import_plugin)
	for Extension in STANDALONE_IMAGE_FORMAT_LOADER_EXTENSIONS:
		var image_format_loader_extension: StandaloneImageFormatLoaderExtension = \
			Extension.new() as StandaloneImageFormatLoaderExtension
		for setting in image_format_loader_extension.get_settings():
			setting.register(editor_settings)
		__image_format_loader_extensions.push_back(image_format_loader_extension)
		image_format_loader_extension.add_format_loader()

func _exit_tree() -> void:
	for editor_import_plugin in __editor_import_plugins:
		remove_import_plugin(editor_import_plugin)
	__editor_import_plugins.clear()
	for image_format_loader_extension in __image_format_loader_extensions:
		image_format_loader_extension.remove_format_loader()
	__image_format_loader_extensions.clear()
