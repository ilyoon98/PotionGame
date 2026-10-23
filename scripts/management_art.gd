extends RefCounted
## Management actions share the shop's plum, brass and ivory pixel palette.
const ROOT := "res://assets/management_v1/"
const GENERATED := ["flow", "filter", "employee", "visitors", "basic", "expedition"]
static var reputation_texture: AtlasTexture
static var readable_icons := {}

static func readable_icon(texture: Texture2D) -> Texture2D:
	# Trim display-only padding; source art and other game views keep their regions.
	if texture == null or texture is AtlasTexture: return texture
	var key := texture.get_instance_id()
	if not readable_icons.has(key):
		var image := texture.get_image()
		var used := image.get_used_rect() if image != null else Rect2i()
		if used.has_area():
			var framed := AtlasTexture.new()
			framed.atlas = texture
			framed.region = Rect2(used)
			framed.filter_clip = true
			readable_icons[key] = framed
		else: readable_icons[key] = texture
	return readable_icons[key]
const DESCRIPTIONS := {
	"flow": "자동 운영 · 톱니바퀴와 물약",
	"cauldron": "솥 강화 · 제조 시간 단축",
	"garden": "약초 화분 강화 · 수확과 보관량 증가",
	"sales_counter": "판매대 강화 · 손님 거래 간격 단축",
	"filter": "정밀 여과기 · 깔때기와 수집 병",
	"employee": "판매 보조 고용 · 상점 앞치마",
	"visitors": "손님과 명성 · 손님과 금빛 별",
	"basic": "기본 레시피 · 물약 제조서",
	"expedition": "숲 가장자리 원정 · 숲 지도와 나침반",
	"journey": "원정 진행 · 숲 지도와 나침반",
	"reputation": "명성 · 금빛 별과 보라색 월계수",
	"aging_cask": "숙성 · 벽 선반 숙성통",
	"keeper": "주인공 · 대기",
	"keeper_sleep": "주인공 · 수면",
	"keeper_faint": "주인공 · 기절",
	"regular_traveler": "단골 · 여행자",
	"regular_mage": "단골 · 여마법사",
	"regular_elf": "단골 · 엘프",
	"regular_rogue": "단골 · 고양이 도적",
	"souvenir_compass": "단골 기념품 · 낡은 나침반",
	"souvenir_bookmark": "단골 기념품 · 별무늬 책갈피",
	"souvenir_leaf_brooch": "단골 기념품 · 잎사귀 브로치",
	"souvenir_silver_bell": "단골 기념품 · 작은 은방울",
	"decor_teacup": "판매대 소품 · 작은 찻잔",
	"decor_dried_vase": "판매대 소품 · 말린 꽃병",
}
## First frame (32×48) of each approved keeper pose sheet (16×4 grid).
const KEEPER_POSES := {"keeper": "idle", "keeper_sleep": "sleep", "keeper_faint": "faint"}
## F22 regulars rows reuse the first idle frame of each approved customer sheet.
const CUSTOMER_SHEETS := {"regular_traveler": "traveler", "regular_mage": "mage", "regular_elf": "elf", "regular_rogue": "rogue"}
static var keeper_icons := {}


static func has_icon(id: String) -> bool:
	return DESCRIPTIONS.has(id)


static func icon(id: String) -> Texture2D:
	if id == "reputation":
		if reputation_texture == null:
			reputation_texture = AtlasTexture.new()
			reputation_texture.atlas = load(ROOT + "reputation_icon.png")
			reputation_texture.region = Rect2(43, 75, 1181, 1179)
			reputation_texture.filter_clip = true
		return reputation_texture
	if id == "sales_counter": return load("res://assets/content_expansion_v1/equipment/sales_counter_basic.png")
	if id == "cauldron": return load("res://assets/cauldron_48.png")
	if id == "aging_cask": return load("res://assets/pixel_v1/props/aging_cask.png")
	# F22 souvenirs approved 2026-10-23, published by tools/publish_f22_souvenirs_v1.py.
	if id.begins_with("souvenir_"): return load("res://assets/pixel_v1/souvenirs/%s.png" % id)
	# F23 counter props are small on a 32x32 canvas; show a 16x16 crop so the
	# 48px list icon is an exact 3x, the same scale as the workshop.
	if id.begins_with("decor_"):
		if not keeper_icons.has(id):
			var sheet: Texture2D = load("res://assets/pixel_v1/decor/%s.png" % id)
			var used := sheet.get_image().get_used_rect()
			var corner := (used.position + used.size / 2 - Vector2i(8, 8)).clamp(Vector2i.ZERO, Vector2i(16, 16))
			var crop := AtlasTexture.new()
			crop.atlas = sheet
			crop.region = Rect2(Vector2(corner), Vector2(16, 16))
			crop.filter_clip = true
			keeper_icons[id] = crop
		return keeper_icons[id]
	if KEEPER_POSES.has(id) or CUSTOMER_SHEETS.has(id):
		if not keeper_icons.has(id):
			var frame := AtlasTexture.new()
			var sheet: String = "keeper/%s" % KEEPER_POSES[id] if KEEPER_POSES.has(id) else "%s/idle" % CUSTOMER_SHEETS[id]
			frame.atlas = load("res://assets/pixel_v1/characters/%s-native.png" % sheet)
			frame.region = Rect2(0, 0, 32, 48)
			frame.filter_clip = true
			keeper_icons[id] = frame
		return keeper_icons[id]
	if id == "garden":
		var texture := AtlasTexture.new()
		texture.atlas = load("res://assets/herb_growth.png")
		texture.region = Rect2(0, 40, 32, 40)
		return texture
	if id == "journey": id = "expedition"
	var path := ROOT + id + "_icon.png"
	# Newly supplied management art may still be awaiting import.
	return load(path) if id in GENERATED and ResourceLoader.exists(path) else null
