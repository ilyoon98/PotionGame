"""Build role-based palette records and review boards from approved v6 art.

No sprite is recolored here. Existing PNGs are read for validation and previews;
the 24-color master palette and runtime resources are left unchanged.
"""
from __future__ import annotations

import hashlib
import html
import json
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_full_ingame_mockup import LIQUIDS, content_rows
from process_pixel_art import ROOT, rgb, validate

OUT = ROOT / "art/palettes/v1"
V6 = ROOT / "art/mockups/full-ingame-v6"
INK, SKIN, BROWN = "#241C32", "#F6D1AC", "#916047"
CREAM, PURPLE, GOLD = "#FFF0BC", "#86548E", "#E9B95F"
MASTER = ["#" + value.strip().lstrip("#").upper()
          for value in (ROOT / "art/palette.hex").read_text().splitlines() if value.strip()]
RAMPS = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
APPROVAL_PATH = OUT / "approval.json"
PALETTE_APPROVED = APPROVAL_PATH.is_file() and json.loads(APPROVAL_PATH.read_text(encoding="utf-8")).get("approved_by_user",False)
ROLES_KO = {
    "outline": "테두리", "skin": "피부", "shirt": "셔츠",
    "hair_leather": "머리·가죽", "cloth": "옷·망토", "accent": "장식",
    "cloth_light": "옷 밝은 면", "hair": "머리", "robe": "로브",
    "robe_shadow": "머리·로브 그림자", "leather": "벨트·신발",
    "hair_tail": "머리·귀·꼬리", "hair_tail_light": "주황 밝은 면",
    "scarf": "목도리", "dark_clothing": "검은 옷·신발",
    "cork": "마개", "glass": "유리·라벨", "liquid": "내용물",
    "body": "솥 몸체", "emblem": "달 문양", "hearth": "화덕",
    "bubbles": "기포", "wood": "나무", "brass": "금속 장식",
    "leaf": "잎", "pot": "화분", "fire": "불꽃", "stone": "돌",
}


def unique_colors(roles):
    return list(dict.fromkeys(color for colors in roles.values() for color in colors))


def record(id, name, roles, note, source=None, approved=False):
    role_ramps = {"outline": "outline", "skin": "skin", "shirt": "skin" if id == "keeper" else "gold",
        "hair_leather": "wood", "cloth": {"keeper": "purple", "elf": "leaf", "traveler": "wood"}.get(id, "purple"),
        "accent": "gold", "cloth_light": "leaf", "robe_shadow": "purple", "robe": "purple",
        "leather": "wood", "hair_tail": "fire", "hair_tail_light": "fire", "scarf": "fire", "dark_clothing": "outline"}
    return {"id": id, "name": name, "status": "approved_reference" if approved else "approved_palette" if PALETTE_APPROVED else "candidate",
            "roles": roles, "role_ramps": {role: role_ramps[role] for role in roles},
            "colors": unique_colors(roles), "note": note,
            "reference": source, "native_canvas": [32, 48], "eyes_color": INK}


