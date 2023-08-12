@tool
extends "_.gd"

const _RectPacker = preload("../rect_packer.gd")

class SpriteProps:
	extends RefCounted
	var images_props: Array[ImageProps]
	var atlas_region_props: AtlasRegionProps

	var offset: Vector2i

	func create_sprite(atlas_region_position: Vector2i) -> _Common.SpriteInfo:
		var sprite = _Common.SpriteInfo.new()
		sprite.region = Rect2i(atlas_region_position, atlas_region_props.size)
		sprite.offset = offset
		return sprite

class AtlasRegionProps:
	extends RefCounted
	var sprites_props: Array[SpriteProps]
	var images_props: Array[ImageProps]

	var size: Vector2i

class ImageProps:
	extends RefCounted
	var sprite_props: SpriteProps
	var atlas_region_props: AtlasRegionProps

	var image: Image
	var used_rect: Rect2i
	var used_fragment: Image
	var used_fragment_data: PackedByteArray
	var used_fragment_data_hash: int

	func _init(image: Image) -> void:
		self.image = image
		used_rect = image.get_used_rect()
		if used_rect.has_area():
			used_fragment = image.get_region(used_rect)
			used_fragment_data = used_fragment.get_data()
			used_fragment_data_hash = hash(used_fragment_data)

class SpriteSheetBuildingContext:
	extends RefCounted
	var images_props: Array[ImageProps]
	var sprites_props: Array[SpriteProps]
	var atlas_regions_props: Array[AtlasRegionProps]
	var _similar_images_props_by_used_fragment_data_hash: Dictionary
	var _collapsed_image_props: ImageProps

	func _init(images: Array[Image]) -> void:
		var images_count: int = images.size()
		images_props.resize(images_count)
		for image_index in images_count:
			images_props[image_index] = _process_image_props(ImageProps.new(images[image_index]))

	func _process_image_props(image_props: ImageProps) -> ImageProps:
		if not image_props.used_rect.has_area():
			if _collapsed_image_props == null:
				_collapsed_image_props = image_props
			return _collapsed_image_props

		var similar_images_props: Array[ImageProps]
		if not _similar_images_props_by_used_fragment_data_hash.has(image_props.used_fragment_data_hash):
			_similar_images_props_by_used_fragment_data_hash[image_props.used_fragment_data_hash] = similar_images_props
		else:
			similar_images_props = _similar_images_props_by_used_fragment_data_hash[image_props.used_fragment_data_hash]
			for similar_image_props in similar_images_props:
				if image_props.image == similar_image_props.image:
					# The same image found.
					return similar_image_props
				elif image_props.used_rect.size == similar_image_props.used_rect.size:
					if image_props.used_fragment_data == similar_image_props.used_fragment_data:
						if image_props.used_rect.position == similar_image_props.used_rect.position:
							# An image with equal content found.
							return similar_image_props
						else:
							# An image with equal, but offsetted content found.
							# It will have the same region, but new sprite.
							image_props.atlas_region_props = similar_image_props.atlas_region_props
							image_props.sprite_props = SpriteProps.new()
							image_props.sprite_props.offset = image_props.used_rect.position
							image_props.sprite_props.images_props.push_back(image_props)
							image_props.sprite_props.atlas_region_props = similar_image_props.atlas_region_props
							sprites_props.push_back(image_props.sprite_props)
							return image_props
		# A new unique image found.
		# It will have new region and sprite.
		image_props.atlas_region_props = AtlasRegionProps.new()
		image_props.atlas_region_props.size = image_props.used_rect.size
		image_props.sprite_props = SpriteProps.new()
		image_props.sprite_props.offset = image_props.used_rect.position
		image_props.sprite_props.images_props.push_back(image_props)
		image_props.sprite_props.atlas_region_props = image_props.atlas_region_props
		image_props.atlas_region_props.sprites_props.push_back(image_props.sprite_props)
		image_props.atlas_region_props.images_props.push_back(image_props)
		sprites_props.push_back(image_props.sprite_props)
		atlas_regions_props.push_back(image_props.atlas_region_props)
		similar_images_props.push_back(image_props)
		return image_props

