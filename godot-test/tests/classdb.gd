extends "res://tests/test_case.gd"

## ClassDB surface of the LiveNode extension class: registration,
## instantiation, signal metadata, and integer constants.


func run() -> void:
	if not check(ClassDB.class_exists("LiveNode"), "ClassDB.class_exists(\"LiveNode\")"):
		return

	var node: Object = ClassDB.instantiate("LiveNode")
	if not check(node != null, "ClassDB.instantiate(\"LiveNode\") returns an instance"):
		return
	check(node is Node, "LiveNode instance is a Node")

	_check_signal()
	_check_constants()

	node.free()
	check(not is_instance_valid(node), "LiveNode instance is freed")


func _check_signal() -> void:
	var signal_list := ClassDB.class_get_signal_list("LiveNode", true)
	var pinged := {}
	for signal_info in signal_list:
		var info: Dictionary = signal_info
		if String(info.get("name", "")) == "pinged":
			pinged = info
			break

	if not check(not pinged.is_empty(), "signal list has 'pinged'"):
		return
	var args: Array = pinged.get("args", [])
	if not check(args.size() == 1, "signal 'pinged' has exactly one argument"):
		return
	var health_arg: Dictionary = args[0]
	check(String(health_arg.get("name", "")) == "health", "signal 'pinged' argument is named 'health'")
	check(int(health_arg.get("type", TYPE_NIL)) == TYPE_INT, "signal 'pinged' argument 'health' is TYPE_INT")


func _check_constants() -> void:
	var constants: PackedStringArray = ClassDB.class_get_integer_constant_list("LiveNode", true)
	check(constants.has("MAX_HEALTH"), "integer constant 'MAX_HEALTH' is registered")
	check(constants.has("IDLE"), "integer constant 'IDLE' (Mode.idle) is registered")
	check(constants.has("RUNNING"), "integer constant 'RUNNING' (Mode.running = 3) is registered")
	check(ClassDB.class_get_integer_constant("LiveNode", "MAX_HEALTH") == 100, "constant 'MAX_HEALTH' is 100")
	check(ClassDB.class_get_integer_constant("LiveNode", "RUNNING") == 3, "constant 'RUNNING' is 3")