def character_records():
    rows = [
        record("keeper", "주인공 · 남자 상점 주인", {
            "outline": [INK], "skin": [SKIN], "shirt": [SKIN],
            "hair_leather": [BROWN], "cloth": [PURPLE], "accent": [GOLD],
        }, "v6 유지. 짧은 갈색 머리, 크림 셔츠, 보라 모자·망토, 반바지·부츠. 피부와 셔츠는 한 색을 공유한다.",
            "art/mockups/full-ingame-v6/characters/witch-native.png", True),
        record("traveler", "손님 · 여행자", {
            "outline": [INK], "skin": [SKIN], "shirt": [CREAM],
            "hair_leather": [BROWN], "cloth": ["#C99463"],
        }, "현재 여행자의 갈색 머리·배낭·반바지와 밝은 셔츠를 유지하는5색이다. 키프레임은 별도 검토 단계이다."),
        record("mage", "손님 · 여마법사", {
            "outline": [INK], "skin": [SKIN], "robe_shadow": ["#50315F"],
            "robe": [PURPLE], "leather": [BROWN],
        }, "여마법사 정체성과 긴 보라 로브·모자·보라 머리를 유지한다. 주인공과 옷 길이·색 덩어리 비율로 구분한다."),
        record("elf", "손님 · 엘프", {
            "outline": [INK], "skin": [SKIN], "hair_leather": [BROWN],
            "cloth": ["#718C59"], "cloth_light": ["#B5C77D"],
        }, "승인한 v6의 갈색 머리·초록 의상·22×16 머리 기준·정리된 하의를 유지한다.",
            "art/mockups/full-ingame-v6/characters/elf-native.png", True),
        record("rogue", "손님 · 고양이 도적", {
            "outline": [INK], "skin": [SKIN], "hair_tail": ["#DE7356"],
            "hair_tail_light": ["#F4AC68"], "scarf": ["#9D4359"],
            "dark_clothing": [INK],
        }, "현재 게임 v4의 주황 머리·귀·꼬리와 붉은 목도리를 유지한다. 검은 상의·반바지·장갑·부츠는 테두리색을 공유한다."),
    ]
    for row in rows:
        keyframe_path=f'art/characters/keyframes-v1/{row["id"]}/frames/idle.png'
        if row["id"] in ("traveler","mage","rogue") and (ROOT / keyframe_path).is_file():
            row["reference"]=keyframe_path
            row["keyframe_review"]=f'art/characters/keyframes-v1/{row["id"]}/review.html'
        if row["id"]=="elf" and (ROOT / keyframe_path).is_file():
            row["keyframe_reference"]=keyframe_path
            row["keyframe_review"]="art/characters/keyframes-v1/elf/review.html"
            row["keyframe_status"]="candidate_keyframes"
        row["reference_status"]="approved_v6" if row["id"] in ("keeper","elf") else "candidate_keyframe" if row["reference"] else "not_created"
        refined=f'art/characters/face-refinement-v1/faces/{row["id"]}.png'
        if (ROOT / refined).is_file():
            row["identity_reference_before_face_refinement"]=row["reference"]
            row["reference"]=refined
            row["reference_status"]="candidate_face_refinement"
            row["face_review"]="art/characters/face-refinement-v1/review.html"
            row["status"]="approved_palette" if PALETTE_APPROVED else "candidate"
            row["note"]+=" 현재 얼굴 그림은 최신 윤곽 수정 후보이며 별도 검토 대상이다."
    # The new coherent whole-body customer poses supersede older face-only references.
    for row in rows:
        latest=f'art/characters/keyframes-v2/{row["id"]}/frames/idle.png'
        registry=ROOT/'art/characters/current-art.json'
        if registry.is_file():
            current=json.loads(registry.read_text(encoding='utf-8')).get('characters',{}).get(row['id'])
            if current:
                latest=current['neutral']
                if current.get('motion_review'):row['action_review']=current['motion_review']
        if row['id'] in ('keeper','elf','rogue') and (ROOT / latest).is_file():
            row.update(reference=latest,reference_status='candidate_keyframe',
                keyframe_review=latest.removesuffix('/frames/idle.png')+'/review.html',keyframe_status='candidate_keyframes')
    return rows


def reference_label(row):
    if row["reference_status"]=="candidate_face_refinement":return "얼굴 수정 후보"
    if row["reference_status"]=="approved_v6":return "v6 유지"
    if row["reference_status"]=="candidate_keyframe":return "키프레임 후보"
    return "색상 확정" if PALETTE_APPROVED else "색 배정 후보"


def material_records():
    rows = [
        {"id": "shelf_counter_floor", "name": "선반·카운터·공통 발판", "roles": {
            "outline": [INK], "wood": [BROWN, "#C99463"], "brass": [GOLD]}},
        {"id": "herb_station", "name": "약초·화분", "roles": {
            "outline": [INK], "leaf": ["#718C59"], "pot": [PURPLE],
            "wood": [BROWN], "accent": [CREAM]}},
        {"id": "fire", "name": "솥 밑 불꽃", "roles": {
            "outline": [INK], "fire": ["#9D4359", "#DE7356", "#F4AC68"]}},
        {"id": "hearth", "name": "돌 화덕", "roles": {
            "outline": [INK], "stone": ["#4A3C52", "#827589"]}},
    ]
    ramps = {"outline": "outline", "wood": "wood", "brass": "gold", "leaf": "leaf",
             "pot": "purple", "accent": "gold", "fire": "fire", "stone": "stone"}
    for row in rows:
        row["role_ramps"] = {role: ramps[role] for role in row["roles"]}
    return rows


