extends Control
## Actual single representatives; only the three small detail buttons accept input.
const Status = preload("res://scripts/management_status.gd")
const Content = preload("res://scripts/shop_content.gd")
const ItemArt = preload("res://scripts/item_art.gd")
const Layout = preload("res://scripts/workshop_layout.gd")
const POT := Rect2(111, 66, 108, 24)
const HERBS := [Rect2(12, 144, 96, 96)]
const TRIPS := [Rect2(471, 42, 48, 60)]
const CAPTION_SIZE := 14
const HERB_SUMMARY := Rect2(10, 116, 76, 18)
## F21 keeper stat row, directly under the cauldron panel and above the cauldron.
const KEEPER_PANEL := Rect2(111, 92, 108, 22)
const KEEPER_CAPTION_SIZE := 12
## Fatigue band colors from the approved palette: rested, normal, tired, exhausted.
const FATIGUE_COLORS := [[80.0, "DE7356"], [60.0, "F4AC68"], [40.0, "E9B95F"], [0.0, "718C59"]]
const DETAIL_RECTS := Layout.BUTTONS
var host: Control
var herb_ids: Array[String] = ["herb"]
var region_ids: Array[String] = ["forest_edge"]
var herbs: Array[Dictionary] = []
var trips: Array[Dictionary] = []
var craft := {}
var active_herbs := 0
var active_regions := 0
var herb_summary := "재배 대기"
var herb_caption := "재배 대기"
var region_summary := "원정 대기"
var growth_texture: Texture2D
var detail_buttons := {}
var icons := {}
var font: Font

static func click_regions() -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for rect in DETAIL_RECTS.values(): result.append(rect)
	return result

func _ready() -> void:
	size = Vector2(Layout.SIZE.x, Layout.ART_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 3
	font = host.body_font
	for category in ["potions", "materials", "regions"]:
		for source in Content.DATA[category]: icons[source.id] = ItemArt.icon(source.id)
	for key in DETAIL_RECTS:
		var rect: Rect2i = DETAIL_RECTS[key]
		var button := Button.new()
		button.position = rect.position
		button.size = rect.size
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.icon = preload("res://assets/icons/search.svg")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 12)
		for part in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("49364f") if part == "hover" else Color("281f33")
			style.border_color = Color("efc77c") if part in ["hover", "focus"] else Color("766180")
			style.set_border_width_all(1)
			style.set_content_margin_all(2)
			button.add_theme_stylebox_override(part, style)
		button.pressed.connect(func(): host.open_management_page({"potions": host.ManagementPanel.POTIONS, "herbs": host.ManagementPanel.HERBS, "expeditions": host.ManagementPanel.EXPEDITIONS}[key]))
		add_child(button)
		detail_buttons[key] = button
	refresh()

func refresh() -> void:
	if host == null: return
	var state: RefCounted = host.state
	visible = state.window_mode == state.WindowMode.WORKSHOP
	if not visible: return
	herbs.assign([Status.material(state, "herb")])
	trips.assign([Status.region(state, "forest_edge")])
	var counts := Status.activity_counts(state)
	active_herbs = counts.herbs
	active_regions = counts.regions
	herb_summary = "%d종 재배 중" % active_herbs if active_herbs > 0 else "재배 대기"
	herb_caption = "채집 중" if herbs[0].running else "보관 가득" if herbs[0].status.contains("보관") else "재배 대기"
	region_summary = "%d곳 탐사 중" % active_regions if active_regions > 0 else "원정 대기"
	craft = Status.crafting(state)
	# The frame reads exactly the same paused or growing cycle as the herb bar.
	growth_texture = ItemArt.growth_frame("herb", herbs[0].progress)
	if not detail_buttons.is_empty():
		detail_buttons.potions.tooltip_text = "포션 전체 보기 · %s · %s\n주인공 %s" % [craft.name, craft.status, keeper_text(state.keeper)]
		detail_buttons.herbs.tooltip_text = "약초 전체 보기 · %s · 기본 약초 %s" % [herb_summary, herbs[0].status]
		detail_buttons.expeditions.tooltip_text = "원정 전체 보기 · %s · 숲 가장자리 %s" % [region_summary, trips[0].status]
	queue_redraw()

func _process(_delta: float) -> void: refresh()

func _backing(rect: Rect2) -> void:
	draw_rect(rect, Color("281f33"))
	draw_rect(rect, Color("766180"), false, 1.0)

