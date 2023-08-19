@tool
extends "_sprite_with_animation_player.gd"

func _init() -> void:
	super("Sprite3D with AnimationPlayer", "PackedScene", "scn")

func import(
	res_source_file_path: String,
	atlas: Texture2D,
	sprite_sheet: _Common.SpriteSheetInfo,
	animation_library: _Common.AnimationLibraryInfo,
	options: Dictionary,
	save_path: String
	) -> ImportResult:
	var result: ImportResult = ImportResult.new()

	var sprite_size: Vector2i = sprite_sheet.source_image_size

	var sprite: Sprite3D = Sprite3D.new()
	var node_name: String = options[_Options.ROOT_NODE_NAME].strip_edges()
	sprite.name = res_source_file_path.get_file().get_basename() \
		if node_name.is_empty() else node_name
	sprite.centered = options[_Options.SPRITE_CENTERED]

	var filter_clip_enabled: bool = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]

	var animation_player: AnimationPlayer
	match options[_Options.ANIMATION_STRATEGY]:

		AnimationStrategy.SPRITE_REGION_AND_OFFSET:
			sprite.texture = atlas
			sprite.region_enabled = true
			animation_player = _create_animation_player(animation_library, {
				".:offset": func(frame: _Common.FrameInfo) -> Vector2:
					return Vector2( # spatial sprite offset (the Y-axis is Up-directed)
						frame.sprite.offset.x,
						sprite_size.y - frame.sptite.offset.y -
						frame.sprite.region.size.y) + \
						# add center correction
						((Vector2(frame.sprite.region.size - sprite_size) * 0.5)
						if sprite.centered else Vector2.ZERO),
				".:region_rect": func(frame: _Common.FrameInfo) -> Rect2:
					return Rect2(frame.sprite.region) })

		AnimationStrategy.SINGLE_ATLAS_TEXTURE_REGION_AND_MARGIN:
			var atlas_texture: AtlasTexture = AtlasTexture.new()
			atlas_texture.filter_clip = filter_clip_enabled
			atlas_texture.resource_local_to_scene = true
			atlas_texture.atlas = atlas
			atlas_texture.region = Rect2(0, 0, 1, 1)
			atlas_texture.margin = Rect2(2, 2, 0, 0)
			sprite.texture = atlas_texture
			animation_player = _create_animation_player(animation_library, {
				".:texture:margin": func(frame: _Common.FrameInfo) -> Rect2:
					return \
						Rect2(frame.sprite.offset,
							sprite_size - frame.sprite.region.size) \
						if frame.sprite.region.has_area() else \
						Rect2(2, 2, 0, 0),
				".:texture:region": func(frame: _Common.FrameInfo) -> Rect2:
					return Rect2(frame.sprite.region) if frame.sprite.region.has_area() else Rect2(0, 0, 1, 1) })

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

	sprite.add_child(animation_player)
	animation_player.owner = sprite

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(sprite)
	result.success(packed_scene,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	return result
