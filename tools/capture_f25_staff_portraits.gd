extends SceneTree
## F25 staff layout D preview: management staff rows with candidate portraits.
## Isolated preview; candidate sprites are loaded from art/ only for this capture.
const Shop = preload("res://scripts/shop.gd")
const SPRITES := "res://art/mockups/f25-staff-concept-v2/sprites/"
const OUT := "res://.verification/f25-staff-portraits-20261105/"
func _initialize() -> void:
	set_meta("isolated_preview", true); call_deferred("run")
func run() -> void:
	var shop := Shop.new(); root.add_child(shop)
	await process_frame
	shop.set_process(false); shop.art.set_process(false); shop.open_management()
	var panel = shop.management; panel.set_process(false)
	panel.select_page(panel.UPGRADES); panel.refresh()
	for i in 3: await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var first: Dictionary = panel.rows["employee"]
	panel.scroll.ensure_control_visible(panel.rows["expedition_guide"].icon)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	panel.get_texture().get_image().save_png(OUT + "before.png")
	for pair in [["employee", "staff_sales_assistant"], ["cultivation_assistant", "staff_cultivation_assistant"], ["brewing_assistant", "staff_brewing_assistant"], ["expedition_guide", "staff_expedition_guide"]]:
		var image := Image.load_from_file(ProjectSettings.globalize_path(SPRITES + pair[1] + ".png"))
		var icon: TextureRect = panel.rows[pair[0]].icon
		print(pair[0], " icon size ", icon.size, " image ", image.get_size())
		icon.texture = ImageTexture.create_from_image(image)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	panel.get_texture().get_image().save_png(OUT + "candidate-D.png")
	print("CAPTURED")
	quit(0)
