"""F26 new region (새벽 등대) + four potions: candidate art for approval.

Candidate only. Nothing under assets/, scripts/ or data/ is written; player saves, the running game and
Windows registration are untouched.

Sources are hand-authored letter maps in art/mockups/f26-region-potions-v1/source/*.txt:
  - four shelf bottles in the approved display grid (8x12, the lighthouse bottle 8x16),
  - four 32x40 potion icons and four 32x40 recipe icons (the size/format of the existing
    assets/content_expansion_v1/potions/*_icon.png and assets/rare_recipes_v1/recipes/*_recipe.png),
  - one 32x40 material icon (dawn_bloom) and one 32x40 region icon (dawn_lighthouse).
Each map is registered as a native PNG and run through the fixed tools/process_pixel_art.py pipeline with an
explicit per-letter material manifest (no nearest-colour lookup). Extra checks: outline on every silhouette edge,
approved 24 colours only, <=5 colours, no partial alpha, <=3 shades per ramp, no 3x3 dithering, top-left
lighting for bottles, silhouettes different from all 36 existing bottles.

Cauldron liquids: the approved pot frames (assets/pixel_v1/pots/health-{0,1,2}.png) are recoloured only inside the
63-pixel liquid mask from assets/pixel_v1/catalog.json, exactly like the runtime does for the existing 36 potions.
The new liquid colours must not be a cauldron body colour (#86548E body, #827589 stone, #E9B95F emblem, #241C32
outline) and must differ from the 36 existing liquid colours. The comparison uses the main-branch F25 liquid
recolour (2026-11-05: stealth / nightwalk / arcane_amplification / shadow_elixir no longer use #86548E), which is
not in this branch's assets, so it is re-applied here for display only.

Run with Pillow + NumPy: python tools/build_f26_region_potions_v1.py
"""
from __future__ import annotations

import colorsys
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "art/mockups/f26-region-potions-v1"
SRC = MOCK / "source"
REG = MOCK / "registered"
PIPE = MOCK / "pipeline"
SPRITES = MOCK / "sprites"
POTS = MOCK / "pots"
COMPARE = MOCK / "compare"
SCALE = 3
DATE = "2026-11-05"
OUTLINE_HEX = "#241C32"
OUTLINE = (0x24, 0x1C, 0x32)
POT_BODY = {"#86548E": "솥 몸체", "#827589": "솥 돌 테·다리", "#E9B95F": "솥 달 문양", "#241C32": "외곽선"}
PALETTE = ["#" + line.strip().upper().lstrip("#") for line in (ROOT / "art/palette.hex").read_text(encoding="utf-8").splitlines() if line.strip()]
RAMPS = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
CATALOG = json.loads((ROOT / "assets/pixel_v1/catalog.json").read_text(encoding="utf-8"))

# main-branch F25 liquid recolour (art/mockups/f25-potion-liquid-fix-v1/recolor.json), display-only here.
F25 = {
    "stealth": {"ramp": "leaf", "liquid": "#718C59", "map": {"#86548E": "#718C59", "#50315F": "#3D544D"}},
    "nightwalk": {"ramp": "teal", "liquid": "#3BA8A3", "map": {"#86548E": "#3BA8A3", "#50315F": "#24566A"}},
    "arcane_amplification": {"ramp": "purple", "liquid": "#C38EB5", "map": {"#86548E": "#C38EB5", "#50315F": "#86548E"}},
    "shadow_elixir": {"ramp": "purple", "liquid": "#C38EB5", "map": {"#86548E": "#C38EB5", "#50315F": "#86548E"}},
}

