extends SceneTree
## Records the actual UI from an isolated economy; never reads/writes player saves.
const ShopScene = preload("res://scenes/shop.tscn")


func _initialize() -> void:
	set_meta("isolated_preview", true)
	call_deferred("_record")


func _record() -> void:
	var game := ShopScene.instantiate()
	root.add_child(game)
	root.always_on_top = false
	root.title = "약초 수급 미리보기 · 테스트"
	assert(game.test_mode)
	game.art.set_process(false)
	game.herb_plant.set_process(false)
	game.state.herbs = 0
	game.state.level = 5
	game.state.gold = 24
	DirAccess.make_dir_recursive_absolute("res://.verification/herb-frames")
	for index in range(140):
		game._advance_game(0.1)
		game._update_interface()
		game.art._process(0.1)
		game.herb_plant._process(0.1)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.verification/herb-frames/frame-%03d.png" % index)
	assert(game.state.total_sold == 2 and game.state.gold == 36)
	assert(game.income.gold == 12)
	print("HERB PREVIEW PASS: zero initial herbs -> three free harvests -> two real sales; isolated from player saves")
	quit()
