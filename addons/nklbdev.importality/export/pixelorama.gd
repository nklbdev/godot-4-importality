@tool
extends "_.gd"

const _PxoV2 = preload("_pxo_v2.gd")
const _PxoV3 = preload("_pxo_v3.gd")

func _init() -> void:
	var recognized_extensions: PackedStringArray = ["pxo"]
	super("Pixelorama", recognized_extensions, [
	], [
		# settings
	], CustomImageFormatLoaderExtension.new(recognized_extensions))

func _export(res_source_file_path: String, options: Dictionary) -> ExportResult:
	var v2_result: ExportResult
	var v3_result := _PxoV3.new(res_source_file_path).export(options)

	if v3_result.error:
		v2_result = _PxoV2.export(res_source_file_path, options)

		# Only return the v2 result if it succeeded; if both failed, the v3 result
		# is returned on the theory that the more recent format is more likely to
		# be what was intended.
		if not v2_result.error:
			return v2_result

	return v2_result if v2_result else v3_result

class CustomImageFormatLoaderExtension:
	extends ImageFormatLoaderExtension

	var __recognized_extensions: PackedStringArray

	func _init(recognized_extensions: PackedStringArray) -> void:
		__recognized_extensions = recognized_extensions

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
		var v3_error: int = _PxoV3.new(file_access.get_path()).set_image_data(image)

		if v3_error != OK:
			if OK == _PxoV2.load_image(image, file_access, flags, scale):
				return OK

		return v3_error
