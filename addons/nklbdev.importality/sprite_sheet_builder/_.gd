extends Object

const _Models = preload("../models.gd")

var _edges_artifacts_avoidance_method: _Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod
var _sprites_surrounding_color: Color

func _init(
	edges_artifacts_avoidance_method: _Models.SpriteSheetModel.EdgesArtifactsAvoidanceMethod,
	sprites_surrounding_color: Color = Color.TRANSPARENT
	) -> void:
	_edges_artifacts_avoidance_method = edges_artifacts_avoidance_method
	_sprites_surrounding_color = sprites_surrounding_color

class Result:
	var error: Error
	var error_message: String
	var sprite_sheet: _Models.SpriteSheetModel
	static func success(sprite_sheet: _Models.SpriteSheetModel) -> Result:
		var result = Result.new()
		result.sprite_sheet = sprite_sheet
		return result

	static func fail(error: Error, error_message: String = "") -> Result:
		var result = Result.new()
		result.error = error
		result.error_message = error_message
		return result

func build_sprite_sheet(images: Array[Image]) -> Result:
	assert(false, "This method is abstract and must be overriden.")
	return null

static func __hash_combine(a: int, b: int) -> int:
	return a ^ (b + 0x9E3779B9 + (a<<6) + (a>>2))

const __hash_precision: int = 5
static func _get_image_hash(image: Image) -> int:
	var image_size: Vector2i = image.get_size()
	if image_size.x * image_size.y == 0:
		return 0
	var hash: int = 0
	hash = __hash_combine(hash, image_size.x)
	hash = __hash_combine(hash, image_size.y)
	var grid_cell_size: Vector2i = image_size / __hash_precision
	for y in range(0, image_size.y, grid_cell_size.y):
		for x in range(0, image_size.x, grid_cell_size.x):
			var pixel: Color = image.get_pixel(x, y)
			hash = __hash_combine(hash, pixel.r8)
			hash = __hash_combine(hash, pixel.g8)
			hash = __hash_combine(hash, pixel.b8)
			hash = __hash_combine(hash, pixel.a8)
	return hash

static func _extrude_borders(image: Image, rect: Rect2i) -> void:
	if not rect.has_area():
		return
	# extrude borders
	# left border
	image.blit_rect(image,
		rect.grow_side(SIDE_RIGHT, 1 - rect.size.x),
		rect.position + Vector2i.LEFT)
	# top border
	image.blit_rect(image,
		rect.grow_side(SIDE_BOTTOM, 1 - rect.size.y),
		rect.position + Vector2i.UP)
	# right border
	image.blit_rect(image,
		rect.grow_side(SIDE_LEFT, 1 - rect.size.x),
		rect.position + Vector2i(rect.size.x, 0))
	# bottom border
	image.blit_rect(image,
		rect.grow_side(SIDE_TOP, 1 - rect.size.y),
		rect.position + Vector2i(0, rect.size.y))

	# corner pixels
	# top left corner
	image.set_pixelv(rect.position - Vector2i.ONE,
		image.get_pixelv(rect.position))
	# top right corner
	image.set_pixelv(rect.position + Vector2i(rect.size.x, -1),
		image.get_pixelv(rect.position + Vector2i(rect.size.x - 1, 0)))
	# bottom right corner
	image.set_pixelv(rect.end,
		image.get_pixelv(rect.end - Vector2i.ONE))
	# bottom left corner
	image.set_pixelv(rect.position + Vector2i(-1, rect.size.y),
		image.get_pixelv(rect.position + Vector2i(0, rect.size.y -1)))
