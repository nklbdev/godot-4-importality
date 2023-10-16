@tool
extends RefCounted

const _Result = preload("result.gd").Class

var __editor_settings: EditorSettings

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

func register(editor_settings: EditorSettings) -> void:
	__editor_settings = editor_settings
	if not __editor_settings.has_setting(__name):
		__editor_settings.set_setting(__name, __initial_value)
	__editor_settings.set_initial_value(__name, __initial_value, false)
	var property_info: Dictionary = {
		"name": __name,
		"type": __type,
		"hint": __hint, }
	if __hint_string:
		property_info["hint_string"] = __hint_string
	__editor_settings.add_property_info(property_info)

class GettingValueResult:
	extends _Result
	var value: Variant
	func success(value: Variant) -> void:
		_success()
		self.value = value

func get_value() -> GettingValueResult:
	var result = GettingValueResult.new()
	var value = __editor_settings.get_setting(__name)
	if __is_required:
		if __is_value_empty_func.call(value):
			result.fail(ERR_UNCONFIGURED,
				"The project settging \"%s\" is not specified!" % [__name] + \
				"Specify it in Projest Settings -> General -> Importality.")
			return result
	result.success(value)
	return result
