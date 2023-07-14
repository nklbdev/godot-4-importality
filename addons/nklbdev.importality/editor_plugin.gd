@tool
extends EditorPlugin

const ExporterBase = preload("export/_.gd")
const EXPORTERS_SCRIPTS: Array[GDScript] = [
	preload("export/aseprite.gd"),
	preload("export/gif.gd"),
	preload("export/graphicsgale.gd"),
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
	# TODO: preload("import/sprite_sheet.gd"),
]

const CombinedEditorImportPlugin = preload("combined_editor_import_plugin.gd")

var __editor_import_plugins: Array[EditorImportPlugin]
var __image_format_loader_extensions: Array[ImageFormatLoaderExtension]

func _enter_tree() -> void:
	var editor_file_system: EditorFileSystem = get_editor_interface().get_resource_filesystem()
	var exporters: Array[ExporterBase]
	for Exporter in EXPORTERS_SCRIPTS:
		var exporter: ExporterBase = Exporter.new(editor_file_system)
		for setting in exporter.get_project_settings():
			setting.register()
		exporters.push_back(exporter)
		var image_format_loader_extension: ImageFormatLoaderExtension = \
			exporter.get_image_format_loader_extension()
		if image_format_loader_extension:
			__image_format_loader_extensions.push_back(image_format_loader_extension)
			image_format_loader_extension.add_format_loader()
	var importers: Array[ImporterBase]
	for Importer in IMPORTERS_SCRIPTS:
		importers.push_back(Importer.new())
	for exporter in exporters:
		for importer in importers:
			var editor_import_plugin: EditorImportPlugin = \
				CombinedEditorImportPlugin.new(exporter, importer)
			__editor_import_plugins.push_back(editor_import_plugin)
			add_import_plugin(editor_import_plugin)

func _exit_tree() -> void:
	for editor_import_plugin in __editor_import_plugins:
		remove_import_plugin(editor_import_plugin)
	__editor_import_plugins.clear()
	for image_format_loader_extension in __image_format_loader_extensions:
		image_format_loader_extension.remove_format_loader()
	__image_format_loader_extensions.clear()
