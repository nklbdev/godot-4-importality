const SPRITE_SHEET_LAYOUTS_NAMES: PackedStringArray = [
	"Packed",
	"Horizontal strips",
	"Vertical strips",
]
enum SpriteSheetLayout {
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

const ANIMATION_DIRECTIONS_NAMES: PackedStringArray = [
	"Forward",
	"Reverse",
	"Ping-pong",
	"Ping-pong reverse",
]
enum AnimationDirection {
	FORWARD = 0,
	REVERSE = 1,
	PING_PONG = 2,
	PING_PONG_REVERSE = 3,
}

class SpriteInfo:
	extends RefCounted
	var region: Rect2i
	var offset: Vector2i

class SpriteSheetInfo:
	extends RefCounted
	var atlas_image: Image
	var atlas: Texture2D
	var source_image_size: Vector2i
	var strips_count: int
	var cells_in_strip_count: int
	var sprites: Array[SpriteInfo]

class FrameInfo:
	extends RefCounted
	var sprite: SpriteInfo
	var duration: float

class AnimationInfo:
	extends RefCounted
	var name: String
	var direction: AnimationDirection
	var repeat_count: int
	var frames: Array[FrameInfo]
	func get_output_frames() -> Array[FrameInfo]:
		var iteration_frames: Array[FrameInfo] = frames.duplicate()
		if direction == AnimationDirection.REVERSE or direction == AnimationDirection.PING_PONG_REVERSE:
			iteration_frames.reverse()
		if direction == AnimationDirection.PING_PONG or direction == AnimationDirection.PING_PONG_REVERSE:
			var returning_frames: Array[FrameInfo] = iteration_frames.duplicate()
			returning_frames.pop_front()
			returning_frames.reverse()
			iteration_frames.append_array(returning_frames)
		if repeat_count <= 1:
			return iteration_frames
		var output_frames: Array[FrameInfo]
		var iteration_frames_count: int = iteration_frames.size()
		output_frames.resize(iteration_frames_count * repeat_count)
		for iteration_number in repeat_count:
			for frame_index in iteration_frames_count:
				output_frames[iteration_number * iteration_frames_count + frame_index] = \
					iteration_frames[frame_index]
		return output_frames

class AnimationLibraryInfo:
	extends RefCounted
	var animations: Array[AnimationInfo]
	var autoplay_animation_index: int = -1

class Result:
	extends RefCounted
	var error: Error
	var error_description: String
	var inner_result: Result
	func _get_result_type_description() -> String:
		return "Abstract operation"
	func fail(error: Error, error_description: String = "", inner_result: Result = null) -> void:
		assert(error != OK)
		self.error = error
		self.error_description = error_description
		self.inner_result = inner_result
	func _success():
		error = OK
		error_description = ""
		inner_result = null
	func _to_string() -> String:
		return "%s error: %s (%s)%s%s" % [
			_get_result_type_description(),
			error,
			error_string(error),
			(", description: \"%s\"" % [error_description]) if error_description else "",
			(", inner error:\n%s" % [inner_result]) if inner_result else "",
		] if error else "%s(success)"

class ExportResult:
	extends Result
	var sprite_sheet: SpriteSheetInfo
	var animation_library: AnimationLibraryInfo
	func _get_result_type_description() -> String:
		return "Export"
	func success(
		sprite_sheet: SpriteSheetInfo,
		animation_library: AnimationLibraryInfo
		) -> void:
		_success()
		self.sprite_sheet = sprite_sheet
		self.animation_library = animation_library

class ImportResult:
	extends Result
	var resource: Resource
	var resource_saver_flags: ResourceSaver.SaverFlags
	func _get_result_type_description() -> String:
		return "Import"
	func success(
		resource: Resource,
		resource_saver_flags: ResourceSaver.SaverFlags = ResourceSaver.FLAG_NONE
		) -> void:
		_success()
		self.resource = resource
		self.resource_saver_flags = resource_saver_flags

static func simplify(value: Variant, deep: bool = false, with_privates: bool = false) -> Variant:
	var type: Variant.Type = typeof(value)
	if type < TYPE_OBJECT:
		return value
	elif type > TYPE_ARRAY:
		return value.duplicate()
	else:
		match type:
			TYPE_OBJECT:
				if value == null:
					return null
				var result: Dictionary
				for property_info in value.get_property_list():
					if property_info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
						continue
					var property_name: StringName = property_info.name
					if property_name.begins_with("_") and not with_privates:
						continue
					result[property_name] = simplify(value.get(property_name), true)
				return result
			TYPE_CALLABLE: return null
			TYPE_SIGNAL: return null
			TYPE_DICTIONARY:
				if not deep:
					return value.duplicate()
				var result: Dictionary
				for key in value.keys():
					result[key] = simplify(value[key], true)
				return result
			TYPE_ARRAY:
				if not deep:
					return value.duplicate()
				var size: int = value.size()
				var result: Array
				result.resize(size)
				for index in size:
					result[index] = simplify(value[index], true)
				return result
			_: assert(false, "Unexpected value type: %s" % [type])
	return null
