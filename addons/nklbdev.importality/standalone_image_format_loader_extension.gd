@tool
extends ImageFormatLoaderExtension

const _Setting = preload("setting.gd")

func get_settings() -> Array[_Setting]:
	assert(false, "This method is abstract and must be overriden.")
	return []
