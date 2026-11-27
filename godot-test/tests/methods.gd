extends "res://tests/test_case.gd"

## Engine methods of the LiveMethods extension class. A call on a statically
## typed instance compiles to the validated ptrcall path; `Object.call` and
## `Callable` take the Variant path. The suite pins the registered signature
## metadata, the borrowed raw and owned `Ref` results, and the adapter error
## reports for bad argument counts and types.


func run() -> void:
	if not check(ClassDB.class_exists("LiveMethods"), "ClassDB.class_exists(\"LiveMethods\")"):
		return

	var node: LiveMethods = ClassDB.instantiate("LiveMethods")
	if not check(node != null, "ClassDB.instantiate(\"LiveMethods\") returns an instance"):
		return

	_check_metadata()
	_check_calls(node)
	_check_converter(node)
	_check_resources(node)
	# A rejected GDScript call aborts only the function that made it, so every
	# bad call runs in its own helper and the fixture must stay usable.
	_check_error_reports(node)
	check(node.add(2, 3) == 5, "fixture still answers after the rejected calls")

	node.free()
	check(not is_instance_valid(node), "LiveMethods fixture is freed")


func _method_info(method_name: String) -> Dictionary:
	for method_info in ClassDB.class_get_method_list("LiveMethods", true):
		var info: Dictionary = method_info
		if String(info.get("name", "")) == method_name:
			return info
	return {}


