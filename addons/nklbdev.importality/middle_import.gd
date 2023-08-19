extends RefCounted

const SpriteSheetLayout = preload("common.gd").SpriteSheetLayout
const EdgesArtifactsAvoidanceMethod = preload("common.gd").EdgesArtifactsAvoidanceMethod
const AnimationDirection = preload("common.gd").AnimationDirection
const SpriteInfo = preload("common.gd").SpriteInfo
const SpriteSheetInfo = preload("common.gd").SpriteSheetInfo
const FrameInfo = preload("common.gd").FrameInfo
const AnimationInfo = preload("common.gd").AnimationInfo
const AnimationLibraryInfo = preload("common.gd").AnimationLibraryInfo

static func modify(
	atlas_image: Image,
	sprite_sheet: SpriteSheetInfo,
	animation_library: AnimationLibraryInfo) -> void:
	pass