def potion_records():
    source = json.loads((V6 / "potions/recipes.json").read_text(encoding="utf-8"))
    old = {row["id"]: row for row in source["recipes"]}
    result = []
    for row in content_rows():
        id = row["id"]
        ramp, liquids = LIQUIDS[id]
        if old[id]["liquid_color"] != liquids[-1] or old[id]["liquid_ramp"] != ramp:
            raise ValueError(f"v6 recipe palette drift: {id}")
        bottle = {"outline": [INK], "cork": [BROWN], "glass": [CREAM], "liquid": liquids}
        cauldron = {"outline": [INK], "body": [PURPLE], "emblem": [GOLD],
                    "hearth": ["#827589"], "liquid": [liquids[-1]], "bubbles": [INK]}
        result.append({"id": id, "name": row["name"], "family": row["family"],
            "rare": bool(row.get("rare")), "status": "v6_mapping_retained",
            "liquid_ramp": ramp, "liquid_ramp_colors": liquids,
            "bottle": {"roles": bottle, "colors": unique_colors(bottle),
                       "role_ramps": {"outline": "outline", "cork": "wood", "glass": "gold", "liquid": ramp},
                       "native_size": old[id]["bottle_size"],
                       "reference": "art/mockups/full-ingame-v6/potions/" + old[id]["bottle_path"]},
            "cauldron": {"roles": cauldron, "colors": unique_colors(cauldron),
                         "role_ramps": {"outline": "outline", "body": "purple", "emblem": "gold",
                                        "hearth": "stone", "liquid": ramp, "bubbles": "outline"},
                         "native_size": [32, 32],
                         "reference": "art/mockups/full-ingame-v6/potions/" + old[id]["pot_frames"][0]},
            "note": "병과 솥은 같은 액체 램프를 사용한다. 솥 몸체·달 문양·화덕은 고정하며 노출 액체63픽셀만 레시피에 따라 바뀐다."})
    return result


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def check_roles(roles, ramps=None, role_ramps=None):
    colors = unique_colors(roles)
    if len(colors) > 5 or any(c not in MASTER for c in colors):
        raise ValueError(f"Palette budget or master membership: {roles}")
    if ramps:
        for name, values in ramps.items():
            allowed = RAMPS["ramps"][name]["colors"]
            if any(c not in allowed for c in values) or values != sorted(values, key=allowed.index):
                raise ValueError(f"Material ramp order: {name}")
    if role_ramps:
        if set(role_ramps) != set(roles):
            raise ValueError("Every color role must have an explicit material ramp")
        for role, values in roles.items():
            allowed = RAMPS["ramps"][role_ramps[role]]["colors"]
            if any(c not in allowed for c in values) or values != sorted(values, key=allowed.index):
                raise ValueError(f"Role outside approved ramp: {role}")
    return {"unique_colors": len(colors), "off_palette": 0}


