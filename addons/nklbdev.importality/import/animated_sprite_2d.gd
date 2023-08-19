@tool
extends "_node.gd"

const _SpriteFramesImporter = preload("sprite_frames.gd")

var __sprite_frames_importer: _SpriteFramesImporter

func _init() -> void:
	super("AnimatedSprite2D", "PackedScene", "scn")
	__sprite_frames_importer =  _SpriteFramesImporter.new()

func import(
	res_source_file_path: String,
	atlas: Texture2D,
	sprite_sheet: _Common.SpriteSheetInfo,
	animation_library: _Common.AnimationLibraryInfo,
	options: Dictionary,
	save_path: String
	) -> ImportResult:
	var result: ImportResult = ImportResult.new()

	var sprite_frames_import_result: ImportResult = __sprite_frames_importer \
		.import(res_source_file_path, atlas, sprite_sheet,	animation_library, options, save_path)
	if sprite_frames_import_result.error:
		return sprite_frames_import_result
	var sprite_frames: SpriteFrames = sprite_frames_import_result.resource

	var animated_sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	var node_name: String = options[_Options.ROOT_NODE_NAME].strip_edges()
	animated_sprite.name = res_source_file_path.get_file().get_basename() \
		if node_name.is_empty() else node_name
	animated_sprite.sprite_frames = sprite_frames

	if animation_library.autoplay_index >= 0:
		if animation_library.autoplay_index >= animation_library.animations.size():
			result.fail(ERR_INVALID_DATA, "Autoplay animation index overflow")
			return result
		animated_sprite.autoplay = animation_library \
			.animations[animation_library.autoplay_index].name

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(animated_sprite)
	result.success(packed_scene,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	return result
