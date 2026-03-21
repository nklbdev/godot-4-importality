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
		self._export_all()

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

func _is_version_supported(version: int) -> bool:
	return version == 3

## Compare two frame cels by z-index.
##
## [br]
## If both cels have the same z-index, they are sorted by their layer index
## instead (i.e. their order is preserved).
static func _compare_cels(a: Dictionary, b: Dictionary) -> bool:
	if a.z_index < b.z_index:
		return true

	if a.z_index > b.z_index:
		return false

	if a.layer_index < b.layer_index:
		return true

	assert(a.layer_index != b.layer_index, "Can't happen; layer indices should be unique.")

	return false


## Get the specified option as a string.
##
## [br]
## This both ensures that the value is, in fact, a string and trims its ends
## of whitespace.
func _get_string_option(name: String) -> String:
	return (self._options[name] as String).strip_edges()

## Returns true if the layer at the given index is effectively visible
## (the layer itself and all parent groups are visible).
func _is_layer_effectively_visible(layer_index: int) -> bool:
	var layer: Dictionary = self._data.layers[layer_index]
	if not layer.visible:
		return false
	if layer.parent >= 0:
		return _is_layer_effectively_visible(layer.parent)
	return true

## Returns the indices of all effectively visible pixel layers.
func _get_visible_pixel_layer_indices() -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for i in self._data.layers.size():
		var layer: Dictionary = self._data.layers[i]
		if layer.type != _PxoLayerType.PIXEL_LAYER:
			continue
		if _is_layer_effectively_visible(i):
			result.push_back(i)
	return result

## Load the raw pixel data for a single layer of a single frame (no compositing).
func _load_layer_raw_frame_image(frame_index: int, layer_index: int) -> Image:
	var data: PackedByteArray = self._zip_reader.read_file(
		"image_data/frames/%d/layer_%d" % [frame_index + 1, layer_index + 1])
	if data.is_empty():
		return self._empty_image.duplicate()
	return Image.create_from_data(
		self._data.size_x, self._data.size_y, false, Image.FORMAT_RGBA8, data)

