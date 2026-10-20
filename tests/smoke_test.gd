extends SceneTree
## Loads the main scene and starts every shift once. Run:
##   godot --headless --path . --script res://tests/smoke_test.gd

func _initialize() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.save_enabled = false
	root.add_child(game)
	_run.call_deferred(game)


func _run(game) -> void:
	await process_frame
	var levels = load("res://scripts/levels.gd")
	for i in levels.count():
		game.start_level(i)
		await physics_frame
		await process_frame
	print("SMOKE OK")
	quit(0)