def validate_catalog(chars, potions, materials):
    code = (ROOT / "scripts/shop_content.gd").read_text(encoding="utf-8")
    roster_block = code.split("const CUSTOMERS := [", 1)[1].split("\n]", 1)[0]
    roster = [re.search(r'"id": "([^"]+)"', line).group(1)
              for line in roster_block.splitlines() if '"id":' in line and '"enabled": false' not in line]
    if {r["id"] for r in chars} != {"keeper", *roster}:
        raise ValueError("Character coverage does not match enabled runtime roster")
    char_checks, potion_checks = {}, {}
    palette = {rgb(c) for c in MASTER}
    reference_hashes = {}
    for row in chars:
        check = check_roles(row["roles"], role_ramps=row["role_ramps"])
        if row["reference"]:
            path = ROOT / row["reference"]
            image = Image.open(path).convert("RGBA")
            check["reference"] = validate(image, [32, 48], palette, 5)
            used = {"#%02X%02X%02X" % p[:3] for p in image.get_flattened_data() if p[3] == 255}
            if not check["reference"]["passed"] or used != set(row["colors"]):
                raise ValueError(f"Approved character color mismatch: {row['id']}")
            reference_hashes[row["reference"]] = hashlib.sha256(path.read_bytes()).hexdigest()
        char_checks[row["id"]] = check
    for row in potions:
        potion_checks[row["id"]] = {}
        check_roles({"liquid": row["liquid_ramp_colors"]}, {row["liquid_ramp"]: row["liquid_ramp_colors"]})
        for kind in ("bottle", "cauldron"):
            obj = row[kind]
            check = check_roles(obj["roles"], role_ramps=obj["role_ramps"])
            path = ROOT / obj["reference"]
            image = Image.open(path).convert("RGBA")
            check["reference"] = validate(image, obj["native_size"], palette, 5)
            used = {"#%02X%02X%02X" % p[:3] for p in image.get_flattened_data() if p[3] == 255}
            if not check["reference"]["passed"] or not used.issubset(set(obj["colors"])):
                raise ValueError(f"Existing {kind} outside recorded roles: {row['id']}")
            reference_hashes[obj["reference"]] = hashlib.sha256(path.read_bytes()).hexdigest()
            potion_checks[row["id"]][kind] = check
    return {"status": "passed", "master_colors": len(MASTER), "new_colors_added": 0,
            "character_count": len(chars), "enabled_customers": roster,
            "potion_count": len(potions), "common_material_count": len(materials),
            "characters": char_checks, "potions": potion_checks,
            "materials": {r["id"]: check_roles(r["roles"], role_ramps=r["role_ramps"]) for r in materials},
            "reference_sha256": reference_hashes, "runtime_changed": False,
            "keyframes_generated_by_palette_builder": False, "action_animations_generated_by_palette_builder": False,
            "keyframe_reference_characters": [r["id"] for r in chars if r["reference_status"]=="candidate_keyframe"]}


def production_plan(chars):
    progress_path=ROOT / "art/characters/keyframes-v1/production-status.json"
    progress=json.loads(progress_path.read_text(encoding="utf-8")) if progress_path.is_file() else {}
    return {"schema_version": 1, "sequence": ["palettes", "character_keyframes", "action_animations"],
        "current_stage": progress.get("current_stage","palettes"), "completed_keyframe_candidates":progress.get("completed_keyframe_candidates",[]),
        "reference": "art/mockups/full-ingame-v6/approval.json",
        "character_ids": [r["id"] for r in chars],
        "anatomy": {"native_canvas": [32, 48], "head_rows": [11, 26],
            "torso_rows": [27, 39], "legs_and_boots_rows": [40, 46], "foot_row": 46,
            "notes": "모자는 머리 크기 기준에 포함하지 않는다. 행동에 필요한 관절 변화는 허용하며 머리 크기·의상·성별을 유지한다."},
        "keyframes": {
            "keeper": ["idle", "brew_reach", "brew_stir_left", "brew_stir_right", "handover_extend", "handover_return"],
            "customers": ["idle", "walk_contact_a", "walk_pass_a", "walk_contact_b", "walk_pass_b", "receive_extend", "receive_hold"]},
        "actions": {
            "keeper": [{"id": "idle", "loop": True}, {"id": "brew", "loop": True}, {"id": "handover", "loop": False}],
            "customers": [{"id": "arrive", "uses": "walk", "loop": True}, {"id": "wait", "uses": "idle", "loop": True},
                {"id": "receive", "loop": False}, {"id": "depart", "uses": "walk_carry", "loop": True}]},
        "carry_bottle": "별도 레시피 병 에셋을 손 앵커에 합성한다. 캐릭터 PNG에 물약색을 칠하지 않는다.",
        "idle": "v6 상하 호흡·깜빡임·모자/망토/머리 부분 움직임을 유지한다.",
        "walk": "반대쪽 다리의 접지·통과 포즈와 팔의 반대 스윙을 전신으로 검토한다. 걷는 방향을 바꿀 때 인물 정체성을 바꾸지 않는다.",
        "review_order": ["5명 중립 전신", "주인공 제조/전달", "손님 걷기/받기", "행동별 보간과 부분 움직임", "전체 목업 합성", "Godot 적용"],
        "checks": ["팔레트 밖0", "캐릭터별 최대5색", "반투명0", "외곽선 경계 위반0", "머리 크기 유지", "발 접지", "손-물약 앵커", "이벤트 시점 일치"],
        "keyframes_status": "customer_candidates_in_progress" if progress else "planned_not_generated",
        "current_customer":progress.get("current_customer"),"remaining_customers":progress.get("remaining_customers",["traveler","mage","elf","rogue"]),
        "animations_status": progress.get('action_animations','planned_not_generated'),
        "next_stage":progress.get('next_stage','action_animations'),
        "latest_keeper_keyframes":progress.get('keeper',{}).get('keyframes'),
        "latest_keeper_motion":progress.get('keeper',{}).get('motion'),
        "completed_customer_action_candidates":progress.get('completed_customer_action_candidates',[]),
        "remaining_customer_actions":progress.get('remaining_customer_actions',['traveler','mage','elf','rogue']),
        "customer_action_reviews":{name:progress.get(name,{}).get('motion_review') for name in ('traveler','mage','elf','rogue') if progress.get(name,{}).get('motion_review')}}


