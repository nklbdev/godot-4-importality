extends "_sprite_with_animation_player.gd"

func _init() -> void:
	super("Sprite2D with AnimationPlayer", "PackedScene", "scn")

func import(
	res_source_file_path: String,
	export_result: _Common.ExportResult,
	options: Dictionary,
	save_path: String
	) -> _Common.ImportResult:
	var result: _Common.ImportResult = _Common.ImportResult.new()

	var sprite_size: Vector2i = export_result.sprite_sheet.source_image_size

	var sprite: Sprite2D = Sprite2D.new()
	var node_name: String = options[_Options.ROOT_NODE_NAME].strip_edges()
	sprite.name = res_source_file_path.get_file().get_basename() \
		if node_name.is_empty() else node_name
	sprite.centered = options[_Options.SPRITE_CENTERED]

	var animation_player: AnimationPlayer
	match options[_Options.ANIMATION_STRATEGY]:

		AnimationStrategy.SPRITE_REGION_AND_OFFSET:
			sprite.texture = export_result.sprite_sheet.atlas
			sprite.region_enabled = true
			animation_player = _create_animation_player(export_result.animation_library, {
				".:offset": func(frame: _Common.FrameInfo) -> Vector2:
					return \
						Vector2(frame.sprite.offset) - 0.5 * (frame.sprite.region.size - sprite_size) \
						if sprite.centered else \
						frame.sprite.offset,
				".:region_rect": func(frame: _Common.FrameInfo) -> Rect2:
					return Rect2(frame.sprite.region) })

		AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
			var atlas_texture: AtlasTexture = AtlasTexture.new()
			atlas_texture.filter_clip = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
			atlas_texture.resource_local_to_scene = true
			atlas_texture.atlas = export_result.sprite_sheet.atlas
			atlas_texture.region = Rect2(0, 0, 1, 1)
			atlas_texture.margin = Rect2(2, 2, 0, 0)
			sprite.texture = atlas_texture
			animation_player = _create_animation_player(export_result.animation_library, {
				".:texture:margin": func(frame: _Common.FrameInfo) -> Rect2:
					return \
						Rect2(frame.sprite.offset,
							sprite_size - frame.sprite.region.size) \
						if frame.sprite.region.has_area() else \
						Rect2(2, 2, 0, 0),
				".:texture:region": func(frame: _Common.FrameInfo) -> Rect2:
					return Rect2(frame.sprite.region) if frame.sprite.region.has_area() else Rect2(0, 0, 1, 1) })

		AnimationStrategy.MULTIPLE_ATLAS_TEXTURES_INSTANCES:
			var atlas_texture_cache: Array[AtlasTexture]
			animation_player = _create_animation_player(export_result.animation_library, {
				".:texture": func(frame: _Common.FrameInfo) -> Texture2D:
					var region: Rect2 = \
						Rect2(frame.sprite.region) \
						if frame.sprite.region.has_area() else \
						Rect2(0, 0, 1, 1)
					var margin: Rect2 = \
						Rect2(frame.sprite.offset,
							sprite_size - frame.sprite.region.size) \
						if frame.sprite.region.has_area() else \
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

	sprite.add_child(animation_player)
	animation_player.owner = sprite

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(sprite)
	result.success(packed_scene,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	return result