## Unified export implementation — handles both composite and per-layer split modes.
## Normal import is the special case with one composite "layer" and no name affix.
func _export_all() -> void:
	var split_layers: bool = self._options.get(_Options.SPLIT_LAYERS, false)
	var layer_name_first: bool = self._options.get(_Options.LAYERS_ANIMATION_NAME_FORMAT, 0) == 0
	var autoplay_animation_name: String = self._get_string_option(_Options.AUTOPLAY_ANIMATION_NAME)

	# Resolve tags with default fallback
	var tags: Array = self._data.tags
	var use_default_tag: bool = tags.is_empty()
	if use_default_tag:
		var default_name: String = self._get_string_option(_Options.DEFAULT_ANIMATION_NAME)
		if default_name.is_empty():
			default_name = "default"
		tags = [{name = default_name, from = 1, to = self._data.frames.size()}]

	# Parse all tags
	var parsed_tags: Array = []
	for tag in tags:
		var params := _Export._parse_animation_params(
			tag.name,
			_Export.AnimationOptions.Direction | _Export.AnimationOptions.RepeatCount,
			tag.from - 1,
			tag.to - tag.from + 1)
		if params.error:
			self._error = _Export.ExportResult.new()
			self._error.fail(ERR_CANT_RESOLVE, "Failed to parse animation parameters", params)
			return
		var direction: _Common.AnimationDirection = params.direction
		var repeat_count: int = params.repeat_count
		if not use_default_tag:
			var tag_ud: String = tag.get("user_data", "")
			if not tag_ud.is_empty() and (direction < 0 or repeat_count < 0):
				var ud := _Export._parse_animation_params(tag_ud,
					_Export.AnimationOptions.Direction | _Export.AnimationOptions.RepeatCount,
					tag.from - 1, tag.to - tag.from + 1)
				if direction < 0: direction = ud.direction
				if repeat_count < 0: repeat_count = ud.repeat_count
		if direction < 0:
			direction = self._options[_Options.DEFAULT_ANIMATION_DIRECTION] as _Common.AnimationDirection
		if repeat_count < 0:
			repeat_count = self._options[_Options.DEFAULT_ANIMATION_REPEAT_COUNT] as int
		parsed_tags.push_back({
			name = params.name,
			direction = direction,
			repeat_count = repeat_count,
			from = tag.from - 1,
			to = tag.to - 1,
		})

	# Collect the set of frame indices needed across all tags
	var needed_fi_set: Dictionary = {}
	for pt in parsed_tags:
		for fi in range(pt.from, pt.to + 1):
			needed_fi_set[fi] = true
	var needed_fi: PackedInt32Array = PackedInt32Array(needed_fi_set.keys())
	needed_fi.sort()

	# Build layer infos.
	# Non-split: one info with layer_index = -1 (use composite frame images).
	# Split: one info per visible pixel layer with per-layer raw images.
	# Each info: {layer_index: int, name_prefix: String, name_suffix: String, canvas_offset: Vector2i}
	var layer_infos: Array = []

	if not split_layers:
		for fi in needed_fi:
			self._load_frame_image(fi)
		if self._error: return
		layer_infos.push_back({
			layer_index = -1, name_prefix = "", name_suffix = "", canvas_offset = Vector2i.ZERO})
	else:
		var visible_indices: PackedInt32Array = _get_visible_pixel_layer_indices()
		if visible_indices.is_empty():
			self._error = _Export.ExportResult.new()
			self._error.fail(ERR_INVALID_DATA, "No visible pixel layers found in Pixelorama project.")
			return
		for layer_index in visible_indices:
			var layer: Dictionary = self._data.layers[layer_index]
			var name_params := _Export._parse_layer_params(layer.name)
			if name_params.error:
				self._error = _Export.ExportResult.new()
				self._error.fail(ERR_INVALID_DATA, "Failed to parse layer name params for \"%s\"" % layer.name, name_params)
				return
			var display_name: String = name_params.name
			var canvas_offset: Vector2i = name_params.canvas_offset
			var layer_ud: String = layer.get("user_data", "")
			if not layer_ud.is_empty() and canvas_offset == Vector2i.ZERO:
				var ud := _Export._parse_layer_params(layer_ud)
				if not ud.error: canvas_offset = ud.canvas_offset
			layer_infos.push_back({
				layer_index = layer_index,
				name_prefix = display_name + "/" if layer_name_first else "",
				name_suffix = "" if layer_name_first else "/" + display_name,
				canvas_offset = canvas_offset,
			})

	# Collect all frame images, applying canvas offsets where needed
	var all_frame_images: Array[Image] = []
	var sprite_indices: Array = []  # Array of Dict[fi -> sprite_sheet_index]
	for info in layer_infos:
		var sidx: Dictionary = {}
		for fi in needed_fi:
			var img: Image
			if info.layer_index < 0:
				img = self._frame_images[fi]
			else:
				img = _load_layer_raw_frame_image(fi, info.layer_index)
			if info.canvas_offset != Vector2i.ZERO:
				var shifted := Image.create_empty(
					self._data.size_x, self._data.size_y, false, Image.FORMAT_RGBA8)
				shifted.blit_rect(img,
					Rect2i(info.canvas_offset.x, info.canvas_offset.y,
						self._data.size_x, self._data.size_y),
					Vector2i.ZERO)
				img = shifted
			sidx[fi] = all_frame_images.size()
			all_frame_images.push_back(img)
		sprite_indices.push_back(sidx)

	# Build sprite sheet
	var builder := _Export._create_sprite_sheet_builder(self._options)
	var build_result := builder.build_sprite_sheet(all_frame_images)
	if build_result.error:
		self._error = _Export.ExportResult.new()
		self._error.fail(ERR_BUG, "Failed to build sprite sheet", build_result)
		return
	self._atlas_image = build_result.atlas_image
	self._sprite_sheet = build_result.sprite_sheet

	# Create animations — identical loop for both split and non-split
	self._animation_library = _Common.AnimationLibraryInfo.new()
	for di in layer_infos.size():
		var info: Dictionary = layer_infos[di]
		var sidx: Dictionary = sprite_indices[di]
		var unqualified: bool = info.name_prefix.is_empty() and info.name_suffix.is_empty()
		for pt in parsed_tags:
			var anim_name: String = info.name_prefix + pt.name + info.name_suffix
			var animation := _Common.AnimationInfo.new()
			animation.name = anim_name
			animation.direction = pt.direction
			animation.repeat_count = pt.repeat_count
			for fi in range(pt.from, pt.to + 1):
				var frame := _Common.FrameInfo.new()
				frame.duration = self._data.frames[fi].duration / self._data.fps
				frame.sprite = self._sprite_sheet.sprites[sidx[fi]]
				animation.frames.push_back(frame)
			if unqualified and anim_name == autoplay_animation_name:
				self._animation_library.autoplay_index = self._animation_library.animations.size()
			self._animation_library.animations.push_back(animation)
	if not split_layers and not autoplay_animation_name.is_empty() \
			and self._animation_library.autoplay_index < 0:
		push_warning("Autoplay animation name not found: \"%s\". Continuing..." % [autoplay_animation_name])

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

	if not _is_version_supported(int(json.data.pxo_version)):
		self._error = _Export.ExportResult.new()
		self._error.fail(ERR_FILE_UNRECOGNIZED,
			"pxo version %d is not handled by this reader" % [int(json.data.pxo_version)])
		return

	self._data = json.data
	self._empty_image = Image.create_empty(self._data.size_x, self._data.size_y, false, Image.FORMAT_RGBA8)
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
