extends "_.gd"

const _RectPacker = preload("../rect_packer.gd")

func build_sprite_sheet(images: Array[Image]) -> Result:
	var result: Result = Result.new()
	var images_count: int = images.size()

	var sprite_sheet: _Common.SpriteSheetInfo = _Common.SpriteSheetInfo.new()

	if images_count == 0:
		result.success(sprite_sheet)
		return result

	sprite_sheet.source_image_size = images.front().get_size()
	if not images.all(func(i: Image) -> bool: return i.get_size() == sprite_sheet.source_image_size):
		result.fail(ERR_INVALID_DATA, "Input images have different sizes")
		return result

	sprite_sheet.sprites.resize(images_count)

	var sprites_offsets: Array[Vector2i]
	sprites_offsets.resize(images_count)

	var sprites_sizes: Array[Vector2i]
	sprites_sizes.resize(images_count)

	var max_image_used_rect: Rect2i
	var images_infos_cache: Dictionary # of arrays of images indices by image hashes

	var unique_sprites_indices: Array[int]
	var collapsed_sprite: _Common.SpriteInfo = _Common.SpriteInfo.new()
	var images_used_rects: Array[Rect2i]

	for image_index in images_count:
		var image = images[image_index]
		var image_used_rect: Rect2i = image.get_used_rect()
		sprites_offsets[image_index] = image_used_rect.position
		sprites_sizes[image_index] = image_used_rect.size

		var is_image_invisible: bool = not image_used_rect.has_area()

		if is_image_invisible:
			sprite_sheet.sprites[image_index] = collapsed_sprite
			continue
		var image_hash: int = _get_image_hash(image)
		var similar_images_indices: PackedInt32Array = \
			images_infos_cache.get(image_hash, PackedInt32Array())
		var is_duplicate_found: bool = false
		for similar_image_index in similar_images_indices:
			var similar_image: Image = images[similar_image_index]
			if image == similar_image or image.get_data() == similar_image.get_data():
				sprite_sheet.sprites[image_index] = \
					sprite_sheet.sprites[similar_image_index]
				is_duplicate_found = true
				break
		if similar_images_indices.is_empty():
			images_infos_cache[image_hash] = similar_images_indices
		similar_images_indices.push_back(image_index)
		if is_duplicate_found:
			continue

		var sprite: _Common.SpriteInfo = _Common.SpriteInfo.new()
		sprite.region = image_used_rect
		sprite_sheet.sprites[image_index] = sprite
		unique_sprites_indices.push_back(image_index)
		if not is_image_invisible:
			max_image_used_rect = \
				image_used_rect.merge(max_image_used_rect) \
				if max_image_used_rect.has_area() else \
				image_used_rect

	if not max_image_used_rect.has_area():
		pass

	var unique_sprites_count: int = unique_sprites_indices.size()
	var unique_sprites_sizes: Array[Vector2i]
	unique_sprites_sizes.resize(unique_sprites_count)
	for unique_sprite_index in unique_sprites_count:
		var sprite_index: int = unique_sprites_indices[unique_sprite_index]
		unique_sprites_sizes[unique_sprite_index] = sprites_sizes[sprite_index] if sprite_index >= 0 else Vector2i.ZERO

	match _edges_artifacts_avoidance_method:
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_SPACING, \
		_Common.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
			for unique_sprite_index in unique_sprites_count:
				unique_sprites_sizes[unique_sprite_index] += Vector2i.ONE
		_Common.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION, \
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION:
			for unique_sprite_index in unique_sprites_count:
				unique_sprites_sizes[unique_sprite_index] += Vector2i.ONE * 2

	var packing_result: _RectPacker.Result = _RectPacker.pack(unique_sprites_sizes)
	if packing_result.error:
		result.fail(ERR_BUG, "Rect packing failed", packing_result)
		return result

	match _edges_artifacts_avoidance_method:
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_SPACING:
			packing_result.bounds -= Vector2i.ONE
		_Common.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
			packing_result.bounds += Vector2i.ONE
			for rect_index in unique_sprites_count:
				packing_result.rects_positions[rect_index] += Vector2i.ONE
		_Common.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION:
			for rect_index in unique_sprites_count:
				packing_result.rects_positions[rect_index] += Vector2i.ONE

	sprite_sheet.atlas_image = Image.create(
		packing_result.bounds.x, packing_result.bounds.y, false, Image.FORMAT_RGBA8)

	if _edges_artifacts_avoidance_method == _Common.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
		sprite_sheet.atlas_image.fill(_sprites_surrounding_color)

	var extrude_sprites_borders: bool = _edges_artifacts_avoidance_method == \
		_Common.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION
	var expand_sprites: bool = _edges_artifacts_avoidance_method == \
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION
	for unique_sprite_index in unique_sprites_count:
		var sprite_index: int = unique_sprites_indices[unique_sprite_index]
		var image: Image = images[sprite_index]
		var sprite: _Common.SpriteInfo = sprite_sheet.sprites[sprite_index]
		sprite.region = Rect2i(
			packing_result.rects_positions[unique_sprite_index] +
			(Vector2i.ONE if expand_sprites else Vector2i.ZERO),
			sprites_sizes[sprite_index])
		sprite.offset = sprites_offsets[sprite_index]
		if sprite.region.has_area():
			sprite_sheet.atlas_image.blit_rect(image,
				Rect2i(sprite.offset, sprite.region.size),
				sprite.region.position)
			if extrude_sprites_borders:
				_extrude_borders(sprite_sheet.atlas_image, sprite.region)
			if expand_sprites:
				sprite.region = sprite.region.grow(1)
				sprite.offset -= Vector2i.ONE
	if expand_sprites:
		sprite_sheet.source_image_size += Vector2i.ONE * 2
	result.success(sprite_sheet)
	return result
