extends "res://addons/nklbdev.importality/external_scripts/middle_import_script_base.gd"

static func modify_context(
	# Path to the source file from which the import is performed
	res_source_file_path: String,
	# Path to save imported resource file
	res_save_file_path: String,
	# EditorImportPlugin instance to call append_import_external_resource
	# or other methods
	editor_import_plugin: EditorImportPlugin,
	# Import options
	options: Dictionary,
	# Context-object to modify
	context: Context) -> Error:
	# ------------------------------------------------
	# You can modify or replace objects in context fields.
	# (Be careful not to shoot yourself in the foot!)
	# ------------------------------------------------
	#
	# context.atlas_image: Image
	#     The image that will be saved as a PNG file next to the original file
	#     and automatically imported by the engine into a resource
	#     that will be used as an atlas
	#
	# context.sprite_sheet: SpriteSheetInfo
	#     Sprite sheet data. Stores source image size and sprites data (SpriteInfo)
	#
	# context.animation_library: AnimationLibraryInfo
	#     Animations data. Uses sprites data (SpriteInfo) stored in context.sprite_sheet
	#
	# gen_files_to_add: PackedStringArray
	#     Gen-files paths to add to gen_files array of import-function
	#
	# context.middle_import_data: Variant
	#     Your custom data to use in the post-import script

	# You can save your new resources directly in .godot/import folder
	# in *.res or *.tres formats.
	#
	# If you want to save an image as Texture resource,
	# use PortableCompressedTexture2D resource. It has almost the same file
	# structure as CompressedTexture2D (engine internal *.ctex - files).
	# And you can embed this resource into another resources!
	# You cannot save an image in *.ctex format yourself. Sad but true.

	box_blur(context.atlas_image)
	grayscale(context.atlas_image)
	return OK

static func box_blur(image: Image) -> void:
	var image_copy = image.duplicate()
	var image_size: Vector2i = image.get_size()
	for y in range(1, image_size.y - 1): for x in range(1, image_size.x - 1):
		# Set P to the average of 9 pixels:
		# X X X
		# X P X
		# X X X
		image.set_pixel(x, y, (
			image_copy.get_pixel(x - 1, y + 1) + # Top left
			image_copy.get_pixel(x + 0, y + 1) + # Top center
			image_copy.get_pixel(x + 1, y + 1) + # Top right
			image_copy.get_pixel(x - 1, y + 0) + # Mid left
			image_copy.get_pixel(x + 0, y + 0) + # Current pixel
			image_copy.get_pixel(x + 1, y + 0) + # Mid right
			image_copy.get_pixel(x - 1, y - 1) + # Low left
			image_copy.get_pixel(x + 0, y - 1) + # Low center
			image_copy.get_pixel(x + 1, y - 1)   # Low right
		) / 9.0)

static func grayscale(image: Image) -> void:
	var image_size: Vector2i = image.get_size()
	for y in image_size.y: for x in image_size.x:
		var pixel_color: Color = image.get_pixel(x, y)
		var luminance: float = pixel_color.get_luminance()
		image.set_pixel(x, y, Color(luminance, luminance, luminance, pixel_color.a));
