extends RefCounted
## F22 regulars. Every completed sale adds record points to the buying customer:
## 1 for an ordinary sale, 3 for a preferred one. Points are a record, never spent
## and never reduced. Stages unlock short stories and a souvenir kept for good.
## The record never changes prices, demand or any other part of the economy.
const Content = preload("res://scripts/shop_content.gd")
const VERSION := 1
const NORMAL_POINTS := 1
const PREFERRED_POINTS := 3
const MAX_POINTS := 1000000000
## Points needed for stages 1..4. Provisional values from the 2026-10-07 proposal.
const THRESHOLDS := [1, 15, 60, 150]
const STAGE_NAMES := ["처음 보는 손님", "첫 거래", "익숙한 손님", "단골", "믿고 찾는 손님"]
const SOUVENIR_STAGE := 3
## Draft lines; stage 1 introduces, 2 and 4 are stories, 3 gives the souvenir.
const STORIES := {
	"traveler": {
		"intro": "길 위에서 지내는 여행자예요. 먼 길을 떠나기 전 늘 체력 물약부터 챙겨요.",
		"story": "“이번엔 돌아오는 길에도 들를게요.”",
		"souvenir": "souvenir_compass", "souvenir_name": "낡은 나침반",
		"souvenir_line": "“바늘이 늘 이 가게 쪽을 가리켜요. 이제 이건 당신이 가져요.”",
		"trust": "“어느 마을에 가도 달그늘 물약 이야기를 해요. 다들 한 번 와 보고 싶대요.”",
	},
	"mage": {
		"intro": "밤마다 별을 연구하는 여마법사예요. 달빛 물약과 마나 물약을 즐겨 찾아요.",
		"story": "“오늘은 연구가 조금 더 잘 풀리겠네요.”",
		"souvenir": "souvenir_bookmark", "souvenir_name": "별무늬 책갈피",
		"souvenir_line": "“연구 노트에 꽂아 두던 책갈피예요. 고마워서 드려요.”",
		"trust": "“새 논문 감사의 글에 이 가게 이름을 적었어요. 비밀은 아니에요.”",
	},
	"elf": {
		"intro": "비 오는 날 숲에서 내려오는 엘프예요. 정화 물약을 찾아요.",
		"story": "“이 가게에서는 숲과 닮은 향이 나요.”",
		"souvenir": "souvenir_leaf_brooch", "souvenir_name": "잎사귀 브로치",
		"souvenir_line": "“숲에서 가장 오래된 나무의 잎이에요. 시들지 않아요.”",
		"trust": "“숲 친구들에게 비 오는 날엔 여기로 오라고 말해 뒀어요.”",
	},
	"rogue": {
		"intro": "밤일을 앞두고 조용히 들르는 고양이 도적이에요. 민첩 물약을 좋아해요.",
		"story": "“여기서 산 건 비밀로 해줘.”",
		"souvenir": "souvenir_silver_bell", "souvenir_name": "작은 은방울",
		"souvenir_line": "“소리가 안 나는 방울이야. 도둑한텐 딱이지만… 너한테 줄게.”",
		"trust": "“이 동네에선 일 안 해. 단골 가게가 있는 곳은 건드리지 않는 게 규칙이거든.”",
	},
}

var points := {} # customer id -> record points
## Stage when the report period started. A higher stage is "new" until the next
## period; viewing never writes here, so opening statistics stays side-effect free.
var report_stages := {}


## Customers in the current roster, in content order.
static func ids() -> Array:
	var result: Array = []
	for row in Content.CUSTOMERS:
		if row.get("enabled", true) and STORIES.has(row.id): result.append(row.id)
	return result


static func stage_for(value: int) -> int:
	var result := 0
	for threshold in THRESHOLDS:
		if value >= threshold: result += 1
	return result


static func customer_name(id: String) -> String:
	for row in Content.CUSTOMERS:
		if row.id == id: return row.name
	return id


func points_of(id: String) -> int:
	return int(points.get(id, 0))


func stage(id: String) -> int:
	return stage_for(points_of(id))


## Add the points of one completed sale. Returns the new stage event, or {}.
func record(id: String, preferred: bool) -> Dictionary:
	if not STORIES.has(id): return {}
	var before := stage(id)
	points[id] = mini(MAX_POINTS, points_of(id) + (PREFERRED_POINTS if preferred else NORMAL_POINTS))
	var after := stage(id)
	if after == before: return {}
	return {"kind": "regular", "customer": id, "stage": after, "souvenir": STORIES[id].souvenir if after == SOUVENIR_STAGE else ""}


