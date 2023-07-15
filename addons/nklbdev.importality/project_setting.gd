extends Object

var __name: StringName
var __initial_value: Variant
var __type: Variant.Type
var __hint: PropertyHint
var __hint_string: String
var __is_required: bool
var __is_value_empty_func: Callable

func __default_is_value_empty_func(value: Variant) -> bool:
	if value: return false
	return true

func _init(
	name: String,
	initial_value: Variant,
	type: int,
	hint: int,
	hint_string: String = "",
	is_required: bool = false,
	is_value_empty_func: Callable = __default_is_value_empty_func
	) -> void:
	__name = "importality/" + name
	__initial_value = initial_value
	__type = type
	__hint = hint
	__hint_string = hint_string
	__is_required = is_required
	__is_value_empty_func = is_value_empty_func

func register() -> void:
	if not ProjectSettings.has_setting(__name):
		ProjectSettings.set_setting(__name, __initial_value)
	ProjectSettings.set_initial_value(__name, __initial_value)
	var property_info: Dictionary = {
		"name": __name,
		"type": __type,
		"hint": __hint, }
	if __hint_string:
		property_info["hint_string"] = __hint_string
	ProjectSettings.add_property_info(property_info)

class Result:
	var error: Error
	var error_message: String
	var value: Variant
	static func success(value: Variant) -> Result:
		var result = Result.new()
		result.value = value
		return result
	static func fail(error: Error, error_message: String = "") -> Result:
		var result = Result.new()
		result.error = error
		result.error_message = error_message
		return result

func get_value() -> Result:
	var value = ProjectSettings.get_setting(__name)
	if __is_required:
		if __is_value_empty_func.call(value):
			return Result.fail(ERR_UNCONFIGURED,
				"The project settging \"%s\" is not specified!" % [__name] + \
				"Specify it in Projest Settings -> General -> Importality.")
	return Result.success(value)
