@tool
extends ImageFormatLoaderExtension

const _ProjectSetting = preload("project_setting.gd")

func get_project_settings() -> Array[_ProjectSetting]:
	assert(false, "This method is abstract and must be overriden.")
	return []
