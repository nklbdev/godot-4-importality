extends "_.gd"

func _init() -> void: super("SpriteFrames", "SpriteFrames", "res")

func import(
	res_source_file_path: String,
	export_result: _Common.ExportResult,
	options: Dictionary,
	save_path: String
	) -> _Common.ImportResult:
	var result: _Common.ImportResult = _Common.ImportResult.new()

	var sprite_frames: SpriteFrames = SpriteFrames.new()
	for animation_name in sprite_frames.get_animation_names():
		sprite_frames.remove_animation(animation_name)

	var filter_clip_enabled: bool = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
	var atlas_textures: Dictionary = {}
	for animation in export_result.animation_library.animations:
		sprite_frames.add_animation(animation.name)
		sprite_frames.set_animation_loop(animation.name, animation.repeat_count == 0)
		sprite_frames.set_animation_speed(animation.name, 1)
		var previous_texture: Texture2D
		for frame in animation.get_output_frames():
			var atlas_texture = atlas_textures.get(frame.sprite.region)
			if atlas_texture == null:
				atlas_texture = AtlasTexture.new()
				atlas_texture.filter_clip = filter_clip_enabled
				atlas_texture.atlas = export_result.sprite_sheet.atlas
				if frame.sprite.region.has_area():
					atlas_texture.region = frame.sprite.region
					atlas_texture.margin = Rect2(
						frame.sprite.offset,
						export_result.sprite_sheet.source_image_size - frame.sprite.region.size)
				else:
					atlas_texture.region = Rect2i(0, 0, 1, 1)
					atlas_texture.margin = Rect2(2, 2, 0, 0)
				atlas_textures[frame.sprite.region] = atlas_texture
			elif atlas_texture == previous_texture:
				var last_frame_index: int = sprite_frames.get_frame_count(animation.name) - 1
				sprite_frames.set_frame(animation.name, last_frame_index, atlas_texture,
					sprite_frames.get_frame_duration(animation.name, last_frame_index) + frame.duration)
				continue
			sprite_frames.add_frame(animation.name, atlas_texture, frame.duration)
			previous_texture = atlas_texture

	result.success(sprite_frames,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
	return result
