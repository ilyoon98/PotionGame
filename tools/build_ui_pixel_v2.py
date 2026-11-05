"""Normalize generated UI sheets using the project's fixed pixel-art pipeline.

Input PNGs in art/mockups/ui-pixel-v2/source are retained unchanged. This script
only registers their cells, writes explicit semantic material rules, invokes
process_pixel_art.py, and packages validated native sprites. It never uses a
nearest-palette-color lookup or redraws a source silhouette.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "art/mockups/ui-pixel-v2"
SOURCE = REVIEW / "source"
REGISTERED = REVIEW / "registered"
PIPELINE = REVIEW / "pipeline"
DEST = ROOT / "assets/ui_pixel_v2/icons"
OUTLINE = "#241C32"


def rule(material, hue=None, **limits):
    result = {"material": material, **limits}
    if hue is not None:
        result["hue"] = hue
    return result


def spec(name, materials, rules, fallback, **extra):
    return {
        "id": name, "materials": {"outline": [OUTLINE], **materials},
        "rules": rules, "fallback_material": fallback, **extra,
    }


# Hue classifications name materials (foliage, wood, glass, etc.), not target
# RGB distances. The subsequent ramp conversion ranks source luminance only
# inside each assigned material. Every sprite uses at most five output colors.
LEAF = [0.15, 0.39]
TEAL = [0.39, 0.62]
PURPLE = [0.62, 0.96]
WARM = [0.02, 0.15]

REGIONS = [
    spec("forest_edge", {"leaf": ["#718C59", "#B5C77D"], "wood": ["#916047", "#C99463"]},
         [rule("leaf", LEAF)], "wood"),
    spec("abandoned_greenhouse", {"wood": ["#916047"], "teal": ["#9BE2CF"], "leaf": ["#718C59"], "gold": ["#FFF0BC"]},
         [rule("gold", WARM, value_min=0.85), rule("teal", TEAL), rule("leaf", LEAF)], "wood"),
    spec("mist_valley", {"stone": ["#4A3C52", "#827589"], "teal": ["#3BA8A3"], "leaf": ["#718C59"]},
         [rule("teal", TEAL), rule("leaf", LEAF)], "stone"),
    spec("crystal_mine", {"stone": ["#4A3C52"], "purple": ["#86548E", "#C38EB5"], "gold": ["#E9B95F"]},
         [rule("gold", WARM), rule("purple", PURPLE, saturation_min=0.22, value_min=0.46)], "stone"),
    spec("fog_marsh", {"wood": ["#916047"], "leaf": ["#718C59"], "teal": ["#3BA8A3", "#9BE2CF"]},
         [rule("leaf", LEAF), rule("teal", TEAL)], "wood"),
    spec("forgotten_tower", {"stone": ["#4A3C52", "#827589"], "purple": ["#86548E"], "gold": ["#E9B95F"]},
         [rule("gold", WARM), rule("purple", PURPLE, saturation_min=0.3, y_min=0.55)], "stone"),
    spec("moon_ruins", {"stone": ["#4A3C52", "#827589"], "purple": ["#C38EB5"], "gold": ["#FFF0BC"]},
         [rule("gold", WARM, value_min=0.72), rule("purple", PURPLE, saturation_min=0.26, value_min=0.6)], "stone"),
    spec("star_garden", {"wood": ["#916047"], "leaf": ["#718C59"], "gold": ["#E9B95F", "#FFF0BC"]},
         [rule("leaf", LEAF), rule("gold", WARM, value_min=0.78)], "wood"),
    spec("dawn_lighthouse", {"gold": ["#E9B95F", "#FFF0BC"], "fire": ["#DE7356"], "teal": ["#3BA8A3"]},
         [rule("teal", TEAL), rule("fire", [0.0, 0.065], saturation_min=0.35), rule("outline", PURPLE)], "gold"),
]

MATERIALS = [
    spec("herb", {"leaf": ["#3D544D", "#718C59", "#B5C77D"], "wood": ["#916047"]},
         [rule("wood", WARM)], "leaf"),
    spec("moon_mushroom", {"teal": ["#24566A", "#3BA8A3", "#9BE2CF"], "gold": ["#FFF0BC"]},
         [rule("gold", WARM), rule("gold", saturation_max=0.18, value_min=0.7)], "teal"),
    spec("starleaf", {"purple": ["#86548E", "#C38EB5"], "leaf": ["#718C59"], "gold": ["#E9B95F"]},
         [rule("leaf", LEAF), rule("gold", WARM)], "purple"),
    spec("dewgrass", {"leaf": ["#718C59", "#B5C77D"], "teal": ["#3BA8A3", "#9BE2CF"]},
         [rule("teal", TEAL)], "leaf"),
    spec("silver_moss", {"leaf": ["#3D544D", "#718C59", "#B5C77D"], "gold": ["#FFF0BC"]},
         [rule("gold", saturation_max=0.25, value_min=0.78), rule("gold", WARM, value_min=0.8)], "leaf"),
    spec("blue_reed", {"teal": ["#24566A", "#3BA8A3", "#9BE2CF"], "leaf": ["#718C59"]},
         [rule("leaf", LEAF)], "teal"),
    spec("crystal_herb", {"purple": ["#86548E", "#C38EB5"], "leaf": ["#718C59"], "gold": ["#FFF0BC"]},
         [rule("leaf", LEAF), rule("gold", saturation_max=0.2, value_min=0.83)], "purple"),
    spec("mist_mushroom", {"purple": ["#86548E", "#C38EB5"], "gold": ["#FFF0BC"], "leaf": ["#718C59"]},
         [rule("leaf", LEAF), rule("gold", WARM), rule("gold", saturation_max=0.2, value_min=0.83)], "purple"),
    spec("ash_sage", {"stone": ["#4A3C52", "#827589"], "purple": ["#C38EB5"], "wood": ["#916047"]},
         [rule("wood", WARM), rule("purple", PURPLE, saturation_min=0.27, value_min=0.6)], "stone"),
    spec("moonflower", {"gold": ["#E9B95F", "#FFF0BC"], "leaf": ["#718C59", "#B5C77D"]},
         [rule("leaf", LEAF)], "gold"),
    spec("star_seed", {"gold": ["#E9B95F", "#FFF0BC"], "fire": ["#DE7356"], "wood": ["#916047"]},
         [rule("fire", [0.0, 0.065], saturation_min=0.42), rule("wood", WARM, value_max=0.55)], "gold"),
    spec("dawn_bloom", {"fire": ["#DE7356", "#F4AC68"], "gold": ["#FFF0BC"], "leaf": ["#718C59"]},
         [rule("leaf", LEAF), rule("gold", [0.1, 0.18], value_min=0.78)], "fire"),
]

ROLES = [
    spec("sales_assistant", {"purple": ["#50315F", "#86548E"], "gold": ["#E9B95F", "#FFF0BC"]},
         [rule("gold", WARM)], "purple"),
    spec("cultivation_assistant", {"wood": ["#916047"], "leaf": ["#718C59", "#B5C77D"], "gold": ["#FFF0BC"]},
         [rule("leaf", LEAF), rule("gold", WARM, value_min=0.84)], "wood"),
    spec("brewing_assistant", {"gold": ["#E9B95F", "#FFF0BC"], "wood": ["#916047"], "leaf": ["#718C59"]},
         [rule("leaf", LEAF), rule("wood", WARM, value_max=0.65)], "gold"),
    spec("expedition_guide", {"wood": ["#916047", "#C99463"], "gold": ["#FFF0BC"], "purple": ["#86548E"]},
         [rule("purple", PURPLE), rule("gold", WARM, value_min=0.87)], "wood"),
    spec("family_vitality", {"fire": ["#DE7356"], "highlight": ["#F4AC68"], "gold": ["#E9B95F"]},
         [rule("gold", [0.08, 0.17]), rule("highlight", saturation_max=0.5, value_min=0.88)], "fire",
         material_ramps={"highlight": "fire"}),
    spec("family_arcane", {"purple": ["#86548E", "#C38EB5"], "gold": ["#E9B95F", "#FFF0BC"]},
         [rule("gold", WARM)], "purple"),
    spec("family_nature", {"leaf": ["#718C59", "#B5C77D"], "gold": ["#E9B95F", "#FFF0BC"]},
         [rule("gold", WARM)], "leaf"),
    spec("family_craft", {"teal": ["#3BA8A3", "#9BE2CF"], "gold": ["#E9B95F"]},
         [rule("teal", TEAL)], "gold"),
    spec("flow", {"purple": ["#86548E"], "gold": ["#E9B95F", "#FFF0BC"], "teal": ["#3BA8A3"]},
         [rule("gold", WARM), rule("teal", TEAL)], "purple"),
    spec("basic", {"purple": ["#50315F", "#86548E"], "gold": ["#E9B95F"], "paper": ["#FFF0BC"]},
         [rule("paper", saturation_max=0.32, value_min=0.85), rule("gold", WARM)], "purple",
         material_ramps={"paper": "gold"}),
    spec("filter", {"wood": ["#916047"], "gold": ["#FFF0BC"], "teal": ["#3BA8A3", "#9BE2CF"]},
         [rule("teal", TEAL), rule("gold", WARM, value_min=0.72)], "wood"),
    spec("reputation", {"purple": ["#86548E", "#C38EB5"], "gold": ["#E9B95F"]},
         [rule("gold", WARM)], "purple"),
    spec("coin", {"gold": ["#A56A3D", "#E9B95F", "#FFF0BC"]}, [], "gold"),
    spec("visitors", {"purple": ["#86548E"], "leaf": ["#718C59"], "gold": ["#E9B95F", "#FFF0BC"]},
         [rule("gold", WARM), rule("leaf", LEAF)], "purple"),
    spec("unknown_recipe", {"wood": ["#916047"], "purple": ["#86548E"], "gold": ["#FFF0BC"]},
         [rule("purple", PURPLE), rule("gold", WARM, value_min=0.77)], "wood"),
    spec("expedition", {"wood": ["#916047"], "leaf": ["#718C59"], "gold": ["#E9B95F", "#FFF0BC"]},
         [rule("leaf", LEAF), rule("gold", WARM, value_min=0.77)], "wood"),
]

TRACKS = ["cauldron", "herb_pot", "sales_counter", "precision_filter", "herb_storage", "potion_cabinet", "drying_rack", "expedition_path"]
TIERS = ["basic", "improved", "premium"]
TRACK_SPECS = {
    "cauldron": spec("cauldron", {"purple": ["#86548E"], "shade": ["#50315F"], "gold": ["#E9B95F"], "teal": ["#3BA8A3"]},
                      [rule("teal", TEAL), rule("gold", WARM), rule("shade", value_max=0.4)], "purple",
                      material_ramps={"shade": "purple"}),
    "herb_pot": spec("herb_pot", {"wood": ["#916047"], "gold": ["#E9B95F"], "leaf": ["#718C59", "#B5C77D"]},
                      [rule("leaf", LEAF), rule("gold", WARM, value_min=0.8)], "wood"),
    "sales_counter": spec("sales_counter", {"wood": ["#916047", "#C99463"], "gold": ["#E9B95F"], "purple": ["#86548E"]},
                           [rule("purple", PURPLE), rule("gold", WARM, value_min=0.83)], "wood"),
    "precision_filter": spec("precision_filter", {"wood": ["#916047"], "gold": ["#FFF0BC"], "teal": ["#3BA8A3", "#9BE2CF"]},
                              [rule("teal", TEAL), rule("gold", WARM, value_min=0.72)], "wood"),
    "herb_storage": spec("herb_storage", {"wood": ["#916047", "#C99463"], "leaf": ["#718C59"], "gold": ["#E9B95F"]},
                          [rule("leaf", LEAF), rule("gold", WARM, value_min=0.83)], "wood"),
    "potion_cabinet": spec("potion_cabinet", {"wood": ["#916047", "#C99463"], "teal": ["#3BA8A3"], "gold": ["#FFF0BC"]},
                            [rule("teal", TEAL), rule("gold", WARM, value_min=0.87)], "wood"),
    "drying_rack": spec("drying_rack", {"wood": ["#916047", "#C99463"], "leaf": ["#718C59"], "gold": ["#E9B95F"]},
                         [rule("leaf", LEAF), rule("gold", WARM, value_min=0.83)], "wood"),
    "expedition_path": spec("expedition_path", {"wood": ["#916047"], "stone": ["#827589"], "leaf": ["#718C59"], "gold": ["#FFF0BC"]},
                             [rule("leaf", LEAF), rule("stone", PURPLE), rule("gold", WARM, value_min=0.87)], "wood"),
}
EQUIPMENT = [{**TRACK_SPECS[track], "id": f"{track}_{tier}"} for track in TRACKS for tier in TIERS]
SHEETS = {"regions": (3, 3, REGIONS), "materials": (4, 3, MATERIALS), "roles": (4, 4, ROLES), "equipment": (6, 4, EQUIPMENT)}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def cell_boundaries(sheet: Image.Image, columns: int, rows: int):
    """Register cells on actual empty gutters, never through a sprite.

    A generated 4x4 sheet need not land on exact quarter-image coordinates.
    Select the nearest fully transparent gap to each requested grid line.
    An opaque pixel is never erased just to make the nominal grid fit.
    """
    solid = np.asarray(sheet)[:, :, 3] >= 128
    boundaries = []
    for axis, count in ((0, columns), (1, rows)):
        empty = ~solid.any(axis=axis)
        starts = np.where(empty & ~np.r_[False, empty[:-1]])[0]
        ends = np.where(empty & ~np.r_[empty[1:], False])[0] + 1
        gaps = [(int(start), int(end)) for start, end in zip(starts, ends)]
        dimension = len(empty)
        splits = [0]
        for index in range(1, count):
            expected = index * dimension / count
            candidates = [(start, end) for start, end in gaps
                          if start > 0 and end < dimension and
                          abs((start + end) / 2 - expected) < dimension / count * 0.35]
            if not candidates:
                raise ValueError(f"No empty gutter near grid boundary {index}/{count}")
            start, end = min(candidates, key=lambda gap: abs((gap[0] + gap[1]) / 2 - expected))
            splits.append((start + end) // 2)
        splits.append(dimension)
        if any(a >= b for a, b in zip(splits, splits[1:])):
            raise ValueError("Source sheet gutters do not form ordered cells")
        boundaries.append(splits)
    return boundaries


def boundary_violations(image):
    pixels = np.array(image.convert("RGBA"))
    solid = pixels[:, :, 3] == 255
    padded = np.pad(solid, 1)
    inside = padded[1:-1, :-2] & padded[1:-1, 2:] & padded[:-2, 1:-1] & padded[2:, 1:-1]
    boundary = solid & ~inside
    return int(np.any(pixels[:, :, :3] != (36, 28, 50), axis=2)[boundary].sum())


def names():
    content = json.loads((ROOT / "data/content_expansion.json").read_text(encoding="utf-8"))
    result = {item["id"]: item["name"] for category in ("regions", "materials", "employees") for item in content[category]}
    result.update({"family_" + item["id"]: item["name"] for item in content["families"]})
    result.update({
        "flow": "자동 운영", "basic": "기본 레시피", "filter": "정밀 여과", "reputation": "명성",
        "coin": "골드", "visitors": "손님", "unknown_recipe": "미발견 레시피", "expedition": "원정",
        "reputation_small": "명성 · 작은 표시", "coin_small": "골드 · 작은 표시",
    })
    equipment = {}
    for item in content["upgrades"]:
        if item["track"] in TRACKS:
            equipment.setdefault(item["track"], item["name"])
    for track, name in equipment.items():
        for tier, label in zip(TIERS, ["기본", "개량", "고급"]):
            result[f"{track}_{tier}"] = f"{name} · {label}"
    return result


def review_board(group, entries):
    columns = SHEETS[group][0]
    rows = (len(entries) + columns - 1) // columns
    board = Image.new("RGB", (columns * 220, 60 + rows * 155), "#30273F")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 13)
    title = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 20)
    draw.text((20, 15), f"{group} · 32px / 3× / ≤5 colors", font=title, fill="#FFF0BC")
    labels = names()
    for i, entry in enumerate(entries):
        x, y = (i % columns) * 220, 60 + (i // columns) * 155
        icon = Image.open(DEST / (entry["id"] + ".png")).convert("RGBA")
        board.paste(icon.resize((96, 96), Image.Resampling.NEAREST), (x + 62, y), icon.resize((96, 96), Image.Resampling.NEAREST))
        draw.text((x + 12, y + 103), labels[entry["id"]], font=font, fill="#FFF0BC")
        draw.text((x + 12, y + 124), entry["id"], font=font, fill="#C38EB5")
    board.save(REVIEW / f"{group}-review.png")


def overview_board(paths):
    sections = [
        ("원정 지역", [x["id"] for x in REGIONS]),
        ("약초와 재료", [x["id"] for x in MATERIALS]),
        ("직원 역할 · 물약 계열", [x["id"] for x in ROLES[:8]]),
        ("운영과 관리", [x["id"] for x in ROLES[8:]]),
        ("설비 · 기본 / 개량 / 고급", [x["id"] for x in EQUIPMENT]),
        ("작은 표시", ["coin_small", "reputation_small"]),
    ]
    sections = [(label, [key for key in keys if key in paths]) for label, keys in sections]
    sections = [(label, keys) for label, keys in sections if keys]
    width, columns, cell_height = 1092, 6, 145
    height = 112 + sum(50 + ((len(keys) + columns - 1) // columns) * cell_height for _, keys in sections)
    board = Image.new("RGB", (width, height), "#FAFAF4")
    draw = ImageDraw.Draw(board)
    title = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 26)
    heading = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 20)
    font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 14)
    utility = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 11)
    draw.text((24, 20), "달그늘 물약상점 · 아이콘 통일", font=title, fill=OUTLINE)
    draw.text((24, 62), f"{len(paths)}개 · 원본 32×32 (작은 표시 16×16) · 공통 3배 · 승인 팔레트 · 그림당 최대 5색", font=font, fill="#4A3C52")
    y = 112
    labels = names()
    for section, keys in sections:
        draw.text((24, y), section, font=heading, fill=OUTLINE)
        y += 42
        for index, key in enumerate(keys):
            x = 18 + (index % columns) * 176
            top = y + (index // columns) * cell_height
            draw.rectangle((x, top, x + 168, top + 134), fill="#E6EBDD" if index % 2 else "#FFFFFF")
            icon = Image.open(DEST / f"{key}.png").convert("RGBA")
            display = icon.resize((icon.width * 3, icon.height * 3), Image.Resampling.NEAREST)
            board.paste(display, (x + (168 - display.width) // 2, top + (100 - display.height) // 2), display)
            draw.text((x + 8, top + 102), labels[key], font=font, fill=OUTLINE)
            draw.text((x + 8, top + 120), key, font=utility, fill="#4A3C52")
        y += ((len(keys) + columns - 1) // columns) * cell_height + 8
    board.save(REVIEW / "icons-overview-light.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--groups", nargs="+", choices=list(SHEETS), default=list(SHEETS))
    args = parser.parse_args()
    REGISTERED.mkdir(parents=True, exist_ok=True)
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = {
        "output": rel(PIPELINE), "palette": "art/palette.hex", "ramps": "art/ramps.json",
        "status": "user_requested_style_unification", "approved_by_user": False,
        "scale": 3, "alpha_threshold": 128, "max_colors": 5, "compose": False,
        "scene": {"size": [32, 32], "background": OUTLINE}, "assets": [],
        "source_sheets": {},
    }
    groups = {}
    for name in args.groups:
        path = SOURCE / f"{name}.png"
        if not path.exists():
            print(f"Pending source sheet: {rel(path)}")
            continue
        columns, rows, entries = SHEETS[name]
        sheet = Image.open(path).convert("RGBA")
        xcuts, ycuts = cell_boundaries(sheet, columns, rows)
        manifest["source_sheets"][name] = {"path": rel(path), "sha256": digest(path), "grid": [columns, rows], "size": list(sheet.size), "x_cuts": xcuts, "y_cuts": ycuts}
        groups[name] = entries
        for i, item in enumerate(entries):
            x, y = i % columns, i // columns
            bounds = [xcuts[x], ycuts[y], xcuts[x + 1], ycuts[y + 1]]
            crop = sheet.crop(bounds)
            mask = np.asarray(crop)[:, :, 3] >= 128
            yy, xx = np.where(mask)
            if not len(xx):
                raise ValueError(f"{item['id']}: empty registered source")
            used = [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1]
            if used[0] == 0 or used[1] == 0 or used[2] == crop.width or used[3] == crop.height:
                raise ValueError(f"{item['id']}: source sprite touches registered crop edge")
            crop_path = REGISTERED / f"{item['id']}.png"
            crop.save(crop_path)
            manifest["assets"].append({
                **item, "source": rel(crop_path), "source_sheet": rel(path), "source_cell": [x, y],
                "source_crop": bounds, "size": [32, 32], "position": [0, 0], "margin": 2,
                "source_opaque_bbox": used, "source_crop_edge_contacts": 0,
                "dark_value": 0.24, "preserve_source_outline": False,
            })
            if item["id"] in ("reputation", "coin"):
                manifest["assets"].append({
                    **manifest["assets"][-1], "id": item["id"] + "_small", "size": [16, 16], "margin": 1,
                })
    if not manifest["assets"]:
        raise SystemExit("No source sheets available; nothing was published")
    write_json(REVIEW / "manifest.json", manifest)
    result = subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"), rel(REVIEW / "manifest.json")], cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    if result.returncode:
        print(result.stdout)
        print(result.stderr)
        raise SystemExit(result.returncode)
    report = json.loads((PIPELINE / "validation.json").read_text(encoding="utf-8"))
    if report["status"] != "passed":
        raise SystemExit("Fixed pixel pipeline failed; no runtime copy performed")
    paths = {}
    for item in manifest["assets"]:
        native = PIPELINE / f"{item['id']}-native.png"
        sprite = Image.open(native).convert("RGBA")
        violations = boundary_violations(sprite)
        if violations:
            raise SystemExit(f"{item['id']}: {violations} common-outline violations; no publication")
        report["assets"][item["id"]]["boundary_color_violations"] = violations
        report["assets"][item["id"]]["source_crop_edge_contacts"] = item["source_crop_edge_contacts"]
        report["assets"][item["id"]]["source_opaque_bbox"] = item["source_opaque_bbox"]
    for item in manifest["assets"]:
        native = PIPELINE / f"{item['id']}-native.png"
        path = DEST / f"{item['id']}.png"
        path.write_bytes(native.read_bytes())
        paths[item["id"]] = "res://" + rel(path)
    report["runtime_paths"] = paths
    report["source_sheets"] = manifest["source_sheets"]
    write_json(REVIEW / "icon-validation.json", report)
    equipment = {
        track: [paths[f"{track}_{tier}"] for tier in TIERS]
        for track in TRACKS if all(f"{track}_{tier}" in paths for tier in TIERS)
    }
    write_json(REVIEW / "generated-icons.json", {"icons": paths, "equipment": equipment})
    for name, entries in groups.items():
        review_board(name, entries)
    overview_board(paths)
    print(json.dumps({"status": report["status"], "published": len(paths), "groups": list(groups), "report": rel(REVIEW / "icon-validation.json")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
