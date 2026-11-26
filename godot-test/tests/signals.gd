extends "res://tests/test_case.gd"

## Typed signal emission of the LiveNode extension class. The fixture emits
## from `_ready`; the receiver is connected before `add_child`, so borrowed
## String/Array/Variant arguments and an owned heap-builtin argument are
## delivered to a GDScript callback while the node enters the tree.


func run() -> void:
	if not check(ClassDB.class_exists("LiveNode"), "ClassDB.class_exists(\"LiveNode\")"):
		return

	var node: Node = ClassDB.instantiate("LiveNode")
	if not check(node != null, "ClassDB.instantiate(\"LiveNode\") returns an instance"):
		return

	# GDScript lambdas capture variables by value, so record into the captured
	# array by reference instead of reassigning it.
	var received: Array = []
	var receiver := func(text: String, numbers: Array, payload: Variant, transform: Transform3D, count: int) -> void:
		received.assign([text, numbers, payload, transform, count])
	if not check(node.connect("signaled", receiver) == OK, "LiveNode 'signaled' connects before entering the tree"):
		node.free()
		return

	var tree := Engine.get_main_loop() as SceneTree
	if not check(tree != null and tree.root != null, "signals suite runs inside a SceneTree"):
		node.free()
		return

	tree.root.add_child(node) # `_ready` emits the signal synchronously.
	tree.root.remove_child(node)
	node.free()

	if not check(received.size() == 5, "signal 'signaled' delivers five arguments"):
		return
	check(typeof(received[0]) == TYPE_STRING, "signal 'signaled' text argument is a String")
	check(received[0] == "borrowed", "signal 'signaled' text argument is \"borrowed\"")
	check(typeof(received[1]) == TYPE_ARRAY, "signal 'signaled' numbers argument is an Array")
	check(received[1] == [5, 6], "signal 'signaled' numbers argument is [5, 6]")
	check(received[2] == 42, "signal 'signaled' payload argument is 42")
	check(typeof(received[3]) == TYPE_TRANSFORM3D, "signal 'signaled' transform argument is a Transform3D")
	check(received[3] == Transform3D.IDENTITY, "signal 'signaled' transform argument is the identity transform")
	check(received[4] == 7, "signal 'signaled' count argument is 7")
