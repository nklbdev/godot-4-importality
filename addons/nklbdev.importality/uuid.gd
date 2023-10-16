extends RefCounted

const __BYTE_MASK: int = 0b11111111
static var __default_rng: RandomNumberGenerator = RandomNumberGenerator.new()

var __bytes: PackedByteArray

func _init(rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = __default_rng
		rng.randomize()
	const size: int = 16
	__bytes.resize(size)
	for i in size:
		__bytes[i] = rng.randi() & __BYTE_MASK
	__bytes[6] = __bytes[6] & 0x0f | 0x40
	__bytes[8] = __bytes[8] & 0x3f | 0x80

func to_bytes() -> PackedByteArray:
	return __bytes.duplicate()

func is_equal(other: Object) -> bool:
	return \
		other != null and \
		get_script() == other.get_script() and \
		__bytes == other.__bytes

func _to_string() -> String:
	return '%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x' % Array(__bytes)