POTIONS = [
    {"id": "sunrise", "name": "해돋이 물약", "family": "vitality", "family_ko": "활력", "customer": "여행자", "ramp": "fire",
     "light": "#F4AC68", "dark": "#DE7356", "liquid": "#F4AC68", "bottle_size": [8, 12],
     "bottle": "평평한 수평선 바닥 위의 둥근 돔(떠오르는 해). 바닥 행이 병 폭 전체인 유일한 8×12 병.",
     "icon": "같은 돔 병을 32×40으로 다시 그림. 산호색 반원 해와 빛살, 수평선.",
     "recipe": "두루마리 원형 인장 안에 귤빛 해와 빛살, 크림 수평선."},
    {"id": "beacon", "name": "등대불 물약", "family": "craft", "family_ko": "기교", "customer": "고양이 도적", "ramp": "gold",
     "light": "#E9B95F", "dark": "#A56A3D", "liquid": "#A56A3D", "bottle_size": [8, 16],
     "bottle": "4→6→8칸으로 넓어지는 등대 탑 모양 긴 병. 꼭대기 버터색 등불, 탑에 버터색 띠 2줄.",
     "icon": "코르크색 뾰족 지붕(마개)·등불 방·버터색 띠 3줄의 등대 탑.",
     "recipe": "호박색 인장 안에 작은 등대(등불·띠)."},
    {"id": "sea_spray", "name": "물보라 물약", "family": "nature", "family_ko": "자연", "customer": "엘프", "ramp": "teal",
     "light": "#9BE2CF", "dark": "#24566A", "liquid": "#24566A", "bottle_size": [8, 12],
     "bottle": "어깨가 넓고 아래로 뾰족해지는 거꾸로 된 물방울. 윗줄 전체가 민트 물거품, 몸통은 깊은 청록.",
     "icon": "같은 거꾸로 물방울 병, 위쪽 물거품 띠와 크림색 소용돌이 파도 문양.",
     "recipe": "깊은 청록 인장 안에 민트 소용돌이 파도와 크림 물마루."},
    {"id": "sun_moon_elixir", "name": "일월의 물약", "family": "arcane", "family_ko": "비술", "customer": "여마법사", "ramp": "fire",
     "light": "#F4AC68", "dark": "#9D4359", "liquid": "#9D4359", "bottle_size": [8, 12],
     "bottle": "짧은 목·둥근 몸통·가는 대·받침이 있는 잔 모양 병. 진홍 액체 안 왼쪽 위 귤빛 해 2×2.",
     "icon": "받침 달린 둥근 구슬 병. 진홍 액체 안에 귤빛 해와 크림색 초승달.",
     "recipe": "진홍 인장 안에 귤빛 해와 크림 초승달."},
]
EXTRA = [
    {"id": "dawn_bloom_icon", "name": "여명초 (재료)", "kind": "material", "size": [32, 40],
     "legend": {"#": ("#241C32", "outline", "outline"), "L": ("#F4AC68", "fire", "petal_light"), "D": ("#DE7356", "fire", "petal_shade"),
                "h": ("#FFF0BC", "gold", "flower_heart"), "G": ("#718C59", "leaf", "leaf_and_stem")},
     "description": "여섯 꽃잎의 귤빛 꽃(오른쪽 아래 꽃잎은 산호 그늘), 크림색 꽃심, 줄기와 세이지 잎 2장. 기존 재료 아이콘과 같은 32×40."},
    {"id": "dawn_lighthouse_icon", "name": "새벽 등대 (지역)", "kind": "region", "size": [32, 40],
     "legend": {"#": ("#241C32", "outline", "outline"), "L": ("#F4AC68", "fire", "sun_and_lamp"), "r": ("#DE7356", "fire", "roof_and_stripes"),
                "h": ("#FFF0BC", "gold", "tower"), "s": ("#827589", "stone", "cliff")},
     "description": "돌 절벽 위 흰 등대(산호 띠 2줄·지붕, 귤빛 등불)와 뒤로 떠오르는 해. 기존 지역 아이콘과 같은 32×40."},
]
EXISTING_ICONS = [
    ("assets/content_expansion_v1/potions/eternity_icon.png", "영원 (기존 물약 아이콘)"),
    ("assets/content_expansion_v1/potions/sage_elixir_icon.png", "현자의 물약 (기존 물약 아이콘)"),
    ("assets/rare_recipes_v1/potions/rare_nebula_distillate_icon.png", "성운 증류액 (기존 특별 물약 아이콘)"),
    ("assets/rare_recipes_v1/recipes/rare_nebula_distillate_recipe.png", "성운 증류액 (기존 레시피 아이콘)"),
    ("assets/content_expansion_v1/materials/star_seed_icon.png", "별씨 (기존 재료 아이콘)"),
    ("assets/content_expansion_v1/regions/star_garden_icon.png", "별의 정원 (기존 지역 아이콘)"),
]


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def hexs(color) -> str:
    return "#%02X%02X%02X" % tuple(int(c) for c in color[:3])


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def luminance(color) -> float:
    values = np.asarray(color, dtype=float) / 255.0
    linear = np.where(values <= 0.04045, values / 12.92, ((values + 0.055) / 1.055) ** 2.4)
    return float(linear @ np.array([0.2126, 0.7152, 0.0722]))


def lab(value: str):
    r, g, b = (c / 255 for c in rgb(value))
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = f(r), f(g), f(b)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    t = lambda v: v ** (1 / 3) if v > 0.008856 else 7.787 * v + 16 / 116
    return 116 * t(y) - 16, 500 * (t(x) - t(y)), 200 * (t(y) - t(z))


def delta_e(a: str, b: str) -> float:
    return round(float(np.linalg.norm(np.subtract(lab(a), lab(b)))), 1)


def exact_rules(colors: dict[str, str]) -> list[dict]:
    rules = []
    for material, value in colors.items():
        h, s, v = colorsys.rgb_to_hsv(*(np.array(rgb(value)) / 255.0))
        rules.append({"material": material, "hue": [round(h - .004, 4), round(h + .004, 4)],
                      "saturation_min": round(s - .01, 4), "saturation_max": round(s + .01, 4),
                      "value_min": round(v - .01, 4), "value_max": round(v + .01, 4)})
    return rules


# ---------------------------------------------------------------- assets
def potion_legend(p: dict, kind: str) -> dict:
    if kind == "recipe":
        legend = {"#": ("#241C32", "outline", "outline"), "h": ("#FFF0BC", "gold", "parchment"), "g": ("#E9B95F", "gold", "scroll_roll")}
        legend["L"] = (p["light"], p["ramp"], "emblem_light")
        legend["D"] = (p["dark"], p["ramp"], "emblem_dark")
        return legend
    legend = {"#": ("#241C32", "outline", "outline"), "c": ("#916047", "wood", "cork"), "h": ("#FFF0BC", "gold", "glass_glint")}
    legend["L"] = (p["light"], p["ramp"], "liquid_light")
    legend["D"] = (p["dark"], p["ramp"], "liquid_dark")
    return legend


def assets() -> list[dict]:
    items = []
    for p in POTIONS:
        items.append({"id": p["id"] + "_bottle", "potion": p["id"], "kind": "bottle", "name": p["name"] + " · 진열 병",
                      "size": p["bottle_size"], "legend": potion_legend(p, "bottle"), "description": p["bottle"]})
        items.append({"id": p["id"] + "_icon", "potion": p["id"], "kind": "icon", "name": p["name"] + " · 물약 아이콘",
                      "size": [32, 40], "legend": potion_legend(p, "icon"), "description": p["icon"]})
        items.append({"id": p["id"] + "_recipe", "potion": p["id"], "kind": "recipe", "name": p["name"] + " · 레시피 아이콘",
                      "size": [32, 40], "legend": potion_legend(p, "recipe"), "description": p["recipe"]})
    items.extend(EXTRA)
    return items


