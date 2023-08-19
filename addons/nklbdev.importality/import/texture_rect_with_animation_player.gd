@tool
extends "_node_with_animation_player.gd"

const ANIMATION_STRATEGIES_NAMES: PackedStringArray = [
	"Animate single atlas texture's region and margin",
	"Animate multiple atlas textures instances",
]
enum AnimationStrategy {
	SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN = 1,
	MULTIPLE_ATLAS_TEXTURES_INSTANCES = 2
}

func _init() -> void:
	super("TextureRect with AnimationPlayer", "PackedScene", "scn", [
		_Options.create_option(_Options.ANIMATION_STRATEGY, AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN,
		PROPERTY_HINT_ENUM, ",".join(ANIMATION_STRATEGIES_NAMES), PROPERTY_USAGE_DEFAULT),
	])

func import(
	res_source_file_path: String,
	atlas: Texture2D,
	sprite_sheet: _Common.SpriteSheetInfo,
	animation_library: _Common.AnimationLibraryInfo,
	options: Dictionary,
	save_path: String
	) -> ImportResult:
	var result: ImportResult = ImportResult.new()

	var texture_rect: TextureRect = TextureRect.new()
	var node_name: String = options[_Options.ROOT_NODE_NAME].strip_edges()
	texture_rect.name = res_source_file_path.get_file().get_basename() \
		if node_name.is_empty() else node_name
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var sprite_size: Vector2i = sprite_sheet.source_image_size
	texture_rect.size = sprite_size

	var filter_clip_enabled: bool = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]

	var animation_player: AnimationPlayer
	match options[_Options.ANIMATION_STRATEGY]:

		AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
			var atlas_texture: AtlasTexture = AtlasTexture.new()
			atlas_texture.atlas = atlas
			atlas_texture.filter_clip = filter_clip_enabled
			atlas_texture.resource_local_to_scene = true
			atlas_texture.region = Rect2(0, 0, 1, 1)
			atlas_texture.margin = Rect2(2, 2, 0, 0)
			texture_rect.texture = atlas_texture

			animation_player = _create_animation_player(animation_library, {
				".:texture:margin": func(frame: _Common.FrameInfo) -> Rect2:
					return \
						Rect2(frame.sprite.offset,
							sprite_size - frame.sprite.region.size) \
						if frame.sprite.region.has_area() else \
						Rect2(2, 2, 0, 0),
				".:texture:region" : func(frame: _Common.FrameInfo) -> Rect2:
					return \
						Rect2(frame.sprite.region) \
						if frame.sprite.region.has_area() else \
						Rect2(0, 0, 1, 1) })

		AnimationStrategy.MULTIPLE_ATLAS_TEXTURES_INSTANCES:
			var atlas_textures: Array[AtlasTexture]
			var empty_atlas_texture: AtlasTexture = AtlasTexture.new()
			empty_atlas_texture.filter_clip = filter_clip_enabled
			empty_atlas_texture.atlas = atlas
			empty_atlas_texture.region = Rect2(0, 0, 1, 1)
			empty_atlas_texture.margin = Rect2(2, 2, 0, 0)
			animation_player = _create_animation_player(animation_library, {
				".:texture": func(frame: _Common.FrameInfo) -> Texture2D:
					if not frame.sprite.region.has_area():
						return empty_atlas_texture
					var region: Rect2 = frame.sprite.region
					var margin: Rect2 = Rect2(
						frame.sprite.offset,
						sprite_size - frame.sprite.region.size)
					var equivalent_atlas_textures: Array = atlas_textures.filter(
						func(t: AtlasTexture) -> bool: return t.margin == margin and t.region == region)
					if not equivalent_atlas_textures.is_empty():
						return equivalent_atlas_textures.front()
					var atlas_texture: AtlasTexture = AtlasTexture.new()
					atlas_texture.atlas = atlas
					atlas_texture.filter_clip = filter_clip_enabled
					atlas_texture.region = region
					atlas_texture.margin = margin
					atlas_textures.append(atlas_texture)
					return atlas_texture})

	texture_rect.add_child(animation_player)
	animation_player.owner = texture_rect

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(texture_rect)
	result.success(packed_scene,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	return result
