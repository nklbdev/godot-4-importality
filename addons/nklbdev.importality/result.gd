class Class:
	extends RefCounted

	var error: Error
	var error_description: String
	var inner_result: Class
	func _get_result_type_description() -> String:
		return "Operation"
	func fail(error: Error, error_description: String = "", inner_result: Class = null) -> void:
		assert(error != OK)
		self.error = error
		self.error_description = error_description
		self.inner_result = inner_result
	func _success():
		error = OK
		error_description = ""
		inner_result = null
	func _to_string() -> String:
		return "%s error: %s (%s)%s%s" % [
			_get_result_type_description(),
			error,
			error_string(error),
			(", description: \"%s\"" % [error_description]) if error_description else "",
			(", inner error:\n%s" % [inner_result]) if inner_result else "",
		] if error else "%s(success)"