def read_map(path: Path) -> list[str]:
    rows = [line.rstrip("\r\n") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows or any(len(r) != len(rows[0]) for r in rows):
        raise SystemExit(f"Map rows must share one width: {rel(path)}")
    return rows


def render(rows: list[str], legend: dict) -> Image.Image:
    data = np.zeros((len(rows), len(rows[0]), 4), dtype=np.uint8)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            if ch not in legend:
                raise SystemExit(f"Undeclared letter {ch!r} at {x},{y}")
            data[y, x] = (*rgb(legend[ch][0]), 255)
    return Image.fromarray(data)


def manifest_entry(item: dict, source: Path) -> dict:
    letters = {c: v for c, v in item["legend"].items() if c != "#"}
    materials = {"outline": [OUTLINE_HEX]}
    ramps = {}
    seen = {}
    for c, (color, ramp, material) in letters.items():
        materials[material] = [color]
        ramps[material] = ramp
        seen.setdefault(color, material)
    # Bottles keep the approved 36-bottle construction: the cork top row touches transparency at its sides
    # (assets/pixel_v1/potions/*.png row 1 "...cc..."), so the pipeline must not turn that cork into outline.
    return {"id": item["id"], "source": rel(source), "size": list(item["size"]), "position": [0, 0], "margin": 0,
            "dark_value": 0.24, "preserve_native_frame": True, "preserve_source_outline": item["kind"] == "bottle",
            "materials": materials, "material_ramps": ramps,
            "rules": exact_rules({m: c for c, m in seen.items()}), "fallback_material": next(iter(ramps)),
            "name_ko": item["name"]}


def run_pipeline(items: list[dict]) -> dict:
    manifest = {"output": rel(PIPE), "palette": "art/palette.hex", "ramps": "art/ramps.json", "status": "candidate",
                "approved_by_user": False, "scale": SCALE, "alpha_threshold": 128, "max_colors": 5, "compose": False,
                "scene": {"size": [32, 40], "background": OUTLINE_HEX},
                "assets": [manifest_entry(item, REG / f"{item['id']}.png") for item in items]}
    path = MOCK / "manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result = subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"), rel(path)], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8")
    report = json.loads((PIPE / "validation.json").read_text(encoding="utf-8"))
    if result.returncode != 0 or report["status"] != "passed":
        raise SystemExit(f"process_pixel_art failed: {report.get('error')}\n{result.stderr}")
    return report


# ---------------------------------------------------------------- checks
def outline_violations(data: np.ndarray) -> list[list[int]]:
    opaque = data[:, :, 3] == 255
    padded = np.pad(opaque, 1)
    boundary = opaque & ~(padded[1:-1, :-2] & padded[1:-1, 2:] & padded[:-2, 1:-1] & padded[2:, 1:-1])
    bad = boundary & ~np.all(data[:, :, :3] == OUTLINE, axis=2)
    return [[int(x), int(y)] for y, x in zip(*np.where(bad))]


def dither_blocks(data: np.ndarray) -> list[list[int]]:
    found = []
    h, w = data.shape[:2]
    for y in range(h - 2):
        for x in range(w - 2):
            block = data[y:y + 3, x:x + 3]
            if not np.all(block[:, :, 3] == 255):
                continue
            even = {tuple(block[j, i, :3]) for j in range(3) for i in range(3) if (i + j) % 2 == 0}
            odd = {tuple(block[j, i, :3]) for j in range(3) for i in range(3) if (i + j) % 2 == 1}
            if len(even) == 1 and len(odd) == 1 and even != odd and OUTLINE not in even | odd:
                found.append([x, y])
    return found


def lighting(data: np.ndarray) -> dict:
    opaque = data[:, :, 3] == 255
    ys, xs = np.where(opaque)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    tl, br = [], []
    for y, x in zip(ys, xs):
        color = tuple(data[y, x, :3])
        if color == OUTLINE:
            continue
        side = (x - cx) + (y - cy)
        (tl if side < 0 else br if side > 0 else []).append(luminance(color))
    result = {"top_left_mean": round(float(np.mean(tl)), 4), "bottom_right_mean": round(float(np.mean(br)), 4)}
    result["top_left_lit"] = result["top_left_mean"] > result["bottom_right_mean"]
    return result


