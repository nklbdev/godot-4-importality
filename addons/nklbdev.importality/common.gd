@tool

const _Setting = preload("setting.gd")

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
	var source_image_size: Vector2i
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
	func get_flatten_frames() -> Array[FrameInfo]:
		var iteration_frames: Array[FrameInfo] = frames.duplicate()
		if direction == AnimationDirection.REVERSE or direction == AnimationDirection.PING_PONG_REVERSE:
			iteration_frames.reverse()
		if direction == AnimationDirection.PING_PONG or direction == AnimationDirection.PING_PONG_REVERSE:
			var returning_frames: Array[FrameInfo] = iteration_frames.duplicate()
			returning_frames.pop_back()
			returning_frames.reverse()
			returning_frames.pop_back()
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
	var autoplay_index: int = -1

static func get_vector2i(dict: Dictionary, x_key: String, y_key: String) -> Vector2i:
	return Vector2i(int(dict[x_key]), int(dict[y_key]))

static var common_temporary_files_directory_path_setting: _Setting = _Setting.new(
	"temporary_files_directory_path", "", TYPE_STRING, PROPERTY_HINT_GLOBAL_DIR,
	"", true, func(v: String): return v.is_empty())

const __backslash: String = "\\"
const __quote: String = "\""
const __space: String = " "
const __tab: String = "\t"
const __empty: String = ""
static func split_words_with_quotes(source: String) -> PackedStringArray:
	var parts: PackedStringArray
	if source.is_empty():
		return parts

	var quotation: bool

	var previous: String
	var current: String
	var next: String = source[0]
	var chars_count = source.length()

	var part: String
	for char_idx in chars_count:
		previous = current
		current = next
		next = source[char_idx + 1] if char_idx < chars_count - 1 else ""
		if quotation:
			# seek for quotation end
			if previous != __backslash and current == __quote:
				if next == __space or next == __tab or next == __empty:
					quotation = false
					parts.push_back(part)
					part = ""
					continue
				else:
					push_error("Invalid quotation start at %s:\n%s\n%s" % [char_idx, source, " ".repeat(char_idx) + "^"])
					return PackedStringArray()
		else:
			# seek for quotation start
			if current == __space or current == __tab:
				if not part.is_empty():
					parts.push_back(part)
					part = ""
				continue
			else:
				if previous != __backslash and current == __quote:
					if previous == __space or previous == __tab or previous == __empty:
						quotation = true
						continue
					else:
						push_error("Invalid quotation end at %s:\n%s\n%s" % [char_idx, source, " ".repeat(char_idx) + "^"])
						return PackedStringArray()
		part += current
	if quotation:
		push_error("Invalid quotation end at %s:\n%s\n%s" % [chars_count - 1, source, " ".repeat(chars_count - 1) + "^"])
		return PackedStringArray()
	if not part.is_empty():
		parts.push_back(part)
	return parts
