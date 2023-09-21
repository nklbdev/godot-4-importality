@tool

class XMLNode:
	extends RefCounted
	var text: String
	func _init(text: String) -> void:
		self.text = text
	func _get_solid_text() -> String:
		assert(false, "This method is abstract and must be overriden in derived class")
		return ""
	func get_elements(text: String) -> Array[XMLNodeElement]:
		assert(false, "This method is abstract and must be overriden in derived class")
		return []
	func _dump(target: PackedStringArray, indent: String, level: int) -> void:
		target.append(indent.repeat(level) + _get_solid_text())

class XMLNodeParent:
	extends XMLNode
	var children: Array[XMLNode]
	func _init(text: String) -> void:
		super(text)
	func _get_opening_tag() -> String: return ""
	func _get_closing_tag() -> String: return ""
	func _get_solid_text() -> String:
		assert(false, "This method is abstract and must be overriden in derived class")
		return ""
	func _dump_children(target: PackedStringArray, indent: String, level: int) -> void:
		for child in children:
			child._dump(target, indent, level)
	func _dump(target: PackedStringArray, indent: String, level: int) -> void:
		var tag_indent: String = indent.repeat(level)
		if children.is_empty():
			target.append(tag_indent + _get_solid_text())
		else:
			target.append(tag_indent + _get_opening_tag())
			_dump_children(target, indent, level + 1)
			target.append(tag_indent + _get_closing_tag())
	func get_elements(text: String) -> Array[XMLNodeElement]:
		var result: Array[XMLNodeElement]
		result.append_array(children.filter(func(n): return n is XMLNodeElement and n.text == text))
		return result

class XMLNodeRoot:
	extends XMLNodeParent
	func _init() -> void:
		super("")
	func dump_to_string(indent: String = " ", new_line: String = "\n") -> String:
		var target: PackedStringArray
		_dump_children(target, indent, 0)
		return new_line.join(target)
	func dump_to_buffer(indent: String = " ", new_line: String = "\n") -> PackedByteArray:
		return dump_to_string(indent, new_line).to_utf8_buffer()
	func dump_to_file(absolute_file_path: String, indent: String = " ", new_line: String = "\n") -> void:
		DirAccess.make_dir_recursive_absolute(absolute_file_path.get_base_dir())
		var file: FileAccess = FileAccess.open(absolute_file_path, FileAccess.WRITE)
		file.store_string(dump_to_string(indent, new_line))
		file.close()

class XMLNodeElement:
	extends XMLNodeParent
	var attributes: Dictionary
	var closed: bool
	func _init(text: String, closed: bool = false) -> void:
		super(text)
		self.closed = closed
	func _get_attributes_string() -> String:
		return "".join(attributes.keys().map(func(k): return " %s=\"%s\"" % [k, attributes[k]]))
	func _get_opening_tag() -> String: return "<%s%s>" % [text, _get_attributes_string()]
	func _get_closing_tag() -> String:return "</%s>" % [text]
	func _get_solid_text() -> String: return "<%s%s/>" % [text, _get_attributes_string()]
	func get_string(attribute: String) -> String:
		return attributes[attribute]
	func get_int(attribute: String) -> int:
		return attributes[attribute].to_int()
	func get_int_encoded_hex_color(attribute: String, with_alpha: bool = false) -> Color:
		var arr: PackedByteArray
		arr.resize(4)
		arr.encode_u32(0, attributes[attribute].to_int())
		if not with_alpha:
			arr.resize(3)
		return Color(arr.hex_encode())
	func get_vector2i(attribute_x: String, attribute_y: String) -> Vector2i:
		return Vector2i(attributes[attribute_x].to_int(), attributes[attribute_y].to_int())
	func get_rect2i(attribute_position_x: String, attribute_position_y: String, attribute_size_x: String, attribute_size_y: String) -> Rect2i:
		return Rect2i(
			attributes[attribute_position_x].to_int(),
			attributes[attribute_position_y].to_int(),
			attributes[attribute_size_x].to_int(),
			attributes[attribute_size_y].to_int())
	func get_bool(attribute: String) -> bool:
		var raw_value: String = attributes[attribute]
		if raw_value.is_empty():
			return false
		if raw_value.is_valid_int():
			return bool(raw_value.to_int())
		if raw_value.nocasecmp_to("True") == 0:
			return true
		if raw_value.nocasecmp_to("False") == 0:
			return false
		push_warning("Failed to parse bool value from string: \"%s\", returning false..." % [raw_value])
		return false

class XMLNodeText:
	extends XMLNode
	func _init(text: String) -> void:
		super(text)
	func _get_solid_text() -> String: return text.strip_edges()
	func _dump(target: PackedStringArray, indent: String, level: int) -> void:
		var text: String = _get_solid_text()
		if not text.is_empty():
			target.append(indent.repeat(level) + text)

class XMLNodeCData:
	extends XMLNode
	func _init(text: String) -> void:
		super(text)
	func _get_solid_text() -> String: return "<![CDATA[%s]]>" % [text]

class XMLNodeComment:
	extends XMLNode
	func _init(text: String) -> void:
		super(text)
	func _get_solid_text() -> String: return "<!%s>" % [text]

class XMLNodeUnknown:
	extends XMLNode
	func _init(text: String) -> void:
		super(text)
	func _get_solid_text() -> String: return "<%s>" % [text]

static func parse_file(path: String) -> XMLNodeRoot:
	var parser = XMLParser.new()
	parser.open(path)
	return __parse_xml(parser)

static func parse_buffer(buffer: PackedByteArray) -> XMLNodeRoot:
	var parser = XMLParser.new()
	parser.open_buffer(buffer)
	return __parse_xml(parser)

static func parse_string(xml_string: String) -> XMLNodeRoot:
	return parse_buffer(xml_string.to_utf8_buffer())

static func __parse_xml(parser: XMLParser) -> XMLNodeRoot:
	var root = XMLNodeRoot.new()
	var stack: Array[XMLNode] = [root]
	while parser.read() != ERR_FILE_EOF:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node: XMLNode = XMLNodeElement.new(parser.get_node_name())
				for attr_idx in parser.get_attribute_count():
					node.attributes[parser.get_attribute_name(attr_idx)] = \
						parser.get_attribute_value(attr_idx)
				stack.back().children.push_back(node)
				if not parser.is_empty():
					stack.push_back(node)
			XMLParser.NODE_ELEMENT_END:
				if stack.size() < 2:
					push_warning("Extra end tag found")
				else:
					stack.pop_back()
			XMLParser.NODE_TEXT:
				var text: String = parser.get_node_data().strip_edges()
				if not text.is_empty():
					stack.back().children.push_back(XMLNodeText.new(text))
			XMLParser.NODE_CDATA:
				stack.back().children.push_back(XMLNodeCData.new(parser.get_node_data()))
			XMLParser.NODE_NONE:
				push_error("Incorrect XML node found")
			XMLParser.NODE_UNKNOWN:
				stack.back().children.push_back(XMLNodeUnknown.new(parser.get_node_name()))
			XMLParser.NODE_COMMENT:
				stack.back().children.push_back(XMLNodeComment.new(parser.get_node_name()))
	return root