def check_sprite(item: dict, image: Image.Image, registered: Image.Image, pipe: dict) -> dict:
    data = np.array(image.convert("RGBA"))
    alpha = data[:, :, 3]
    opaque = alpha == 255
    colors = sorted({hexs(p) for p in data[opaque]})
    by_ramp: dict[str, set] = {}
    for color, ramp, _material in item["legend"].values():
        by_ramp.setdefault(ramp, set()).add(color)
    check = {
        "name": item["name"], "kind": item["kind"], "native_size": list(image.size), "expected_size": list(item["size"]),
        "display_size_x3": [image.width * SCALE, image.height * SCALE], "colors": colors, "color_count": len(colors),
        "off_palette_colors": sum(1 for c in colors if c not in PALETTE),
        "partial_alpha_pixels": int(((alpha != 0) & (alpha != 255)).sum()),
        "outline_violations": outline_violations(data), "dither_3x3_blocks": dither_blocks(data),
        "materials": {m: {"letter": c, "color": col, "ramp": r} for c, (col, r, m) in item["legend"].items()},
        "colors_in_declared_ramps": all(col in RAMPS["ramps"][r]["colors"] for col, r, _m in item["legend"].values()),
        "shades_per_ramp": {r: len(v) for r, v in by_ramp.items()},
        "opaque_pixels": int(opaque.sum()), "lighting": lighting(data),
        "pipeline_passed": pipe["passed"],
        "pipeline_preserved_source": bool(np.array_equal(np.array(registered.convert("RGBA")), data)),
        "native_sha256": hashlib.sha256(data.tobytes()).hexdigest(),
    }
    cork_ok = True
    if item["kind"] == "bottle":
        # Same construction as every approved bottle: only the visible cork row (y=1) touches transparency.
        cork = [p for p in check["outline_violations"] if hexs(data[p[1], p[0]]) == "#916047" and p[1] <= 2]
        approved = outline_violations(np.array(Image.open(ROOT / "assets/pixel_v1/potions/health.png").convert("RGBA")))
        check["cork_edge_pixels"] = cork
        check["approved_bottle_cork_edge_pixels"] = approved
        check["outline_violations"] = [p for p in check["outline_violations"] if p not in cork]
        cork_ok = cork == approved
    ok = (check["native_size"] == check["expected_size"] and check["color_count"] <= 5 and OUTLINE_HEX in colors
          and check["off_palette_colors"] == 0 and check["partial_alpha_pixels"] == 0 and not check["outline_violations"]
          and not check["dither_3x3_blocks"] and check["colors_in_declared_ramps"] and cork_ok
          and all(n <= 3 for n in check["shades_per_ramp"].values()) and check["pipeline_passed"]
          and check["pipeline_preserved_source"] and set(colors) == {v[0] for v in item["legend"].values()})
    if item["kind"] == "bottle":
        ok = ok and check["lighting"]["top_left_lit"]
        rows = np.where(opaque.any(axis=1))[0]
        check["bottom_row"] = int(rows.max())
        check["bottom_row_is_canvas_bottom"] = int(rows.max()) == image.height - 1
        ok = ok and check["bottom_row_is_canvas_bottom"]
    else:
        check["lighting_note"] = "32×40 아이콘은 참고값(해·절벽 배치상 강제하지 않음). 병은 필수."
    check["passed"] = bool(ok)
    return check


# ---------------------------------------------------------------- existing bottles / pots
def existing_bottle(pid: str) -> Image.Image:
    image = Image.open(ROOT / f"assets/pixel_v1/potions/{pid}.png").convert("RGBA")
    if pid in F25:
        data = np.array(image)
        out = data.copy()
        for src, dst in F25[pid]["map"].items():
            mask = np.all(data[:, :, :3] == rgb(src), axis=2) & (data[:, :, 3] == 255)
            out[mask, :3] = rgb(dst)
        image = Image.fromarray(out)
    return image


def existing_liquids() -> dict[str, str]:
    result = {}
    for pid, row in CATALOG["potions"].items():
        result[pid] = F25[pid]["liquid"] if pid in F25 else row["liquid_color"].upper()
    return result


def make_pots(potions: list[dict]) -> dict:
    mask = {tuple(p) for p in CATALOG["liquid_pixels"]}
    base_liquid = CATALOG["potions"]["health"]["liquid_color"].upper()
    report = {"source_frames": [], "liquid_mask_pixels": len(mask), "potions": {}}
    POTS.mkdir(parents=True, exist_ok=True)
    frames = []
    for i in range(3):
        path = ROOT / f"assets/pixel_v1/pots/health-{i}.png"
        report["source_frames"].append(rel(path))
        frames.append(np.array(Image.open(path).convert("RGBA")))
    body_colors = sorted({hexs(frames[0][y, x]) for y in range(32) for x in range(32)
                          if frames[0][y, x, 3] == 255 and (x, y) not in mask})
    report["body_colors"] = body_colors
    for p in potions:
        entry = {"liquid": p["liquid"], "frames": [], "outside_mask_identical": True}
        for i, data in enumerate(frames):
            out = data.copy()
            changed = 0
            for (x, y) in mask:
                if out[y, x, 3] == 255 and hexs(out[y, x]) == base_liquid:
                    out[y, x, :3] = rgb(p["liquid"])
                    changed += 1
            outside = np.ones((32, 32), dtype=bool)
            for (x, y) in mask:
                outside[y, x] = False
            same = bool(np.array_equal(out[outside], data[outside]))
            entry["outside_mask_identical"] = entry["outside_mask_identical"] and same
            name = f"{p['id']}-{i}.png"
            Image.fromarray(out).save(POTS / name)
            Image.fromarray(out).resize((96, 96), Image.Resampling.NEAREST).save(POTS / f"{p['id']}-{i}-3x.png")
            entry["frames"].append({"path": rel(POTS / name), "recoloured_pixels": changed})
        entry["is_pot_body_color"] = p["liquid"] in body_colors
        entry["delta_e_to_pot"] = {c: delta_e(p["liquid"], c) for c in body_colors}
        # Large surfaces next to the liquid: body and stone rim need a clear gap (ΔE>=25). The small crescent
        # emblem and the outline only must not be identical (reported, not thresholded).
        entry["large_surface_gap_ok"] = all(entry["delta_e_to_pot"][c] >= 25 for c in ("#86548E", "#827589"))
        entry["passed"] = entry["outside_mask_identical"] and not entry["is_pot_body_color"] and entry["large_surface_gap_ok"]
        report["potions"][p["id"]] = entry
    return report


