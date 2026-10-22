extends SceneTree
## Headless Control/font export only; never captures or controls a desktop window.
const Shop = preload("res://scripts/shop.gd")
const State = preload("res://scripts/shop_state.gd")
const Trips = preload("res://scripts/parallel_expeditions.gd")
const Compare = preload("res://tests/state_compare.gd")
const Currency = preload("res://scripts/currency_text.gd")
const FONT = preload("res://assets/fonts/pretendard/Pretendard-Regular.otf")
var server: TextServer
var shop: Control
var panel: Window
var output := "res://.verification/expedition-cards-20261013"
var texture_paths := {}
var glyph_cache := {}
var serial := 0
var commands := []
var nodes := []
var strict_export_bounds := true
var allow_text_clipping := false

func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless")
	set_meta("isolated_preview", true)
	server = TextServerManager.get_primary_interface()
	if "--inspect-api" in OS.get_cmdline_user_args():
		for method in server.get_method_list():
			if str(method.name).begins_with("font_get_glyph") or method.name in ["font_get_texture_image", "font_render_glyph", "font_render_range", "shaped_text_get_glyphs", "shaped_text_get_object_rect"]: print(JSON.stringify(method))
		for method in TextParagraph.new().get_method_list():
			if str(method.name).begins_with("get_line") or method.name in ["add_string", "add_object"]: print(JSON.stringify(method))
		var paragraph := TextParagraph.new()
		paragraph.add_string("주재료 이슬풀 1~3개", FONT, 16)
		paragraph.width = 100
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		print("GLYPHS ", server.shaped_text_get_glyphs(paragraph.get_line_rid(0)))
		var rid: RID = FONT.get_rids()[0]
		var glyph := server.font_get_glyph_index(rid, 16, "주".unicode_at(0), 0)
		server.font_render_glyph(rid, Vector2i(16, 0), glyph)
		var image := server.font_get_texture_image(rid, Vector2i(16, 0), server.font_get_glyph_texture_idx(rid, Vector2i(16, 0), glyph))
		print("GLYPH IMAGE ", image.get_size(), " uv ", server.font_get_glyph_uv_rect(rid, Vector2i(16, 0), glyph), " size ", server.font_get_glyph_size(rid, Vector2i(16, 0), glyph), " offset ", server.font_get_glyph_offset(rid, Vector2i(16, 0), glyph))
		var object_paragraph := TextParagraph.new()
		object_paragraph.add_string("매회 ", FONT, 16)
		object_paragraph.add_object("coin", Vector2(18, 18), INLINE_ALIGNMENT_CENTER)
		object_paragraph.add_string(" 8", FONT, 16)
		print("OBJECT ", object_paragraph.get_line_object_rect(0, "coin"), " ascent ", object_paragraph.get_line_ascent(0), " descent ", object_paragraph.get_line_descent(0), " size ", object_paragraph.get_size())
		quit()
	else:
		call_deferred("run")

func rectangle(value: Rect2) -> Array: return [value.position.x, value.position.y, value.size.x, value.size.y]
func vector(value: Vector2) -> Array: return [value.x, value.y]

func save_image(value: Image, prefix: String) -> String:
	serial += 1
	var path := output.path_join("textures/%s-%04d.png" % [prefix, serial])
	assert(value != null and not value.is_empty())
	assert(value.save_png(path) == OK)
	return ProjectSettings.globalize_path(path)

func texture_path(texture: Texture2D) -> String:
	var key := texture.get_instance_id()
	if not texture_paths.has(key): texture_paths[key] = save_image(texture.get_image(), "texture")
	return texture_paths[key]

func effective_color(node: CanvasItem, boundary: CanvasItem) -> Color:
	var color := node.self_modulate * node.modulate
	var parent := node.get_parent()
	while parent is CanvasItem:
		color *= parent.modulate
		if parent == boundary: break
		parent = parent.get_parent()
	return color

