extends Object

class SpriteModel:
	var region: Rect2i
	var offset: Vector2i
	func _to_string() -> String:
		return "SpriteModel(region: %s, offset: %s)" % [region, offset]

class SpriteSheetModel:
	const LAYOUTS_NAMES: PackedStringArray = [
		"Packed",
		"Horizontal strips",
		"Vertical strips",
	]
	enum Layout {
		PACKED = 0,
		HORIZONTAL_STRIPS = 1,
		VERTICAL_STRIPS = 2,
	}

	const EDGES_ARTIFACTS_AVOIDANCE_METHODS_NAMES: PackedStringArray = [
		"None",
		"Transparent spacing",
		"Solid color surrounding",
		"Borders extrusion",
		"Transparent expansion",
	]
	enum EdgesArtifactsAvoidanceMethod {
		NONE = 0,
		TRANSPARENT_SPACING = 1,
		SOLID_COLOR_SURROUNDING = 2,
		BORDERS_EXTRUSION = 3,
		TRANSPARENT_EXPANSION = 4,
	}

	var edges_artifacts_avoidance_method: EdgesArtifactsAvoidanceMethod
	var atlas_image: Image
	var atlas: Texture2D
	var layout: Layout
	var source_image_size: Vector2i
	var strips_count: int
	var cells_in_strip_count: int
	var sprites: Array[SpriteModel]
	func _to_string() -> String:
		return "SpriteSheeetModel(edges_artifacts_avoidance_method: %s, layout: %s, image_size: %s, strips_count: %s, cells_in_strip_count: %s, sprites: %s)" % \
			[EDGES_ARTIFACTS_AVOIDANCE_METHODS_NAMES[edges_artifacts_avoidance_method],
			LAYOUTS_NAMES[layout], source_image_size, strips_count, cells_in_strip_count, "\n".join(sprites)]

class FrameModel:
	var sprite: SpriteModel
	var duration: float # or maybe int milliseconds?

class AnimationModel:
	const DIRECTIONS_NAMES: PackedStringArray = [
		"Forward",
		"Reverse",
		"Ping-pong",
		"Ping-pong reverse",
	]
	enum Direction {
		FORWARD = 0,
		REVERSE = 1,
		PING_PONG = 2,
		PING_PONG_REVERSE = 3,
	}

	var name: String
	var direction: Direction
	var repeat_count: int
	var frames: Array[FrameModel]
	func get_output_frames() -> Array[FrameModel]:
		var iteration_frames: Array[FrameModel] = frames.duplicate()
		if direction == Direction.REVERSE or direction == Direction.PING_PONG_REVERSE:
			iteration_frames.reverse()
		if direction == Direction.PING_PONG or direction == Direction.PING_PONG_REVERSE:
			var returning_frames: Array[FrameModel] = iteration_frames.duplicate()
			returning_frames.pop_front()
			returning_frames.reverse()
			iteration_frames.append_array(returning_frames)
		if repeat_count <= 1:
			return iteration_frames
		var output_frames: Array[FrameModel]
		var iteration_frames_count: int = iteration_frames.size()
		output_frames.resize(iteration_frames_count * repeat_count)
		for iteration_number in repeat_count:
			for frame_index in iteration_frames_count:
				output_frames[iteration_number * iteration_frames_count + frame_index] = \
					iteration_frames[frame_index]
		return output_frames
	func _to_string() -> String:
		return "AnimationModel(name: %s, frames_count: %s direction: %s, repeat_count: %s)" % [name, frames.size(), direction, repeat_count]

class AnimationLibraryModel:
	var animations: Array[AnimationModel]
	var autoplay_animation_index: int = -1

class ExportResultModel:
	var status: Error
	var error_description: String
	var sprite_sheet: SpriteSheetModel
	var animation_library: AnimationLibraryModel

	static func success(
		sprite_sheet: SpriteSheetModel,
		animation_library: AnimationLibraryModel
		) -> ExportResultModel:
		var result: ExportResultModel = ExportResultModel.new()
		result.status = OK
		result.error_description = ""
		result.sprite_sheet = sprite_sheet
		result.animation_library = animation_library
		return result

	static func fail(
		status: Error,
		error_description: String = ""
		) -> ExportResultModel:
		assert(status != OK)
		var result: ExportResultModel = ExportResultModel.new()
		result.status = status
		result.error_description = error_description
		return result

class ImportResultModel:
	var status: Error
	var error_description: String
	var resource: Resource
	var resource_saver_flags: ResourceSaver.SaverFlags

	static func success(
		resource: Resource,
		resource_saver_flags: ResourceSaver.SaverFlags = ResourceSaver.FLAG_NONE
		) -> ImportResultModel:
		var result: ImportResultModel = ImportResultModel.new()
		result.status = OK
		result.error_description = ""
		result.resource = resource
		result.resource_saver_flags = resource_saver_flags
		return result

	static func fail(
		status: Error,
		error_description: String = ""
		) -> ImportResultModel:
		assert(status != OK)
		var result: ImportResultModel = ImportResultModel.new()
		result.status = status
		result.error_description = error_description
		return result

	func _to_string() -> String:
		return "%s(status: %s, error_description: %s, resource: %s, resource_saver_flags: %s)" % \
			[get_class(), error_description, resource, resource_saver_flags]