def colour_report(potions: list[dict]) -> dict:
    old = existing_liquids()
    new = {p["id"]: p["liquid"] for p in potions}
    rows = {}
    for p in potions:
        others = {pid: delta_e(p["liquid"], c) for pid, c in old.items()}
        nearest = min(others, key=others.get)
        siblings = {q["id"]: delta_e(p["liquid"], q["liquid"]) for q in potions if q["id"] != p["id"]}
        rows[p["id"]] = {"liquid": p["liquid"], "ramp": p["ramp"], "bottle_colors": [p["light"], p["dark"]],
                         "same_as_existing_liquid": [pid for pid, c in old.items() if c == p["liquid"]],
                         "nearest_existing": {"id": nearest, "color": old[nearest], "delta_e": others[nearest]},
                         "delta_e_to_new_siblings": siblings,
                         "bottle_pair_used_by_existing": []}
    pairs = {}
    for pid in CATALOG["potions"]:
        data = np.array(existing_bottle(pid))
        cols = {hexs(px) for px in data[data[:, :, 3] == 255]} - {OUTLINE_HEX, "#916047", "#FFF0BC"}
        pairs[pid] = cols
    for p in potions:
        rows[p["id"]]["bottle_pair_used_by_existing"] = [pid for pid, cols in pairs.items() if cols == {p["light"], p["dark"]}]
    # Required: the cauldron liquid colour is new (none of the 36 uses it) and the four are apart from each other.
    # A shared two-colour bottle set is reported; the bottle itself must still differ by silhouette (silhouettes).
    passed = all(not r["same_as_existing_liquid"] and min(r["delta_e_to_new_siblings"].values()) >= 20 for r in rows.values())
    return {"existing_liquids_used": old, "new": rows, "passed": passed,
            "note": "ΔE = CIE76 Lab 거리. 10 이상이면 나란히 볼 때 다른 색으로 읽힌다고 본다. 솥 몸체·돌 테와는 25 이상, "
                    "새 4종끼리는 20 이상을 요구했다. 같은 두 색 병 조합은 참고로 보고하고 실루엣으로 구분한다."}


def silhouette_report(sprites: dict[str, Image.Image]) -> dict:
    result = {}
    existing = {pid: np.array(existing_bottle(pid))[:, :, 3] == 255 for pid in CATALOG["potions"]}
    for p in POTIONS:
        mask = np.array(sprites[p["id"] + "_bottle"])[:, :, 3] == 255
        same = [pid for pid, m in existing.items() if m.shape == mask.shape and np.array_equal(m, mask)]
        closest = None
        for pid, m in existing.items():
            if m.shape != mask.shape:
                continue
            diff = int(np.sum(m != mask))
            if closest is None or diff < closest[1]:
                closest = (pid, diff)
        result[p["id"]] = {"identical_silhouettes": same, "closest_same_size": {"id": closest[0], "differing_pixels": closest[1]} if closest else None}
    new_masks = {p["id"]: np.array(sprites[p["id"] + "_bottle"])[:, :, 3] == 255 for p in POTIONS}
    dup = [(a, b) for a in new_masks for b in new_masks if a < b and new_masks[a].shape == new_masks[b].shape and np.array_equal(new_masks[a], new_masks[b])]
    return {"bottles": result, "new_duplicates": dup,
            "passed": all(not r["identical_silhouettes"] for r in result.values()) and not dup}


# ---------------------------------------------------------------- comparison boards
def shelf_board(sprites: dict[str, Image.Image]) -> dict:
    frame_path = ROOT / "art/mockups/full-ingame-v4/potions/shelf_frame-native.png"
    frame = Image.open(frame_path).convert("RGBA")
    layouts = {
        "new4_with_tops": [p["id"] for p in POTIONS] + ["eternity", "sage_elixir", "worldtree_elixir", "rare_nebula_distillate"],
        "mixed": ["sunrise", "eternity", "beacon", "shadow_elixir", "sea_spray", "worldtree_elixir", "sun_moon_elixir", "rare_nebula_distillate"],
    }
    centers = [8, 18, 28, 38]
    boards = {1: 22, 2: 43}
    out = {"frame": rel(frame_path), "boards": boards, "centers": centers, "layouts": {}}
    for name, ids in layouts.items():
        scene = frame.copy()
        placed = []
        for index, pid in enumerate(ids):
            image = sprites[pid + "_bottle"] if pid in {p["id"] for p in POTIONS} else existing_bottle(pid)
            row = 1 if index < 4 else 2
            x = centers[index % 4] - image.width // 2
            y = boards[row] - image.height
            scene.alpha_composite(image, (x, y))
            placed.append({"id": pid, "origin": [x, y], "size": list(image.size)})
        scene.save(COMPARE / f"shelf-{name}-native.png")
        scene.resize((scene.width * SCALE, scene.height * SCALE), Image.Resampling.NEAREST).save(COMPARE / f"shelf-{name}-3x.png")
        out["layouts"][name] = placed
    return out


def lineup(sprites: dict[str, Image.Image]) -> list[dict]:
    rows = []
    folder = COMPARE / "bottles"
    folder.mkdir(parents=True, exist_ok=True)
    for pid, row in CATALOG["potions"].items():
        image = existing_bottle(pid)
        image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST).save(folder / f"{pid}-3x.png")
        rows.append({"id": pid, "name": row["name"], "family": row["family"], "liquid": F25[pid]["liquid"] if pid in F25 else row["liquid_color"],
                     "image": rel(folder / f"{pid}-3x.png"), "new": False, "f25_display_recolour": pid in F25})
    for p in POTIONS:
        image = sprites[p["id"] + "_bottle"]
        image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST).save(folder / f"{p['id']}-3x.png")
        rows.append({"id": p["id"], "name": p["name"].replace(" 물약", ""), "family": p["family"], "liquid": p["liquid"],
                     "image": rel(folder / f"{p['id']}-3x.png"), "new": True, "f25_display_recolour": False})
    return rows


def copy_existing_icons() -> list[dict]:
    folder = COMPARE / "icons"
    folder.mkdir(parents=True, exist_ok=True)
    rows = []
    for path, label in EXISTING_ICONS:
        image = Image.open(ROOT / path).convert("RGBA")
        name = Path(path).stem + "-3x.png"
        image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST).save(folder / name)
        data = np.array(image)
        rows.append({"label": label, "source": path, "size": list(image.size), "image": rel(folder / name),
                     "colors": len({tuple(p[:3]) for p in data[data[:, :, 3] > 0]})})
    return rows


