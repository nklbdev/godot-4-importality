@tool
extends "standalone_image_format_loader_extension.gd"

const _Common = preload("common.gd")

static var command_building_rules_for_custom_image_loader_setting: _Setting = _Setting.new(
	"command_building_rules_for_custom_image_loader", PackedStringArray(), TYPE_PACKED_STRING_ARRAY, PROPERTY_HINT_NONE)

func _get_recognized_extensions() -> PackedStringArray:
	var rules_by_extensions_result: _Setting.GettingValueResult = command_building_rules_for_custom_image_loader_setting.get_value()
	if rules_by_extensions_result.error:
		push_error("Failed to get command building rules for custom image loader setting")
		return PackedStringArray()
	var extensions: PackedStringArray
	for rule_string in rules_by_extensions_result.value:
		var parsed_rule: Dictionary = _parse_rule(rule_string)
		if parsed_rule.is_empty():
			push_error("Failed to parse command building rule")
			return PackedStringArray()
		for extension in parsed_rule.extensions as PackedStringArray:
			if extensions.has(extension):
				push_error("There are duplicated file extensions found in command building rules")
				return PackedStringArray()
			extensions.push_back(extension)
	return extensions

func get_settings() -> Array[_Setting]:
	return [command_building_rules_for_custom_image_loader_setting]

static var regex_middle_spaces: RegEx = RegEx.create_from_string("(?<=\\S)\\s(?>=\\S)")
static func normalize_string(source: String) -> String:
	return regex_middle_spaces.sub(source.strip_edges(), " ", true)

func _parse_rule(rule_string: String) -> Dictionary:
	var parts: PackedStringArray = rule_string.split(":", false, 1)
	if parts.size() != 2:
		push_error("Failed to find colon (:) delimiter in command building rule between file extensions and command template")
		return {}
	var extensions: PackedStringArray
	for extensions_splitted_by_spaces in normalize_string(parts[0]).split(" ", false):
		extensions.append_array(extensions_splitted_by_spaces.split(",", false))
	if extensions.is_empty():
		push_error("Extensions list in command building rule is empty")
		return {}
	var command_template: String = parts[1].strip_edges()
	if command_template.is_empty():
		push_error("Command template in command building rule is empty")
		return {}
	return {
		extensions = extensions,
		command_template = command_template,
	}

func _load_image(
	image: Image,
	file_access: FileAccess,
	flags,
	scale: float
	) -> Error:

	var temp_dir_path_result: _Setting.GettingValueResult = _Common.common_temporary_files_directory_path_setting.get_value()
	if temp_dir_path_result.error:
		push_error("Failed to get Temporary Files Directory Path to export image from source file: %s" % [temp_dir_path_result])
		return ERR_UNCONFIGURED

	var rules_by_extensions_result: _Setting.GettingValueResult = command_building_rules_for_custom_image_loader_setting.get_value()
	if rules_by_extensions_result.error:
		push_error("Failed to get command building rules for custom image loader setting")
		return ERR_UNCONFIGURED

	var command_templates_by_extensions: Dictionary
	for rule_string in rules_by_extensions_result.value:
		var parsed_rule: Dictionary = _parse_rule(rule_string)
		if parsed_rule.is_empty():
			push_error("Failed to parse command building rule")
			return ERR_UNCONFIGURED
		for extension in parsed_rule.extensions as PackedStringArray:
			if command_templates_by_extensions.has(extension):
				push_error("There are duplicated file extensions found in command building rules")
				return ERR_UNCONFIGURED
			command_templates_by_extensions[extension] = \
				parsed_rule.command_template

	var global_input_path: String = file_access.get_path_absolute()
	var extension = global_input_path.get_extension()
	var global_output_path: String = ProjectSettings.globalize_path(
		temp_dir_path_result.value.path_join("temp.png"))

	var command_template: String = command_templates_by_extensions.get(extension, "") as String
	if command_template.is_empty():
		push_error("Failed to find command template for file extension: " + extension)
		return ERR_UNCONFIGURED

	var command_template_parts: PackedStringArray = _Common.split_words_with_quotes(command_template)
	if command_template_parts.is_empty():
		push_error("Failed to recognize command template parts for extension: %s" % [extension])
		return ERR_UNCONFIGURED

	for command_template_part_index in command_template_parts.size():
		var command_template_part: String = command_template_parts[command_template_part_index]
		command_template_parts[command_template_part_index] = \
			command_template_parts[command_template_part_index] \
			.replace("{in_path}", global_input_path) \
			.replace("{in_path_b}", global_input_path.replace("/", "\\")) \
			.replace("{in_path_base}", global_input_path.get_basename()) \
			.replace("{in_path_base_b}", global_input_path.get_basename().replace("/", "\\")) \
			.replace("{in_file}", global_input_path.get_file()) \
			.replace("{in_file_base}", global_input_path.get_file().get_basename()) \
			.replace("{in_dir}", global_input_path.get_base_dir()) \
			.replace("{in_dir_b}", global_input_path.get_base_dir().replace("/", "\\")) \
			.replace("{in_ext}", extension) \
			.replace("{out_path}", global_output_path) \
			.replace("{out_path_b}", global_output_path.replace("/", "\\")) \
			.replace("{out_path_base}", global_output_path.get_basename()) \
			.replace("{out_path_base_b}", global_output_path.get_basename().replace("/", "\\")) \
			.replace("{out_file}", global_output_path.get_file()) \
			.replace("{out_file_base}", global_output_path.get_file().get_basename()) \
			.replace("{out_dir}", global_output_path.get_base_dir()) \
			.replace("{out_dir_b}", global_output_path.get_base_dir().replace("/", "\\")) \
			.replace("{out_ext}", "png")

	var command: String = command_template_parts[0]
	var arguments: PackedStringArray = command_template_parts.slice(1)

	var output: Array
	var exit_code: int = OS.execute(command, arguments, output, true, false)
	if exit_code:
		for arg_index in arguments.size():
			arguments[arg_index] = "\nArgument: " + arguments[arg_index]
		push_error(" ".join([
			"An error occurred while executing",
			"the external image converting utility command.",
			"Process exited with code %s:\nCommand: %s%s"
			]) % [exit_code, command, "".join(arguments)])
		return ERR_QUERY_FAILED

	if not FileAccess.file_exists(global_output_path):
		push_error("The output temporary PNG file is not found: %s" % [global_output_path])
		return ERR_UNCONFIGURED

	var err: Error = image.load_png_from_buffer(FileAccess.get_file_as_bytes(global_output_path))
	if err:
		push_error("Failed to load temporary PNG file as image: %s" % [global_output_path])
		return err

	err = DirAccess.remove_absolute(global_output_path)
	if err:
		push_warning("Failed to remove temporary file \"%s\". Continuing..." % [global_output_path])

	return OK

