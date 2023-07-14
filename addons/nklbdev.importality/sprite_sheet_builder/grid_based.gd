extends "_.gd"

const _RectPacker = preload("../rect_packer.gd")

enum StripDirection {
	HORIZONTAL = 0,
	VERTICAL = 1,
}

var _strips_direction: StripDirection
var _max_cells_in_strip: int
var _trim_sprites_to_overall_min_size: bool
var _collapse_transparent: bool
var _merge_duplicates: bool

func _init(
	edges_artifacts_avoidance_method: _Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod,
	strips_direction: StripDirection,
	max_cells_in_strip: int,
	trim_sprites_to_overall_min_size: bool,
	collapse_transparent: bool,
	merge_duplicates: bool,
	sprites_surrounding_color: Color = Color.TRANSPARENT
	) -> void:
	super(edges_artifacts_avoidance_method, sprites_surrounding_color)
	_strips_direction = strips_direction
	_max_cells_in_strip = max_cells_in_strip
	_trim_sprites_to_overall_min_size = trim_sprites_to_overall_min_size
	_collapse_transparent = collapse_transparent
	_merge_duplicates = merge_duplicates

func build_sprite_sheet(images: Array[Image]) -> Result:
	var images_count: int = images.size()

	var sprite_sheet_model: _Models.SpriteSheetModel = _Models.SpriteSheetModel.new()
	sprite_sheet_model.edges_artifacts_avoidance_method = _edges_artifacts_avoidance_method
	sprite_sheet_model.layout = \
		_Models.SpriteSheetModel.Layout.HORIZONTAL_STRIPS \
		if _strips_direction == StripDirection.HORIZONTAL else \
		_Models.SpriteSheetModel.Layout.VERTICAL_STRIPS

	if images_count == 0:
		return Result.success(sprite_sheet_model)

	sprite_sheet_model.source_image_size = images.front().get_size()
	if not images.all(func(i: Image) -> bool: return i.get_size() == sprite_sheet_model.source_image_size):
		return Result.fail(ERR_INVALID_DATA, "Input images have different sizes")

	sprite_sheet_model.sprites.resize(images_count)

	var first_axis: int = _strips_direction
	var second_axis: int = 1 - first_axis

	var max_image_used_rect: Rect2i
	var images_infos_cache: Dictionary # of arrays of images indices by image hashes

	var unique_sprites_indices: Array[int]
	var collapsed_sprite: _Models.SpriteModel = _Models.SpriteModel.new()
	var images_used_rects: Array[Rect2i]

	for image_index in images_count:
		var image: Image = images[image_index]
		var image_used_rect: Rect2i = image.get_used_rect()
		var is_image_invisible: bool = not image_used_rect.has_area()

		if _collapse_transparent and is_image_invisible:
			sprite_sheet_model.sprites[image_index] = collapsed_sprite
			continue
		elif _merge_duplicates:
			var image_hash: int = _get_image_hash(image)
			var similar_images_indices: PackedInt32Array = \
				images_infos_cache.get(image_hash, PackedInt32Array())
			var is_duplicate_found: bool = false
			for similar_image_index in similar_images_indices:
				var similar_image: Image = images[similar_image_index]
				if image == similar_image or image.get_data() == similar_image.get_data():
					sprite_sheet_model.sprites[image_index] = \
						sprite_sheet_model.sprites[similar_image_index]
					is_duplicate_found = true
					break
			if similar_images_indices.is_empty():
				images_infos_cache[image_hash] = similar_images_indices
			similar_images_indices.push_back(image_index)
			if is_duplicate_found:
				continue

		var sprite_model: _Models.SpriteModel = _Models.SpriteModel.new()
		sprite_model.region = image_used_rect
		sprite_sheet_model.sprites[image_index] = sprite_model
		unique_sprites_indices.push_back(image_index)
		if not is_image_invisible:
			max_image_used_rect = \
				image_used_rect.merge(max_image_used_rect) \
				if max_image_used_rect.has_area() else \
				image_used_rect

	var unique_sprites_count: int = unique_sprites_indices.size()

	if _edges_artifacts_avoidance_method == _Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION:
		sprite_sheet_model.source_image_size += Vector2i.ONE * 2

	var grid_size: Vector2i
	grid_size[second_axis] = \
		unique_sprites_count / _max_cells_in_strip + \
		sign(unique_sprites_count % _max_cells_in_strip) \
		if _max_cells_in_strip > 0 else sign(unique_sprites_count)
	grid_size[first_axis] = _max_cells_in_strip if grid_size[second_axis] > 1 else unique_sprites_count

	var atlas_size: Vector2i = grid_size * sprite_sheet_model.source_image_size
	match _edges_artifacts_avoidance_method:
		_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.NONE:
			pass
		_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.TRANSPARENT_SPACING:
			atlas_size += grid_size - Vector2i.ONE
		_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
			atlas_size += grid_size + Vector2i.ONE
		_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION:
			atlas_size += grid_size * 2
		_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION:
			pass

	var atlas = Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	sprite_sheet_model.atlas_image = atlas

	if _edges_artifacts_avoidance_method == _Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
		atlas.fill(_sprites_surrounding_color)

	var image_region: Rect2i = \
		max_image_used_rect \
		if _trim_sprites_to_overall_min_size else \
		Rect2i(Vector2i.ZERO, sprite_sheet_model.source_image_size)
	var extrude_sprites_borders: bool = _edges_artifacts_avoidance_method == \
		_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION
	var expand_sprites: bool = _edges_artifacts_avoidance_method == \
		_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION
	var cell: Vector2i
	var cell_index: int
	for sprite_index in unique_sprites_indices:
		# calculate cell
		var sprite_model: _Models.SpriteModel = sprite_sheet_model.sprites[sprite_index]
		if sprite_model == collapsed_sprite:
			continue
		sprite_model.region.size = sprite_sheet_model.source_image_size
		var image: Image = images[sprite_index]
		cell[first_axis] = cell_index % _max_cells_in_strip if _max_cells_in_strip > 0 else cell_index
		cell[second_axis] = cell_index / _max_cells_in_strip if _max_cells_in_strip > 0 else 0
		sprite_sheet_model.strips_count = max(sprite_sheet_model.strips_count, cell[first_axis])
		sprite_sheet_model.cells_in_strip_count = max(sprite_sheet_model.cells_in_strip_count, cell[second_axis])
		sprite_model.region.position = cell * sprite_sheet_model.source_image_size
		match _edges_artifacts_avoidance_method:
			_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.TRANSPARENT_SPACING:
				sprite_model.region.position += cell
			_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.SOLID_COLOR_SURROUNDING:
				sprite_model.region.position += cell + Vector2i.ONE
			_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.BORDERS_EXTRUSION:
				sprite_model.region.position += cell * 2 + Vector2i.ONE
			_Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod.TRANSPARENT_EXPANSION:
				sprite_model.region.position += cell * 2 + Vector2i.ONE
		atlas.blit_rect(image, image_region, sprite_model.region.position +
			(Vector2i.ONE if expand_sprites else Vector2i.ZERO))
		if extrude_sprites_borders:
			_extrude_borders(atlas, sprite_model.region)
		if expand_sprites:
			sprite_model.region = sprite_model.region.grow(1)
		cell_index += 1
	if expand_sprites:
		sprite_sheet_model.source_image_size += Vector2i.ONE * 2

	return Result.success(sprite_sheet_model)