def swatches(roles):
    return "".join('<div class="role"><span>' + html.escape(ROLES_KO.get(role, role)) + '</span><div>' +
        "".join(f'<button class="swatch" style="--color:{c}" data-copy="{c}" aria-label="{c} 복사"><i></i><code>{c}</code></button>' for c in values) + '</div></div>'
        for role, values in roles.items())


def relative_image(path):
    return "../../../" + path


def write_html(chars, potions, materials):
    char_cards = []
    for row in chars:
        preview = (f'<img class="character" src="{relative_image(row["reference"])}" width="96" height="144" alt="{row["name"]} {reference_label(row)}">'
                   if row["reference"] else '<div class="pending">외형은 다음 키프레임 단계에서 제작</div>')
        extra=f'<p><a href="{relative_image(row["keyframe_review"])}">키프레임·움직임 보기</a></p>' if row.get("keyframe_review") else ''
        if row.get('action_review'):extra+=f'<p><a href="{relative_image(row["action_review"])}">행동 애니메이션 보기</a></p>'
        char_cards.append(f'<article class="card"><header><h3>{row["name"]}</h3><span class="tag">{len(row["colors"])}색 · {reference_label(row)}</span></header>' +
            f'<div class="character-body">{preview}<div>{swatches(row["roles"])}</div></div><p>{row["note"]}</p>{extra}</article>')
    potion_cards = []
    for row in potions:
        potion_cards.append(f'<article class="card potion" data-search="{row["id"]} {row["name"]} {row["family"]}"><header><h3>{row["name"]}</h3><span class="tag">{row["id"]}</span></header>' +
            f'<div class="objects"><figure><img src="{relative_image(row["bottle"]["reference"])}" width="24" height="{row["bottle"]["native_size"][1]*3}" alt="{row["name"]} 병"><figcaption>병 {len(row["bottle"]["colors"])}색</figcaption></figure>' +
            f'<figure><img src="{relative_image(row["cauldron"]["reference"])}" width="96" height="96" alt="{row["name"]} 솥"><figcaption>솥 {len(row["cauldron"]["colors"])}색</figcaption></figure></div>' +
            swatches(row["bottle"]["roles"]) + '<details><summary>솥 색 역할</summary>' + swatches(row["cauldron"]["roles"]) + '</details></article>')
    common_cards = ''.join(f'<article class="card"><h3>{r["name"]}</h3>{swatches(r["roles"])}</article>' for r in materials)
    master = ''.join(f'<button class="master-color" style="--color:{c}" data-copy="{c}" aria-label="{c} 복사"><i></i><code>{c}</code></button>' for c in MASTER)
    template = '''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>달그늘 물약상점 · 팔레트 v1</title><style>
    :root{color-scheme:dark;--bg:#241C32;--panel:#30263f;--line:#64546f;--text:#fff0bc;--muted:#c6b5d2;--gold:#e9b95f}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}@font-face{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}main{max-width:1200px;margin:auto;padding:32px 24px}h1{font-size:27px;margin:0 0 8px}h2{font-size:21px;margin:24px 0 12px}h3{font-size:17px;margin:0}p{color:var(--muted);margin:12px 0 0}a{color:var(--gold)}.stats{display:flex;gap:20px;flex-wrap:wrap;margin:18px 0}.stats strong{color:var(--gold)}.master{display:grid;grid-template-columns:repeat(12,1fr);gap:6px;margin:20px 0}.master-color{border:1px solid var(--line);background:transparent;color:var(--text);padding:0 0 5px;cursor:pointer}.master-color i{height:30px;display:block;background:var(--color);margin-bottom:4px}.master-color code{font-size:11px}nav{display:flex;gap:8px;margin:24px 0 18px;border-bottom:1px solid var(--line);padding-bottom:14px}nav button{padding:9px 18px;border:1px solid var(--line);background:transparent;color:var(--text);font:inherit;cursor:pointer}nav button[aria-pressed=true]{background:#86548e;border-color:#c38eb5}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.card{border:1px solid var(--line);padding:18px;background:var(--panel)}.card header{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:16px}.tag{font-size:12px;color:var(--gold)}.character-body{display:grid;grid-template-columns:110px 1fr;gap:16px;align-items:center}.character,img{image-rendering:pixelated;object-fit:contain}.pending{height:144px;display:grid;place-content:center;text-align:center;border:1px dashed var(--line);color:var(--muted);padding:10px;font-size:12px}.role{display:flex;align-items:center;justify-content:space-between;gap:6px;margin-bottom:7px}.role>span{font-size:13px;color:var(--muted)}.role>div{display:flex;gap:5px;flex-wrap:wrap}.swatch{display:flex;align-items:center;gap:5px;background:transparent;color:var(--text);border:0;cursor:pointer;padding:0}.swatch i{width:20px;height:20px;background:var(--color);border:1px solid #827589}.swatch code{font-size:11px}.potions{grid-template-columns:repeat(3,minmax(0,1fr))}.objects{display:flex;justify-content:center;gap:24px;align-items:flex-end;margin-bottom:18px;height:120px}.objects figure{margin:0;text-align:center}.objects img{display:block;margin:auto}.objects figcaption{color:var(--muted);font-size:12px;margin-top:8px}details{margin-top:12px}summary{cursor:pointer;color:var(--gold);font-size:13px}details .role:first-of-type{margin-top:12px}.search{width:100%;padding:10px;background:var(--panel);color:var(--text);border:1px solid var(--line);font:inherit;margin-bottom:16px}.notice{border-left:3px solid var(--gold);padding:8px 14px;margin:16px 0;color:var(--muted)}.steps{display:flex;gap:10px;flex-wrap:wrap;padding:18px;border:1px solid var(--line);margin-top:28px}.steps span{color:var(--muted)}#copy-status{min-height:24px;color:var(--gold)}[hidden]{display:none!important}@media(max-width:800px){.master{grid-template-columns:repeat(6,1fr)}.grid,.potions{grid-template-columns:1fr}.character-body{grid-template-columns:96px 1fr}main{padding:24px 16px}.role>span{font-size:12px}}
    </style></head><body><main><h1>달그늘 물약상점 · 팔레트 v1</h1><p>승인한 v6의 색을 기준으로 캐릭터와 물약의 재질별 색 역할을 정리했습니다.</p><div class="stats"><span>공통 <strong>24색</strong></span><span>캐릭터 <strong>5명</strong></span><span>물약 <strong>36종</strong></span><span>에셋당 <strong>최대 5색</strong></span></div><div class="master">__MASTER__</div><div id="copy-status" role="status">색을 누르면 헥스 코드를 복사합니다.</div><nav aria-label="팔레트 분류"><button data-panel="characters" aria-pressed="true">캐릭터별</button><button data-panel="potions" aria-pressed="false">물약별 36종</button><button data-panel="materials" aria-pressed="false">공통 재질</button></nav>
    <section id="characters"><div class="notice">__CHAR_NOTICE__</div><div class="grid">__CHARS__</div></section>
    <section id="potions" hidden><div class="notice">병은 테두리·마개·유리·내용물 2단계로 구성합니다. 솥 몸체·달 문양·화덕은 고정하고 액체만 해당 물약의 색으로 바뀝니다. 같은 색을 쓰는 물약은 기존 병 모양·라벨·이름으로 구분합니다.</div><input class="search" id="potion-search" aria-label="물약 이름 또는 ID 검색" placeholder="물약 이름 또는 ID 검색"><p id="potion-count">36종</p><div class="grid potions">__POTIONS__</div></section>
    <section id="materials" hidden><div class="grid">__COMMON__</div></section><div class="steps"><strong>① 팔레트</strong><span>→</span><span>② 캐릭터 키프레임</span><span>→</span><span>③ 행동별 애니메이션</span><span>→</span><span>④ 전체 화면 확인·Godot 연결</span></div><p><a href="../../../art/mockups/full-ingame-v6/animated-preview.html">승인한 v6 전체 목업</a> · <a href="catalog.json">전체 색 데이터</a> · <a href="production-plan.json">키프레임·행동 제작 순서</a></p></main><script>
    const panels=['characters','potions','materials'];document.querySelectorAll('nav button').forEach(button=>button.addEventListener('click',()=>{panels.forEach(id=>document.getElementById(id).hidden=id!==button.dataset.panel);document.querySelectorAll('nav button').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));}));document.getElementById('potion-search').addEventListener('input',event=>{const query=event.target.value.trim().toLowerCase();let count=0;document.querySelectorAll('.potion').forEach(card=>{card.hidden=!card.dataset.search.toLowerCase().includes(query);if(!card.hidden)count++;});document.getElementById('potion-count').textContent=count+'종';});document.querySelectorAll('[data-copy]').forEach(button=>button.addEventListener('click',async()=>{try{await navigator.clipboard.writeText(button.dataset.copy);document.getElementById('copy-status').textContent=button.dataset.copy+' 복사됨';}catch{document.getElementById('copy-status').textContent=button.dataset.copy+' · 코드를 직접 복사하세요.'}}));
    </script></body></html>'''
    notice="팔레트 배정은 승인됐습니다. 주인공·엘프는 v6를 유지하며, 손님은 한 명씩 키프레임을 제작합니다. 새 여행자는 키프레임 검토 후보입니다." if PALETTE_APPROVED else "주인공·엘프는 승인한 v6 그대로입니다. 나머지 손님은 색 배정 후보이며 키프레임 단계에서 제작합니다."
    for token, value in (("__MASTER__", master), ("__CHAR_NOTICE__",notice), ("__CHARS__", ''.join(char_cards)),
                         ("__POTIONS__", ''.join(potion_cards)), ("__COMMON__", common_cards)):
        template = template.replace(token, value)
    (OUT / "review.html").write_text(template, encoding="utf-8")


