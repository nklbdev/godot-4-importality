@tool
extends "_.gd"

func _init() -> void: super("SpriteFrames", "SpriteFrames", "res")

func import(
	res_source_file_path: String,
	atlas: Texture2D,
	sprite_sheet: _Common.SpriteSheetInfo,
	animation_library: _Common.AnimationLibraryInfo,
	options: Dictionary,
	save_path: String
	) -> ImportResult:
	var result: ImportResult = ImportResult.new()

	var sprite_frames: SpriteFrames = SpriteFrames.new()
	for animation_name in sprite_frames.get_animation_names():
		sprite_frames.remove_animation(animation_name)

	var filter_clip_enabled: bool = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
	var atlas_textures: Array[AtlasTexture]
	var empty_atlas_texture: AtlasTexture
	for animation in animation_library.animations:
		sprite_frames.add_animation(animation.name)
		sprite_frames.set_animation_loop(animation.name, animation.repeat_count == 0)
		sprite_frames.set_animation_speed(animation.name, 1)
		var previous_texture: Texture2D
		for frame in animation.get_flatten_frames():
			var atlas_texture: AtlasTexture
			if frame.sprite.region.has_area():
				var region: Rect2 = frame.sprite.region
				var margin: Rect2 = Rect2(
					frame.sprite.offset,
					sprite_sheet.source_image_size - frame.sprite.region.size)
				var equivalent_atlas_textures: Array = atlas_textures.filter(
					func(t: AtlasTexture) -> bool: return t.margin == margin and t.region == region)
				if not equivalent_atlas_textures.is_empty():
					atlas_texture = equivalent_atlas_textures.front()
				if atlas_texture == null:
					atlas_texture = AtlasTexture.new()
					atlas_texture.filter_clip = filter_clip_enabled
					atlas_texture.atlas = atlas
					atlas_texture.region = region
					atlas_texture.margin = margin
					atlas_textures.push_back(atlas_texture)
			else:
				if empty_atlas_texture == null:
					empty_atlas_texture = AtlasTexture.new()
					empty_atlas_texture.filter_clip = filter_clip_enabled
					empty_atlas_texture.atlas = atlas
					empty_atlas_texture.region = Rect2(0, 0, 1, 1)
					empty_atlas_texture.margin = Rect2(2, 2, 0, 0)
				atlas_texture = empty_atlas_texture
			if atlas_texture == previous_texture:
				var last_frame_index: int = sprite_frames.get_frame_count(animation.name) - 1
				sprite_frames.set_frame(animation.name, last_frame_index, atlas_texture,
					sprite_frames.get_frame_duration(animation.name, last_frame_index) + frame.duration)
				continue
			sprite_frames.add_frame(animation.name, atlas_texture, frame.duration)
			previous_texture = atlas_texture

	result.success(sprite_frames,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	return result
