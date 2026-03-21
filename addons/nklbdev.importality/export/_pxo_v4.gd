@tool
extends "_pxo_v3.gd"
## Represents a Pixelorama project stored in a pxo v4 (or later) file.

func _is_version_supported(version: int) -> bool:
	return version >= 4