# ---------------------------------------------------------------- review page
def page(items, checks, pots, colours, silhouettes, shelf, line, icons) -> str:
    def img(path: str, cls: str = "") -> str:
        return f'<img src="{Path(path).relative_to(rel(MOCK)).as_posix()}" class="{cls}" alt="">'

    def sw(color: str) -> str:
        return f'<span><i style="--c:{color}"></i>{color}</span>'

    cards = []
    for p in POTIONS:
        pid = p["id"]
        c = colours["new"][pid]
        pot = pots["potions"][pid]
        ok = all(checks[pid + k]["passed"] for k in ("_bottle", "_icon", "_recipe")) and pot["passed"]
        cards.append(f"""
<div class="card"><h3>{p['name']} <small>· {p['family_ko']} 계열 · {p['customer']} 선호</small></h3>
<div class="sizes">
 <figure><div class="check">{img(f'art/mockups/f26-region-potions-v1/sprites/{pid}_bottle-3x.png')}</div><figcaption>병 {p['bottle_size'][0]}×{p['bottle_size'][1]} ×3</figcaption></figure>
 <figure><div class="check">{img(f'art/mockups/f26-region-potions-v1/sprites/{pid}_bottle.png', 'x1')}</div><figcaption>원본 1배</figcaption></figure>
 <div class="sep"></div>
 {''.join(f'<figure><div class="check">{img(f"art/mockups/f26-region-potions-v1/pots/{pid}-{i}-3x.png")}</div><figcaption>솥 {i}</figcaption></figure>' for i in range(3))}
 <div class="sep"></div>
 <figure><div class="check">{img(f'art/mockups/f26-region-potions-v1/sprites/{pid}_icon-3x.png')}</div><figcaption>물약 아이콘 32×40</figcaption></figure>
 <figure><div class="check">{img(f'art/mockups/f26-region-potions-v1/sprites/{pid}_recipe-3x.png')}</div><figcaption>레시피 아이콘 32×40</figcaption></figure>
</div>
<p class="desc"><b>병</b> {p['bottle']}<br><b>아이콘</b> {p['icon']}<br><b>레시피</b> {p['recipe']}</p>
<div class="sw">{sw(p['light'])}{sw(p['dark'])}<span>· 솥 액체 <b>{p['liquid']}</b> ({p['ramp']} 램프)</span></div>
<p class="desc">가장 가까운 기존 액체: {c['nearest_existing']['id']} {c['nearest_existing']['color']} (ΔE {c['nearest_existing']['delta_e']}) ·
솥 몸체 #86548E와 ΔE {pot['delta_e_to_pot'].get('#86548E')} · 같은 병 색 조합을 쓰는 기존 물약 {len(c['bottle_pair_used_by_existing'])}종 ·
같은 실루엣 기존 병 {len(silhouettes['bottles'][pid]['identical_silhouettes'])}종 · 검사 <b class="{'ok' if ok else 'bad'}">{'통과' if ok else '실패'}</b></p>
</div>""")
    extra = []
    for item in EXTRA:
        extra.append(f"""<div class="card"><h3>{item['name']}</h3><div class="sizes">
<figure><div class="check">{img(f'art/mockups/f26-region-potions-v1/sprites/{item["id"]}-3x.png')}</div><figcaption>32×40 ×3</figcaption></figure>
<figure><div class="check">{img(f'art/mockups/f26-region-potions-v1/sprites/{item["id"]}.png', 'x1')}</div><figcaption>원본</figcaption></figure></div>
<p class="desc">{item['description']}</p><div class="sw">{''.join(sw(v[0]) for k, v in item['legend'].items())}</div>
<p class="desc">검사 <b class="{'ok' if checks[item['id']]['passed'] else 'bad'}">{'통과' if checks[item['id']]['passed'] else '실패'}</b></p></div>""")
    grid = "".join(f'<figure class="{"new" if r["new"] else ""}"><div class="check bottle">{img(r["image"])}</div><figcaption>{r["name"]}{" ★" if r["new"] else ""}{" ·F25" if r["f25_display_recolour"] else ""}</figcaption></figure>' for r in line)
    old_icons = "".join(f'<figure><div class="check">{img(r["image"])}</div><figcaption>{r["label"]}<br>{r["colors"]}색</figcaption></figure>' for r in icons)
    new_icons = "".join(f'<figure><div class="check">{img(f"art/mockups/f26-region-potions-v1/sprites/{p}-3x.png")}</div><figcaption>{n}</figcaption></figure>'
                        for p, n in [("sunrise_icon", "해돋이 (새)"), ("sun_moon_elixir_icon", "일월 (새)"), ("sea_spray_icon", "물보라 (새)"),
                                     ("sun_moon_elixir_recipe", "일월 레시피 (새)"), ("dawn_bloom_icon", "여명초 (새)"), ("dawn_lighthouse_icon", "새벽 등대 (새)")])
    colour_rows = "".join(
        f"<tr><td>{p['name']}</td><td>{sw(p['liquid'])}</td><td>{', '.join(f'{k} {v}' for k, v in pots['potions'][p['id']]['delta_e_to_pot'].items())}</td>"
        f"<td>{colours['new'][p['id']]['nearest_existing']['id']} ({colours['new'][p['id']]['nearest_existing']['delta_e']})</td>"
        f"<td>{', '.join(f'{k} {v}' for k, v in colours['new'][p['id']]['delta_e_to_new_siblings'].items())}</td></tr>" for p in POTIONS)
    return f"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>새벽 등대 물약 후보</title><style>