func style(stylebox: StyleBox, rect: Rect2, tint: Color) -> void:
	if stylebox is StyleBoxEmpty: return
	if stylebox is StyleBoxLine:
		var line_rect := rect
		if stylebox.vertical:
			line_rect.position.x += (rect.size.x - stylebox.thickness) / 2
			line_rect.size.x = stylebox.thickness
		else:
			line_rect.position.y += (rect.size.y - stylebox.thickness) / 2
			line_rect.size.y = stylebox.thickness
		commands.append({"kind": "solid", "rect": rectangle(line_rect), "color": (stylebox.color * tint).to_html()})
		return
	assert(stylebox is StyleBoxFlat, "The card preview exports actual flat styles, not guessed skins")
	commands.append({"kind": "style", "rect": rectangle(rect), "color": (stylebox.bg_color * tint).to_html(), "border_color": (stylebox.border_color * tint).to_html(), "border_widths": [stylebox.get_border_width(SIDE_LEFT), stylebox.get_border_width(SIDE_TOP), stylebox.get_border_width(SIDE_RIGHT), stylebox.get_border_width(SIDE_BOTTOM)], "radius": stylebox.get_corner_radius(CORNER_TOP_LEFT), "draw_center": stylebox.draw_center})

func picture(texture: Texture2D, rect: Rect2, tint: Color, contain: bool = true) -> void:
	if texture == null or not rect.has_area(): return
	if contain:
		var scaled := texture.get_size() * minf(rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
		rect = Rect2(rect.position + (rect.size - scaled) / 2, scaled)
	commands.append({"kind": "image", "rect": rectangle(rect), "image": texture_path(texture), "color": tint.to_html(), "filter": "nearest"})

func has_property(node: Object, key: String) -> bool:
	for entry in node.get_property_list():
		if entry.name == key: return true
	return false

func paragraph(node: Control, font: Font, font_size: int, width: float, text: String, currency_source: Variant = null) -> TextParagraph:
	var result := TextParagraph.new()
	result.width = width
	result.break_flags = TextServer.BREAK_MANDATORY
	if has_property(node, "autowrap_mode"):
		if node.autowrap_mode == TextServer.AUTOWRAP_WORD: result.break_flags |= TextServer.BREAK_WORD_BOUND
		elif node.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART: result.break_flags |= TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		elif node.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY: result.break_flags |= TextServer.BREAK_GRAPHEME_BOUND
	if has_property(node, "autowrap_trim_flags"): result.break_flags |= int(node.autowrap_trim_flags)
	result.line_spacing = node.get_theme_constant("line_separation" if node is RichTextLabel else "line_spacing")
	if node is Currency:
		var source: String = node.source_text if currency_source == null else str(currency_source)
		var start := 0
		var coin := 0
		for match in Currency.pattern().search_all(source):
			result.add_string(source.substr(start, match.get_start() - start), font, font_size)
			result.add_object("coin-%d" % coin, Vector2(node.currency_size, node.currency_size), INLINE_ALIGNMENT_CENTER)
			result.add_string(" " + match.get_string(1), font, font_size)
			start = match.get_end()
			coin += 1
		result.add_string(source.substr(start), font, font_size)
	else:
		result.add_string(text, font, font_size)
	return result

func glyph_image(glyph: Dictionary) -> Dictionary:
	var rid: RID = glyph.font_rid
	var size := Vector2i(glyph.font_size, 0)
	var key := "%s-%d-%d" % [rid.get_id(), glyph.font_size, glyph.index]
	if glyph_cache.has(key): return glyph_cache[key]
	server.font_render_glyph(rid, size, glyph.index)
	var extent := server.font_get_glyph_size(rid, size, glyph.index)
	var uv := server.font_get_glyph_uv_rect(rid, size, glyph.index)
	if not uv.has_area() or extent.x <= 0 or extent.y <= 0: return {}
	var atlas := server.font_get_texture_image(rid, size, server.font_get_glyph_texture_idx(rid, size, glyph.index))
	var cropped := atlas.get_region(Rect2i(uv))
	var result := {"image": save_image(cropped, "glyph"), "size": extent, "offset": server.font_get_glyph_offset(rid, size, glyph.index)}
	glyph_cache[key] = result
	return result

func text_commands(node: Control, font: Font, font_size: int, text: String, rect: Rect2, color: Color, alignment: int, vertical: int) -> Dictionary:
	# Native RichTextLabel shapes each newline paragraph independently and
	# reserves an empty line for empty paragraphs. Do the same in file export.
	var paragraphs := []
	var source: String = node.source_text if node is Currency else text
	if node is RichTextLabel and source.contains("\n"):
		for part in source.split("\n", true):
			if part.is_empty(): paragraphs.append({"shape": null, "empty": true})
			else: paragraphs.append({"shape": paragraph(node, font, font_size, rect.size.x, part, part), "empty": false})
	else:
		paragraphs.append({"shape": paragraph(node, font, font_size, rect.size.x, text), "empty": false})
	var lines := []
	var total := Vector2.ZERO
	var spacing: float = node.get_theme_constant("line_separation" if node is RichTextLabel else "line_spacing")
	for entry in paragraphs:
		if entry.empty:
			lines.append({"shape": null, "line": 0, "size": Vector2(0, font.get_height(font_size)), "empty": true})
		else:
			var shaped: TextParagraph = entry.shape
			for index in shaped.get_line_count(): lines.append({"shape": shaped, "line": index, "size": shaped.get_line_size(index), "empty": false})
	for item in lines:
		total.x = maxf(total.x, item.size.x)
		total.y += item.size.y + spacing
	if not lines.is_empty(): total.y -= spacing
	var y := rect.position.y
	if vertical == VERTICAL_ALIGNMENT_CENTER: y += (rect.size.y - total.y) / 2
	elif vertical == VERTICAL_ALIGNMENT_BOTTOM: y += rect.size.y - total.y
	var actual_lines: int = node.get_line_count() if node is Label or node is RichTextLabel else lines.size()
	assert(lines.size() == actual_lines, "Exported font lines match actual control lines: %s (%d/%d)" % [text, lines.size(), actual_lines])
	var line_data := []
	for line in lines.size():
		var item: Dictionary = lines[line]
		var shaped: TextParagraph = item.shape
		var extent: Vector2 = item.size
		if node is RichTextLabel:
			# Use cached native offsets, including the ledger's empty paragraphs.
			y = rect.position.y + node.get_line_offset(line)
		var x := rect.position.x
		if alignment == HORIZONTAL_ALIGNMENT_CENTER: x += (rect.size.x - extent.x) / 2
		elif alignment == HORIZONTAL_ALIGNMENT_RIGHT: x += rect.size.x - extent.x
		if item.empty:
			line_data.append({"baseline": y + font.get_ascent(font_size), "rect": rectangle(Rect2(x, y, extent.x, extent.y)), "empty_paragraph": true, "native_line_offset": node.get_line_offset(line)})
			y += extent.y + spacing
			continue
		var shaped_line: int = item.line
		var baseline := y + shaped.get_line_ascent(shaped_line)
		var pen := x
		for glyph: Dictionary in server.shaped_text_get_glyphs(shaped.get_line_rid(shaped_line)):
			for repeat in int(glyph.repeat):
				if glyph.font_rid.is_valid() and int(glyph.index) > 0:
					var cached := glyph_image(glyph)
					if not cached.is_empty():
						var at: Vector2 = Vector2(pen, baseline) + glyph.offset + cached.offset
						commands.append({"kind": "glyph", "rect": rectangle(Rect2(at, cached.size)), "image": cached.image, "color": color.to_html(), "filter": "linear"})
				pen += float(glyph.advance)
		for object in shaped.get_line_objects(shaped_line):
			var area := shaped.get_line_object_rect(shaped_line, object)
			area.position += Vector2(x, y)
			picture(Currency.COIN, area, Color.WHITE)
		var record := {"baseline": baseline, "rect": rectangle(Rect2(x, y, extent.x, extent.y)), "range": vector(Vector2(shaped.get_line_range(shaped_line)))}
		if node is RichTextLabel: record.native_line_offset = node.get_line_offset(line)
		line_data.append(record)
		y += extent.y + spacing
	if not allow_text_clipping:
		assert(total.x <= rect.size.x + 1 and total.y <= rect.size.y + 1, "Text and inline coins fit their actual control: " + text)
	return {"text": text, "font": font.resource_path, "font_size": font_size, "lines": line_data, "actual_line_count": actual_lines, "extent": vector(total)}

func button_content(button: Button, rect: Rect2, box: StyleBox) -> Dictionary:
	# Match Godot 4.6 Button's largest-style margins and icon/text content areas.
	if button.has_meta("_centered_content_styles"):
		var helper := load("res://scripts/centered_button_content.gd")
		var actual: Dictionary = helper.rects(button)
		assert(actual.fits, "The production centered content must fit its real button")
		for key in ["inner", "text", "icon"]:
			var area: Rect2 = actual[key]
			area.position += rect.position
			actual[key] = area
		return actual
	var margins := [0.0, 0.0, 0.0, 0.0]
	for side in range(4): margins[side] = box.get_margin(side)
	if button.get_theme_constant("align_to_largest_stylebox"):
		for part in ["normal", "hover", "pressed", "disabled"]:
			for side in range(4): margins[side] = maxf(margins[side], button.get_theme_stylebox(part).get_margin(side))
	var inner := Rect2(rect.position + Vector2(margins[SIDE_LEFT], margins[SIDE_TOP]), rect.size - Vector2(margins[SIDE_LEFT] + margins[SIDE_RIGHT], margins[SIDE_TOP] + margins[SIDE_BOTTOM]))
	var text_rect := inner
	var icon_rect := Rect2()
	if button is CheckButton:
		# Godot 4.6 reserves the fitted toggle plus h_separation on the right.
		assert(not button.is_layout_rtl())
		var toggle: Dictionary = check_content(button, rect)
		text_rect.size.x -= toggle.reserved.x + maxi(0, button.get_theme_constant("h_separation"))
	if button.icon != null:
		var icon_extent := button.icon.get_size()
		if button.expand_icon: icon_extent *= minf(inner.size.x / icon_extent.x, inner.size.y / icon_extent.y)
		var max_width := button.get_theme_constant("icon_max_width")
		if max_width > 0 and icon_extent.x > max_width: icon_extent *= float(max_width) / icon_extent.x
		icon_extent = icon_extent.round()
		var offset := Vector2(0, (inner.size.y - icon_extent.y) / 2)
		if button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER: offset.x = (inner.size.x - icon_extent.x) / 2
		elif button.icon_alignment == HORIZONTAL_ALIGNMENT_RIGHT: offset.x = inner.size.x - icon_extent.x
		icon_rect = Rect2((inner.position + offset).floor(), icon_extent)
		if button.icon_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			var gap := icon_extent.x + maxi(0, button.get_theme_constant("h_separation"))
			text_rect.size.x -= gap
			if button.icon_alignment == HORIZONTAL_ALIGNMENT_LEFT: text_rect.position.x += gap
	return {"inner": inner, "text": text_rect, "icon": icon_rect}

func fitted_check_size(button: CheckButton, extent: Vector2) -> Vector2:
	var maximum := button.get_theme_constant("icon_max_width")
	if maximum > 0 and extent.x > maximum: extent *= float(maximum) / extent.x
	return extent

func check_content(button: CheckButton, rect: Rect2) -> Dictionary:
	# Native theme textures stay untouched; see scene/gui/check_button.cpp 4.6.
	assert(not button.is_layout_rtl())
	var suffix := "_disabled" if button.disabled else ""
	var on: Texture2D = button.get_theme_icon("checked" + suffix)
	var off: Texture2D = button.get_theme_icon("unchecked" + suffix)
	var reserved := fitted_check_size(button, on.get_size().max(off.get_size()))
	var texture := on if button.button_pressed else off
	var normal: StyleBox = button.get_theme_stylebox("normal")
	var position := rect.position + Vector2(rect.size.x - reserved.x - normal.get_margin(SIDE_RIGHT), (rect.size.y - reserved.y) / 2 + button.get_theme_constant("check_v_offset"))
	var color_key := "button_checked_color" if button.button_pressed else "button_unchecked_color"
	return {"texture": texture, "reserved": reserved, "rect": Rect2(position, fitted_check_size(button, texture.get_size())), "tint": button.get_theme_color(color_key)}

func slider_commands(slider: HSlider, rect: Rect2, tint: Color) -> Dictionary:
	# Match 4.6 Slider NOTIFICATION_DRAW for the actual LTR/no-tick settings.
	assert(not slider.is_layout_rtl() and slider.tick_count <= 1)
	var box: StyleBox = slider.get_theme_stylebox("slider")
	var fill: StyleBox = slider.get_theme_stylebox("grabber_area")
	var grabber: Texture2D = slider.get_theme_icon("grabber" if slider.editable else "grabber_disabled")
	var width := int(rect.size.x)
	var height := int(rect.size.y)
	var widget_height := int(box.get_minimum_size().y)
	var grabber_width := int(grabber.get_width())
	var grabber_height := int(grabber.get_height())
	var centered := slider.get_theme_constant("center_grabber") != 0
	var travel := width - (0 if centered else grabber_width)
	var shift := -int(grabber_width / 2.0) if centered else 0
	var ratio: float = slider.get_as_ratio()
	var track := Rect2(rect.position + Vector2(0, int((height - widget_height) / 2.0)), Vector2(width, widget_height))
	style(box, track, tint)
	var fill_rect := track
	fill_rect.size.x = int(travel * ratio + int(grabber_width / 2.0) + shift)
	if fill_rect.has_area(): style(fill, fill_rect, tint)
	var grabber_rect := Rect2(rect.position + Vector2(int(ratio * travel + shift), int(height / 2.0) - int(grabber_height / 2.0) + slider.get_theme_constant("grabber_offset")), grabber.get_size())
	picture(grabber, grabber_rect, tint, false)
	return {"value": slider.value, "ratio": ratio, "track_rect": rectangle(track), "fill_rect": rectangle(fill_rect), "grabber_rect": rectangle(grabber_rect), "native_geometry_source": "https://raw.githubusercontent.com/godotengine/godot/4.6/scene/gui/slider.cpp"}

func export_node(node: Node, card: Control, clip: Rect2 = Rect2()) -> void:
	if node is CanvasItem and (not node.is_visible_in_tree() or effective_color(node, card).a <= 0): return
	if not clip.has_area(): clip = Rect2(Vector2.ZERO, card.size)
	var child_clip := clip
	if node is Control:
		var rect: Rect2 = node.get_global_rect()
		rect.position -= card.global_position
		if strict_export_bounds: assert(Rect2(Vector2.ZERO, card.size).grow(1).encloses(rect), "Every visible exported control fits the actual card: %s %s" % [card.get_path_to(node), rect])
		if not rect.intersects(clip): return
		if node.clip_contents: child_clip = child_clip.intersection(rect)
		var first_command := commands.size()
		var tint := effective_color(node, card)
		var info := {"name": str(card.get_path_to(node)), "type": node.get_class(), "rect": rectangle(rect), "tooltip": node.tooltip_text, "focus_mode": node.focus_mode, "mouse_filter": node.mouse_filter}
		if node is PanelContainer or node is Panel:
			style(node.get_theme_stylebox("panel"), rect, tint)
		elif node is TextureRect:
			picture(node.texture, rect, tint)
		elif node is ColorRect:
			commands.append({"kind": "solid", "rect": rectangle(rect), "color": (node.color * tint).to_html()})
		elif node is HSeparator or node is VSeparator:
			style(node.get_theme_stylebox("separator"), rect, tint)
		elif node is VScrollBar or node is HScrollBar:
			style(node.get_theme_stylebox("scroll"), rect, tint)
			var track := rect
			var fraction: float = clampf(node.page / maxf(1, node.max_value - node.min_value), 0, 1)
			var travel: float = clampf((node.value - node.min_value) / maxf(1, node.max_value - node.min_value - node.page), 0, 1)
			if node is VScrollBar:
				track.size.y *= fraction
				track.position.y += (rect.size.y - track.size.y) * travel
			else:
				track.size.x *= fraction
				track.position.x += (rect.size.x - track.size.x) * travel
			style(node.get_theme_stylebox("grabber"), track, tint)
		elif node is ProgressBar:
			style(node.get_theme_stylebox("background"), rect, tint)
			var amount: float = clampf((node.value - node.min_value) / (node.max_value - node.min_value), 0, 1)
			var filled := rect
			filled.size.x *= amount
			if amount > 0: style(node.get_theme_stylebox("fill"), filled, tint)
			info.value = node.value
		elif node is HSlider:
			info.merge(slider_commands(node, rect, tint))
		elif node is Button:
			var part := "disabled" if node.disabled else "pressed" if node.button_pressed else "normal"
			var box: StyleBox = node.get_theme_stylebox(part)
			if not node.flat: style(box, rect, tint)
			var content := button_content(node, rect, box)
			var inner: Rect2 = content.text
			if node.icon != null:
				var icon_color := tint
				var icon_key := "icon_disabled_color" if node.disabled else "icon_pressed_color" if node.button_pressed else "icon_normal_color"
				if node.has_theme_color(icon_key): icon_color *= node.get_theme_color(icon_key)
				elif node.disabled: icon_color.a *= 0.4
				picture(node.icon, content.icon, icon_color)
			var color_key := "font_disabled_color" if node.disabled else "font_pressed_color" if node.button_pressed else "font_color"
			info.merge(text_commands(node, node.get_theme_font("font"), node.get_theme_font_size("font_size"), node.text, inner, node.get_theme_color(color_key) * tint, node.alignment, VERTICAL_ALIGNMENT_CENTER))
			info.disabled = node.disabled
			info.flat = node.flat
			info.selected_underline = node.get_meta("selected_underline", false)
			info.content_rect = rectangle(content.inner)
			info.icon_rect = rectangle(content.icon)
			info.text_rect = rectangle(inner)
			if node is CheckButton:
				var toggle: Dictionary = check_content(node, rect)
				picture(toggle.texture, toggle.rect, toggle.tint * tint, false)
				info.toggle_rect = rectangle(toggle.rect)
				info.native_geometry_source = "https://raw.githubusercontent.com/godotengine/godot/4.6/scene/gui/check_button.cpp"
		elif node is Label:
			info.merge(text_commands(node, node.get_theme_font("font"), node.get_theme_font_size("font_size"), node.text, rect, node.get_theme_color("font_color") * tint, node.horizontal_alignment, node.vertical_alignment))
		elif node is RichTextLabel:
			var plain: String = node.get_parsed_text()
			var alignment: int = node.money_alignment if node is Currency else HORIZONTAL_ALIGNMENT_LEFT
			info.merge(text_commands(node, node.get_theme_font("normal_font"), node.get_theme_font_size("normal_font_size"), plain, rect, node.get_theme_color("default_color") * tint, alignment, VERTICAL_ALIGNMENT_TOP))
		for index in range(first_command, commands.size()): commands[index]["clip"] = rectangle(child_clip)
		nodes.append(info)
	for child in node.get_children(): export_node(child, card, child_clip)

func fixture() -> RefCounted:
	var state := State.new()
	state.gold = 1000000
	var p: RefCounted = state.progression
	p.reputation = 10000
	p.expedition_unlocked = true
	p.expedition_count = 1
	p.expansion.regions = ["forest_edge"]
	Trips.ensure(p)
	p.expansion.cycles.forest_edge.merge({"id": 1, "fee": 8, "paid": true, "running": false, "elapsed": 0.0, "duration": 70.0, "rewards": {"dewgrass": 3}}, true)
	p.expansion.pending = {"dewgrass": 3}
	p.expansion.materials.dewgrass = p.expansion.special_capacity()
	return state

func run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(output.path_join("textures")) == OK)
	shop = Shop.new()
	root.add_child(shop)
	shop.set_process(false)
	shop.open_management()
	panel = shop.management
	panel.set_process(false)
	var cases := []
	for item in [{"id": "forest-open-wait", "region": "forest_edge", "open": false, "label": "숲 가장자리 · 열린 대기"}, {"id": "star-garden-locked", "region": "star_garden", "open": false, "label": "별의 정원 · 잠김"}, {"id": "forest-details-open", "region": "forest_edge", "open": true, "label": "숲 가장자리 · 상세 열림"}]:
		shop.state = fixture()
		var before: Dictionary = shop.state.to_data().duplicate(true)
		panel.select_page(panel.EXPEDITIONS)
		panel.refresh()
		var row: Dictionary = panel.rows[item.region]
		row.toggle.set_pressed(item.open)
		for frame in range(4): await process_frame
		commands = []
		nodes = []
		export_node(row.panel, row.panel)
		assert(row.icon.size == Vector2(48, 48) and row.primary_icon.size == Vector2(32, 32))
		assert(row.title.get_theme_font_size("font_size") == 18 and row.summary.get_theme_font_size("normal_font_size") == 16)
		assert(row.detail_box.visible == item.open and not row.detail.visible)
		assert(Compare.equivalent(before, shop.state.to_data()), "The file preview cannot modify economic/model/RNG/saved progress")
		cases.append({"id": item.id, "label": item.label, "region": item.region, "size": vector(row.panel.size), "commands": commands.duplicate(true), "nodes": nodes.duplicate(true), "details_open": item.open, "pending": shop.state.progression.expansion.pending.duplicate(true)})
	var file := FileAccess.open(output.path_join("cards.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"verification": "Headless actual Control rectangles and TextServer glyph cache; file compositing, not GPU pixels or desktop capture", "management_width": panel.size.x, "font": ProjectSettings.globalize_path(FONT.resource_path), "cases": cases}, "\t"))
	panel.free()
	shop.free()
	print("EXPEDITION CARD EXPORT PASS: three actual new-card states, real rectangles/styles/images/Pretendard glyphs and line counts; 18/16px type, 48/32px icons; economy/save/RNG unchanged; headless only: ", ProjectSettings.globalize_path(output))
	quit()
