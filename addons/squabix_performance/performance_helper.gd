class_name PerformanceHelper
extends Object

static var nodestr_root: Node


static func is_object_class(object: Object, class_string: StringName) -> bool:
	if class_string.is_empty():
		return false

	if object == null:
		return false

	if object.is_class(class_string):
		return true

	var current_script: Script = object.get_script()
	while current_script != null:
		if current_script.get_global_name() == class_string:
			return true
		current_script = current_script.get_base_script()

	return false


static func find_children_of_class(parent: Node, class_string: StringName, include_parent := false) -> Array[Node]:
	if not is_instance_valid(parent) or class_string.is_empty():
		return []
	var children: Array[Node] = []

	if include_parent and is_object_class(parent, class_string):
		children.append(parent)

	for child in parent.get_children():
		if is_object_class(child, class_string):
			children.append(child)

		var grandchildren := find_children_of_class(child, class_string)
		if grandchildren.is_empty():
			continue

		children.append_array(grandchildren)

	return children


static func node_error(error: String, ...injections: Array) -> void:
	for i in len(injections):
		var element: Variant = injections[i]
		if not is_instance_valid(element) or not element is Node:
			continue
		injections[i] = nodestr(element)
	push_error(error % injections)


static func get_tree() -> SceneTree:
	var main_loop := Engine.get_main_loop()
	if main_loop == null:
		push_error("Cannot get tree root without main loop")
		return null
	return main_loop as SceneTree


static func nodestr(node: Node) -> String:
	if not is_instance_valid(node) or not is_instance_valid(node.get_tree().root):
		return "Invalid Node (%s)" % node

	var root: Node
	if not is_instance_valid(nodestr_root):
		if not is_instance_valid(node.get_tree().root):
			node_error("Cannot find root for %s", node)
			return "Invalid Node (%s)" % node
		root = node.get_tree().root
	elif nodestr_root.get_path_to(node).is_empty():
		node_error("Cannot find root for %s", node)
		return "Invalid Node (%s)" % node
	else:
		root = nodestr_root

	return "%s (%s)" % [node.name, root.get_path_to(node)]


static func safe_free(node: Variant) -> bool:
	if node == null:
		return false
	if not node is Node:
		return false
	if not is_instance_valid(node):
		return false
	if not node.has_method(&"queue_free"):
		return false
	node.queue_free()
	return true


static func set_visibility_deep(node: Node, to: bool, exclude: Array[Node] = []) -> void:
	if not is_instance_valid(node) or node in exclude:
		return
	if node is CanvasItem or node is Node3D:
		node.visible = to
	for child in node.get_children():
		set_visibility_deep(child, to, exclude)
