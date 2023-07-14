extends "_node.gd"

class TrackFrame:
	var duration: float
	var value: Variant
	func _init(duration: float, value: Variant) -> void:
		self.duration = duration
		self.value = value

static func _create_animation_player(
	animation_library_model: _Models.AnimationLibraryModel,
	track_value_getters_by_property_path: Dictionary
	) -> AnimationPlayer:
	var animation_player: AnimationPlayer = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	var animation_library: AnimationLibrary = AnimationLibrary.new()

	for animation_model in animation_library_model.animations:
		var animation: Animation = Animation.new()
		var frames: Array[_Models.FrameModel] = animation_model.get_output_frames()
		for property_path in track_value_getters_by_property_path.keys():
			__create_track(animation, property_path,
				frames, track_value_getters_by_property_path[property_path])

		animation.length = 0
		for frame in frames:
			animation.length += frame.duration

		animation.loop_mode = Animation.LOOP_LINEAR if animation_model.repeat_count == 0 else Animation.LOOP_NONE
		animation_library.add_animation(animation_model.name, animation)
	animation_player.add_animation_library("", animation_library)

	if animation_library_model.autoplay_animation_index >= 0:
		animation_player.autoplay = animation_library_model \
			.animations[animation_library_model.autoplay_animation_index].name

	return animation_player

static func __create_track(
	animation: Animation,
	property_path: NodePath,
	frames: Array[_Models.FrameModel],
	track_value_getter: Callable # func(f: FrameModel) -> Variant for each f in frames
	) -> int:
	var track_index = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track_index, property_path)
	animation.value_track_set_update_mode(track_index, Animation.UPDATE_DISCRETE)
	animation.track_set_interpolation_loop_wrap(track_index, false)
	animation.track_set_interpolation_type(track_index, Animation.INTERPOLATION_NEAREST)
	var track_frames = frames.map(
		func (frame_model: _Models.FrameModel):
			return TrackFrame.new(
				frame_model.duration,
				track_value_getter.call(frame_model)))

	var transition: float = 1
	var track_length: float = 0
	var previous_track_frame: TrackFrame = null
	for track_frame in track_frames:
		if previous_track_frame == null or track_frame.value != previous_track_frame.value:
			animation.track_insert_key(track_index, track_length, track_frame.value, transition)
		previous_track_frame = track_frame
		track_length += track_frame.duration

	return track_index
