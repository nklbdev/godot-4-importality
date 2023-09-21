extends "res://addons/nklbdev.importality/external_scripts/middle_import_script_base.gd"

static func modify_context(
	# Path to the source file from which the import is performed
	res_source_file_path: String,
	# Path to save imported resource file
	res_save_file_path: String,
	# EditorImportPlugin instance to call append_import_external_resource
	# or other methods
	editor_import_plugin: EditorImportPlugin,
	# EditorFileSystem instance to call update_file method
	editor_file_system: EditorFileSystem,
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
	# But with images the situation is somewhat more complicated.
	# You can embed your image into the main importing resource,
	# but this will take up a lot of memory space and it will not be optimized
	# because Godot can only create a CompressedTexture2D resource on its own,
	# and only as a separated *.ctex file.
	# You cannot save an image in *.ctex format yourself. Sad but true.
	#
	# In this case you need to save the image in the main resource file system
	# as a file in supported graphics format:
	# bmp, dds, exr, hdr, jpg/jpeg, png, tga, svg/svgz or webp.
	#
	# When Godot detects changes in the file system, the image will be imported.
	# This will happen a little later.
	# If you want to immediately use the texture from this image during
	# the current import process, you need to force the engine to import
	# this file right now. Do something like this:
	# ------------------------------------------------

	#var my_new_image: Image = Image.new()
	#my_new_image.create(32, 32, false, Image.FORMAT_RGBA8)
	#my_new_image.fill(Color.WHITE)
	#var my_new_texture_path: String = "res://my_new_texture.png"
	#var error: Error
	#
	## 1. Save your image
	#error = my_new_image.save_png(my_new_texture_path)
	#if error: # Do not forget to handle errors!
	#	push_error("Failed to save my image!")
	#	return error
	#
	## 2. Update file in resource filesystem before loading it with ResourceLoader
	## You need this because the resource created from the image does not yet exist.
	## This will force the engine to import the image, and the resource
	## (Texture2D, BitMap or other) created from it will be available at this path.
	# editor_file_system.update_file(my_new_texture_path)
	#
	## 3. Append path to your resource. After this,
	## the resource will be available for download via ResourceLoader
	#error = editor_import_plugin.append_import_external_resource(my_new_texture_path)
	#if error: # Do not forget to handle errors!
	#push_error("Failed to append import my image as external resource!")
	#return error
	#
	## Add the path to your resource to the list of generated files
	## so that the engine will establish a dependency between
	## the main imported resource and your new separated resource.
	#context.gen_files_to_add.push_back(my_new_texture_path)
	#
	## Hooray, your image has been imported and you can get
	## the Texture2D resource from this path using ResourceLoader!
	## You can now use this resource inside the main importing resource
	## without the need for embedding.
	#var my_new_texture: Texture2D = ResourceLoader.load(my_new_texture_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)

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
