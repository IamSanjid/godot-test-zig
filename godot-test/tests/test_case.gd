extends RefCounted

## Shared base for live test suites. Each suite owns its failure list; the
## runner reports those failures with the suite's script basename.


var failures: Array[String] = []


func check(condition: bool, message: String) -> bool:
	if condition:
		return true
	failures.append(message)
	return false


func suite_name() -> String:
	var suite_script := get_script() as Script
	if suite_script == null:
		return "unknown"
	return suite_script.resource_path.get_file().get_basename()