func build_sprite_sheet(images: Array[Image]) -> SpriteSheetBuildingResult:
	var result: SpriteSheetBuildingResult = SpriteSheetBuildingResult.new()
	var images_count: int = images.size()

	var sprite_sheet: _Common.SpriteSheetInfo = _Common.SpriteSheetInfo.new()

	if images_count == 0:
		var atlas_image = Image.new()
		atlas_image.set_data(1, 1, false, Image.FORMAT_RGBA8, PackedByteArray([0, 0, 0, 0]))
		result.success(sprite_sheet, atlas_image)
		return result

	sprite_sheet.source_image_size = images.front().get_size()
	if not images.all(func(i: Image) -> bool:
		return i.get_size() == sprite_sheet.source_image_size):
		result.fail(ERR_INVALID_DATA, "Input images have different sizes")
		return result

	sprite_sheet.sprites.resize(images_count)

	var context: SpriteSheetBuildingContext = SpriteSheetBuildingContext.new(images)
	var atlas_regions_count: int = context.atlas_regions_props.size()
	if atlas_regions_count == 0:
		# All sprites are collapsed
		var collapsed_sprite: _Common.SpriteInfo = _Common.SpriteInfo.new()
		for image_index in images_count:
			sprite_sheet.sprites[image_index] = collapsed_sprite
		var atlas_image = Image.new()
		atlas_image.set_data(1, 1, false, Image.FORMAT_RGBA8, PackedByteArray([0, 0, 0, 0]))
		result.success(sprite_sheet, atlas_image)
		return result

	var atlas_regions_sizes: Array[Vector2i]
	atlas_regions_sizes.resize(atlas_regions_count)
	for atlas_region_index in atlas_regions_count:
		atlas_regions_sizes[atlas_region_index] = \
			context.atlas_regions_props[atlas_region_index].size

	match _edges_artifacts_avoidance_method:
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_SPACING, \
		_Common.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
			for atlas_region_index in atlas_regions_count:
				atlas_regions_sizes[atlas_region_index] += Vector2i.ONE
		_Common.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION, \
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION:
			for atlas_region_index in atlas_regions_count:
				atlas_regions_sizes[atlas_region_index] += Vector2i.ONE * 2

	var packing_result: _RectPacker.RectPackingResult = _RectPacker.pack(atlas_regions_sizes)
	if packing_result.error:
		result.fail(ERR_BUG, "Rect packing failed", packing_result)
		return result

	match _edges_artifacts_avoidance_method:
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_SPACING:
			packing_result.bounds -= Vector2i.ONE
		_Common.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
			packing_result.bounds += Vector2i.ONE
			for atlas_region_index in atlas_regions_count:
				packing_result.rects_positions[atlas_region_index] += Vector2i.ONE
		_Common.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION:
			for atlas_region_index in atlas_regions_count:
				packing_result.rects_positions[atlas_region_index] += Vector2i.ONE

	var atlas_image: Image = Image.create(
		packing_result.bounds.x, packing_result.bounds.y, false, Image.FORMAT_RGBA8)

	if _edges_artifacts_avoidance_method == _Common.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
		atlas_image.fill(_sprites_surrounding_color)

	var extrude_sprites_borders: bool = _edges_artifacts_avoidance_method == \
		_Common.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION
	var expand_sprites: bool = _edges_artifacts_avoidance_method == \
		_Common.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION

	var atlas_regions_positions_by_atlas_regions_props: Dictionary
	for atlas_region_index in atlas_regions_count:
		var atlas_region_props: AtlasRegionProps = context.atlas_regions_props[atlas_region_index]
		packing_result.rects_positions[atlas_region_index] += \
			Vector2i.ONE if expand_sprites else Vector2i.ZERO
		var image_props: ImageProps = atlas_region_props.images_props.front()
		atlas_image.blit_rect(image_props.used_fragment,
			Rect2i(Vector2i.ZERO, atlas_region_props.size),
			packing_result.rects_positions[atlas_region_index])
		if extrude_sprites_borders:
			_extrude_borders(atlas_image, Rect2i(
				packing_result.rects_positions[atlas_region_index],
				atlas_region_props.size))
		atlas_regions_positions_by_atlas_regions_props[atlas_region_props] = \
			packing_result.rects_positions[atlas_region_index]

	var sprites_by_sprites_props: Dictionary
	for sprite_props in context.sprites_props:
		var sprite: _Common.SpriteInfo = sprite_props.create_sprite(
				atlas_regions_positions_by_atlas_regions_props[sprite_props.atlas_region_props])
		if expand_sprites:
			sprite.region = sprite.region.grow(1)
			sprite.offset -= Vector2i.ONE
		sprites_by_sprites_props[sprite_props] = sprite

	var collapsed_sprite: _Common.SpriteInfo
	for image_index in images_count:
		var image_props: ImageProps = context.images_props[image_index]
		var sprite: _Common.SpriteInfo = sprites_by_sprites_props.get(image_props.sprite_props, null)
		if sprite == null:
			if collapsed_sprite == null:
				collapsed_sprite = _Common.SpriteInfo.new()
			sprite = collapsed_sprite
		sprite_sheet.sprites[image_index] = sprite

	if expand_sprites:
		sprite_sheet.source_image_size += Vector2i.ONE * 2
	result.success(sprite_sheet, atlas_image)
	return result
