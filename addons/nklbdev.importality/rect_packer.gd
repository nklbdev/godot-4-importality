@tool
# This code is taken from: https://github.com/semibran/pack/blob/master/lib/pack.js
# Copyright (c) 2018 Brandon Semilla (MIT License) - original author
# Copyright (c) 2023 Nikolay Lebedev (MIT License) - porting to gdscript, refactoring and optimization

const _Result = preload("result.gd").Class
const _Common = preload("common.gd")

const __WHITESPACE_WEIGHT: float = 1
const __SIDE_LENGTH_WEIGHT: float = 10

class RectPackingResult:
	extends _Result
	# Total size of the entire layout of rectangles.
	var bounds: Vector2i
	# Computed positions of the input rectangles
	# in the same order as their sizes were passed in.
	var rects_positions: Array[Vector2i]
	func _get_result_type_description() -> String:
		return "Rect packing"
	func success(bounds: Vector2i, rects_positions: Array[Vector2i]) -> void:
		_success()
		self.bounds = bounds
		self.rects_positions = rects_positions

static func __add_rect_to_cache(rect: Rect2i, cache: Dictionary, cache_grid_size: Vector2i) -> void:
	var left_top_cell: Vector2i = rect.position / cache_grid_size
	var right_bottom_cell: Vector2i = rect.end / cache_grid_size + (rect.end % cache_grid_size).sign()
	for y in range(left_top_cell.y, right_bottom_cell.y):
		for x in range(left_top_cell.x, right_bottom_cell.x):
			var cell: Vector2i = Vector2i(x, y)
			if cache.has(cell):
				cache[cell].push_back(rect)
			else:
				cache[cell] = [rect] as Array[Rect2i]

const __empty_rect_array: Array[Rect2i] = []
static func __has_intersection(rect: Rect2i, cache: Dictionary, cache_grid_size: Vector2i) -> bool:
	var left_top_cell: Vector2i = rect.position / cache_grid_size
	var right_bottom_cell: Vector2i = rect.end / cache_grid_size + (rect.end % cache_grid_size).sign()
	for y in range(left_top_cell.y, right_bottom_cell.y):
		for x in range(left_top_cell.x, right_bottom_cell.x):
			for cached_rect in cache.get(Vector2i(x, y), __empty_rect_array):
				if cached_rect.intersects(rect):
					return true
	return false

# The function takes an array of rectangle sizes as input and compactly packs them.
static func pack(rects_sizes: Array[Vector2i]) -> RectPackingResult:
	var result: RectPackingResult = RectPackingResult.new()
	var rects_count: int = rects_sizes.size()
	if rects_count == 0:
		result.success(Vector2i.ZERO, [])
		return result
	var rects_positions: Array[Vector2i]
	rects_positions.resize(rects_count)
	var min_area: int
	var rect_sizes_sum: Vector2i
	for size in rects_sizes:
		if size.x < 0 or size.y < 0:
			result.fail(ERR_INVALID_DATA, "Negative rect size found")
			return result
		min_area += size.x * size.y
		rect_sizes_sum += size
	if min_area == 0:
		result.success(Vector2i.ZERO, rects_positions)
		return result
	var average_rect_size: Vector2 = Vector2(rect_sizes_sum) / rects_count
	var rect_cache_grid_size: Vector2i = average_rect_size.ceil() * 2
	var average_squared_rect_side_length: float = sqrt(min_area / float(rects_count))

	var rect_cache: Dictionary

	var possible_bounds_side_length: int = ceili(sqrt(rects_count))
	nearest_po2(possible_bounds_side_length)

	var rects_order_arr: Array = PackedInt32Array(range(0, rects_count))
	rects_order_arr.sort_custom(func(a: int, b: int) -> bool:
		return rects_sizes[a].x * rects_sizes[a].y > rects_sizes[b].x * rects_sizes[b].y)
	var rects_order: PackedInt32Array = PackedInt32Array(rects_order_arr)

	var bounds: Vector2i = rects_sizes[rects_order[0]]
	var utilized_area: int = bounds.x * bounds.y

	var splits_by_axis: Array[PackedInt32Array] = [[0, bounds.x], [0, bounds.y]]
	__add_rect_to_cache(Rect2i(Vector2i.ZERO, rects_sizes[rects_order[0]]), rect_cache, rect_cache_grid_size)

	for rect_index in range(1, rects_count): # skip first rect at (0, 0)
		var ordered_rect_index: int = rects_order[rect_index]
		var rect: Rect2i = Rect2i(Vector2i.ZERO, rects_sizes[ordered_rect_index])
		var rect_area: int = rect.get_area()
		if rect_area == 0:
			continue
		utilized_area += rect_area

		var best_score: float = INF
		var best_new_bounds: Vector2i = bounds
		for landing_rect_index in rect_index:
			var ordered_landing_rect_index: int = rects_order[landing_rect_index]
			var landing_rect: Rect2i = Rect2i(
				rects_positions[ordered_landing_rect_index],
				rects_sizes[ordered_landing_rect_index])
			for split_axis_index in 2:
				var orthogonal_asis_index: int = (split_axis_index + 1) % 2
				var splits: PackedInt32Array = splits_by_axis[split_axis_index]
				rect.position[orthogonal_asis_index] = landing_rect.end[orthogonal_asis_index]
				for split_index in range(
					splits.bsearch(landing_rect.position[split_axis_index]),
					splits.bsearch(landing_rect.end[split_axis_index])):
					rect.position[split_axis_index] = splits[split_index]
					if __has_intersection(rect, rect_cache, rect_cache_grid_size):
						continue
					var new_bounds: Vector2i = Vector2i(
						maxi(bounds.x, rect.end.x),
						maxi(bounds.y, rect.end.y))
					var score: float = \
						__WHITESPACE_WEIGHT * (new_bounds.x * new_bounds.y - utilized_area) + \
						__SIDE_LENGTH_WEIGHT * average_squared_rect_side_length * maxf(new_bounds.x, new_bounds.y)
					if score < best_score:
						best_score = score
						rects_positions[ordered_rect_index] = rect.position
						best_new_bounds = new_bounds
		bounds = best_new_bounds
		rect.position = rects_positions[ordered_rect_index]

		__add_rect_to_cache(rect, rect_cache, rect_cache_grid_size)
		# Add new splits at rect.end if they dot't already exist
		for split_axis_index in 2:
			var splits: PackedInt32Array = splits_by_axis[split_axis_index]
			var position: int = rect.end[split_axis_index]
			var split_index: int = splits.bsearch(position)
			if split_index == splits.size():
				splits.append(position)
			elif splits[split_index] != position:
				splits.insert(split_index, position)

	result.success(bounds, rects_positions)
	return result
