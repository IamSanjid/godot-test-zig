extends "res://tests/test_case.gd"

## Property metadata and value round-trips for the LiveNode extension class.


func run() -> void:
	var node: Object = ClassDB.instantiate("LiveNode")
	if not check(node != null, "ClassDB.instantiate(\"LiveNode\") returns an instance"):
		return

	_check_property_metadata(node)
	_check_values(node)

	if is_instance_valid(node):
		node.free()


func _check_property_metadata(node: Object) -> void:
	var live_group := false
	var health := {}
	var label := {}
	var mode := {}

	for property_info in node.get_property_list():
		var info: Dictionary = property_info
		var info_name := String(info.get("name", ""))
		if info_name == "Live":
			live_group = int(info.get("type", TYPE_NIL)) == TYPE_NIL and (int(info.get("usage", 0)) & PROPERTY_USAGE_GROUP) != 0
		elif info_name == "health":
			health = info
		elif info_name == "label":
			label = info
		elif info_name == "mode":
			mode = info

	check(live_group, "property list has group 'Live' (TYPE_NIL, PROPERTY_USAGE_GROUP)")

	check(not health.is_empty(), "property list has 'health'")
	if not health.is_empty():
		check(int(health.get("type", TYPE_NIL)) == TYPE_INT, "property 'health' is TYPE_INT")
		check(int(health.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_RANGE, "property 'health' hint is PROPERTY_HINT_RANGE")
		check(String(health.get("hint_string", "")) == "0,100", "property 'health' hint_string is \"0,100\"")

	check(not label.is_empty(), "property list has 'label'")
	if not label.is_empty():
		check(int(label.get("type", TYPE_NIL)) == TYPE_STRING, "property 'label' is TYPE_STRING")

	check(not mode.is_empty(), "property list has 'mode'")
	if not mode.is_empty():
		var mode_usage := int(mode.get("usage", 0))
		check(int(mode.get("type", TYPE_NIL)) == TYPE_INT, "property 'mode' is TYPE_INT")
		check(int(mode.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_ENUM, "property 'mode' hint is PROPERTY_HINT_ENUM")
		check(String(mode.get("hint_string", "")) == "Idle:0,Running:3", "property 'mode' hint_string is \"Idle:0,Running:3\"")
		check((mode_usage & PROPERTY_USAGE_CLASS_IS_ENUM) != 0, "property 'mode' usage has PROPERTY_USAGE_CLASS_IS_ENUM")
		check(String(mode.get("class_name", "")) == "LiveNode.Mode", "property 'mode' class_name is \"LiveNode.Mode\"")


func _check_values(node: Object) -> void:
	check(node.get("health") == 100, "health default value is 100")
	check(node.get("label") == "live", "label initializer value is 'live'")
	check(node.get("mode") == 0, "mode default value is idle (0)")

	node.set("health", 42)
	check(node.get("health") == 42, "health round-trips 42")
	node.set("label", "changed")
	check(node.get("label") == "changed", "label round-trips 'changed'")
	node.set("mode", 3)
	check(node.get("mode") == 3, "mode round-trips running (3)")
