@tool
extends "_.gd"

const __ANIMATION_MERGE_EQUAL_CONSEQUENT_FRAMES_OPTION: StringName = "animation/merge_equal_sonsequent_frames"
const __ANIMATION_FLATTEN_REPETITION_OPTION: StringName = "animation/flatten_repetition"

func _init() -> void: super("Sprite sheet (JSON)", "JSON", "res", [
		_Options.create_option(__ANIMATION_MERGE_EQUAL_CONSEQUENT_FRAMES_OPTION, true,
			PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
		_Options.create_option(__ANIMATION_FLATTEN_REPETITION_OPTION, true,
			PROPERTY_HINT_NONE, "", PROPERTY_USAGE_DEFAULT),
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

	var unique_indixes_by_sprites: Dictionary
	var unique_sprite_index: int = 0
	var sprites: Array[Dictionary]
	for sprite in sprite_sheet.sprites:
		if not unique_indixes_by_sprites.has(sprite):
			unique_indixes_by_sprites[sprite] = unique_sprite_index
			sprites.push_back({
				region = sprite.region,
				offset = sprite.offset
			})
			unique_sprite_index += 1

	var flatten_animation_repetition: bool = options[__ANIMATION_FLATTEN_REPETITION_OPTION]
	var merge_equal_consequent_frames: bool = options[__ANIMATION_MERGE_EQUAL_CONSEQUENT_FRAMES_OPTION]
	var animations: Array[Dictionary]
	for animation in animation_library.animations:
		var frames_data: Array[Dictionary]
		var frames: Array[_Common.FrameInfo] = \
			animation.get_flatten_frames() \
			if flatten_animation_repetition else \
			animation.frames
		var previous_sprite_index: int = -1
		for frame in frames:
			var sprite_index: int = unique_indixes_by_sprites[frame.sprite]
			if merge_equal_consequent_frames and sprite_index == previous_sprite_index:
				frames_data.back().duration += frame.duration
			else:
				frames_data.push_back({
					sprite_index = sprite_index,
					duration = frame.duration,
				})
			previous_sprite_index = sprite_index
		animations.push_back({
			name = animation.name,
			direction =
				_Common.AnimationDirection.FORWARD
				if flatten_animation_repetition else
				animation.direction,
			repeat_count =
				mini(1, animation.repeat_count)
				if flatten_animation_repetition else
				animation.repeat_count,
			frames = frames_data,
		})

	var json: JSON = JSON.new()
	json.data = {
		sprite_sheet = {
			atlas = atlas,
			source_image_size = sprite_sheet.source_image_size,
			sprites = sprites,
		},
		animation_library = {
			animations = animations,
			autoplay_index = animation_library.autoplay_index,
		},
	}
	json.get_parsed_text()
	result.success(json, ResourceSaver.FLAG_COMPRESS)
	return result
