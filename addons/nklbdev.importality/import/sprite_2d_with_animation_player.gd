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
	sprite.centered = options[_Options.SPRITE_CENTERED]

	var animation_player: AnimationPlayer
	match options[_Options.SPRITE_SHEET_LAYOUT]:
		_Models.SpriteSheetModel.Layout.PACKED:
			match options[_Options.ANIMATION_STRATEGY]:

				AnimationStrategy.SPRITE_REGION_AND_OFFSET:
					sprite.texture = export_result.sprite_sheet.atlas
					sprite.region_enabled = true
					animation_player = _create_animation_player(export_result.animation_library, {
						".:offset": func(frame_model: _Models.FrameModel) -> Vector2:
							return Vector2(frame_model.sprite.offset) + 0.5 * \
								(Vector2(frame_model.sprite.region.size - sprite_size)
								if sprite.centered else \
								Vector2.ZERO),
						".:region_rect": func(frame_model: _Models.FrameModel) -> Rect2:
							return Rect2(frame_model.sprite.region) })

				AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
					var atlas_texture: AtlasTexture = AtlasTexture.new()
					atlas_texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
					atlas_texture.resource_local_to_scene = true
					atlas_texture.atlas = export_result.sprite_sheet.atlas
					atlas_texture.region = Rect2(0, 0, 1, 1)
					atlas_texture.margin = Rect2(2, 2, 0, 0)
					sprite.texture = atlas_texture
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture:margin": func(frame_model: _Models.FrameModel) -> Rect2:
							return \
								Rect2(frame_model.sprite.offset,
									sprite_size - frame_model.sprite.region.size) \
								if frame_model.sprite.region.has_area() else \
								Rect2(2, 2, 0, 0),
						".:texture:region": func(frame_model: _Models.FrameModel) -> Rect2:
							return Rect2(frame_model.sprite.region) if frame_model.sprite.region.has_area() else Rect2(0, 0, 1, 1) })

				AnimationStrategy.MULTIPLE_ATLAS_TEXTURES_INSTANCES:
					var atlas_texture_cache: Array[AtlasTexture]
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture": func(frame_model: _Models.FrameModel) -> Texture2D:
							var region: Rect2 = \
								Rect2(frame_model.sprite.region) \
								if frame_model.sprite.region.has_area() else \
								Rect2(0, 0, 1, 1)
							var margin: Rect2 = \
								Rect2(frame_model.sprite.offset,
									sprite_size - frame_model.sprite.region.size) \
								if frame_model.sprite.region.has_area() else \
								Rect2(2, 2, 0, 0)
							var cached_result = atlas_texture_cache.filter(func(t: AtlasTexture) -> bool: return t.margin == margin and t.region == region)
							var atlas_texture: AtlasTexture
							if not cached_result.is_empty():
								return cached_result.front()
							atlas_texture = AtlasTexture.new()
							atlas_texture.atlas = export_result.sprite_sheet.atlas
							atlas_texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
							atlas_texture.region = region
							atlas_texture.margin = margin
							atlas_texture_cache.append(atlas_texture)
							return atlas_texture})

		_Models.SpriteSheetModel.Layout.HORIZONTAL_STRIPS, \
		_Models.SpriteSheetModel.Layout.VERTICAL_STRIPS:

			var not_collapsed_sprites_models: Array[_Models.SpriteModel]
			for sprite_model in export_result.sprite_sheet.sprites:
				if sprite_model.region.has_area():
					not_collapsed_sprites_models.push_back(sprite_model)
			var typical_sprite_model: _Models.SpriteModel = \
				_Models.SpriteModel.new() \
				if not_collapsed_sprites_models.is_empty() else \
				not_collapsed_sprites_models.front()
			print(export_result.sprite_sheet.sprites)
			print(not_collapsed_sprites_models)
			print(typical_sprite_model)

			match options[_Options.ANIMATION_STRATEGY]:

				AnimationStrategy.SPRITE_REGION_AND_OFFSET:
					sprite.texture = export_result.sprite_sheet.atlas
					sprite.region_enabled = true
					sprite.offset = Vector2(typical_sprite_model.offset) + \
						(Vector2(typical_sprite_model.region.size - sprite_size) if sprite.centered else Vector2.ZERO) / 2
					animation_player = _create_animation_player(export_result.animation_library, {
						".:region_rect": func(frame_model: _Models.FrameModel) -> Rect2:
							return Rect2(frame_model.sprite.region) })

				AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
					var atlas_texture = AtlasTexture.new()
					atlas_texture.atlas = export_result.sprite_sheet.atlas
					atlas_texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
					atlas_texture.resource_local_to_scene = true
					atlas_texture.region = Rect2(0, 0, 1, 1)
					atlas_texture.margin = \
						Rect2(typical_sprite_model.offset,
							sprite_size - typical_sprite_model.region.size) \
						if typical_sprite_model.region.has_area() else \
						Rect2(2, 2, 0, 0)
					sprite.texture = atlas_texture
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture:region": func(frame_model: _Models.FrameModel) -> Rect2:
							return \
								Rect2(frame_model.sprite.region) \
								if frame_model.sprite.region.has_area() else \
								Rect2(0, 0, 1, 1) })

				AnimationStrategy.MULTIPLE_ATLAS_TEXTURES_INSTANCES:
					var atlas_texture_cache: Array[AtlasTexture]
					animation_player = _create_animation_player(export_result.animation_library, {
						".:texture": func(frame_model: _Models.FrameModel) -> Texture2D:
							var region: Rect2 = \
								Rect2(frame_model.sprite.region) \
								if frame_model.sprite.region.has_area() else \
								Rect2(0, 0, 1, 1)
							var margin: Rect2 = \
								Rect2() \
								if frame_model.sprite.region.has_area() else \
								Rect2(2, 2, 0, 0)
							var cached_result = atlas_texture_cache.filter(func (t: AtlasTexture) -> bool: return t.region == region)
							var atlas_texture: AtlasTexture
							if not cached_result.is_empty():
								return cached_result.front()
							atlas_texture = AtlasTexture.new()
							atlas_texture.atlas = export_result.sprite_sheet.atlas
							atlas_texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
							atlas_texture.region = region
							atlas_texture.margin = margin
							atlas_texture_cache.append(atlas_texture)
							return atlas_texture})


	sprite.add_child(animation_player)
	animation_player.owner = sprite

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(sprite)
	return _Models.ImportResultModel.success(packed_scene,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
