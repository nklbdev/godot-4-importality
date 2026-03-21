@tool
extends "_.gd"

const _PxoV2 = preload("_pxo_v2.gd")
const _PxoV3 = preload("_pxo_v3.gd")
const _PxoV4 = preload("_pxo_v4.gd")

func _init() -> void:
	var recognized_extensions: PackedStringArray = ["pxo"]
	super("Pixelorama", recognized_extensions, [
	], [
		# settings
	], CustomImageFormatLoaderExtension.new(recognized_extensions))

func _export(res_source_file_path: String, options: Dictionary) -> ExportResult:
	var v4_result := _PxoV4.new(res_source_file_path).export(options)
	if not v4_result.error:
		return v4_result

	var v3_result := _PxoV3.new(res_source_file_path).export(options)
	if not v3_result.error:
		return v3_result

	var v2_result := _PxoV2.export(res_source_file_path, options)
	if v2_result and not v2_result.error:
		return v2_result

	# All readers failed — return the newest version's error as most likely relevant.
	return v4_result

class CustomImageFormatLoaderExtension:
	extends ImageFormatLoaderExtension

	var __recognized_extensions: PackedStringArray

	func _init(recognized_extensions: PackedStringArray) -> void:
		__recognized_extensions = recognized_extensions

	func _get_recognized_extensions() -> PackedStringArray:
		return __recognized_extensions

	func _load_image(image: Image, file_access: FileAccess, flags: int, scale: float) -> Error:
		var v4_error: int = _PxoV4.new(file_access.get_path()).set_image_data(image)
		if v4_error == OK:
			return OK

		var v3_error: int = _PxoV3.new(file_access.get_path()).set_image_data(image)
		if v3_error == OK:
			return OK

		if OK == _PxoV2.load_image(image, file_access, flags, scale):
			return OK

		return v4_error
