extends "_node.gd"

const _SpriteFramesImporter = preload("sprite_frames.gd")

var __sprite_frames_importer: _SpriteFramesImporter

func _init() -> void:
	super("AnimatedSprite3D", "PackedScene", "scn")
	__sprite_frames_importer =  _SpriteFramesImporter.new()

func import(
	res_source_file_path: String,
	export_result: _Models.ExportResultModel,
	options: Dictionary,
	save_path: String
	) -> _Models.ImportResultModel:

	var sprite_frames_import_result: _Models.ImportResultModel = __sprite_frames_importer \
		.import(res_source_file_path, export_result, options, save_path)
	if sprite_frames_import_result.status:
		return sprite_frames_import_result
	var sprite_frames: SpriteFrames = sprite_frames_import_result.resource

	var animated_sprite: AnimatedSprite3D = AnimatedSprite3D.new()
	var node_name: String = options[_Options.ROOT_NODE_NAME].strip_edges()
	animated_sprite.name = res_source_file_path.get_file().get_basename() \
		if node_name.is_empty() else node_name
	animated_sprite.sprite_frames = sprite_frames

	if export_result.animation_library.autoplay_animation_index >= 0:
		animated_sprite.autoplay = export_result.animation_library \
			.animations[export_result.animation_library.autoplay_animation_index].name

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(animated_sprite)
	return _Models.ImportResultModel.success(packed_scene,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
