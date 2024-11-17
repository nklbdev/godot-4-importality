@tool
extends RefCounted
## Represents a Pixelorama project stored in a pxo v3 file.

enum _PxoLayerType {
	PIXEL_LAYER = 0,
	GROUP_LAYER = 1,
	LAYER_3D = 2,
}

const _Common = preload("../common.gd")
const _Export = preload("_.gd")
const _Result = preload("../result.gd").Class
const _Options = preload("../options.gd")

var _animation_library: _Common.AnimationLibraryInfo
var _atlas_image: Image
var _data: Dictionary
var _empty_image: Image
var _error: _Export.ExportResult
var _has_composited_frames: bool
var _frame_images: Array[Image]
var _frame_rect: Rect2i
var _options: Dictionary
var _path: String
var _sprite_sheet: _Common.SpriteSheetInfo
var _zip_reader: ZIPReader

func _init(path: String) -> void:
	self._path = path

## Export the project.
func export(options: Dictionary) -> _Export.ExportResult:
	self._options = options
	self._load()

	if not self._error:
		self._load_animation_images()

	if not self._error:
		self._build_sprite_sheet()

	if not self._error:
		self._create_animations()

	if self._error:
		return self._error

	var result := _Export.ExportResult.new()

	result.success(self._atlas_image, self._sprite_sheet, self._animation_library)

	return result

## Replace an image's data with the first frame in the project.
func set_image_data(image: Image) -> Error:
	self._load()

	if self._error:
		return self._error.error

	self._load_frame_image(0)

	image.set_data(
		self._frame_images[0].get_width(),
		self._frame_images[0].get_height(),
		false,
		Image.FORMAT_RGBA8,
		self._frame_images[0].get_data(),
	)

	return OK

## Build a sprite sheet containing all loaded frame images.
func _build_sprite_sheet() -> void:
	if not self._options:
		self._error = _Export.ExportResult.new()
		self._error.fail(ERR_BUG, "Building a sprite sheet requires export options.")

		return

	var sprite_sheet_builder := _Export._create_sprite_sheet_builder(self._options)
	var sprite_sheet_result := sprite_sheet_builder.build_sprite_sheet(self._frame_images)

	if sprite_sheet_result.error:
		self._error = _Export.ExportResult.new()
		self._error.fail(ERR_BUG, "Failed to build sprite sheet", sprite_sheet_result)

		return

	self._atlas_image = sprite_sheet_result.atlas_image
	self._sprite_sheet = sprite_sheet_result.sprite_sheet

## Compare two frame cels by z-index.
##
## [br]
## If both cels have the same z-index, they are sorted by their layer index
## instead (i.e. their order is preserved).
static func _compare_cels(a: Dictionary, b: Dictionary) -> bool:
	if a.z_index > b.z_index:
		return true

	if a.z_index < b.z_index:
		return false

	if a.layer_index > b.layer_index:
		return true

	assert(a.layer_index != b.layer_index, "Can't happen; layer indices should be unique.")

	return false

## Create a single animation.
##
## [br]
## [param start] The zero-based index of the first frame to include in the
## animation. If creating an animation from a tag, this should be
## [code]tag.from - 1[/code].
## [br]
## [param end] The zero-based index of the first frame to [b]not[/b] include
## in the animation. If creating an animation from a tag, this should be
## [code]tag.to[/code].
func _create_animation(
	name: String,
	direction: _Common.AnimationDirection,
	repeat_count: int,
	start: int,
	end: int,
) -> _Common.AnimationInfo:
	var animation := _Common.AnimationInfo.new()

	animation.name = name
	animation.direction = direction
	animation.repeat_count = repeat_count
	animation.frames.resize(end - start)

	for animation_frame_index in end - start:
		var project_frame_index := start + animation_frame_index
		var frame := _Common.FrameInfo.new()

		frame.duration = self._data.frames[project_frame_index].duration / self._data.fps
		frame.sprite = self._sprite_sheet.sprites[project_frame_index]

		animation.frames[animation_frame_index] = frame

	return animation

## Create an animation for each tag in the project.
##
## If the project doesn't contain any tags, a single animation will be created
## which contains every frame in the project.
func _create_animations() -> void:
	if self._animation_library:
		return

	if not self._options:
		self._error = _Export.ExportResult.new()
		self._error.fail(ERR_BUG, "Creating animations requires export options.")

		return

	self._animation_library = _Common.AnimationLibraryInfo.new()

	var autoplay_animation_name := self._get_string_option(_Options.AUTOPLAY_ANIMATION_NAME)

	# If no tags are defined, create a single animation with the default name and
	# containing all frames.
	if self._data.tags.is_empty():
		var default_animation_name := self._get_string_option(_Options.DEFAULT_ANIMATION_NAME)
		var name := "default" if default_animation_name.is_empty() else default_animation_name

		self._animation_library.animations.resize(1)

		self._animation_library.animations[0] = self._create_animation(
			name,
			self._options[_Options.DEFAULT_ANIMATION_DIRECTION] as _Common.AnimationDirection,
			self._options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT] as int,
			0,
			(self._data.frames as Array[Dictionary]).size()
		)

		if name == autoplay_animation_name:
			self._animation_library.autoplay_index = 0

		return

	self._animation_library.animations.resize(self._data.tags.size())

	for tag_index in self._data.tags.size():
		var tag := self._data.tags[tag_index] as Dictionary

		var animation_params_result := _Export._parse_animation_params(
			tag.name,
			_Export.AnimationOptions.Direction | _Export.AnimationOptions.RepeatCount,
			tag.from - 1,
			tag.to - tag.from + 1,
		)

		self._animation_library.animations[tag_index] = self._create_animation(
			animation_params_result.name,
			animation_params_result.direction,
			animation_params_result.repeat_count,
			animation_params_result.first_frame_index,
			animation_params_result.first_frame_index + animation_params_result.frames_count,
		)

		if animation_params_result.name == autoplay_animation_name:
			self._animation_library.autoplay_index = tag_index