@font-face{{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}}
:root{{--bg:#241c32;--panel:#30263f;--line:#827589;--text:#fff0bc;--muted:#c38eb5;--accent:#e9b95f;--ok:#b5c77d;--bad:#de7356}}
*{{box-sizing:border-box}}html,body{{background:var(--bg)}}body{{margin:0;color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}}
main{{max-width:1210px;margin:auto;padding:18px 16px 48px}}h1{{font-size:23px;margin:0 0 6px}}h2{{font-size:17px;margin:28px 0 8px}}h3{{font-size:15px;margin:0}}h3 small{{color:var(--muted);font-weight:normal}}
p{{margin:6px 0 10px}}.muted{{color:var(--muted)}}.ok{{color:var(--ok)}}.bad{{color:var(--bad)}}
.note{{border-left:3px solid #718c59;padding:8px 12px;background:var(--panel);margin:10px 0}}.warn{{border-left-color:var(--accent)}}
.check{{background-color:#4a3c52;background-image:linear-gradient(45deg,#3f3347 25%,transparent 25%),linear-gradient(-45deg,#3f3347 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#3f3347 75%),linear-gradient(-45deg,transparent 75%,#3f3347 75%);background-size:12px 12px;background-position:0 0,0 6px,6px -6px,-6px 0}}
img{{image-rendering:pixelated;image-rendering:crisp-edges;max-width:none;display:block}}img.x1{{zoom:1}}
.cards{{display:grid;grid-template-columns:repeat(auto-fill,minmax(520px,1fr));gap:12px}}@media(max-width:600px){{.cards{{grid-template-columns:1fr}}}}
.card{{background:var(--panel);border:1px solid #4a3c52;border-radius:6px;padding:12px;overflow-x:auto}}
.sizes{{display:flex;align-items:flex-end;gap:10px;margin:10px 0 6px;flex-wrap:wrap}}.sizes figure{{margin:0;text-align:center}}.sizes .check{{display:flex;align-items:center;justify-content:center;padding:4px}}
.sizes .sep{{width:1px;align-self:stretch;background:#4a3c52}}figcaption{{font-size:11px;color:var(--muted);margin-top:3px}}
.desc{{font-size:13px;margin:6px 0}}.sw{{display:flex;flex-wrap:wrap;gap:8px;font-size:11px;color:var(--muted)}}.sw span{{display:flex;align-items:center;gap:3px}}
.sw i{{width:12px;height:12px;display:inline-block;border:1px solid #000;background:var(--c)}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(70px,1fr));gap:8px}}.grid figure{{margin:0;text-align:center}}
.grid .bottle{{height:64px;display:flex;align-items:flex-end;justify-content:center;padding-bottom:4px}}.grid figure.new figcaption{{color:var(--accent);font-weight:bold}}.grid figure.new .bottle{{outline:2px solid var(--accent)}}
.row{{display:flex;flex-wrap:wrap;gap:14px}}.row figure{{margin:0;text-align:center}}.row .check{{padding:6px}}
table{{border-collapse:collapse;font-size:13px;width:100%}}td,th{{border-bottom:1px solid #4a3c52;padding:5px 6px;text-align:left;vertical-align:top}}.wrap{{overflow-x:auto}}
</style></head><body><main>
<h1>새 원정 지역 「새벽 등대」 · 새 물약 4종 아트 후보 v1</h1>
<p class="muted">{DATE} · 상태 <b>후보(candidate)</b> · 게임 미연결 · 승인 전. 기획은 <code>docs/새-원정-지역과-물약-F26-기획안.md</code>.</p>
<div class="note">모든 그림은 손으로 작성한 문자 픽셀 지도(<code>source/*.txt</code>)를 고정 후처리 <code>tools/process_pixel_art.py</code>에 통과시킨 결과다.
승인된 24색·물체당 5색 이하·1픽셀 외곽선·반투명 0·공통 3배. 체크무늬는 CSS 배경이며 그림에 구워 넣지 않았다.</div>
<div class="note warn">솥 액체색: 솥 몸체(#86548E)·돌 테(#827589)·문양(#E9B95F)과 같은 색을 쓰지 않는다. 기존 36종이 쓰지 않는 액체색만 골랐다
(#F4AC68 귤빛·#A56A3D 호박·#24566A 깊은 청록·#9D4359 진홍). 비교에는 main 브랜치의 F25 재색(은신·야행·비전 증폭·그림자 엘릭서)을 표시용으로 다시 적용했다(표시 ·F25).</div>

<h2>1. 새 물약 4종 · 병 / 솥 / 아이콘 / 레시피</h2>
<div class="cards">{''.join(cards)}</div>

<h2>2. 기존 36종 진열 병과 나란히 (★ 새 병, 모두 ×3)</h2>
<div class="grid">{grid}</div>

<h2>3. 승인 선반(v4 48×48)에 올린 모습 ×3</h2>
<div class="row">
<figure><div class="check">{img('art/mockups/f26-region-potions-v1/compare/shelf-new4_with_tops-3x.png')}</div><figcaption>윗칸 새 4종 · 아랫칸 기존 최상위(영원·현자·세계수·성운)</figcaption></figure>
<figure><div class="check">{img('art/mockups/f26-region-potions-v1/compare/shelf-mixed-3x.png')}</div><figcaption>섞어서 진열</figcaption></figure>
</div>

<h2>4. 재료·지역 아이콘</h2>
<div class="cards">{''.join(extra)}</div>

<h2>5. 32×40 아이콘 형식 비교</h2>
<p class="desc">기존 32×40 아이콘(<code>assets/content_expansion_v1</code>, <code>assets/rare_recipes_v1</code>)은 승인 24색 규칙 이전의 생성 그림이라 수백 색을 쓴다.
새 후보는 크기·투명 배경·용도는 같게 맞추되 현재 AGENTS 규칙(24색·5색)으로 그렸다. 관리 화면에서 섞였을 때의 질감 차이는 결정 필요 항목이다.</p>
<div class="row">{old_icons}</div><div class="row" style="margin-top:10px">{new_icons}</div>

<h2>6. 색 거리 (CIE76 ΔE)</h2>
<div class="wrap"><table><tr><th>물약</th><th>솥 액체</th><th>솥 색과의 거리</th><th>가장 가까운 기존 액체</th><th>새 4종끼리</th></tr>{colour_rows}</table></div>
<p class="desc muted">해돋이 #F4AC68는 행운 #E9B95F와 ΔE 13.7로 가장 가깝다(귤빛 대 버터 금빛). 병 모양(평평한 돔 대 둥근 병)으로 구분한다. 더 떨어뜨리려면 결정 필요 목록의 대안을 쓴다.</p>

<h2>7. 결정 필요</h2>
<ul>
<li>이름: 지역 「새벽 등대」, 재료 「여명초」, 물약 해돋이·등대불·물보라·일월의 물약.</li>
<li>병 모양 4종과 액체색 4종(특히 해돋이와 행운의 가까운 색).</li>
<li>32×40 아이콘을 새 규칙(24색)으로 둘지, 기존 생성 아이콘 질감에 맞춘 별도 생성을 할지.</li>
<li>재배 화분 성장 그림(64×80)과 원정 카드용 큰 그림은 이번 범위 밖(승인 후 제작).</li>
</ul>
<p class="muted">검사 결과: <code>validation.json</code> · 후처리 원본 보고: <code>pipeline/validation.json</code> · 승인 상태: <code>approval.json</code></p>
</main></body></html>
"""


def main() -> int:
    for folder in (REG, SPRITES, POTS, COMPARE):
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
    items = assets()
    registered = {}
    for item in items:
        rows = read_map(SRC / f"{item['id']}.txt")
        if [len(rows[0]), len(rows)] != list(item["size"]):
            raise SystemExit(f"{item['id']}: map is {len(rows[0])}x{len(rows)}, expected {item['size']}")
        image = render(rows, item["legend"])
        image.save(REG / f"{item['id']}.png")
        registered[item["id"]] = image
    pipe = run_pipeline(items)
    checks, sprites = {}, {}
    for item in items:
        image = Image.open(PIPE / f"{item['id']}-native.png").convert("RGBA")
        sprites[item["id"]] = image
        image.save(SPRITES / f"{item['id']}.png")
        image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST).save(SPRITES / f"{item['id']}-3x.png")
        check = check_sprite(item, image, registered[item["id"]], pipe["assets"][item["id"]])
        check["source"] = rel(SRC / f"{item['id']}.txt")
        check["description"] = item["description"]
        checks[item["id"]] = check
    sprites_by_potion = {k: v for k, v in sprites.items()}
    pots = make_pots(POTIONS)
    colours = colour_report(POTIONS)
    silhouettes = silhouette_report(sprites_by_potion)
    shelf = shelf_board(sprites_by_potion)
    line = lineup(sprites_by_potion)
    icons = copy_existing_icons()
    passed = all(c["passed"] for c in checks.values()) and all(p["passed"] for p in pots["potions"].values()) \
        and colours["passed"] and silhouettes["passed"]
    validation = {"schema_version": 1, "date": DATE, "status": "passed" if passed else "failed", "art_status": "candidate",
                  "approved_by_user": False, "scale": SCALE, "palette": "art/palette.hex (approved 24)",
                  "pipeline": {"tool": "tools/process_pixel_art.py", "manifest": rel(MOCK / "manifest.json"),
                               "report": rel(PIPE / "validation.json"), "status": pipe["status"], "stage_order": pipe["stage_order"]},
                  "sprites": checks, "pots": pots, "liquid_colours": colours, "silhouettes": silhouettes, "shelf": shelf,
                  "existing_icon_format": icons,
                  "f25_display_recolour": {k: v["map"] for k, v in F25.items()},
                  "scope_note": "후보 검사. assets/·scripts/·data/는 쓰지 않았다."}
    (MOCK / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    approval = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "approved_on": None, "user_reply": None,
        "date": DATE, "review": rel(MOCK / "review.html"), "plan": "docs/새-원정-지역과-물약-F26-기획안.md",
        "runtime_integrated": False,
        "scope": {
            **{f"{p['id']}_bottle": f"{p['name']} 진열 병 {p['bottle_size'][0]}×{p['bottle_size'][1]} (후보)" for p in POTIONS},
            **{f"{p['id']}_pot": f"{p['name']} 솥 액체 {p['liquid']} · 승인 솥 프레임 3장의 액체 마스크만 재색 (후보)" for p in POTIONS},
            **{f"{p['id']}_icon": f"{p['name']} 물약 아이콘 32×40 (후보)" for p in POTIONS},
            **{f"{p['id']}_recipe": f"{p['name']} 레시피 아이콘 32×40 (후보)" for p in POTIONS},
            "dawn_bloom_icon": "여명초 재료 아이콘 32×40 (후보)",
            "dawn_lighthouse_icon": "새벽 등대 지역 아이콘 32×40 (후보)",
        },
        "not_in_scope": ["재배 화분 성장 그림 64×80", "원정 카드 큰 그림", "게임 연결(assets/·catalog·scripts·data)"],
        "pending_decisions": ["이름 6개", "병 모양·액체색 4종", "32×40 아이콘 질감(24색 규칙 대 기존 생성 질감)"],
        "publish_after_approval": "추가 전용 게시 스크립트로 assets/pixel_v1/potions·pots와 catalog potions 키만 더한다(기존 자산 재생성 금지).",
    }
    (MOCK / "approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (MOCK / "review.html").write_text(page(items, checks, pots, colours, silhouettes, shelf, line, icons), encoding="utf-8")
    print(json.dumps({"status": validation["status"], "sprites": {k: v["passed"] for k, v in checks.items()},
                      "pots": {k: v["passed"] for k, v in pots["potions"].items()}, "colours": colours["passed"],
                      "silhouettes": silhouettes["passed"]}, ensure_ascii=False, indent=1))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
