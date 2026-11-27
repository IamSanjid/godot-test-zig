extends SceneTree

## Headless live tests for the extension loaded by `test_extension.gdextension`.
## Run with `godot --headless --path godot-test --script res://run_tests.gd`;
## the process exit code is the test result.

const SUITES = [
	preload("res://tests/classdb.gd"),
	preload("res://tests/collections.gd"),
	preload("res://tests/methods.gd"),
	preload("res://tests/ownership.gd"),
	preload("res://tests/properties.gd"),
	preload("res://tests/signals.gd"),
]


func _initialize() -> void:
	# Run after the first idle frame: the scene tree root is ready then, so a
	# suite adding a node triggers `_enter_tree`/`_ready` synchronously.
	_run.call_deferred()


func _run() -> void:
	var failure_count := 0
	for suite_script in SUITES:
		var suite = suite_script.new()
		suite.run()
		for failure in suite.failures:
			printerr("LIVE TEST FAILED [%s]: %s" % [suite.suite_name(), failure])
			failure_count += 1

	if failure_count == 0:
		print("LIVE TESTS PASSED")
		quit(0)
		return
	quit(1)