def font(size):
    return ImageFont.truetype(str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"), size)


def text(image, xy, value, size=15, color=CREAM):
    ImageDraw.Draw(image).text(xy, value, font=font(size), fill=color)


def bars(image, roles, x, y, width=285):
    draw = ImageDraw.Draw(image)
    for i, (role, values) in enumerate(roles.items()):
        yy = y + i * 27
        text(image, (x, yy), ROLES_KO.get(role, role), 13, "#C38EB5")
        for j, color in enumerate(values):
            xx = x + 104 + j * 105
            draw.rectangle((xx, yy + 1, xx + 18, yy + 19), fill=color, outline="#827589")
            text(image, (xx + 24, yy + 1), color, 12)


def boards(chars, potions):
    board = Image.new("RGBA", (1120, 1040), INK)
    text(board, (24, 20), "달그늘 물약상점 · 캐릭터 팔레트 v1", 26)
    text(board, (24, 61), "공통 24색 · 캐릭터별 최대 5색 · v6 주인공·엘프 유지", 16, "#C38EB5")
    for i, color in enumerate(MASTER):
        x, y = 24 + (i % 12) * 90, 103 + (i // 12) * 57
        ImageDraw.Draw(board).rectangle((x, y, x + 76, y + 27), fill=color, outline="#827589")
        text(board, (x, y + 30), color, 11)
    for i, row in enumerate(chars):
        x, y = 24 + (i % 2) * 548, 241 + (i // 2) * 250
        ImageDraw.Draw(board).rectangle((x, y, x + 520, y + 234), fill="#30263F", outline="#827589")
        text(board, (x + 12, y + 12), row["name"], 18)
        text(board, (x + 12, y + 42), reference_label(row), 12, GOLD)
        if row["reference"]:
            sprite = Image.open(ROOT / row["reference"]).convert("RGBA")
            board.alpha_composite(sprite.resize((96, 144), Image.Resampling.NEAREST), (x + 6, y + 76))
        else:
            text(board, (x + 16, y + 110), "키프레임", 13, "#C38EB5")
            text(board, (x + 16, y + 135), "제작 예정", 13, "#C38EB5")
        bars(board, row["roles"], x + 115, y + 56)
    x, y = 572, 741
    ImageDraw.Draw(board).rectangle((x, y, x + 520, y + 234), fill="#30263F", outline="#827589")
    text(board, (x + 16, y + 14), "다음 제작 · 캐릭터 키프레임", 18)
    for i, line in enumerate(("원본 32×48 · 모자를 제외한 신체 비율 유지",
        "머리 16행 / 몸통 13행 / 다리·신발 7행",
        "발 접지 46행 · 눈 크기·머리 크기·의상 유지",
        "주인공: 대기 → 제조 → 전달",
        "손님: 입장 → 대기 → 받기 → 병을 든 퇴장",
        "키프레임 확인 후 행동별 애니메이션 제작")):
        text(board, (x + 16, y + 58 + i * 25), line, 14, "#C38EB5")
    text(board, (24, 1006), "색 역할을 고정한 뒤 전신 키프레임 → 행동별 움직임을 제작합니다.", 13, "#C38EB5")
    board.convert("RGB").save(OUT / "characters-overview.png")
    sheet = Image.new("RGBA", (1120, 1380), INK)
    text(sheet, (24, 18), "36종 물약 · 병과 솥 액체색", 26)
    text(sheet, (24, 60), "병: 테두리 / 마개 / 유리 / 액체 2색 · 솥: 몸체 고정, 내용물만 변경", 15, "#C38EB5")
    for i, row in enumerate(potions):
        x, y = 24 + (i % 6) * 182, 105 + (i // 6) * 208
        ImageDraw.Draw(sheet).rectangle((x, y, x + 170, y + 194), fill="#30263F", outline="#827589")
        text(sheet, (x + 8, y + 8), row["name"], 15, GOLD if row["rare"] else CREAM)
        text(sheet, (x + 8, y + 32), row["id"], 9, "#C38EB5")
        bottle = Image.open(ROOT / row["bottle"]["reference"]).convert("RGBA")
        pot = Image.open(ROOT / row["cauldron"]["reference"]).convert("RGBA")
        sheet.alpha_composite(bottle.resize((24, bottle.height * 3), Image.Resampling.NEAREST), (x + 21, y + 139 - bottle.height * 3))
        sheet.alpha_composite(pot.resize((96, 96), Image.Resampling.NEAREST), (x + 60, y + 47))
        for j, color in enumerate(row["bottle"]["colors"]):
            ImageDraw.Draw(sheet).rectangle((x + 10 + j * 30, y + 155, x + 34 + j * 30, y + 174), fill=color, outline="#827589")
        text(sheet, (x + 10, y + 177), f'병 {len(row["bottle"]["colors"])}색 / 솥 {len(row["cauldron"]["colors"])}색', 11)
    sheet.convert("RGB").save(OUT / "potions-overview.png")


def main():
    chars, potions, materials = character_records(), potion_records(), material_records()
    report = validate_catalog(chars, potions, materials)
    OUT.mkdir(parents=True, exist_ok=True)
    common = {"schema_version": 1, "master_palette": "art/palette.hex", "ramps": "art/ramps.json",
              "basis": "art/mockups/full-ingame-v6", "new_colors_added": 0, "scope": "art production; runtime unchanged"}
    dump(OUT / "characters.json", {**common, "characters": chars})
    dump(OUT / "potions.json", {**common, "potions": potions})
    dump(OUT / "materials.json", {**common, "materials": materials})
    dump(OUT / "catalog.json", {**common, "characters": chars, "potions": potions, "materials": materials})
    dump(OUT / "production-plan.json", production_plan(chars))
    for kind, rows in (("characters", chars), ("potions", potions), ("materials", materials)):
        for row in rows:
            if kind == "potions":
                for part in ("bottle", "cauldron"):
                    path = OUT / kind / f'{row["id"]}-{part}.hex'
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("\n".join(c.lstrip("#") for c in row[part]["colors"]) + "\n", encoding="utf-8")
            else:
                path = OUT / kind / f'{row["id"]}.hex'
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("\n".join(c.lstrip("#") for c in unique_colors(row["roles"])) + "\n", encoding="utf-8")
    write_html(chars, potions, materials)
    boards(chars, potions)
    for path, digest in report["reference_sha256"].items():
        if hashlib.sha256((ROOT / path).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Reference modified during board build: {path}")
    report["reference_files_unchanged"] = True
    dump(OUT / "validation.json", report)
    print(json.dumps({key: report[key] for key in ("status", "master_colors", "character_count", "potion_count", "new_colors_added", "reference_files_unchanged")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
