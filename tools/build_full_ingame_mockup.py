"""Build a 540x300 candidate workshop from inspected project content and art.

No Godot process, player save, startup registration or runtime asset is changed.
Imagegen sources go through process_pixel_art.py; UI marks are code-native.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from process_pixel_art import ROOT, rgb, validate

OUT = ROOT / "art/mockups/full-ingame-v1"
OLD = "art/mockups/cozy-witch-v1"
PALETTE = {rgb(value) for value in (ROOT / "art/palette.hex").read_text().splitlines()}
COLORS = {"outline": "#241C32", "paper": "#50315F", "purple": "#86548E",
          "lilac": "#C38EB5", "wood": "#916047", "honey": "#C99463",
          "cream": "#FFF0BC", "gold": "#E9B95F", "mint": "#3BA8A3",
          "pale_mint": "#9BE2CF", "blue": "#24566A", "stone": "#827589",
          "leaf": "#718C59", "mat": "#4A3C52"}
SELECTED = ["health", "mana", "moon", "purify", "agility", "vigor", "nightwalk", "rare_forest_breath"]
# Explicit target material ramps. Several recipes share hues; silhouettes and
# retained cream markings distinguish them. These are never nearest RGB picks.
LIQUIDS = {
    "health": ("skin", ["#A65D64", "#DE9B88"]),
    "mana": ("teal", ["#24566A", "#3BA8A3"]),
    "moon": ("purple", ["#86548E", "#C38EB5"]),
    "purify": ("teal", ["#3BA8A3", "#9BE2CF"]),
    "agility": ("gold", ["#E9B95F", "#FFF0BC"]),
    "vigor": ("fire", ["#9D4359", "#DE7356"]),
    "antidote": ("leaf", ["#3D544D", "#718C59"]),
    "fortune": ("gold", ["#A56A3D", "#E9B95F"]),
    "focus": ("teal", ["#24566A", "#9BE2CF"]),
    "restoration": ("skin", ["#DE9B88", "#F6D1AC"]),
    "growth": ("leaf", ["#718C59", "#B5C77D"]),
    "clarity": ("teal", ["#3BA8A3", "#9BE2CF"]),
    "ward": ("stone", ["#4A3C52", "#827589"]),
    "spirit": ("teal", ["#24566A", "#9BE2CF"]),
    "arcane_amplification": ("purple", ["#50315F", "#86548E"]),
    "iron_skin": ("stone", ["#4A3C52", "#827589"]),
    "stealth": ("purple", ["#50315F", "#86548E"]),
    "poison_resistance": ("leaf", ["#3D544D", "#718C59"]),
    "illusion": ("purple", ["#86548E", "#C38EB5"]),
    "soul_purification": ("teal", ["#3BA8A3", "#9BE2CF"]),
    "wisdom": ("purple", ["#86548E", "#C38EB5"]),
    "reflection": ("teal", ["#24566A", "#9BE2CF"]),
    "haste": ("gold", ["#E9B95F", "#FFF0BC"]),
    "nightwalk": ("purple", ["#50315F", "#86548E"]),
    "moonradiance": ("gold", ["#E9B95F", "#FFF0BC"]),
    "regeneration": ("skin", ["#A65D64", "#F6D1AC"]),
    "starlight": ("purple", ["#50315F", "#C38EB5"]),
    "wish": ("gold", ["#E9B95F", "#FFF0BC"]),
    "eternity": ("gold", ["#A56A3D", "#FFF0BC"]),
    "sage_elixir": ("purple", ["#50315F", "#C38EB5"]),
    "worldtree_elixir": ("leaf", ["#718C59", "#B5C77D"]),
    "shadow_elixir": ("purple", ["#50315F", "#86548E"]),
    "rare_forest_breath": ("leaf", ["#718C59", "#B5C77D"]),
    "rare_mist_veil": ("teal", ["#24566A", "#9BE2CF"]),
    "rare_lunar_seal": ("purple", ["#86548E", "#C38EB5"]),
    "rare_nebula_distillate": ("purple", ["#50315F", "#C38EB5"]),
}


def asset(id, size, materials, rules, fallback, source=None, **extra):
    return {"id": id, "source": source or f"art/mockups/full-ingame-v1/source/{id}.png",
            "size": size, "position": [0, 0], "margin": 1, "dark_value": .25,
            "materials": {"outline": [COLORS["outline"]], **materials},
            "rules": rules, "fallback_material": fallback, **extra}


def content_rows():
    data = json.loads((ROOT / "data/content_expansion.json").read_text(encoding="utf-8-sig"))
    rows = [dict(row) for row in data["potions"]]
    # This mirrors ItemArt.bottle's legacy branches rather than using the
    # similarly named (but unused for these five IDs) content-catalog images.
    legacy = {"health": "assets/potion_12x16.png", "mana": "assets/mana_12x16.png",
              "moon": "assets/items_v1/moon_12x16.png", "purify": "assets/items_v1/purify_12x16.png",
              "agility": "assets/items_v1/agility_12x16.png"}
    for row in rows:
        row["runtime_source"] = legacy.get(row["id"], row["bottle_candidate"].removeprefix("res://"))
    rare_code = (ROOT / "scripts/rare_recipes.gd").read_text(encoding="utf-8")
    rare_catalog = json.loads((ROOT / "assets/rare_recipes_v1/catalog.json").read_text(encoding="utf-8-sig"))
    for record in rare_catalog["assets"]:
        id = record["id"]
        line = next(line for line in rare_code.splitlines() if '"id": "' + id + '"' in line)
        rows.append({"id": id, "name": re.search(r'"name": "([^"]+)"', line).group(1),
                     "family": re.search(r'"family": "([^"]+)"', line).group(1),
                     "runtime_source": record["bottle_path"].removeprefix("res://"), "rare": True})
    if len(rows) != 36 or {row["id"] for row in rows} != set(LIQUIDS):
        raise ValueError("Explicit palette mapping no longer matches the 36 runtime recipes")
    for row in rows:
        if not (ROOT / row["runtime_source"]).is_file():
            raise ValueError(f"Missing runtime bottle: {row['id']}")
        source = Image.open(ROOT / row["runtime_source"]).convert("RGBA")
        bounds = source.getbbox()
        row["preserve_slim_native"] = bool(source.size == (12, 16) and bounds and bounds[2]-bounds[0] <= 5 and bounds[0] >= 2 and bounds[2] <= 10)
        row["mock_native_size"] = [8, 16] if row["preserve_slim_native"] else [8, 12]
    return rows


def prepare_manifest(rows):
    wood = {"wood": [COLORS["wood"], COLORS["honey"]], "gold": [COLORS["gold"], COLORS["cream"]]}
    gold_rule = {"material": "gold", "hue": [.10, .22], "value_min": .78}
    assets = [
        asset("window", [32, 32], wood, [gold_rule], "wood"),
        asset("shelf_frame", [48, 48], wood, [gold_rule], "wood"),
        asset("counter", [48, 16], wood, [gold_rule], "wood"),
        asset("poster", [24, 32], {"wood": [COLORS["wood"]], "gold": [COLORS["gold"], COLORS["cream"]],
                                     "purple": [COLORS["paper"]]},
              [{"material": "purple", "hue": [.65, .90]}, gold_rule], "wood"),
        asset("herb_station", [32, 32], {"purple": [COLORS["purple"]], "leaf": [COLORS["leaf"]],
                                            "wood": [COLORS["wood"]], "gold": [COLORS["cream"]]},
              [{"material": "leaf", "hue": [.20, .45]},
               {"material": "gold", "hue": [.07, .22], "value_min": .85},
               {"material": "wood", "y_min": .73}], "purple"),
        asset("elf", [32, 48], {"wood": [COLORS["wood"]], "skin": ["#F6D1AC"],
                                      "leaf": ["#718C59", "#B5C77D"]},
              [{"material": "skin", "hue": [0, .17], "value_min": .82},
               {"material": "leaf", "hue": [.20, .45]}], "wood"),
        asset("cauldron_moon", [32, 32], {"purple": [COLORS["purple"]], "liquid": [COLORS["lilac"]],
                                               "gold": [COLORS["gold"]], "stone": [COLORS["stone"]]},
              [{"material": "gold", "hue": [.04, .19], "saturation_min": .35},
               {"material": "liquid", "hue": [.36, .62], "saturation_min": .22},
               {"material": "stone", "y_min": .78, "saturation_max": .35}], "purple",
              source=OLD + "/cauldron-native.png", preserve_native_frame=True, material_ramps={"liquid": "purple"}),
    ]
    for row in rows:
        ramp, colors = LIQUIDS[row["id"]]
        options = {"native_crop": [2, 0, 10, 16], "preserve_native_frame": True} if row["preserve_slim_native"] else {}
        assets.append(asset("potion_" + row["id"], row["mock_native_size"],
                            {"glass": [COLORS["cream"]], "wood": [COLORS["wood"]], "liquid": colors},
                            [{"material": "wood", "y_max": .34, "hue": [.025, .18], "saturation_min": .28, "value_max": .88},
                             {"material": "glass", "saturation_max": .32, "value_min": .80}],
                            "liquid", source=row["runtime_source"], margin=0,
                            material_ramps={"glass": "gold", "liquid": ramp}, preserve_source_outline=True, **options))
    config = {"schema_version": 1, "status": "candidate", "approved_by_user": False,
              "compose": False, "scale": 3, "alpha_threshold": 224, "max_colors": 5,
              "palette": "art/palette.hex", "ramps": "art/ramps.json",
              "output": "art/mockups/full-ingame-v1", "scene": {"size": [180, 100], "background": COLORS["mat"]},
              "assets": assets}
    (OUT / "manifest.json").write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def native(id):
    return Image.open(OUT / (id + "-native.png")).convert("RGBA")


def text(canvas, position, value, size=14, color="cream", anchor=None):
    """Use the project's readable UI font; threshold glyphs to palette pixels."""
    font = ImageFont.truetype(str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"), size)
    mask = Image.new("L", canvas.size)
    ImageDraw.Draw(mask).text(position, value, font=font, fill=255, anchor=anchor)
    mask = mask.point(lambda alpha: 255 if alpha >= 128 else 0)
    canvas.paste(COLORS.get(color, color), (0, 0, *canvas.size), mask)


def enclosed_holes(image):
    empty = np.array(image)[:, :, 3] == 0
    seen = set()
    holes = []
    for y, x in zip(*np.where(empty)):
        if (x, y) in seen:
            continue
        queue = [(x, y)]
        seen.add((x, y))
        area = []
        touches = False
        while queue:
            px, py = queue.pop()
            area.append((px, py))
            if px in (0, image.width - 1) or py in (0, image.height - 1):
                touches = True
            for nx, ny in ((px-1, py), (px+1, py), (px, py-1), (px, py+1)):
                if 0 <= nx < image.width and 0 <= ny < image.height and empty[ny, nx] and (nx, ny) not in seen:
                    seen.add((nx, ny))
                    queue.append((nx, ny))
        if not touches and len(area) >= 30:
            holes.append(area)
    return sorted(holes, key=lambda hole: min(x for x, y in hole))


def shelf_boards(image):
    occupied = (np.array(image)[:, :, 3] == 255).sum(axis=1)
    wide = np.where(occupied >= image.width * .72)[0]
    runs = []
    for y in wide:
        if not runs or y > runs[-1][-1] + 1:
            runs.append([int(y)])
        else:
            runs[-1].append(int(y))
    boards = [run[0] for run in runs if len(run) >= 2]
    if len(boards) != 2 or boards[0] < 12 or boards[1] - boards[0] < 12:
        raise ValueError(f"Shelf boards need visual correction: {boards}")
    return boards


def icon(kind, size=9):
    image = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(image)
    if kind == "moon":
        d.ellipse((1,1,7,7), fill=COLORS["gold"])
        d.ellipse((4,0,8,5), fill=COLORS["outline"])
    elif kind == "rain":
        d.rectangle((2,1,6,2), fill=COLORS["stone"])
        d.rectangle((1,3,7,4), fill=COLORS["stone"])
        for x in (2,4,6): d.line((x,6,x-1,7), fill=COLORS["pale_mint"])
    elif kind == "coin":
        d.ellipse((1,1,7,7), fill=COLORS["gold"], outline=COLORS["wood"])
        d.line((4,3,4,5), fill=COLORS["cream"])
    elif kind == "search":
        d.ellipse((1,1,5,5), outline=COLORS["gold"])
        d.line((5,5,7,7), fill=COLORS["gold"])
    elif kind == "move":
        for x in (2,5):
            for y in (2,4,6): d.point((x,y), fill=COLORS["cream"])
    elif kind == "minimize":
        d.line((2,6,6,6), fill=COLORS["cream"])
    elif kind == "expand":
        d.rectangle((2,2,6,6), outline=COLORS["cream"])
    elif kind == "close":
        d.line((2,2,6,6), fill=COLORS["cream"])
        d.line((6,2,2,6), fill=COLORS["cream"])
    return image


def stamp_icon(canvas, kind, position, scale=2):
    source = icon(kind)
    check = validate(source, list(source.size), PALETTE, 5)
    if not check["passed"]: raise ValueError(f"UI icon failed: {kind}")
    canvas.alpha_composite(source.resize((source.width*scale,source.height*scale),Image.Resampling.NEAREST),position)


def render_scene(rows):
    art = Image.new("RGBA", (180, 83))
    placements = {"window": [4, 5], "herb_station": [4, 40], "shelf_frame": [105, 1],
                  "poster": [153, 1], "counter": [105, 64], "witch": [72, 32],
                  "cauldron_moon": [41, 47], "elf": [148, 33]}
    frame = native("window")
    holes = enclosed_holes(frame)
    if len(holes) != 2: raise ValueError("Window must have two enclosed transparent panes")
    sky = Image.new("RGBA",frame.size)
    for area in holes:
        for x,y in area: sky.putpixel((x,y), (*rgb(COLORS["blue"]),255))
    d = ImageDraw.Draw(sky)
    left = holes[0]
    lx, ly = min(x for x,y in left), min(y for x,y in left)
    d.ellipse((lx+2,ly+2,lx+7,ly+7),fill=COLORS["cream"])
    d.ellipse((lx+5,ly+1,lx+8,ly+5),fill=COLORS["blue"])
    right = holes[1]
    rx, ry = min(x for x,y in right), min(y for x,y in right)
    d.rectangle((rx+2,ry+3,rx+6,ry+4),fill=COLORS["stone"])
    for x in (rx+2,rx+5): d.line((x,ry+6,x-1,ry+9),fill=COLORS["pale_mint"])
    # Keep weather inside the observed frame panes.
    hole_set = set(holes[0] + holes[1])
    for y in range(sky.height):
        for x in range(sky.width):
            if (x,y) not in hole_set: sky.putpixel((x,y),(0,0,0,0))
    art.alpha_composite(sky, tuple(placements["window"]))
    for id in ("window", "herb_station", "shelf_frame", "poster"):
        art.alpha_composite(native(id),tuple(placements[id]))
    boards = shelf_boards(native("shelf_frame"))
    stock_positions = []
    for index,id in enumerate(SELECTED):
        x = placements["shelf_frame"][0] + 5 + (index%4)*10
        y = placements["shelf_frame"][1] + boards[index//4] - native("potion_"+id).height
        stock_positions.append({"id":id,"position":[x,y]})
        art.alpha_composite(native("potion_"+id),(x,y))
    d = ImageDraw.Draw(art)
    d.ellipse((73,75,102,81),fill=COLORS["paper"],outline=COLORS["gold"])
    keeper = Image.open(ROOT/OLD/"witch-native.png").convert("RGBA")
    if not validate(keeper,[32,48],PALETTE,5)["passed"]: raise ValueError("Approved witch failed validation")
    art.alpha_composite(keeper,tuple(placements["witch"]))
    for id in ("cauldron_moon", "counter", "elf"):
        art.alpha_composite(native(id),tuple(placements[id]))
    # This bottle has already been sold; it is separate from the eight owned
    # stock instances. The mock state documents it explicitly.
    art.alpha_composite(native("potion_purify"),(154,57))
    enlarged = art.resize((540,249),Image.Resampling.NEAREST)
    screen = Image.new("RGBA",(540,300))
    screen.alpha_composite(enlarged.crop((0,0,540,248)),(0,0))
    d=ImageDraw.Draw(screen)
    # Current readable UI text is composed at screen resolution. Pixel art,
    # including furniture, characters and bottles, remains exactly 3x.
    d.rectangle((6,222,111,247),fill=COLORS["outline"],outline=COLORS["stone"])
    text(screen,(12,225),"9종 재배 중",14,"cream")
    d.rectangle((12,243,92,245),fill=COLORS["paper"])
    d.rectangle((12,243,66,245),fill=COLORS["leaf"])
    stamp_icon(screen,"search",(94,230),1)
    d.rectangle((120,85,215,114),fill=COLORS["outline"],outline=COLORS["stone"])
    stamp_icon(screen,"moon",(124,89),2)
    text(screen,(145,88),"제작 중",14,"cream")
    stamp_icon(screen,"search",(202,91),1)
    d.rectangle((126,109,197,111),fill=COLORS["paper"])
    d.rectangle((126,109,168,111),fill=COLORS["lilac"])
    # The poster's generated panel is a narrow 24x32 sprite, so use two short
    # lines instead of squeezing a six-character caption into it.
    paper_pixels = np.all(np.array(native("poster"))[:,:,:3] == rgb(COLORS["paper"]), axis=2)
    py,px = np.where(paper_pixels)
    paper_left = (placements["poster"][0] + int(px.min())) * 3
    paper_right = (placements["poster"][0] + int(px.max()) + 1) * 3
    paper_top = (placements["poster"][1] + int(py.min())) * 3
    paper_center = (paper_left + paper_right) // 2
    text(screen,(paper_center,paper_top+4),"2곳",14,"cream",anchor="mt")
    text(screen,(paper_center,paper_top+23),"탐사 중",14,"cream",anchor="mt")
    d.rectangle((paper_left+3,paper_top+41,paper_right-4,paper_top+43),fill=COLORS["outline"])
    d.rectangle((paper_left+3,paper_top+41,paper_center,paper_top+43),fill=COLORS["gold"])
    stamp_icon(screen,"search",(517,84),1)
    text(screen,(323,158),"재고 8 / 12",14,"cream")
    stamp_icon(screen,"coin",(324,176),1)
    text(screen,(337,174),"+24 G · 선호",14,"gold")
    # 52px toolbar and main controls match WorkshopLayout's current geometry.
    d.rectangle((0,248,539,299),fill=COLORS["outline"])
    d.line((0,248,539,248),fill=COLORS["wood"])
    stamp_icon(screen,"move",(9,266),2)
    stamp_icon(screen,"coin",(43,265),2)
    text(screen,(68,264),"1,284 G",17,"gold")
    stamp_icon(screen,"moon",(187,262),2)
    stamp_icon(screen,"rain",(225,262),2)
    text(screen,(254,266),"밤 · 비",14,"cream")
    for x,w,label in ((398,42,"관리"),(444,28,"minimize"),(476,28,"expand"),(508,28,"close")):
        d.rectangle((x,258,x+w-1,289),fill=COLORS["paper"],outline=COLORS["stone"])
        if label == "관리": text(screen,(x+5,264),label,16,"cream")
        else: stamp_icon(screen,label,(x+(w-18)//2,265),2)
    matte=Image.new("RGBA",screen.size,COLORS["mat"])
    matte.alpha_composite(screen)
    # Names are outside the scene: the runtime workshop does not display a
    # recipe catalogue grid. This separate QA sheet covers all 36 recipes.
    board=Image.new("RGBA",(720,582),COLORS["outline"])
    text(board,(24,18),"전체 물약 36종 · 동일한 24색 팔레트",22,"cream")
    text(board,(24,53),"일반 32종 + 특별 4종 / 기본 8×12 · 긴 병 8×16 / 공통 3배",14,"lilac")
    for index,row in enumerate(rows):
        col,row_index=index%6,index//6
        x,y=20+col*116,97+row_index*78
        bottle=native("potion_"+row["id"])
        board.alpha_composite(bottle.resize((bottle.width*3,bottle.height*3),Image.Resampling.NEAREST),(x+40,y))
        text(board,(x+52,y+55),row["name"],12,"gold" if row.get("rare") else "cream",anchor="mt")
    screen_check=validate(screen,[540,300],PALETTE,24)
    art_check=validate(art,[180,83],PALETTE,24)
    exact_scale=bool(np.array_equal(np.array(enlarged),np.repeat(np.repeat(np.array(art),3,axis=0),3,axis=1)))
    transparent_trim=not bool(np.array(enlarged)[248,:,3].any())
    if not screen_check["passed"] or not art_check["passed"] or not exact_scale or not transparent_trim:
        raise ValueError("Final full-screen validation failed")
    art.save(OUT/"workshop-art-native.png")
    enlarged.save(OUT/"workshop-art-3x.png")
    screen.save(OUT/"full-ingame-transparent.png")
    matte.convert("RGB").save(OUT/"full-ingame.png")
    matte.resize((1080,600),Image.Resampling.NEAREST).convert("RGB").save(OUT/"full-ingame-2x.png")
    board.convert("RGB").save(OUT/"potions-36-review.png")
    state={"status":"candidate", "validation_status":"passed", "approved_by_user":False, "image_size":[540,300],
           "art_native_size":[180,83], "art_scale":3, "art_height":248, "toolbar_height":52,
           "matte_is_preview_only":True, "placements":placements, "shelf_board_rows":boards,
           "visible_owned_stock":stock_positions, "inventory_count":8, "capacity":12,
           "current_brew":"moon", "sold_customer_potion":"purify", "customer":"elf",
           "sold_bottle_not_in_owned_stock":True, "gold":1284, "sale_gold":24,
           "active_growing_species":9, "active_expeditions":2, "environment":["night","rain"],
           "values_are_mock_state_not_player_save":True,
           "runtime_content_count":len(rows), "screen_validation":screen_check,
           "art_validation":art_check, "integer_art_scale_verified":exact_scale, "trimmed_row_was_transparent":transparent_trim,
           "source_code":["scripts/workshop_layout.gd","scripts/item_art.gd","scripts/potion_display.gd",
                          "scripts/shop_content.gd","scripts/rare_recipes.gd","data/content_expansion.json"],
           "scope_note":"Main workshop candidate at current window size; new art placements differ from current runtime coordinates. No game changes."}
    (OUT/"scene.json").write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows=content_rows()
    (OUT/"potion-identities.json").write_text(json.dumps(rows,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    prepare_manifest(rows)
    result=subprocess.run([sys.executable,str(ROOT/"tools/process_pixel_art.py"),"art/mockups/full-ingame-v1/manifest.json"],
                          cwd=ROOT,capture_output=True,text=True,encoding="utf-8")
    if result.returncode:
        (OUT/"scene.json").write_text(json.dumps({"status":"failed","validation_status":"failed","final_screen_from_this_run":False,"error":"Asset preprocessing failed"},indent=2)+"\n",encoding="utf-8")
        print(result.stdout)
        print(result.stderr)
        raise SystemExit(result.returncode)
    try:
        render_scene(rows)
    except (ValueError, KeyError, OSError) as error:
        (OUT/"scene.json").write_text(json.dumps({"status":"failed","validation_status":"failed","final_screen_from_this_run":False,"error":str(error)},indent=2)+"\n",encoding="utf-8")
        raise
    report=json.loads((OUT/"validation.json").read_text(encoding="utf-8"))
    print(json.dumps({"status":report["status"],"processed_assets":len(report["assets"]),
                      "potions":len(rows),"visible_potions":SELECTED,"size":[540,300],
                      "max_asset_colors":max(check["color_count"] for check in report["assets"].values()),
                      "off_palette_total":sum(check["off_palette_colors"] for check in report["assets"].values())},
                     ensure_ascii=False,indent=2))


if __name__ == "__main__":
    main()
