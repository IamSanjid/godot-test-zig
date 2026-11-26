extends "res://tests/test_case.gd"

## Typed container properties of the LiveTypedNode extension class: declared
## `Property` container hints, engine-side typing, and value round-trips.
## Also covers owned `ownership.Ref(Resource)` property storage, including a
## resource produced by the generated engine method `Resource.duplicate`.


func run() -> void:
	check(ClassDB.class_exists("LiveResource"), "ClassDB.class_exists(\"LiveResource\")")
	if not check(ClassDB.class_exists("LiveTypedNode"), "ClassDB.class_exists(\"LiveTypedNode\")"):
		return

	var node: Object = ClassDB.instantiate("LiveTypedNode")
	if not check(node != null, "ClassDB.instantiate(\"LiveTypedNode\") returns an instance"):
		return

	_check_property_metadata(node)
	_check_numbers(node)
	_check_resources(node)
	_check_scores(node)
	_check_ref_properties(node)

	if is_instance_valid(node):
		node.free()


func _property_info(object: Object, property_name: String) -> Dictionary:
	for property_info in object.get_property_list():
		var info: Dictionary = property_info
		if String(info.get("name", "")) == property_name:
			return info
	return {}


func _check_property_metadata(node: Object) -> void:
	var numbers := _property_info(node, "numbers")
	if check(not numbers.is_empty(), "property list has 'numbers'"):
		check(int(numbers.get("type", TYPE_NIL)) == TYPE_ARRAY, "property 'numbers' is TYPE_ARRAY")
		check(int(numbers.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_ARRAY_TYPE, "property 'numbers' hint is PROPERTY_HINT_ARRAY_TYPE")
		check(String(numbers.get("hint_string", "")) == "2/0:", "property 'numbers' hint_string is \"2/0:\"")

	var resources := _property_info(node, "resources")
	if check(not resources.is_empty(), "property list has 'resources'"):
		check(int(resources.get("type", TYPE_NIL)) == TYPE_ARRAY, "property 'resources' is TYPE_ARRAY")
		check(int(resources.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_ARRAY_TYPE, "property 'resources' hint is PROPERTY_HINT_ARRAY_TYPE")
		check(String(resources.get("hint_string", "")) == "24/17:LiveResource", "property 'resources' hint_string is \"24/17:LiveResource\"")

	var scores := _property_info(node, "scores")
	if check(not scores.is_empty(), "property list has 'scores'"):
		check(int(scores.get("type", TYPE_NIL)) == TYPE_DICTIONARY, "property 'scores' is TYPE_DICTIONARY")
		check(int(scores.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_DICTIONARY_TYPE, "property 'scores' hint is PROPERTY_HINT_DICTIONARY_TYPE")
		check(String(scores.get("hint_string", "")) == "4/0:;2/0:", "property 'scores' hint_string is \"4/0:;2/0:\"")


func _check_numbers(node: Object) -> void:
	var numbers: Array = node.get("numbers")
	check(numbers.get_typed_builtin() == TYPE_INT, "numbers is a typed int array")
	check(numbers == [1, 2, 3], "numbers contains [1, 2, 3]")

	var changed: Array[int] = [4, 5, 6]
	node.set("numbers", changed)

	var updated: Array = node.get("numbers")
	check(updated.get_typed_builtin() == TYPE_INT, "numbers stays a typed int array after set")
	check(updated == [4, 5, 6], "numbers round-trips [4, 5, 6]")


func _check_resources(node: Object) -> void:
	var resources: Array = node.get("resources")
	check(resources.get_typed_builtin() == TYPE_OBJECT, "resources is a typed object array")
	check(String(resources.get_typed_class_name()) == "LiveResource", "resources element class is LiveResource")

	var resource: Object = ClassDB.instantiate("LiveResource")
	if not check(resource != null, "ClassDB.instantiate(\"LiveResource\") returns an instance"):
		return

	var resources_with_resource: Array = resources.duplicate()
	resources_with_resource.push_back(resource)
	node.set("resources", resources_with_resource)

	var updated: Array = node.get("resources")
	check(updated.size() == 1, "resources round-trips one LiveResource")
	check(updated.get_typed_builtin() == TYPE_OBJECT, "resources stays a typed object array after set")
	check(String(updated.get_typed_class_name()) == "LiveResource", "resources element class stays LiveResource after set")


func _check_scores(node: Object) -> void:
	var scores: Dictionary = node.get("scores")
	check(scores.get_typed_key_builtin() == TYPE_STRING, "scores is a typed String-keyed dictionary")
	check(scores.get_typed_value_builtin() == TYPE_INT, "scores is a typed int-valued dictionary")
	check(scores.get("kills") == 3, "scores[\"kills\"] is 3")

	var changed: Dictionary[String, int] = {"kills": 7}
	node.set("scores", changed)

	var updated: Dictionary = node.get("scores")
	check(updated.get_typed_key_builtin() == TYPE_STRING, "scores stays typed after set")
	check(updated.get_typed_value_builtin() == TYPE_INT, "scores value type stays typed after set")
	check(updated.get("kills") == 7, "scores round-trips kills = 7")


func _check_ref_properties(node: Object) -> void:
	var resource_info := _property_info(node, "resource")
	if check(not resource_info.is_empty(), "property list has 'resource'"):
		check(int(resource_info.get("type", TYPE_NIL)) == TYPE_OBJECT, "property 'resource' is TYPE_OBJECT")
		check(int(resource_info.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_RESOURCE_TYPE, "property 'resource' hint is PROPERTY_HINT_RESOURCE_TYPE")
		check(String(resource_info.get("hint_string", "")) == "Resource", "property 'resource' hint_string is \"Resource\"")
		check(String(resource_info.get("class_name", "")) == "Resource", "property 'resource' class_name is \"Resource\"")

	var resource: Object = node.get("resource")
	check(resource != null, "resource is non-null after onInit")
	check(resource is Resource, "resource is a Resource")

	var resource_copy: Object = node.get("resource_copy")
	check(resource_copy != null, "resource_copy from generated Ref return is non-null")
	check(resource_copy is Resource, "resource_copy from Resource.duplicate is a Resource")
	check(resource_copy != resource, "resource_copy is a distinct duplicate")

	var replacement := Resource.new()
	node.set("resource", replacement)

	var updated: Object = node.get("resource")
	check(updated != null, "resource set/read round-trip is non-null")
	check(updated is Resource, "resource round-trip value is a Resource")
	check(updated == replacement, "resource round-trips the Resource set from GDScript")