func _check_metadata() -> void:
	for method_name in ["add", "echo_variant", "label", "make_owned_resource", "make_resource", "shift", "version"]:
		check(not _method_info(method_name).is_empty(), "method list has '%s'" % method_name)

	var add := _method_info("add")
	if check(not add.is_empty(), "method list has 'add'"):
		check((int(add.get("flags", 0)) & METHOD_FLAG_NORMAL) != 0, "add is a normal method")
		var args: Array = add.get("args", [])
		if check(args.size() == 2, "add declares two arguments"):
			check(String(args[0].get("name", "")) == "a", "add argument 0 is named 'a'")
			check(String(args[1].get("name", "")) == "b", "add argument 1 is named 'b'")
			check(int(args[0].get("type", TYPE_NIL)) == TYPE_INT, "add argument 'a' is TYPE_INT")
		check(int(add.get("return", {}).get("type", TYPE_NIL)) == TYPE_INT, "add returns TYPE_INT")

	var label := _method_info("label")
	if check(not label.is_empty(), "method list has 'label'"):
		check((int(label.get("flags", 0)) & METHOD_FLAG_CONST) != 0, "label is a const method")
		check(int(label.get("return", {}).get("type", TYPE_NIL)) == TYPE_STRING, "label returns TYPE_STRING")

	var version := _method_info("version")
	if check(not version.is_empty(), "method list has 'version'"):
		check((int(version.get("flags", 0)) & METHOD_FLAG_STATIC) != 0, "version is a static method")
		check((version.get("args", []) as Array).is_empty(), "version takes no engine argument")
		check(int(version.get("return", {}).get("type", TYPE_NIL)) == TYPE_INT, "version returns TYPE_INT")

	var make_resource := _method_info("make_resource")
	if check(not make_resource.is_empty(), "method list has 'make_resource'"):
		var resource_return: Dictionary = make_resource.get("return", {})
		check(int(resource_return.get("type", TYPE_NIL)) == TYPE_OBJECT, "make_resource returns TYPE_OBJECT")
		check(String(resource_return.get("class_name", "")) == "Resource", "make_resource returns a Resource")

	var make_owned_resource := _method_info("make_owned_resource")
	if check(not make_owned_resource.is_empty(), "method list has 'make_owned_resource'"):
		var owned_return: Dictionary = make_owned_resource.get("return", {})
		check(int(owned_return.get("type", TYPE_NIL)) == TYPE_OBJECT, "make_owned_resource returns TYPE_OBJECT")
		check(String(owned_return.get("class_name", "")) == "Resource", "make_owned_resource returns a Resource")

	var echo_variant := _method_info("echo_variant")
	if check(not echo_variant.is_empty(), "method list has 'echo_variant'"):
		# An untyped Variant slot is registered as TYPE_NIL plus
		# PROPERTY_USAGE_NIL_IS_VARIANT; without the flag GDScript reads the
		# result as void and refuses to use the return value.
		var echo_return: Dictionary = echo_variant.get("return", {})
		check(int(echo_return.get("type", -1)) == TYPE_NIL, "echo_variant return is untyped")
		check((int(echo_return.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT) != 0, "echo_variant return is marked Variant")
		var echo_args: Array = echo_variant.get("args", [])
		if check(echo_args.size() == 1, "echo_variant declares one argument"):
			check(String(echo_args[0].get("name", "")) == "value", "echo_variant argument is named 'value'")
			check((int(echo_args[0].get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT) != 0, "echo_variant argument is marked Variant")

	var shift := _method_info("shift")
	if check(not shift.is_empty(), "method list has 'shift'"):
		var shift_args: Array = shift.get("args", [])
		if check(shift_args.size() == 1, "shift declares one argument"):
			check(String(shift_args[0].get("name", "")) == "duration", "shift argument is named 'duration'")
			check(int(shift_args[0].get("type", TYPE_NIL)) == TYPE_INT, "converter argument registers its engine i32")
		check(int(shift.get("return", {}).get("type", TYPE_NIL)) == TYPE_INT, "shift returns TYPE_INT")


func _check_calls(node: LiveMethods) -> void:
	check(node.add(2, 3) == 5, "direct add(2, 3) via the validated ptrcall path")
	check(node.call("add", 2, 3) == 5, "Object.call add(2, 3) via the Variant path")
	check(Callable(node, "add").call(2, 3) == 5, "Callable add(2, 3) via the Variant path")

	check(node.label() == "live_methods", "direct const label() moves the managed String through ptrcall")
	check(node.call("label") == "live_methods", "Object.call label() releases the copied String")
	check(Callable(node, "label").call() == "live_methods", "Callable label() releases the copied String")

	check(LiveMethods.version() == 7, "static version() is callable on the class name")
	check(node.version() == 7, "static version() is callable on an instance")
	check(node.call("version") == 7, "static version() dispatches through Object.call")

	var echoed: Variant = node.echo_variant(42)
	check(typeof(echoed) == TYPE_INT and echoed == 42, "direct echo_variant(42) round-trips an int Variant")
	var echoed_text: Variant = node.echo_variant("text")
	check(typeof(echoed_text) == TYPE_STRING and echoed_text == "text", "direct echo_variant(\"text\") round-trips a String Variant")
	check(node.call("echo_variant", [1, 2]) == [1, 2], "Object.call echo_variant round-trips an Array Variant")
	check(Callable(node, "echo_variant").call(42) == 42, "Callable echo_variant round-trips a Variant")


func _check_converter(node: LiveMethods) -> void:
	check(node.shift(7) == 8, "direct shift(7) decodes the converter on the ptrcall path")
	check(node.call("shift", 7) == 8, "Object.call shift(7) decodes the converter on the Variant path")
	check(Callable(node, "shift").call(11) == 12, "Callable shift(11) decodes the converter on the Variant path")


func _check_resources(node: LiveMethods) -> void:
	# Borrowed raw result: the fixture's Ref owns the reference and keeps the
	# resource alive; the returned Variant/GDScript value only retains its own.
	var borrowed: Resource = node.make_resource()
	if check(borrowed != null, "direct make_resource() returns a borrowed Resource"):
		check(borrowed.get_class() == "Resource", "borrowed make_resource() result is a plain engine Resource")
	var borrowed_call: Variant = node.call("make_resource")
	if check(borrowed_call != null, "Object.call make_resource() returns a borrowed Resource"):
		check(borrowed_call is Resource, "Object.call make_resource() result is a Resource")

	# Owned Ref result: both adapters release the returned wrapper after the
	# engine keeps its own reference, so nothing is left behind.
	var owned: Resource = node.make_owned_resource()
	if check(owned != null, "direct make_owned_resource() returns an owned Resource"):
		check(owned is Resource, "direct make_owned_resource() result is a Resource")
	var owned_call: Variant = node.call("make_owned_resource")
	if check(owned_call != null, "Object.call make_owned_resource() returns an owned Resource"):
		check(owned_call is Resource, "Object.call make_owned_resource() result is a Resource")
	var owned_callable: Variant = Callable(node, "make_owned_resource").call()
	if check(owned_callable != null, "Callable make_owned_resource() returns an owned Resource"):
		check(owned_callable is Resource, "Callable make_owned_resource() result is a Resource")


func _check_error_reports(node: LiveMethods) -> void:
	_call_too_few(node)
	_call_too_many(node)
	_call_wrong_type(node)
	check(is_instance_valid(node), "rejected calls leave the fixture alive")


func _call_too_few(node: LiveMethods) -> void:
	node.call("add", 2)


func _call_too_many(node: LiveMethods) -> void:
	node.call("add", 2, 3, 4)


func _call_wrong_type(node: LiveMethods) -> void:
	node.call("add", 2.5, 3.0)
