extends "_sprite_with_animation_player.gd"

func _init() -> void:
	super("Sprite2D with AnimationPlayer", "PackedScene", "scn")

func import(
	res_source_file_path: String,
	export_result: _Models.ExportResultModel,
	options: Dictionary,
	save_path: String
	) -> _Models.ImportResultModel:

	var sprite_size: Vector2i = export_result.sprite_sheet.source_image_size

	var sprite: Sprite2D = Sprite2D.new()
	var node_name: String = options[_Options.ROOT_NODE_NAME].strip_edges()
	sprite.name = res_source_file_path.get_file().get_basename() \
		if node_name.is_empty() else node_name
	sprite.texture = export_result.sprite_sheet.atlas
	sprite.centered = options[_Options.SPRITE_CENTERED]

	var animation_player: AnimationPlayer
	match options[_Options.SPRITE_SHEET_LAYOUT]:
		_Models.SpriteSheetModel.Layout.PACKED:
			match options[_Options.ANIMATION_STRATEGY]:

				AnimationStrategy.SPRITE_REGION_AND_OFFSET:
					sprite.region_enabled = true
					sprite.region_filter_clip_enabled = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
					animation_player = _create_animation_player(export_result.animation_library, {
						".:offset": func(frame_model: _Models.FrameModel) -> Vector2:
							return frame_model.sprite.offset + \
								((frame_model.sprite.region.size - sprite_size) if sprite.centered else Vector2i.ZERO) / 2,
						".:region_rect": func(frame_model: _Models.FrameModel) -> Rect2i:
							return frame_model.sprite.region })

				AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
					var atlas_texture: AtlasTexture = AtlasTexture.new()
					atlas_texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
					atlas_texture.resource_local_to_scene = true
					atlas_texture.atlas = export_result.sprite_sheet.atlas
					sprite.texture = atlas_texture
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture:margin": func(frame_model: _Models.FrameModel) -> Rect2:
							return Rect2(frame_model.sprite.offset, sprite_size - frame_model.sprite.region.size),
						".:texture:region": func(frame_model: _Models.FrameModel) -> Rect2i:
							return frame_model.sprite.region })

				AnimationStrategy.MULTIPLE_ATLAS_TEXTURES_INSTANCES:
					var texture_cache: Array[AtlasTexture]
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture": func(frame_model: _Models.FrameModel) -> Texture2D:
							var margin = Rect2(frame_model.sprite.offset, sprite_size - frame_model.sprite.region.size)
							var region = Rect2(frame_model.sprite.region)
							var cached_result = texture_cache.filter(func(t: AtlasTexture) -> bool: return t.margin == margin and t.region == region)
							var texture: AtlasTexture
							if not cached_result.is_empty():
								return cached_result.front()
							texture = AtlasTexture.new()
							texture.atlas = export_result.sprite_sheet.atlas
							texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
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

				AnimationStrategy.SPRITE_REGION_AND_OFFSET:
					sprite.region_enabled = true
					sprite.region_filter_clip_enabled = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
					sprite.offset = typical_sprite_model.offset + \
						((typical_sprite_model.region.size - sprite_size) if sprite.centered else Vector2i.ZERO) / 2
					animation_player = _create_animation_player(export_result.animation_library, {
						".:region_rect": func(frame_model: _Models.FrameModel) -> Rect2i:
							return frame_model.sprite.region })

				AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
					var atlas_texture = AtlasTexture.new()
					atlas_texture.atlas = export_result.sprite_sheet.atlas
					atlas_texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
					atlas_texture.resource_local_to_scene = true
					atlas_texture.margin = Rect2(typical_sprite_model.offset, sprite_size - typical_sprite_model.region.size)
					sprite.texture = atlas_texture
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture:region": func(frame_model: _Models.FrameModel) -> Rect2i:
							return  frame_model.region })

				AnimationStrategy.MULTIPLE_ATLAS_TEXTURES_INSTANCES:
					var texture_cache: Array[AtlasTexture]
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture": func(frame_model: _Models.FrameModel) -> Texture2D:
							var region: Rect2 = Rect2(frame_model.sprite.region)
							var cached_result = texture_cache.filter(func (t: AtlasTexture) -> bool: return t.region == region)
							var texture: AtlasTexture
							if not cached_result.is_empty():
								return cached_result.front()
							texture = AtlasTexture.new()
							texture.atlas = export_result.sprite_sheet.atlas
							texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
							texture.region = region
							texture_cache.append(texture)
							return texture})


	sprite.add_child(animation_player)
	animation_player.owner = sprite

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(sprite)
	return _Models.ImportResultModel.success(packed_scene,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
