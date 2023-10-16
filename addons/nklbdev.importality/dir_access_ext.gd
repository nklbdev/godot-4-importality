extends Object

const _Result = preload("result.gd").Class

class CreationResult:
	extends _Result
	var path: String
	func success(path: String) -> void:
		super._success()
		self.path = path

class RemovalResult:
	extends _Result

static func create_directory_with_unique_name(base_directory_path: String) -> CreationResult:
	const error_description: String = "Failed to create a directory with unique name"
	var name: String
	var path: String
	var result = CreationResult.new()

	var error = DirAccess.make_dir_recursive_absolute(base_directory_path)
	match error:
		OK, ERR_ALREADY_EXISTS:
			pass
		_:
			var inner_result: CreationResult = CreationResult.new()
			inner_result.fail(ERR_QUERY_FAILED, "Failed to create base directory recursive")
			result.fail(
				ERR_CANT_CREATE,
				"%s: %s \"%s\"" %
				[error_description, error, error_string(error)],
				inner_result)
			return result

	while true:
		name = "%d" % (Time.get_unix_time_from_system() * 1000)
		path = base_directory_path.path_join(name)
		if not DirAccess.dir_exists_absolute(path):
			error = DirAccess.make_dir_absolute(path)
			match error:
				ERR_ALREADY_EXISTS:
					pass
				OK:
					result.success(path)
					break
				_:
					result.fail(
						ERR_CANT_CREATE,
						"%s: %s \"%s\"" %
						[error_description, error, error_string(error)])
					break
	return result

static func remove_dir_recursive(dir_path: String) -> RemovalResult:
	const error_description: String = "Failed to remove a directory with contents recursive"
	var result: RemovalResult = RemovalResult.new()
	for child_file_name in DirAccess.get_files_at(dir_path):
		var child_file_path = dir_path.path_join(child_file_name)
		var error: Error = DirAccess.remove_absolute(child_file_path)
		if error:
			var inner_result: RemovalResult = RemovalResult.new()
			inner_result.fail(
				ERR_QUERY_FAILED,
				"Failed to remove a file: \"%s\". Error: %s \"%s\"" %
				[child_file_path, error, error_string(error)])
			result.fail(ERR_QUERY_FAILED, "%s: \"%s\"" % [error_description, dir_path], inner_result)
			return result
	for child_dir_name in DirAccess.get_directories_at(dir_path):
		var child_dir_path = dir_path.path_join(child_dir_name)
		var inner_result: RemovalResult = remove_dir_recursive(child_dir_path)
		if inner_result.error:
			result.fail(ERR_QUERY_FAILED, "%s: \"%s\"" % [error_description, dir_path], inner_result)
			return result
	var error: Error = DirAccess.remove_absolute(dir_path)
	if error:
		result.fail(
			ERR_QUERY_FAILED,
			"%s: \"%s\". Error: %s \"%s\"" %
			[error_description, dir_path, error, error_string(error)])
	return result