## Get the specified option as a string.
##
## [br]
## This both ensures that the value is, in fact, a string and trims its ends
## of whitespace.
func _get_string_option(name: String) -> String:
	return (self._options[name] as String).strip_edges()

## Load the project from its pxo file and initialize it.
func _load() -> void:
	if self._zip_reader:
		return

	self._zip_reader = ZIPReader.new()

	var open_error := self._zip_reader.open(self._path)

	if open_error != OK:
		self._error = _Export.ExportResult.new()
		self._error.fail(open_error, "Could not open pxo file")

		return

	var raw_data := self._zip_reader.read_file("data.json")

	if raw_data.is_empty():
		self._error = _Export.ExportResult.new()
		self._error.fail(ERR_DOES_NOT_EXIST, "Invalid Pixelorama project: data.json missing or empty")

		return

	var json := JSON.new()
	var json_error := json.parse(raw_data.get_string_from_utf8())

	if json_error != OK:
		self._error = _Export.ExportResult.new()
		self._error.fail(
			ERR_PARSE_ERROR,
			"Invalid Pixelorama project: could not parse data.json (%s on line %d)" % [
				json.get_error_message(),
				json.get_error_line(),
			],
		)

		return

	if typeof(json.data) != TYPE_DICTIONARY:
		self._error = _Export.ExportResult.new()
		self._error.fail(ERR_INVALID_DATA, "Invalid Pixelorama project: data.json is not a dictionary")

		return

	if json.data.pxo_version != 3:
		push_warning(
			"This project uses version " + str(json.data.pxo_version) +
			" of the pxo file format, which is not currently supported by Importality."
		)

	self._data = json.data
	self._empty_image = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	self._frame_images = []
	self._frame_images.resize(self._data.frames.size())
	self._frame_images.fill(self._empty_image)
	self._frame_rect = Rect2i(Vector2i.ZERO, Vector2i(self._data.size_x, self._data.size_y))
	self._has_composited_frames = self._zip_reader.file_exists("image_data/final_images/1")

	if not self._has_composited_frames:
		push_warning(
			"The Pixelorama project '%s' does not contain blended/precomposited frame images." %[self._path] +
			" Not all Pixelorama compositing features are supported by Importality, so frames may not" +
			" look the way you expect unless you enable \"Include blended images\" in Pixelorama."
		)

## Preload the frame images for all animations.
##
## [br]
## This allows the sprite sheet to be built before the animations, which can
## then be created in a single step.
func _load_animation_images() -> void:
	if self._data.tags.is_empty():
		for frame_index in self._data.frames.size():
			self._load_frame_image(frame_index)
	else:
		for tag in self._data.tags:
			for frame_index in range(tag.from - 1, tag.to):
				self._load_frame_image(frame_index)

## Ensure a frame's image has been loaded.
##
## [br]
## If the image for the frame is not already loaded, it will either load the
## frame's precomposited image (a.k.a. blended image) if availble or attempt
## to composite the frame layers into an image itself otherwise.
func _load_frame_image(frame_index: int) -> void:
	if self._frame_images[frame_index] != self._empty_image:
		return

	if self._has_composited_frames:
		# Having precomposited frames available greatly simplifies things.

		self._frame_images[frame_index] = Image.create_from_data(
			self._data.size_x,
			self._data.size_y,
			false,
			Image.FORMAT_RGBA8,
			self._zip_reader.read_file("image_data/final_images/%d" % [frame_index + 1]),
		)

		return

	# Blended images aren't available, so the layers need composited.

	var frame: Dictionary = self._data.frames[frame_index]
	var cels := (frame.cels as Array[Dictionary]).duplicate(true)

	for index in range(cels.size()):
		cels[index].layer_index = index

	cels.sort_custom(_compare_cels)

	var frame_image := Image.create_empty(self._data.size_x, self._data.size_y, false, Image.FORMAT_RGBA8)
	var cel_image := Image.create_empty(self._data.size_x, self._data.size_y, false, Image.FORMAT_RGBA8)

	for cel in cels:
		var layer: Dictionary = self._data.layers[cel.layer_index]

		if layer.type != _PxoLayerType.PIXEL_LAYER:
			continue

		var opacity: float = cel.opacity

		while opacity > 0.0:
			if layer.visible:
				opacity *= layer.opacity

				if layer.parent < 0:
					break

				layer = self._data.layers[layer.parent]
			else:
				opacity = 0.0

		if is_equal_approx(opacity, 0.0):
			continue

		var cel_data := self._zip_reader.read_file("image_data/frames/%d/layer_%d" % [frame_index + 1, cel.layer_index + 1])

		if not is_equal_approx(opacity, 1.0):
			# Apply the cel opacity by scaling all the alpha-channel bytes.

			for alpha_index in range(3, cel_data.size(), 4):
				cel_data[alpha_index] *= opacity

		cel_image.set_data(self._data.size_x, self._data.size_y, false, Image.FORMAT_RGBA8, cel_data)
		frame_image.blend_rect(cel_image, self._frame_rect, Vector2i.ZERO)

	self._frame_images[frame_index] = frame_image
