extends SceneTree
## Prints the number of shifts, for checks/autoplay.sh.

func _initialize() -> void:
	print("LEVELS ", load("res://scripts/levels.gd").count())
	quit(0)
