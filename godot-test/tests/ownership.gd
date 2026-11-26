extends "res://tests/test_case.gd"

## Runtime behavior of the manual ownership handles. `Node` is not
## `RefCounted`, so `Node.construct()` returns `ownership.Owned(Node)`; the
## `LiveOwnedNode` fixture destroys one constructed node with `Owned.deinit()`
## and hands another to itself with `Owned.take()`. This suite checks both
## outcomes and that freeing the fixture also frees the taken child.


func run() -> void:
	if not check(ClassDB.class_exists("LiveOwnedNode"), "ClassDB.class_exists(\"LiveOwnedNode\")"):
		return

	var node: Node = ClassDB.instantiate("LiveOwnedNode")
	if not check(node != null, "ClassDB.instantiate(\"LiveOwnedNode\") returns an instance"):
		return

	_check_deinit(node)
	var child := _check_take(node)

	if is_instance_valid(node):
		node.free()
	check(not is_instance_valid(node), "LiveOwnedNode fixture is freed")
	if child != null:
		check(not is_instance_valid(child), "Owned.take child is freed together with its parent")


## `Owned.deinit` destroyed the unparented constructed node: its recorded
## instance id must no longer resolve to a live object.
func _check_deinit(node: Node) -> void:
	var destroyed_id := int(node.get("destroyed_id"))
	if not check(destroyed_id != 0, "Owned.deinit recorded the constructed node's instance id"):
		return
	check(instance_from_id(destroyed_id) == null, "Owned.deinit destroyed the unparented constructed Node")


## `Owned.take` handed the second constructed node to the fixture as a child.
func _check_take(node: Node) -> Node:
	if not check(node.get_child_count() == 1, "Owned.take handed exactly one constructed Node to the fixture"):
		return null

	var child: Node = node.get_child(0)
	check(child.get_class() == "Node", "taken child is a plain engine Node")
	check(child.get_parent() == node, "taken child is parented to the LiveOwnedNode fixture")
	check(String(child.name) == "owned_child", "taken child keeps the name set before the handoff")
	return child