func next_threshold(id: String) -> int:
	var current := stage(id)
	return 0 if current >= THRESHOLDS.size() else int(THRESHOLDS[current])


func has_souvenir(id: String) -> bool:
	return stage(id) >= SOUVENIR_STAGE


func souvenirs() -> Array:
	var result: Array = []
	for id in ids():
		if has_souvenir(id): result.append(STORIES[id].souvenir)
	return result


## Unlocked lines in stage order.
func lines(id: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not STORIES.has(id): return result
	var story: Dictionary = STORIES[id]
	var current := stage(id)
	if current >= 1: result.append(story.intro)
	if current >= 2: result.append(story.story)
	if current >= 3: result.append("%s · %s" % [story.souvenir_name, story.souvenir_line])
	if current >= 4: result.append(story.trust)
	return result


func is_new(id: String) -> bool:
	return stage(id) > int(report_stages.get(id, 0))


func view(id: String) -> Dictionary:
	var current := stage(id)
	var next := next_threshold(id)
	var value := points_of(id)
	var previous := 0 if current == 0 else int(THRESHOLDS[current - 1])
	return {
		"id": id, "name": customer_name(id), "points": value, "stage": current,
		"stage_name": STAGE_NAMES[current], "next": next,
		"fraction": 1.0 if next == 0 else clampf(float(value - previous) / float(next - previous), 0.0, 1.0),
		"progress": "기록 %d · 최고 단계" % value if next == 0 else "기록 %d / %d · 다음 %s" % [value, next, STAGE_NAMES[current + 1]],
		"souvenir": STORIES[id].souvenir if current >= SOUVENIR_STAGE else "",
		"souvenir_name": STORIES[id].souvenir_name,
		"lines": lines(id), "new": is_new(id),
	}


## Visits and the preferred potions the shop already makes. Operational facts are
## never hidden behind a stage; recipes not yet bought stay unnamed.
static func habits(id: String, progression: RefCounted) -> String:
	var names := PackedStringArray()
	for row in Content.CUSTOMERS:
		if row.id != id: continue
		for kind in row.preferences:
			# Health and mana are owned from the start; legacy bool names lack the "물약" suffix.
			if kind is bool: names.append(Content.potion_name(kind) + " 물약")
			elif kind is String and progression.owned.has(kind): names.append(Content.potion_name(kind))
	for kind in progression.owned:
		if kind is String and not Content.LEGACY_RECIPES.has(kind) and Content.lookup("potions", kind).get("preferred_customer", "") == id: names.append(Content.potion_name(kind))
	var shown := names.slice(0, 3)
	var preferred := "선호 물약을 아직 갖추지 않았어요" if names.is_empty() else "선호 " + ", ".join(shown) + (" 외 %d" % (names.size() - shown.size()) if names.size() > shown.size() else "")
	return "방문 %d회 · %s" % [int(progression.by_customer.get(id, 0)), preferred]


func start_report() -> void:
	for id in ids(): report_stages[id] = stage(id)


## Stage changes since the report period started, newest stage only per customer.
func report_lines() -> PackedStringArray:
	var result := PackedStringArray()
	for id in ids():
		var current := stage(id)
		if current <= int(report_stages.get(id, 0)): continue
		var line := "단골 · %s %s" % [customer_name(id), STAGE_NAMES[current]]
		if current >= SOUVENIR_STAGE and int(report_stages.get(id, 0)) < SOUVENIR_STAGE: line += " · 기념품 %s" % STORIES[id].souvenir_name
		result.append(line)
	return result


func to_data() -> Dictionary:
	return {"version": VERSION, "points": points.duplicate(), "report_stages": report_stages.duplicate()}


## Validate everything before assigning; a malformed record rejects the save.
func load_data(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION: return false
	var parsed := {}
	for key in ["points", "report_stages"]:
		var table: Variant = data.get(key)
		if not table is Dictionary: return false
		var clean := {}
		for id in table:
			var value: Variant = table[id]
			if not id is String or not STORIES.has(id): return false
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) != int(value) or value < 0: return false
			if key == "points" and value > MAX_POINTS: return false
			if key != "points" and value > THRESHOLDS.size(): return false
			clean[id] = int(value)
		parsed[key] = clean
	for id in parsed.report_stages:
		if parsed.report_stages[id] > stage_for(int(parsed.points.get(id, 0))): return false
	points = parsed.points
	report_stages = parsed.report_stages
	return true