func _bar(rect: Rect2, fraction: float, running: bool, color: Color) -> void:
	draw_rect(rect, Color("49364f"))
	var width := floorf(clampf(fraction, 0, 1) * rect.size.x)
	if width > 0: draw_rect(Rect2(rect.position, Vector2(width, rect.size.y)), color if running else Color("81718a"))
	if not running:
		for x in [rect.end.x - 3, rect.end.x - 1]: draw_rect(Rect2(x, rect.position.y - 2, 1, 2), Color("efd7a2"))

func _caption(text: String, rect: Rect2, alignment: int = HORIZONTAL_ALIGNMENT_LEFT, font_size: int = CAPTION_SIZE) -> void:
	draw_string(font, rect.position + Vector2(0, font.get_ascent(font_size)), text, alignment, rect.size.x, font_size, Color("efc77c"))

func _caption_command(text: String, rect: Rect2, font_size: int = CAPTION_SIZE) -> Dictionary:
	return {"kind": "caption", "text": text, "rect": rect, "font_size": font_size, "baseline": font.get_ascent(font_size)}

static func fatigue_color(fatigue: float) -> Color:
	for row in FATIGUE_COLORS:
		if fatigue >= float(row[0]) - 0.000001: return Color(row[1])
	return Color(FATIGUE_COLORS[-1][1])

## "상쾌 · 피로 12" while awake; sleep or faint replaces the condition word.
static func keeper_text(keeper: RefCounted) -> String:
	var word: String = "기절" if keeper.state == "fainted" else "수면" if keeper.state == "asleep" else keeper.condition()
	return "%s · 피로 %d" % [word, int(floor(keeper.fatigue))]

func render_commands() -> Array[Dictionary]:
	# The file proof consumes these same commands; no separate mock state/layout.
	var result: Array[Dictionary] = []
	if craft.is_empty(): return result
	result.append({"kind": "backing", "rect": POT})
	result.append({"kind": "texture", "texture": icons[craft.icon], "rect": Rect2(135, 69, 14, 16)})
	result.append(_caption_command(craft.status, Rect2(151, 67, 66, 18)))
	result.append({"kind": "bar", "rect": Rect2(151, 87, 63, 2), "progress": craft.progress, "running": craft.running, "color": Color("e9b95f")})
	var keeper: RefCounted = host.state.keeper
	result.append({"kind": "backing", "rect": KEEPER_PANEL, "role": "keeper_panel"})
	var keeper_caption := _caption_command(keeper_text(keeper), Rect2(KEEPER_PANEL.position.x + 5, KEEPER_PANEL.position.y + 1, KEEPER_PANEL.size.x - 10, 16), KEEPER_CAPTION_SIZE)
	keeper_caption["role"] = "keeper_caption"
	result.append(keeper_caption)
	result.append({"kind": "bar", "rect": Rect2(KEEPER_PANEL.position.x + 5, KEEPER_PANEL.end.y - 5, KEEPER_PANEL.size.x - 10, 2), "progress": keeper.fatigue / 100.0, "running": true, "color": fatigue_color(keeper.fatigue), "role": "keeper_fatigue"})
	result.append({"kind": "backing", "rect": Layout.rect("herbPanel")})
	result.append(_caption_command(herb_summary, HERB_SUMMARY))
	result.append({"kind": "bar", "rect": Rect2(12, 135, 68, 2), "progress": herbs[0].progress, "running": herbs[0].running, "color": Color("718c59")})
	for line in [["%d곳" % active_regions if active_regions > 0 else "원정",39],["탐사 중" if active_regions > 0 else "대기",53]]:
		var caption := _caption_command(line[0],Rect2(Layout.POSTER_INTERIOR.position.x,line[1],Layout.POSTER_INTERIOR.size.x,14),11)
		caption["role"] = "expedition_caption"
		caption["alignment"] = HORIZONTAL_ALIGNMENT_CENTER
		result.append(caption)
	result.append(_caption_command("재고 %d / %d" % [host.state.stock,host.state.capacity()], Rect2(375,150,84,20)))
	if host.art.sale_flash > 0:
		result.append(_caption_command(("+%d G · 선호" if host.art.preferred_sale else "+%d G") % host.art.motion.earned_gold,Rect2(375,173,84,18)))

	return result

func _draw() -> void:
	for command in render_commands():
		match command.kind:
			"backing": _backing(command.rect)
			"texture": draw_texture_rect(command.texture, command.rect, false)
			"caption": _caption(command.text, command.rect, command.get("alignment",HORIZONTAL_ALIGNMENT_LEFT),command.font_size)
			"bar": _bar(command.rect, command.progress, command.running, command.color)
