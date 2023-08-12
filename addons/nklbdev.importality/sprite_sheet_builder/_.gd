@tool
extends RefCounted

const _Result = preload("../result.gd").Class
const _Common = preload("../common.gd")

var _edges_artifacts_avoidance_method: _Common.EdgesArtifactsAvoidanceMethod
var _sprites_surrounding_color: Color

func _init(
	edges_artifacts_avoidance_method: _Common.EdgesArtifactsAvoidanceMethod,
	sprites_surrounding_color: Color = Color.TRANSPARENT
	) -> void:
	_edges_artifacts_avoidance_method = edges_artifacts_avoidance_method
	_sprites_surrounding_color = sprites_surrounding_color

class SpriteSheetBuildingResult:
	extends _Result
	var sprite_sheet: _Common.SpriteSheetInfo
	var atlas_image: Image
	func _get_result_type_description() -> String:
		return "Sprite sheet building"
	func success(sprite_sheet: _Common.SpriteSheetInfo, atlas_image: Image) -> void:
		_success()
		self.sprite_sheet = sprite_sheet
		self.atlas_image = atlas_image

func build_sprite_sheet(images: Array[Image]) -> SpriteSheetBuildingResult:
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
