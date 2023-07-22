extends "_.gd"

func _init() -> void: super("SpriteFrames", "SpriteFrames", "res")

func import(
	res_source_file_path: String,
	export_result: _Models.ExportResultModel,
	options: Dictionary,
	save_path: String
	) -> _Models.ImportResultModel:

	var sprite_frames: SpriteFrames = SpriteFrames.new()
	for animation_name in sprite_frames.get_animation_names():
		sprite_frames.remove_animation(animation_name)

	var filter_clip_enabled: bool = options[_Options.ATLAS_TEXTURES_REGION_FILTER_CLIP_ENABLED]
	var atlas_textures: Dictionary = {}
	for animation_model in export_result.animation_library.animations:
		sprite_frames.add_animation(animation_model.name)
		sprite_frames.set_animation_loop(animation_model.name, animation_model.repeat_count == 0)
		sprite_frames.set_animation_speed(animation_model.name, 1)
		var previous_texture: Texture2D
		for frame_model in animation_model.get_output_frames():
			var atlas_texture = atlas_textures.get(frame_model.sprite.region)
			if atlas_texture == null:
				atlas_texture = AtlasTexture.new()
				atlas_texture.filter_clip = filter_clip_enabled
				atlas_texture.atlas = export_result.sprite_sheet.atlas
				if frame_model.sprite.region.has_area():
					atlas_texture.region = frame_model.sprite.region
					atlas_texture.margin = Rect2(
						frame_model.sprite.offset,
						export_result.sprite_sheet.source_image_size - frame_model.sprite.region.size)
				else:
					atlas_texture.region = Rect2i(0, 0, 1, 1)
					atlas_texture.margin = Rect2(2, 2, 0, 0)
				atlas_textures[frame_model.sprite.region] = atlas_texture
			elif atlas_texture == previous_texture:
				var last_frame_index: int = sprite_frames.get_frame_count(animation_model.name) - 1
				sprite_frames.set_frame(animation_model.name, last_frame_index, atlas_texture,
					sprite_frames.get_frame_duration(animation_model.name, last_frame_index) + frame_model.duration)
				continue
			sprite_frames.add_frame(animation_model.name, atlas_texture, frame_model.duration)
			previous_texture = atlas_texture

	return _Models.ImportResultModel.success(sprite_frames,
		ResourceSaver.FLAG_COMPRESS | ResourceSaver.FLAG_BUNDLE_RESOURCES)
