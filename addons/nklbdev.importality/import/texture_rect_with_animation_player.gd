extends "_node_with_animation_player.gd"

const ANIMATION_STRATEGIES_NAMES: PackedStringArray = [
	"Animate single atlas texture's region and optionally margin",
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
	export_result: _Models.ExportResultModel,
	options: Dictionary,
	save_path: String
	) -> _Models.ImportResultModel:

	var atlas_texture: AtlasTexture = AtlasTexture.new()
	atlas_texture.atlas = export_result.sprite_sheet.atlas
	atlas_texture.filter_clip = true
	atlas_texture.resource_local_to_scene = true
	# for TextureRect, AtlasTexture must have region with area
	# we gave it frame size and negative position to avoid to show any visible pixel of the texture
	var sprite_size: Vector2i = export_result.sprite_sheet.source_image_size
	atlas_texture.region = Rect2(-sprite_size - Vector2i.ONE, sprite_size)

	var texture_rect: TextureRect = TextureRect.new()
	var node_name: String = options[_Options.ROOT_NODE_NAME].strip_edges()
	texture_rect.name = res_source_file_path.get_file().get_basename() \
		if node_name.is_empty() else node_name
	texture_rect.texture = atlas_texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.size = sprite_size

	var animation_player: AnimationPlayer
	match options[_Options.SPRITE_SHEET_LAYOUT]:
		_Models.SpriteSheetModel.Layout.PACKED:
			match options[_Options.ANIMATION_STRATEGY]:

				AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture:margin": func(frame_model: _Models.FrameModel) -> Rect2:
							return Rect2(frame_model.sprite.offset, sprite_size - frame_model.sprite.region.size),
						".:texture:region" : func(frame_model: _Models.FrameModel) -> Rect2i:
							return  frame_model.sprite.region })

				AnimationStrategy.MULTIPLE_ATLAS_TEXTURES_INSTANCES:
					var texture_cache: Array[AtlasTexture]
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture": func(frame_model: _Models.FrameModel) -> Texture2D:
							var margin: Rect2 = Rect2(frame_model.sprite.offset, sprite_size - frame_model.sprite.region.size)
							var region: Rect2 = Rect2(frame_model.sprite.region)
							var cached_result = texture_cache.filter(func(t: AtlasTexture) -> bool: return t.margin == margin and t.region == region)
							var texture: AtlasTexture
							if not cached_result.is_empty():
								return cached_result.front()
							texture = AtlasTexture.new()
							texture.atlas = export_result.sprite_sheet.atlas
							texture.filter_clip = true
							texture.margin = margin
							texture.region = region
							texture_cache.append(texture)
							return texture})

		_Models.SpriteSheetModel.Layout.HORIZONTAL_STRIPS, \
		_Models.SpriteSheetModel.Layout.VERTICAL_STRIPS:

			var not_collapsed_sprites_models = export_result.sprite_sheet.sprites \
				.filter(func(sprite: _Models.SpriteModel): sprite.region.has_area())
			var typical_sprite_model: _Models.SpriteModel = \
				_Models.SpriteModel.new() \
				if not_collapsed_sprites_models.is_empty() else \
				not_collapsed_sprites_models.front()

			match options[_Options.ANIMATION_STRATEGY]:

				AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
					atlas_texture.margin = Rect2(typical_sprite_model.offset, typical_sprite_model.offset * 2)
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture:region" : func(frame_model: _Models.FrameModel) -> Rect2i:
							return frame_model.sprite.region })

				AnimationStrategy.MULTIPLE_ATLAS_TEXTURES_INSTANCES:
					var common_atlas_texture_margin: Rect2 = Rect2(
						typical_sprite_model.offset,
						sprite_size - typical_sprite_model.region.size)
					var texture_cache: Array[AtlasTexture]
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture": func(frame_model: _Models.FrameModel) -> Texture2D:
							var region = Rect2(frame_model.sprite.region)
							var cached_result = texture_cache.filter(func(t: AtlasTexture) -> bool: return t.region == region)
							var texture: AtlasTexture
							if not cached_result.is_empty():
								return cached_result.front()
							texture = AtlasTexture.new()
							texture.atlas = export_result.sprite_sheet.atlas
							texture.filter_clip = true
							texture.region = region
							texture.margin = common_atlas_texture_margin
							texture_cache.append(texture)
							return texture})

	texture_rect.add_child(animation_player)
	animation_player.owner = texture_rect

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(texture_rect)
	return _Models.ImportResultModel.success(packed_scene,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
