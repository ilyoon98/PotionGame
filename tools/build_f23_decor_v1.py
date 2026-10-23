"""F23 decor (꾸미기) candidates: two counter props and workshop slot layouts A/B.

Candidate only. Reads hand-authored 32x32 native pixel maps
(art/mockups/f23-decor-v1/source/*.txt), registers them as native PNGs, runs the
fixed tools/process_pixel_art.py pipeline with an explicit per-color material
manifest, adds prop checks (outline, palette, colors, partial alpha, dithering,
lighting, grounding row), then places the props and the approved F22 souvenirs
(assets/pixel_v1/souvenirs, read only) into the real 540x249 workshop art area
and counts opaque-pixel overlaps against every moving or HUD element.

Workshop geometry is copied from scripts/workshop_layout.gd, pixel_shop_scene.gd,
potion_display.gd, shop_motion.gd and workshop_gauges.gd; the copies are checked
against the script text at run time so a layout change fails loudly.

Nothing under assets/ or scripts/ is written. Player saves, the running game and
Windows registration are untouched.

Run with Pillow + NumPy: python tools/build_f23_decor_v1.py
"""
from __future__ import annotations

import colorsys
import hashlib
import json
import math
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "art/mockups/f23-decor-v1"
SRC = MOCK / "source"
PIPE = MOCK / "pipeline"
SPRITES = MOCK / "sprites"
LAYOUT_DIR = MOCK / "layouts"
SCALE = 3
SIZE = (32, 32)
GROUND_ROW = 30
OUTLINE_HEX = "#241C32"
OUTLINE = (0x24, 0x1C, 0x32)
DATE = "2026-10-23"
W, H = 540, 249  # workshop art area in display pixels (native 180x83 x3)

# Map letter -> (approved color, ramp).
LEGEND = {
    "#": ("#241C32", "outline"),
    "l": ("#9BE2CF", "teal"), "m": ("#3BA8A3", "teal"), "d": ("#24566A", "teal"),
    "t": ("#C99463", "wood"),
    "g": ("#E9B95F", "gold"), "a": ("#A56A3D", "gold"),
    "p": ("#86548E", "purple"), "q": ("#50315F", "purple"),
}

PROPS = [
    {
        "id": "decor_teacup", "name": "작은 찻잔", "price_candidate": "120 G 1회 구매", "slot": "판매대 소품",
        "description": "청록 유약을 바른 낮은 찻잔과 받침, 위에서 보이는 꿀빛 차 한 줄, 오른쪽 손잡이(가운데 1픽셀 구멍). "
                       "왼쪽 테두리·받침은 밝은 민트, 오른쪽은 깊은 청록 그림자. 판매대 위 빈 높이에 맞춰 원본 12×6.",
        "materials": {"#": "outline", "l": "glaze_light", "m": "glaze", "d": "glaze_shadow", "t": "tea"},
    },
    {
        "id": "decor_dried_vase", "name": "말린 꽃병", "price_candidate": "240 G 1회 구매", "slot": "판매대 소품",
        "description": "자두빛 작은 항아리 꽃병에 꽂힌 말린 금빛 꽃대 4줄기. 왼쪽 두 줄기는 길고 밝은 꽃송이, 오른쪽 두 줄기는 짧고 "
                       "그늘진 색. 꽃병은 왼쪽 밝게·오른쪽 어둡게. 판매대 위 빈 높이에 맞춰 원본 10×7.",
        "materials": {"#": "outline", "g": "flower_light", "a": "flower_shadow", "p": "vase", "q": "vase_shadow"},
    },
]
SOUVENIRS = {
    "souvenir_compass": "여행자 · 낡은 나침반", "souvenir_bookmark": "여마법사 · 별무늬 책갈피",
    "souvenir_leaf_brooch": "엘프 · 잎사귀 브로치", "souvenir_silver_bell": "고양이 도적 · 작은 은방울",
}

# ---------------------------------------------------------------- workshop geometry (display px)
# Each entry is (value, script, literal text that must exist in that script).
GEOMETRY = {
    "counter": ((315, 192), "scripts/pixel_shop_scene.gd", '"counter":Vector2(315,192)'),
    "window": ((12, 15), "scripts/pixel_shop_scene.gd", '"window":Vector2(12,15)'),
    "herb": ((12, 144), "scripts/pixel_shop_scene.gd", '"herb":Vector2(12,144)'),
    "poster": ((459, 3), "scripts/pixel_shop_scene.gd", '"poster":Vector2(459,3)'),
    "shelf": ((315, 3), "scripts/pixel_shop_scene.gd", 'Catalog.DATA.props.shelf), Vector2(315,3)'),
    "aging_cask": ((219, 0), "scripts/pixel_shop_scene.gd", 'Catalog.DATA.props.aging_cask), Vector2(219,0)'),
    "keeper": ((216, 96), "scripts/pixel_shop_scene.gd", 'return Vector2(216,96) if view.workshop'),
    "customer_y": (96, "scripts/pixel_shop_scene.gd", 'Vector2(x - 48, 96 if view.workshop'),
    "pot": ((123, 144), "scripts/workshop_layout.gd", '"pot": Rect2(123, 144, 96, 96)'),
    "hearth": ((153, 213), "scripts/workshop_layout.gd", '"hearth": Rect2(153, 213, 36, 24)'),
    "purchase_feet_x": (492, "scripts/workshop_layout.gd", '"purchaseFeet": Vector2(492, 240)'),
    "offscreen_feet_x": (600, "scripts/workshop_layout.gd", '"offscreenFeet": Vector2(600, 240)'),
    "brew_origin": ((171, 165), "scripts/workshop_layout.gd", '"brewOrigin": Vector2(171, 165)'),
    "table_anchor": ((351, 192), "scripts/shop_art.gd", 'Vector2(351,192) if workshop'),
    "wrap_shelf_left": (315, "scripts/potion_display.gd", '315.0 if workshop_layout'),
    "reserve": ((447, 159), "scripts/workshop_layout.gd", '"reserve": Vector2(447, 159)'),
}
SLOTS = [(339, 51), (369, 51), (399, 51), (429, 51), (339, 114), (369, 114), (399, 114), (429, 114)]
SLOTS_TEXT = "const SLOTS := [Vector2(339, 51), Vector2(369, 51), Vector2(399, 51), Vector2(429, 51),"
HUD = {  # display rects that WorkshopGauges / ShopArt draw above the art in workshop mode
    "pot_panel": ((111, 66, 108, 24), "scripts/workshop_gauges.gd", "const POT := Rect2(111, 66, 108, 24)"),
    "keeper_panel": ((111, 92, 108, 22), "scripts/workshop_gauges.gd", "const KEEPER_PANEL := Rect2(111, 92, 108, 22)"),
    "herb_panel": ((6, 114, 102, 24), "scripts/workshop_layout.gd", '"herbPanel": Rect2(6, 114, 102, 24)'),
    "potions_button": ((114, 69, 18, 18), "scripts/workshop_layout.gd", '"potions": Rect2i(114, 69, 18, 18)'),
    "herbs_button": ((86, 117, 18, 18), "scripts/workshop_layout.gd", '"herbs": Rect2i(86, 117, 18, 18)'),
    "expeditions_button": ((487, 68, 16, 16), "scripts/workshop_layout.gd", '"expeditions": Rect2i(487, 68, 16, 16)'),
    "poster_captions": ((477, 39, 36, 45), "scripts/workshop_layout.gd", "const POSTER_INTERIOR := Rect2(477,39,36,45)"),
    "stock_caption": ((375, 150, 84, 20), "scripts/workshop_gauges.gd", "Rect2(375,150,84,20)"),
    "sale_caption": ((375, 173, 84, 18), "scripts/workshop_gauges.gd", "Rect2(375,173,84,18)"),
    # Harvest / rare-harvest reward flashes (icon 20x20 + 16pt text, baseline drifts 14 / 14 px).
    "harvest_flash": ((52, 100, 70, 37), "scripts/shop_art.gd", "Vector2(52 if workshop else 76, (132 if workshop"),
    "rare_flash": ((52, 125, 70, 37), "scripts/shop_art.gd", "Vector2(52 if workshop else 76, (157 if workshop"),
}
MINI = {"size": (256, 228), "art_height": 177, "keeper_origin": (117, 24), "pot_origin": (24, 72), "keeper_badge": (8, 35, 96, 22)}
MINI_TEXT = ["const SIZE := Vector2i(256, 228)", "const ART_HEIGHT := 177", "const KEEPER_ORIGIN := Vector2(117,24)",
             "const POT_ORIGIN := Vector2(24,72)", "const KEEPER_BADGE := Rect2(8, 35, 96, 22)"]

# Souvenir wall slot above the keeper (the aging-cask spot): each approved 32x32 sprite
# hangs with its opaque top row at native y=0 and its canvas left edge at x=68. The
# leaf brooch is 26 px wide on a diagonal; at x=68 its pin tip would sit 3 px under the
# cauldron HUD panel corner, so it alone moves 2 px right (its top-right leaf tip then
# lies on the shelf-wrap stock path, where the bottle is drawn in front of it).
SOUVENIR_SLOT = {"x": 68, "top_y": 0, "x_offsets": {"souvenir_leaf_brooch": 2}}
STOCK_EXCEPTIONS = {"souvenir_leaf_brooch"}

# Layout candidates (native coordinates; display = native x3). Both props share one
# 32x32 canvas origin per layout; their ground row 30 lands on counter row 70.
LAYOUTS = {
    "A": {"title": "A안 · 주인공 옆 판매대 끝 + 숙성통 우선",
          "counter_origin": (96, 40), "cask_policy": "cask_first",
          "summary": "판매대 왼쪽 끝(주인공 쪽, 원본 x107~118)에 소품. 기념품은 주인공 머리 위 벽(숙성통 자리, 원본 x68~). "
                     "숙성 선반이 열려 숙성통이 그려지면 숙성통이 그 자리를 쓰고 기념품은 작업실에서만 숨긴다(장착 상태 유지)."},
    "B": {"title": "B안 · 판매 병 쉼터 오른쪽 + 기념품 우선",
          "counter_origin": (109, 40), "cask_policy": "souvenir_first",
          "summary": "판매 병이 잠깐 멈추는 자리 오른쪽(손님 쪽, 원본 x120~131)에 소품. 기념품은 같은 벽 자리. "
                     "기념품을 장착하면 숙성통 그림 대신 기념품을 걸고, 해제하면 숙성통이 돌아온다."},
}
EXAMPLES = {
    "A": [
        {"id": "A-1", "prop": "decor_teacup", "souvenir": "souvenir_compass", "aging_open": False, "moment": "wait",
         "customer": "traveler", "weather": "day_clear", "label": "찻잔 + 낡은 나침반 · 숙성 전 · 손님 대기"},
        {"id": "A-2", "prop": "decor_dried_vase", "souvenir": "souvenir_bookmark", "aging_open": False, "moment": "sale",
         "customer": "mage", "weather": "night_clear", "label": "말린 꽃병 + 별무늬 책갈피 · 숙성 전 · 판매 병이 판매대에 멈춘 순간"},
        {"id": "A-3", "prop": "decor_teacup", "souvenir": "souvenir_leaf_brooch", "aging_open": True, "moment": "wait",
         "customer": "elf", "weather": "day_rain", "label": "찻잔 + 잎사귀 브로치 장착 · 숙성 후(숙성통 우선, 기념품 숨김)"},
    ],
    "B": [
        {"id": "B-1", "prop": "decor_dried_vase", "souvenir": "souvenir_leaf_brooch", "aging_open": False, "moment": "wait",
         "customer": "elf", "weather": "day_clear", "label": "말린 꽃병 + 잎사귀 브로치 · 숙성 전 · 손님 대기"},
        {"id": "B-2", "prop": "decor_teacup", "souvenir": "souvenir_silver_bell", "aging_open": True, "moment": "sale",
         "customer": "rogue", "weather": "night_rain", "label": "찻잔 + 작은 은방울 · 숙성 후(기념품이 숙성통 대신) · 판매 병이 멈춘 순간"},
        {"id": "B-3", "prop": "decor_dried_vase", "souvenir": "souvenir_compass", "aging_open": True, "moment": "wait",
         "customer": "traveler", "weather": "night_clear", "label": "말린 꽃병 + 낡은 나침반 · 숙성 후(기념품이 숙성통 대신)"},
    ],
}
FORBIDDEN = ["keeper", "customers", "sale_bottle", "stock_bottles", "hud"]
STRICT = ["keeper", "customers", "sale_bottle", "hud"]  # the user's explicit "do not cover" set
CUSTOMERS = ["traveler", "mage", "elf", "rogue"]


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def res(path: str) -> Path:
    return ROOT / path.replace("res://", "")


# ---------------------------------------------------------------- source maps + pipeline
def read_map(path: Path) -> list[str]:
    rows = [line.rstrip("\r\n") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(rows) != SIZE[1] or any(len(row) != SIZE[0] for row in rows):
        raise SystemExit(f"Map must be {SIZE[0]}x{SIZE[1]}: {rel(path)}")
    return rows


def render_map(rows: list[str], allowed: dict[str, str]) -> Image.Image:
    data = np.zeros((len(rows), len(rows[0]), 4), dtype=np.uint8)
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            if char == ".":
                continue
            if char not in allowed:
                raise SystemExit(f"Letter {char!r} at {x},{y} is not a declared material")
            data[y, x] = (*rgb(LEGEND[char][0]), 255)
    return Image.fromarray(data)


def exact_rules(colors: dict[str, str]) -> list[dict]:
    """One material per exact approved color, keyed by its HSV point (no nearest-RGB search)."""
    rules = []
    for material, value in colors.items():
        h, s, v = colorsys.rgb_to_hsv(*(np.array(rgb(value)) / 255.0))
        rules.append({"material": material, "hue": [round(h - .004, 4), round(h + .004, 4)],
                      "saturation_min": round(s - .01, 4), "saturation_max": round(s + .01, 4),
                      "value_min": round(v - .01, 4), "value_max": round(v + .01, 4)})
    return rules


def asset_entry(item: dict, source: Path) -> dict:
    letters = {c: m for c, m in item["materials"].items() if c != "#"}
    materials = {"outline": [OUTLINE_HEX]}
    materials.update({m: [LEGEND[c][0]] for c, m in letters.items()})
    return {
        "id": item["id"], "source": rel(source), "size": list(SIZE), "position": [0, 0], "margin": 0,
        "dark_value": 0.24, "preserve_native_frame": True, "materials": materials,
        "material_ramps": {m: LEGEND[c][1] for c, m in letters.items()},
        "rules": exact_rules({m: LEGEND[c][0] for c, m in letters.items()}),
        "fallback_material": next(iter(letters.values())),
        "name_ko": item["name"], "slot": item["slot"],
    }


def run_pipeline(manifest_path: Path) -> dict:
    result = subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"), rel(manifest_path)],
                            cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    report = json.loads((PIPE / "validation.json").read_text(encoding="utf-8"))
    if result.returncode != 0 or report["status"] != "passed":
        raise SystemExit(f"process_pixel_art failed: {report.get('error')}\n{result.stderr}")
    return report


# ---------------------------------------------------------------- prop checks
def luminance(color) -> float:
    values = np.asarray(color, dtype=float) / 255.0
    linear = np.where(values <= 0.04045, values / 12.92, ((values + 0.055) / 1.055) ** 2.4)
    return float(linear @ np.array([0.2126, 0.7152, 0.0722]))


def outline_violations(data: np.ndarray) -> list[list[int]]:
    """Opaque pixels touching transparency (4-neighbour or canvas edge) that are not #241C32."""
    opaque = data[:, :, 3] == 255
    padded = np.pad(opaque, 1)
    boundary = opaque & ~(padded[1:-1, :-2] & padded[1:-1, 2:] & padded[:-2, 1:-1] & padded[2:, 1:-1])
    bad = boundary & ~np.all(data[:, :, :3] == OUTLINE, axis=2)
    return [[int(x), int(y)] for y, x in zip(*np.where(bad))]


def dither_blocks(data: np.ndarray) -> list[list[int]]:
    """3x3 two-color checkerboards of non-outline colors (1px diagonal lines are allowed)."""
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
    """Mean luminance of non-outline pixels on the top-left vs bottom-right side of the bbox centre."""
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


def grounding(data: np.ndarray) -> dict:
    """The lowest opaque row is the contact row: one continuous run of outline pixels at row 30."""
    opaque = data[:, :, 3] == 255
    rows = np.where(opaque.any(axis=1))[0]
    bottom = int(rows.max())
    xs = np.where(opaque[bottom])[0]
    result = {"ground_row": bottom, "ground_row_expected": GROUND_ROW, "ground_x": [int(xs.min()), int(xs.max())],
              "ground_width": int(len(xs)), "ground_contiguous": bool(xs.max() - xs.min() + 1 == len(xs)),
              "ground_all_outline": bool(np.all(data[bottom, xs, :3] == OUTLINE)),
              "rows_below_ground_empty": bool(not opaque[bottom + 1:].any()),
              "opaque_rows": [int(rows.min()), bottom], "opaque_height": bottom - int(rows.min()) + 1}
    result["passed"] = (bottom == GROUND_ROW and result["ground_contiguous"] and result["ground_all_outline"]
                        and result["ground_width"] >= 4 and result["rows_below_ground_empty"])
    return result


def check_prop(item: dict, image: Image.Image, registered: Image.Image, palette: set, ramps: dict, pipe: dict) -> dict:
    data = np.array(image.convert("RGBA"))
    alpha = data[:, :, 3]
    opaque = alpha == 255
    colors = sorted({"#%02X%02X%02X" % tuple(p[:3]) for p in data[opaque]})
    ys, xs = np.where(opaque)
    by_ramp: dict[str, list[str]] = {}
    for c in item["materials"]:
        by_ramp.setdefault(LEGEND[c][1], []).append(LEGEND[c][0])
    shades = {ramp: len(hexes) for ramp, hexes in by_ramp.items()}
    check = {
        "name": item["name"], "size": list(image.size), "native_32x32": image.size == SIZE,
        "colors": colors, "color_count": len(colors), "max_colors": 5,
        "off_palette_colors": sum(1 for c in colors if rgb(c) not in palette),
        "partial_alpha_pixels": int(((alpha != 0) & (alpha != 255)).sum()),
        "outline_violations": outline_violations(data), "outline_color_present": OUTLINE_HEX in colors,
        "materials": {m: {"color": LEGEND[c][0], "ramp": LEGEND[c][1]} for c, m in item["materials"].items()},
        "colors_in_declared_ramps": all(h in ramps[r]["colors"] for r, hs in by_ramp.items() for h in hs),
        "shades_per_ramp": shades, "max_3_shades_per_ramp": all(n <= 3 for n in shades.values()),
        "opaque_bbox": [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1],
        "opaque_size": [int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)],
        "dither_3x3_blocks": dither_blocks(data), "lighting": lighting(data), "grounding": grounding(data),
        "pipeline_passed": pipe["passed"],
        "pipeline_preserved_source": bool(np.array_equal(np.array(registered.convert("RGBA")), data)),
        "native_sha256": hashlib.sha256(data.tobytes()).hexdigest(),
    }
    check["passed"] = bool(
        check["native_32x32"] and check["color_count"] <= 5 and check["outline_color_present"]
        and check["off_palette_colors"] == 0 and check["partial_alpha_pixels"] == 0
        and not check["outline_violations"] and check["colors_in_declared_ramps"] and check["max_3_shades_per_ramp"]
        and not check["dither_3x3_blocks"] and check["lighting"]["top_left_lit"] and check["grounding"]["passed"]
        and check["pipeline_passed"] and check["pipeline_preserved_source"]
        and set(colors) == {LEGEND[c][0] for c in item["materials"]})
    return check


# ---------------------------------------------------------------- scene loading
class Scene:
    def __init__(self):
        self.catalog = json.loads((ROOT / "assets/pixel_v1/catalog.json").read_text(encoding="utf-8"))
        self.cache: dict[str, Image.Image] = {}
        self.ids = list(self.catalog["potions"])

    def load(self, path: str) -> Image.Image:
        if path not in self.cache:
            self.cache[path] = Image.open(res(path)).convert("RGBA")
        return self.cache[path]

    def x3(self, path: str) -> Image.Image:
        im = self.load(path)
        return im.resize((im.width * SCALE, im.height * SCALE), Image.Resampling.NEAREST)

    def fine_cells(self, cid: str, pose: str) -> list[Image.Image]:
        sheet = self.load(self.catalog["characters"][cid]["poses"][pose]["fine"])
        cols, rows = sheet.width // 96, sheet.height // 144
        return [sheet.crop((q * 96, r * 144, q * 96 + 96, r * 144 + 144)) for r in range(rows) for q in range(cols)]

    def bottle_size(self, pid: str) -> tuple[int, int]:
        return tuple(self.catalog["potions"][pid]["bottle_size"])

    def slot_center(self, index: int, pid: str) -> tuple[float, float]:
        x, y = SLOTS[index]
        return x, y - (self.bottle_size(pid)[1] - 12) * 1.5


def alpha_of(image: Image.Image) -> np.ndarray:
    return np.array(image)[:, :, 3] == 255


def stamp(mask: np.ndarray, alpha: np.ndarray, x: int, y: int) -> None:
    h, w = alpha.shape
    x0, y0, x1, y1 = max(0, x), max(0, y), min(W, x + w), min(H, y + h)
    if x0 < x1 and y0 < y1:
        mask[y0:y1, x0:x1] |= alpha[y0 - y:y1 - y, x0 - x:x1 - x]


def bez(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u ** 3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t ** 3 * d for a, b, c, d in zip(p0, p1, p2, p3))


def smooth(t: float) -> float:
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, s):
    return a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s


def handover(start, finish, p, bottle_h):
    """PotionDisplay.handover_position (workshop table anchor 351,192)."""
    tx, ty = GEOMETRY["table_anchor"][0]
    table = (tx, ty - bottle_h / 2)
    if p < 0.27:
        return bez(start, (start[0], 165), (table[0] + 27, table[1] - 12), table, p / 0.27)
    if p < 0.54:
        return table
    return bez(table, (table[0] + 51, table[1] - 18), (finish[0] - 21, finish[1] + 12), finish, (p - 0.54) / 0.46)


def build_masks(scene: Scene) -> dict[str, np.ndarray]:
    cat = scene.catalog
    masks = {name: np.zeros((H, W), bool) for name in FORBIDDEN}
    kx, ky = GEOMETRY["keeper"][0]
    # Keeper: every published pose and motion cell, sleep Zs / faint stars, brewing spoon.
    for pose in cat["characters"]["keeper"]["poses"]:
        union = np.zeros((144, 96), bool)
        for cell in scene.fine_cells("keeper", pose):
            union |= alpha_of(cell)
        stamp(masks["keeper"], union, kx, ky)
    z = alpha_of(scene.x3(cat["effects"]["sleep_z"]))
    star = alpha_of(scene.x3(cat["effects"]["dizzy_star"]))
    for step in range(8):
        for lead in (0, 4):
            s = (step + lead) % 8
            stamp(masks["keeper"], z, kx + (22 + lead + s // 2) * 3, ky + (16 - s) * 3)
        for phase in (0.0, math.pi):
            angle = step / 8 * 2 * math.pi + phase
            stamp(masks["keeper"], star, kx + (11 + round(10 * math.cos(angle))) * 3, ky + (13 + round(2 * math.sin(angle))) * 3)
    px, py = GEOMETRY["pot"][0]
    bowl = scene.load(cat["spoon"]).crop((0, 9, 4, 12))
    bowl3 = alpha_of(bowl.resize((12, 9), Image.Resampling.NEAREST))
    for pose, bowl_point in {"brew_reach": (20, 8), "brew_stir_left": (18, 9), "brew_stir_right": (21, 10)}.items():
        hand = cat["characters"]["keeper"]["grips"][pose]
        grip = (round((kx - px) / 3 + hand[0]), round((ky - py) / 3 + hand[1]))
        count = int(max(abs(grip[0] - bowl_point[0]), abs(grip[1] - bowl_point[1])))
        for i in range(count + 1):
            pt = lerp(bowl_point, grip, i / max(count, 1))
            stamp(masks["keeper"], np.ones((3, 3), bool), px + round(pt[0]) * 3, py + round(pt[1]) * 3)
        stamp(masks["keeper"], bowl3, px + (bowl_point[0] - 1) * 3, py + (bowl_point[1] - 1) * 3)

    # Customers: waiting / receiving at the counter, walking in and carrying out (flipped), palms.
    cy = GEOMETRY["customer_y"][0]
    wait_x = GEOMETRY["purchase_feet_x"][0] - 48
    out_x = GEOMETRY["offscreen_feet_x"][0] - 48
    for cid in CUSTOMERS:
        char = cat["characters"][cid]
        for pose in char["poses"]:
            union = np.zeros((144, 96), bool)
            for cell in scene.fine_cells(cid, pose):
                union |= alpha_of(cell)
            if pose.startswith("carry_"):
                union = union[:, ::-1]
            xs = range(wait_x, out_x + 1) if pose.startswith(("walk_", "carry_")) else [wait_x]
            for x in xs:
                stamp(masks["customers"], union, x, cy)
        for pose, path in char["palms"].items():
            palm = alpha_of(scene.x3(path))
            if pose.startswith("carry_"):
                for x in range(wait_x, out_x + 1):
                    stamp(masks["customers"], palm[:, ::-1], x, cy)
            else:
                stamp(masks["customers"], palm, wait_x, cy)

    # Bottles: dedupe stamps by bottle silhouette.
    shapes, shape_of = {}, {}
    for pid in scene.ids:
        a = alpha_of(scene.x3(cat["potions"][pid]["bottle"]))
        key = hashlib.sha1(a.tobytes() + bytes(a.shape)).hexdigest()
        shapes[key] = a
        shape_of[pid] = key
    seal = alpha_of(scene.x3(cat["props"]["aged_seal"]))

    def bottle_rect(pid, center):
        bw, bh = scene.bottle_size(pid)
        return round(center[0] - bw * 1.5), round(center[1] - bh * 1.5)

    sale_points, seal_points, stock_points = set(), set(), set()
    for cid in CUSTOMERS:
        char = cat["characters"][cid]
        for pid in scene.ids:
            grip = char["bindings"][pid]["local_grip"]
            bw, bh = scene.bottle_size(pid)

            def held(pose, ox, flip):
                g = list(char["grips"][pose])
                if flip:
                    g[0] = 31 - g[0]
                return ox + (g[0] - grip[0] + bw / 2) * 3, cy + (g[1] - grip[1] + bh / 2) * 3

            finish = held("receive_extend", wait_x, False)
            starts = [(scene.slot_center(i, pid), False) for i in range(8)]
            # Aged sales leave from slot 0's centre, adjusted by whichever bottle stands there.
            starts += [((SLOTS[0][0], SLOTS[0][1] - (h - 12) * 1.5), True) for h in (12, 16)]
            for start, aged in starts:
                for k in range(401):
                    center = tuple(round(v) for v in handover(start, finish, k / 400, bh * 3))
                    x, y = bottle_rect(pid, center)
                    sale_points.add((shape_of[pid], x, y))
                    if aged:
                        seal_points.add((x + (bw - 3) * 3, y + (bh - 6) * 3))
            for pose in ("receive_extend", "receive_hold"):
                x, y = bottle_rect(pid, held(pose, wait_x, False))
                sale_points.add((shape_of[pid], x, y))
                seal_points.add((x + (bw - 3) * 3, y + (bh - 6) * 3))
            for pose in ("carry_contact_a", "carry_pass_a", "carry_contact_b", "carry_pass_b"):
                for ox in range(wait_x, out_x + 1):
                    x, y = bottle_rect(pid, held(pose, ox, True))
                    sale_points.add((shape_of[pid], x, y))
                    seal_points.add((x + (bw - 3) * 3, y + (bh - 6) * 3))
    for key, x, y in sale_points:
        stamp(masks["sale_bottle"], shapes[key], x, y)
    for x, y in seal_points:
        stamp(masks["sale_bottle"], seal, x, y)

    brew = GEOMETRY["brew_origin"][0]
    wrap_x = GEOMETRY["wrap_shelf_left"][0] - 12
    reserve = GEOMETRY["reserve"][0]
    for pid in scene.ids:
        def add(center):
            x, y = bottle_rect(pid, tuple(round(v) for v in center))
            stock_points.add((shape_of[pid], x, y))
        for i in range(8):
            target = scene.slot_center(i, pid)
            add(target)
            staging = (target[0], 165)
            for k in range(301):
                p = k / 300
                if p < 0.68:
                    add(bez(brew, (brew[0] + 104, brew[1] + 8), (staging[0] - 32, staging[1]), staging, smooth(p / 0.68)))
                else:
                    add(lerp(staging, target, smooth((p - 0.68) / 0.32)))
        origin, target = scene.slot_center(4, pid), scene.slot_center(3, pid)
        gap, above, over = (wrap_x, origin[1]), (wrap_x, -24), (target[0], -24)
        for k in range(301):
            p = k / 300
            if p < 0.25:
                add(lerp(origin, gap, smooth(p / 0.25)))
            elif p < 0.55:
                add(lerp(gap, above, smooth((p - 0.25) / 0.30)))
            elif p < 0.85:
                add(lerp(above, over, smooth((p - 0.55) / 0.30)))
            else:
                add(lerp(over, target, smooth((p - 0.85) / 0.15)))
        target = scene.slot_center(7, pid)
        aligned = (reserve[0], target[1])
        for k in range(101):
            p = k / 100
            add(lerp(reserve, aligned, smooth(p / .75)) if p < .75 else lerp(aligned, target, smooth((p - .75) / .25)))
        for a, b in [(1, 0), (2, 1), (3, 2), (5, 4), (6, 5), (7, 6)]:
            o, t = scene.slot_center(a, pid), scene.slot_center(b, pid)
            for k in range(31):
                add(lerp(o, t, k / 30))
    for key, x, y in stock_points:
        stamp(masks["stock_bottles"], shapes[key], x, y)

    for (x, y, w, h), _, _ in HUD.values():
        masks["hud"][y:y + h, x:x + w] = True

    # Furniture (static art); the counter is the intended support for counter props.
    furniture = {}

    def furn(name, paths, point):
        m = np.zeros((H, W), bool)
        for path in paths:
            stamp(m, alpha_of(scene.x3(path)), *point)
        furniture[name] = m
    weather = [p for frames in cat["weather"].values() for p in frames]
    furn("weather_glass", weather, GEOMETRY["window"][0])
    furn("window", [cat["props"]["window"]], GEOMETRY["window"][0])
    furn("herb", [cat["props"]["herb"]], GEOMETRY["herb"][0])
    furn("poster", [cat["props"]["poster"]], GEOMETRY["poster"][0])
    furn("shelf", [cat["props"]["shelf"]], GEOMETRY["shelf"][0])
    furn("counter", [cat["props"]["counter"]], GEOMETRY["counter"][0])
    furn("aging_cask", [cat["props"]["aging_cask"]], GEOMETRY["aging_cask"][0])
    furn("cauldron", sorted({p for info in cat["potions"].values() for p in info["pots"]}), GEOMETRY["pot"][0])
    furn("fire", cat["fire"], GEOMETRY["hearth"][0])
    furn("floor", [cat["props"]["floor"]], (0, 0))
    masks.update({"furniture_" + k: v for k, v in furniture.items()})
    return masks


def native_blocks(mask: np.ndarray) -> np.ndarray:
    return mask.reshape(H // 3, 3, W // 3, 3).any(axis=(1, 3))


# ---------------------------------------------------------------- placement checks
def placed(alpha: np.ndarray, origin_native) -> np.ndarray:
    m = np.zeros((H, W), bool)
    stamp(m, alpha, origin_native[0] * 3, origin_native[1] * 3)
    return m


def souvenir_origin(sid: str, bbox_top: int) -> tuple[int, int]:
    return SOUVENIR_SLOT["x"] + SOUVENIR_SLOT["x_offsets"].get(sid, 0), SOUVENIR_SLOT["top_y"] - bbox_top


def check_placement(layout: dict, prop_alpha: np.ndarray, prop_native: np.ndarray, sid: str, souvenir_alpha: np.ndarray,
                    so: tuple[int, int], masks: dict, aging_open: bool) -> dict:
    co = layout["counter_origin"]
    prop = placed(prop_alpha, co)
    souvenir_shown = not (aging_open and layout["cask_policy"] == "cask_first")
    cask_shown = aging_open and layout["cask_policy"] == "cask_first"
    souv = placed(souvenir_alpha, so) if souvenir_shown else np.zeros((H, W), bool)
    furniture = [k for k in masks if k.startswith("furniture_")]
    result = {"aging_open": aging_open, "souvenir_drawn": souvenir_shown, "aging_cask_drawn": cask_shown,
              "prop_origin_native": list(co), "souvenir_origin_native": list(so),
              "prop_inside_art": int(prop.sum()) == int(prop_alpha.sum()),
              "souvenir_inside_art": (not souvenir_shown) or int(souv.sum()) == int(souvenir_alpha.sum()),
              "prop": {}, "souvenir": {}}
    for name in FORBIDDEN:
        result["prop"][name] = int((prop & masks[name]).sum())
        result["souvenir"][name] = int((souv & masks[name]).sum())
    for name in furniture:
        key = name[len("furniture_"):]
        if key == "aging_cask" and not cask_shown:
            continue
        if key == "counter":
            result["prop"]["counter_contact"] = int((prop & masks[name]).sum())
        else:
            result["prop"][key] = int((prop & masks[name]).sum())
        result["souvenir"][key] = int((souv & masks[name]).sum())
    result["decor_vs_decor"] = int((prop & souv).sum())
    if aging_open:
        result["if_cask_and_souvenir_both_drawn"] = int((placed(souvenir_alpha, so) & masks["furniture_aging_cask"]).sum())
    # Ground row on the counter top: every contact pixel has counter top under/at it and the lip row below.
    counter_native = native_blocks(masks["furniture_counter"])
    ys, xs = np.where(prop_native)
    ground = int(ys.max())
    gx = xs[ys == ground] + co[0]
    gy = ground + co[1]
    result["ground_native_row"] = gy
    result["ground_native_x"] = [int(gx.min()), int(gx.max())]
    result["ground_on_counter_top"] = bool(np.all(counter_native[gy, gx]) and np.all(counter_native[gy + 1, gx]))
    # Gap to the bottle resting on the counter (native rows; 0 = touching, negative = overlap).
    rest = native_blocks(masks["sale_rest"])
    gaps = []
    for x in range(prop_native.shape[1]):
        col = np.where(prop_native[:, x])[0]
        sx = x + co[0]
        if len(col) and rest[:, sx].any():
            gaps.append(int(col.min() + co[1]) - int(np.where(rest[:, sx])[0].max()) - 1)
    result["rest_bottle_min_gap_rows"] = min(gaps) if gaps else None
    strict_hits = sum(result["prop"][n] + result["souvenir"][n] for n in STRICT)
    stock_prop, stock_souvenir = result["prop"]["stock_bottles"], result["souvenir"]["stock_bottles"]
    furniture_hits = sum(v for k, v in result["prop"].items() if k not in FORBIDDEN and k != "counter_contact") \
        + sum(v for k, v in result["souvenir"].items() if k not in FORBIDDEN)
    result["strict_overlap_total"] = strict_hits
    result["stock_overlap_total"] = stock_prop + stock_souvenir
    result["furniture_overlap_total"] = furniture_hits
    # Draw order: both decor layers precede stock bottles, characters, sale bottles and the HUD layer.
    result["decor_drawn_over_any_element_pixels"] = 0
    result["stock_exception"] = bool(stock_souvenir and sid in STOCK_EXCEPTIONS and souvenir_shown)
    result["passed"] = bool(strict_hits == 0 and furniture_hits == 0 and result["decor_vs_decor"] == 0
                            and stock_prop == 0 and (stock_souvenir == 0 or result["stock_exception"])
                            and result["prop_inside_art"] and result["souvenir_inside_art"]
                            and result["prop"]["counter_contact"] > 0 and result["ground_on_counter_top"])
    return result


# ---------------------------------------------------------------- composition
def compose(scene: Scene, layout: dict, example: dict, props: dict, souvenirs: dict, s_origins: dict) -> tuple[Image.Image, bool]:
    """Static frame in ShopArt workshop_commands order; decor goes right after the counter / at the cask slot."""
    cat = scene.catalog
    canvas = Image.new("RGBA", (W, H))
    drawn = np.zeros((H, W), bool)

    def put(image: Image.Image, point, flip=False):
        if flip:
            image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        canvas.alpha_composite(image, (int(point[0]), int(point[1])))
        a = np.array(image)[:, :, 3] > 0
        stamp(drawn, a, int(point[0]), int(point[1]))

    put(scene.x3(cat["weather"][example["weather"]][0]), GEOMETRY["window"][0])
    for key in ("floor", "window", "herb", "poster", "counter"):
        put(scene.x3(cat["props"][key]), (0, 0) if key == "floor" else GEOMETRY[key][0])
    co, so = layout["counter_origin"], s_origins[example["souvenir"]]
    put(props[example["prop"]], (co[0] * 3, co[1] * 3))
    cask = example["aging_open"] and layout["cask_policy"] == "cask_first"
    if cask:
        put(scene.x3(cat["props"]["aging_cask"]), GEOMETRY["aging_cask"][0])
    else:
        put(souvenirs[example["souvenir"]], (so[0] * 3, so[1] * 3))
    sale = example["moment"] == "sale"
    stock = scene.ids[::4][:8]
    for i, pid in enumerate(stock[:7] if sale else stock):
        b = scene.x3(cat["potions"][pid]["bottle"])
        cx, cy = scene.slot_center(i, pid)
        put(b, (round(cx - b.width / 2), round(cy - b.height / 2)))
    put(scene.x3(cat["props"]["shelf"]), GEOMETRY["shelf"][0])
    put(scene.x3(cat["fire"][0]), GEOMETRY["hearth"][0])
    put(scene.x3(cat["potions"][stock[1]]["pots"][0]), GEOMETRY["pot"][0])
    put(scene.fine_cells("keeper", "handover_extend" if sale else "idle")[0], GEOMETRY["keeper"][0])
    wait = (GEOMETRY["purchase_feet_x"][0] - 48, GEOMETRY["customer_y"][0])
    put(scene.fine_cells(example["customer"], "receive_extend" if sale else "idle")[0], wait)
    if sale:
        pid = "moon"
        b = scene.x3(cat["potions"][pid]["bottle"])
        tx, ty = GEOMETRY["table_anchor"][0]
        put(b, (tx - b.width // 2, ty - b.height))
    return canvas, bool(np.all(np.array(canvas)[:, :, 3][~drawn] == 0))


def occupancy_image(masks: dict, layout: dict, prop_alphas: list, souvenir_alphas: list) -> Image.Image:
    """Review aid (not game art): flat palette colors for each element and the decor footprints."""
    colors = [("furniture", "#827589"), ("hud", "#E9B95F"), ("stock_bottles", "#3BA8A3"), ("sale_bottle", "#DE7356"),
              ("customers", "#F4AC68"), ("keeper", "#C38EB5")]
    out = np.zeros((H, W, 4), np.uint8)
    furniture = np.zeros((H, W), bool)
    for k, v in masks.items():
        if k.startswith("furniture_") and k not in ("furniture_aging_cask",):
            furniture |= v
    for name, hex_ in colors:
        m = furniture if name == "furniture" else masks[name]
        out[m] = (*rgb(hex_), 255)
    decor = np.zeros((H, W), bool)
    for a in prop_alphas:
        decor |= placed(a, layout["counter_origin"])
    souv = np.zeros((H, W), bool)
    for a, origin in souvenir_alphas:
        souv |= placed(a, origin)
    out[souv] = (*rgb("#FFF0BC"), 255)
    out[decor] = (*rgb("#B5C77D"), 255)
    return Image.fromarray(out)


def source_constants() -> dict:
    texts = {}
    found = {}
    for name, (_, script, literal) in {**GEOMETRY, **HUD}.items():
        texts.setdefault(script, (ROOT / script).read_text(encoding="utf-8"))
        found[name] = literal in texts[script]
    layout_text = (ROOT / "scripts/workshop_layout.gd").read_text(encoding="utf-8")
    found["slots"] = SLOTS_TEXT in layout_text and "Vector2(339, 114), Vector2(369, 114), Vector2(399, 114), Vector2(429, 114)]" in layout_text
    mini_text = (ROOT / "scripts/mini_workshop.gd").read_text(encoding="utf-8")
    found["mini_workshop"] = all(t in mini_text for t in MINI_TEXT)
    found["cask_drawn_before_stock"] = bool(re.search(r"aging_cask.*\n\s*var stock_start", (ROOT / "scripts/pixel_shop_scene.gd").read_text(encoding="utf-8")))
    return found


# ---------------------------------------------------------------- review page
REVIEW = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>F23 꾸미기 후보</title><style>
@font-face{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}
:root{--bg:#241c32;--panel:#30263f;--line:#827589;--text:#fff0bc;--muted:#c38eb5;--accent:#e9b95f;--ok:#b5c77d;--bad:#de7356}
*{box-sizing:border-box}html,body{background:var(--bg)}body{margin:0;color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}
main{max-width:1210px;margin:auto;padding:18px 16px 48px}h1{font-size:23px;margin:0 0 6px}h2{font-size:17px;margin:28px 0 8px}h3{font-size:15px;margin:14px 0 6px}
p{margin:6px 0 10px}.muted{color:var(--muted)}code{font-size:13px;color:var(--muted)}a{color:var(--accent)}
.note{border-left:3px solid #718c59;padding:8px 12px;background:var(--panel);margin:10px 0}.warn{border-left-color:var(--accent)}
.check{background-color:#4a3c52;background-image:linear-gradient(45deg,#3f3347 25%,transparent 25%),linear-gradient(-45deg,#3f3347 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#3f3347 75%),linear-gradient(-45deg,transparent 75%,#3f3347 75%);background-size:12px 12px;background-position:0 0,0 6px,6px -6px,-6px 0}
img{image-rendering:pixelated;image-rendering:crisp-edges;max-width:none;display:block}
.decide{display:grid;gap:8px}.decide div{background:var(--panel);padding:8px 12px;border-radius:4px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px}
.card{background:var(--panel);border:1px solid #4a3c52;border-radius:6px;padding:12px}.card h3{margin:0}
.sizes{display:flex;align-items:flex-end;gap:10px;margin:10px 0 6px;flex-wrap:wrap}.sizes figure{margin:0;text-align:center}.sizes .check{display:flex;align-items:center;justify-content:center;padding:4px}
figcaption{font-size:11px;color:var(--muted);margin-top:3px}
.desc{font-size:13px;margin:6px 0}.sw{display:flex;flex-wrap:wrap;gap:6px;font-size:11px;color:var(--muted)}.sw span{display:flex;align-items:center;gap:3px}
.sw i{width:12px;height:12px;display:inline-block;border:1px solid #000;background:var(--c)}
.controls{display:flex;flex-wrap:wrap;gap:8px;align-items:center;margin:8px 0}
button,label.tog{font:inherit;font-size:13px;color:var(--text);background:#4a3c52;border:1px solid var(--line);padding:5px 9px;cursor:pointer;border-radius:4px}
button[aria-pressed=true]{border-color:var(--accent);background:#50315f}label.tog input{margin-right:5px}
.compare{display:grid;grid-template-columns:repeat(auto-fit,minmax(560px,1fr));gap:12px}
.col{background:var(--panel);border-radius:6px;padding:10px}.col h3{margin:0 0 4px}
.wrap{overflow-x:auto}.stage{position:relative;width:540px;height:300px}
.stage>img{position:absolute;left:0;top:0;width:540px;height:249px}.stage .occ{opacity:.55;display:none}.stage.show-occ .occ{display:block}
.hud{position:absolute;inset:0;pointer-events:none}.stage.hide-hud .hud{display:none}
.hud .pn{position:absolute;background:#281f33;border:1px solid #766180;color:#efc77c;font-size:12px;line-height:1;display:flex;align-items:center;padding:0 5px;white-space:nowrap;overflow:hidden}
.hud .cap{position:absolute;color:#efc77c;font-size:13px;line-height:1;white-space:nowrap}
.hud .btn{position:absolute;background:#281f33;border:1px solid #766180}
.bar{position:absolute;left:0;top:249px;width:540px;height:51px;background:#30263f;border-top:2px solid #e9b95f;display:flex;align-items:center;gap:14px;padding:0 10px;font-size:13px;color:#efc77c}
.bar .m{margin-left:auto;background:#e9b95f;color:#241c32;border-radius:3px;padding:4px 8px}
.legend{display:flex;flex-wrap:wrap;gap:10px;font-size:12px;color:var(--muted);margin:6px 0}.legend span{display:flex;gap:4px;align-items:center}.legend i{width:12px;height:12px;display:inline-block;background:var(--c);border:1px solid #000}
table{border-collapse:collapse;width:100%;font-size:12.5px}th,td{border-bottom:1px solid #4a3c52;padding:4px 6px;text-align:left;vertical-align:top}th{color:var(--muted);font-weight:normal}
.ok{color:var(--ok)}.bad{color:var(--bad)}.table-wrap{overflow-x:auto}
ul{margin:6px 0 10px;padding-left:20px}
</style></head><body><main>
<h1>F23 꾸미기 장식 후보 v1</h1>
<p class="muted">후보 단계입니다. <code>assets/</code>·<code>scripts/</code>·저장은 바꾸지 않았습니다. 승인 전에는 게임에 연결하지 않습니다. 기념품 4종은 승인·게시된 <code>assets/pixel_v1/souvenirs/</code> 그림을 그대로 썼습니다.</p>
<p id="overall"></p>

<h2>정해 주실 것</h2>
<div class="decide">
<div><b>1. 소품 디자인</b>: 작은 찻잔(청록 유약·꿀빛 차·받침)과 말린 꽃병(자두빛 항아리·말린 금빛 꽃대 4줄기)을 이대로 쓸지, 고칠 곳.</div>
<div><b>2. 배치 A/B</b>: <b>A 주인공 옆 판매대 끝 + 숙성통 우선</b> 또는 <b>B 판매 병 쉼터 오른쪽 + 기념품 우선</b>. 판매대 위치와 숙성통·기념품 우선순위는 서로 바꿔 조합해도 됩니다(예: A 위치 + 기념품 우선). 기념품 벽 자리는 두 안이 같고, 잎사귀 브로치만 2칸 오른쪽에 거는 예외(아래 ‘기념품 자리’ 참고)를 허용할지도 함께 정해 주세요.</div>
<div><b>3. 축소(캐릭터) 모드 표시 여부</b>: 권장은 <b>숨김(장착 상태는 유지)</b>. 아래 메모 참고.</div>
</div>

<h2>판매대 소품 2종 · 원본 32×32</h2>
<div class="note">승인 24색·재질 램프만 사용 · 공통 외곽선 #241C32 1픽셀 · 물체당 최대 5색 · 반투명 0 · 좌측 상단 조명 · 디더링 없음 · 공통 3배 최근접. 바닥 접지 행은 원본 y=30(전부 외곽선, 끊김 없음)이고 판매대 윗면 원본 행 70에 놓입니다. 체크무늬는 페이지 CSS이고 PNG는 투명 배경입니다.</div>
<div class="cards" id="cards"></div>
<div class="note warn"><b>왜 작게 그렸나</b>: 판매대(원본 x106~152, 윗면 행 68~70) 위는 판매 병이 선반에서 내려와 멈추고 손님 손으로 날아가는 길, 솥에서 선반으로 가는 입고 병 길, 재고·판매 글자가 지나갑니다. 실제 경로 전체(물약 36종 × 선반 8칸 × 손님 4명 × 진행 401단계, 숙성 인장 포함)를 겹쳐 보면 아무것도 지나가지 않는 판매대 위 공간은 <span id="band"></span>뿐입니다. 그래서 두 소품 모두 높이 7행 안(찻잔 6행·꽃병 7행)으로 그렸습니다. 더 큰 꽃병은 판매대 왼쪽 끝 좁은 기둥(원본 x102~112)에서만 가능하고, 그 자리는 입고 병 길과 겹칩니다(병이 꽃병 앞으로 지나가게 그리면 가리지는 않음).</div>

<h2>배치 A/B 비교 · 작업실 540×249 아트(공통 3배) + HUD</h2>
<div class="controls"><label class="tog"><input type="checkbox" id="tog-hud" checked>HUD 표시</label><label class="tog"><input type="checkbox" id="tog-occ">움직임·HUD 영역 겹쳐 보기</label></div>
<div class="legend" id="legend"></div>
<div class="compare" id="compare"></div>
<p class="muted">HUD 상자·글자·하단 바는 위치 확인용 일반 DOM 글자이며 PNG에 들어 있지 않습니다. PNG의 빈 공간은 알파 0입니다. ‘판매 병이 멈춘 순간’은 판매대 위 병 쉼터(표시 351,192)에 병이 떠 있는 실제 중간 단계입니다.</p>

<h2>가림 검사</h2>
<p class="muted">숫자는 장식의 불투명 픽셀(표시 3배 기준)과 각 요소가 차지할 수 있는 모든 픽셀의 합집합이 겹치는 수입니다. 주인공은 공개된 8포즈×64칸·수면 Z·기절 별·국자, 손님은 4명의 대기/걷기/받기/병 든 퇴장(좌우 반전)·손바닥, 판매 병은 선반 출고→판매대 쉼터→손님 손→퇴장까지, 입고 병은 솥→선반·줄 바꿈·보관 칸 이동을 모두 포함합니다. 판매대 접촉 픽셀은 소품이 판매대 위에 올라간 의도된 접점입니다.</p>
<div class="table-wrap"><table id="table"></table></div>
<h3>기념품 자리를 이곳으로 한 이유</h3>
<div class="note" id="souvenir-note"></div>

<h2>축소(캐릭터) 모드 메모</h2>
<div class="note" id="mini-note"></div>

<h2>승인 후 연결 메모 (이번 작업에서 하지 않음)</h2>
<ul>
<li>그리는 순서: 판매대 소품은 <code>counter</code> 바로 뒤, 기념품은 숙성통 자리(<code>stock_start</code> 앞). 그래서 모든 병·주인공·손님·HUD가 장식 위에 그려지고 장식이 이들을 가릴 수 없습니다.</li>
<li>장식 위치: 판매대 소품 32×32 캔버스 원점 A (96,40) / B (109,40). 기념품 캔버스 왼쪽 x=68, 불투명 윗줄 y=0(나침반 68,0 · 책갈피 68,−2 · 은방울 68,−1 · 브로치 70,−5) · 원본 좌표, 표시 = ×3.</li>
<li>저장·장착·구매 로직과 관리 화면 UI는 승인 뒤 메인 세션이 붙입니다. 전체 실내(기본) 화면 배치는 이번 범위 밖입니다.</li>
</ul>
<p class="muted">재현: <code>python tools/build_f23_decor_v1.py</code> → 원본 지도(<code>source/*.txt</code>) → 등록 PNG → <code>tools/process_pixel_art.py</code>(<code>manifest.json</code>) → 소품 검사 → 작업실 배치·가림 검사(<code>validation.json</code>) → 이 페이지. 수치 검사는 디자인 승인을 대신하지 않습니다.</p>
</main><script>
const S=/*SUMMARY*/null;
const el=(t,a={},h='')=>{const e=document.createElement(t);for(const k in a)e.setAttribute(k,a[k]);e.innerHTML=h;return e};
const k=(v,good)=>`<span class="${good?'ok':'bad'}">${v}</span>`;
document.getElementById('overall').innerHTML=S.passed?'<span class="ok">수치 검사 통과</span> · 소품 색 수·팔레트 밖 0·반투명 0·외곽선 위반 0·디더링 0 · 두 배치 모두 주인공·손님·판매 병·HUD·다른 가구와 겹침 0 · 입고 병 길 겹침은 잎사귀 브로치 1종 예외(아래 *)':'<span class="bad">검사 실패 항목이 있습니다</span>';
document.getElementById('band').textContent=S.band;
const cards=document.getElementById('cards');
for(const it of S.props){
 const c=el('div',{class:'card'});c.append(el('div',{class:'muted'},`${it.slot} · 후보 ${it.price}`),el('h3',{},it.name));
 const sz=el('div',{class:'sizes'});
 for(const [w,lab,src] of [[32,'32px · 1배',it.native],[96,'96px · 3배',it.x3],[192,'192px · 6배(확인용)',it.x3]]){const f=el('figure');const b=el('div',{class:'check'});b.append(el('img',{src,width:w,height:w,alt:it.name+' '+lab}));f.append(b,el('figcaption',{},lab));sz.append(f)}
 c.append(sz,el('p',{class:'desc'},it.description));
 const sw=el('div',{class:'sw'});for(const m of it.materials)sw.append(el('span',{},`<i style="--c:${m.color}"></i>${m.color} ${m.name}`));c.append(sw);
 c.append(el('p',{class:'desc'},`${k(it.color_count+'색',it.color_count<=5)} · 팔레트 밖 ${k(it.off_palette,it.off_palette===0)} · 반투명 ${k(it.partial_alpha,it.partial_alpha===0)} · 외곽선 위반 ${k(it.outline_violations,it.outline_violations===0)} · 디더링 ${k(it.dither,it.dither===0)} · 좌상단 조명 ${k(it.lit?'예':'아니오',it.lit)} · 접지 행 y=${it.ground_row} 폭 ${it.ground_width} ${k(it.ground_ok?'통과':'실패',it.ground_ok)} · 원본 크기 ${it.opaque_size.join('×')} · <code>${it.id}</code>`));
 cards.append(c)}
const legend=document.getElementById('legend');
for(const [n,c] of S.legend)legend.append(el('span',{},`<i style="--c:${c}"></i>${n}`));
const cmp=document.getElementById('compare');const stages=[];
function hud(sale){const h=el('div',{class:'hud'});const add=(cls,r,txt='')=>{const d=el('div',{class:cls},txt);Object.assign(d.style,{left:r[0]+'px',top:r[1]+'px',width:r[2]+'px',height:r[3]+'px'});h.append(d)};
 add('pn',[111,66,108,24],'&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;제조 중');add('btn',[114,69,18,18]);add('pn',[111,92,108,22],'상쾌 · 피로 12');add('pn',[6,114,102,24],'1종 재배 중');add('btn',[86,117,18,18]);
 add('cap',[375,152,84,18],sale?'재고 7 / 12':'재고 8 / 12');if(sale)add('cap',[375,175,84,16],'+24 G');add('cap',[483,41,30,12],'원정');add('cap',[483,55,30,12],'대기');add('btn',[487,68,16,16]);
 return h}
for(const L of S.layouts){
 const col=el('div',{class:'col'});col.append(el('h3',{},L.title),el('p',{class:'desc muted'},L.summary),el('p',{class:'desc'},`판매대 소품 캔버스 원점 원본 (${L.counter_origin}) = 표시 (${L.counter_origin.map(v=>v*3)}) · 접지 행 원본 y=${L.ground_row}, x ${L.ground_x[0]}~${L.ground_x[1]} · 기념품 캔버스 원점(원본) ${L.souvenir_origins}`));
 const bar=el('div',{class:'controls'});const wrap=el('div',{class:'wrap'});const st=el('div',{class:'stage check'});
 const img=el('img',{alt:L.title});const occ=el('img',{class:'occ',src:L.occupancy,alt:'겹침 확인 영역'});
 const hudBox=el('div');st.append(img,occ,hudBox,el('div',{class:'bar'},'<span>☰</span><span>12,480 G</span><span>낮 · 맑음</span><span class="m">관리</span><span>－</span><span>□</span><span>✕</span>'));
 const cap=el('p',{class:'muted desc'});
 function pick(ex){img.src=ex.png;hudBox.replaceChildren(hud(ex.moment==='sale'));cap.textContent=`${ex.id} · ${ex.label}`;bar.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',b.dataset.id===ex.id))}
 for(const ex of L.examples){const b=el('button',{'data-id':ex.id},ex.id);b.onclick=()=>pick(ex);bar.append(b)}
 wrap.append(st);col.append(bar,wrap,cap);cmp.append(col);stages.push(st);pick(L.examples[0])}
document.getElementById('tog-hud').onchange=e=>stages.forEach(s=>s.classList.toggle('hide-hud',!e.target.checked));
document.getElementById('tog-occ').onchange=e=>stages.forEach(s=>s.classList.toggle('show-occ',e.target.checked));
const t=document.getElementById('table');
t.append(el('tr',{},'<th>배치</th><th>소품</th><th>기념품</th><th>숙성</th><th>주인공</th><th>손님</th><th>판매 병</th><th>입고 병</th><th>HUD</th><th>다른 가구</th><th>판매대 접촉</th><th>쉼터 병과 간격</th><th>판정</th>'));
for(const r of S.rows){t.append(el('tr',{},`<td>${r.layout}</td><td>${r.prop}</td><td>${r.souvenir}</td><td>${r.aging}</td>${['keeper','customers','sale_bottle','stock_bottles','hud','furniture'].map(n=>`<td>${n==='stock_bottles'&&r.exception?`<span style="color:var(--accent)">${r[n]}*</span>`:k(r[n],r[n]===0)}</td>`).join('')}<td>${r.counter_contact}</td><td>${r.gap===null?'-':r.gap+'행'}</td><td>${k(r.passed?(r.exception?'통과*':'통과'):'실패',r.passed)}</td>`))}
t.after(el('p',{class:'muted desc'},'* 잎사귀 브로치 예외: 기념품 오른쪽 위 끝이 선반 재고 정리 병 길 위에 놓임(병이 앞에 그려져 가려지지 않음). 아래 설명 참고.'));
document.getElementById('souvenir-note').innerHTML=S.souvenir_note;
document.getElementById('mini-note').innerHTML=S.mini_note;
</script></body></html>
"""


def main() -> int:
    palette = {rgb(v) for v in (ROOT / "art/palette.hex").read_text(encoding="utf-8").split()}
    ramp_data = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
    ramps = ramp_data["ramps"]
    for char, (hex_, ramp) in LEGEND.items():
        if rgb(hex_) not in palette or hex_ not in ramps[ramp]["colors"]:
            raise SystemExit(f"Legend {char} {hex_} is not an approved {ramp} color")
    constants = source_constants()
    if not all(constants.values()):
        raise SystemExit(f"Workshop geometry drifted from scripts: {[k for k, v in constants.items() if not v]}")

    # ---- register hand-authored maps and run the fixed pipeline
    assets, registered, source_hashes = [], {}, {}
    for item in PROPS:
        text_path = SRC / f"{item['id']}.txt"
        image = render_map(read_map(text_path), item["materials"])
        path = SRC / f"{item['id']}-registered.png"
        image.save(path)
        registered[item["id"]] = image
        source_hashes[item["id"]] = {"map_sha256": hashlib.sha256(text_path.read_bytes()).hexdigest(),
                                     "registered_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        assets.append(asset_entry(item, path))
    manifest = {"schema_version": 1, "status": "candidate", "approved_by_user": False, "compose": False,
                "scale": SCALE, "alpha_threshold": 224, "max_colors": 5,
                "palette": "art/palette.hex", "ramps": "art/ramps.json", "output": rel(PIPE),
                "scene": {"size": list(SIZE), "background": "#4A3C52"},
                "feature": "F23 decor counter props", "runtime_integrated": False, "assets": assets}
    manifest_path = MOCK / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    pipe_report = run_pipeline(manifest_path)

    SPRITES.mkdir(exist_ok=True)
    prop_checks, prop_images, prop_native = {}, {}, {}
    for item in PROPS:
        native = Image.open(PIPE / f"{item['id']}-native.png").convert("RGBA")
        check = check_prop(item, native, registered[item["id"]], palette, ramps, pipe_report["assets"][item["id"]])
        big = native.resize((native.width * SCALE, native.height * SCALE), Image.Resampling.NEAREST)
        expected = np.repeat(np.repeat(np.array(native), SCALE, axis=0), SCALE, axis=1)
        check["integer_3x_nearest_verified"] = bool(np.array_equal(np.array(big), expected))
        check["passed"] = check["passed"] and check["integer_3x_nearest_verified"]
        check["source"] = source_hashes[item["id"]]
        prop_checks[item["id"]] = check
        if check["passed"]:
            native.save(SPRITES / f"{item['id']}.png")
            big.save(SPRITES / f"{item['id']}-3x.png")
        prop_images[item["id"]] = big
        prop_native[item["id"]] = np.array(native)[:, :, 3] == 255

    # ---- approved souvenirs (read only) and the scene masks
    scene = Scene()
    souvenir_images, souvenir_info = {}, {}
    for sid in SOUVENIRS:
        path = res(scene.catalog["souvenirs"][sid])
        approved = ROOT / f"art/mockups/f22-regulars-souvenirs-v1/sprites/{sid}.png"
        souvenir_images[sid] = scene.x3(scene.catalog["souvenirs"][sid])
        souvenir_info[sid] = {"published": rel(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                              "identical_to_approved_f22_sprite": path.read_bytes() == approved.read_bytes(),
                              "opaque_bbox_native": list(Image.open(path).convert("RGBA").getbbox())}
    masks = build_masks(scene)
    rest = np.zeros((H, W), bool)  # the bottle while it pauses above the counter (p 0.27..0.54)
    tx, ty = GEOMETRY["table_anchor"][0]
    for pid in scene.ids:
        a = alpha_of(scene.x3(scene.catalog["potions"][pid]["bottle"]))
        stamp(rest, a, tx - a.shape[1] // 2, ty - a.shape[0])
    masks["sale_rest"] = rest

    # ---- free-space analysis (native): counter band and common souvenir origins
    blocked = np.zeros((H, W), bool)
    for name in FORBIDDEN:
        blocked |= masks[name]
    nb = native_blocks(blocked)
    counter_native = native_blocks(masks["furniture_counter"])
    band = {}
    for x in range(105, 153):
        above = np.where(nb[:68, x])[0]
        band[x] = int(above.max()) + 1 if len(above) else 0
    free_cols = [x for x in band if band[x] <= 64 and counter_native[70, x]]
    other_furniture = np.zeros((H, W), bool)
    for kname, v in masks.items():
        if kname.startswith("furniture_") and kname != "furniture_aging_cask":
            other_furniture |= v
    s_alpha = {sid: alpha_of(img) for sid, img in souvenir_images.items()}
    s_top = {sid: info["opaque_bbox_native"][1] for sid, info in souvenir_info.items()}
    s_origin = {sid: souvenir_origin(sid, s_top[sid]) for sid in SOUVENIRS}
    obstacles = blocked | other_furniture
    zero = {sid: {"cask_hidden": [], "cask_drawn": []} for sid in SOUVENIRS}
    for sid, a in s_alpha.items():
        for oy in range(-8, 40):
            for ox in range(-8, 172):
                m = placed(a, (ox, oy))
                if int(m.sum()) != int(a.sum()) or (m & obstacles).any():
                    continue
                zero[sid]["cask_hidden"].append([ox, oy])
                if not (m & masks["furniture_aging_cask"]).any():
                    zero[sid]["cask_drawn"].append([ox, oy])
    common = {state: sorted(set.intersection(*[{tuple(o) for o in zero[sid][state]} for sid in SOUVENIRS]))
              for state in ("cask_hidden", "cask_drawn")}
    brooch = s_alpha["souvenir_leaf_brooch"]
    brooch_options = []
    for ox in range(66, 73):
        m = placed(brooch, (ox, -s_top["souvenir_leaf_brooch"]))
        brooch_options.append({"origin": [ox, -s_top["souvenir_leaf_brooch"]], "hud": int((m & masks["hud"]).sum()),
                               "stock_bottles": int((m & masks["stock_bottles"]).sum()),
                               "other": int((m & (masks["keeper"] | masks["customers"] | masks["sale_bottle"] | other_furniture)).sum())})
    space = {"counter_free_from_row_by_x": band,
             "counter_columns_free_from_row_64": [min(free_cols), max(free_cols)] if free_cols else None,
             "counter_band_rows": [64, 70],
             "souvenir_zero_overlap_origins": {sid: {k: len(v) for k, v in z.items()} | {"cask_hidden_list": z["cask_hidden"]}
                                               for sid, z in zero.items()},
             "souvenir_common_zero_overlap_origins": {k: [list(o) for o in v] for k, v in common.items()},
             "leaf_brooch_top_aligned_options": brooch_options,
             "slot_rule": SOUVENIR_SLOT, "slot_origins": {sid: list(o) for sid, o in s_origin.items()},
             "note": "native coordinates; zero = no pixel shared with keeper, customers, sale/stock bottles, HUD or furniture"}

    # ---- layouts
    LAYOUT_DIR.mkdir(exist_ok=True)
    placements, rows, layout_summary = {}, [], []
    combos_passed = True
    for lid, layout in LAYOUTS.items():
        placements[lid] = {"title": layout["title"], "counter_origin_native": list(layout["counter_origin"]),
                           "counter_origin_display": [v * 3 for v in layout["counter_origin"]],
                           "souvenir_origins_native": {sid: list(o) for sid, o in s_origin.items()},
                           "souvenir_origins_display": {sid: [v * 3 for v in o] for sid, o in s_origin.items()},
                           "cask_policy": layout["cask_policy"], "combos": {}}
        for pid in prop_images:
            for sid in SOUVENIRS:
                for aging in (False, True):
                    r = check_placement(layout, alpha_of(prop_images[pid]), prop_native[pid], sid, s_alpha[sid], s_origin[sid], masks, aging)
                    placements[lid]["combos"][f"{pid}+{sid}+{'aging_open' if aging else 'aging_closed'}"] = r
                    combos_passed &= r["passed"]
                    furn = sum(v for kk, v in r["prop"].items() if kk not in FORBIDDEN and kk != "counter_contact") \
                        + sum(v for kk, v in r["souvenir"].items() if kk not in FORBIDDEN)
                    rows.append({"layout": lid, "prop": PROPS[[p["id"] for p in PROPS].index(pid)]["name"],
                                 "souvenir": SOUVENIRS[sid].split(" · ")[1] + ("" if r["souvenir_drawn"] else " (숨김)"),
                                 "aging": ("열림 · " + ("숙성통" if r["aging_cask_drawn"] else "기념품")) if aging else "닫힘",
                                 **{n: r["prop"][n] + r["souvenir"][n] for n in FORBIDDEN},
                                 "furniture": furn, "counter_contact": r["prop"]["counter_contact"],
                                 "gap": r["rest_bottle_min_gap_rows"], "passed": r["passed"], "exception": r["stock_exception"]})
        first = next(iter(placements[lid]["combos"].values()))
        examples = []
        for ex in EXAMPLES[lid]:
            image, empty_ok = compose(scene, layout, ex, prop_images, souvenir_images, s_origin)
            alpha = np.array(image)[:, :, 3]
            path = LAYOUT_DIR / f"{ex['id']}-3x.png"
            image.save(path)
            native = image.resize((180, 83), Image.Resampling.NEAREST)
            native.save(LAYOUT_DIR / f"{ex['id']}-native.png")
            ex_check = {"png": rel(path), "size": list(image.size), "partial_alpha": int(((alpha != 0) & (alpha != 255)).sum()),
                        "empty_space_alpha_zero": empty_ok,
                        "combo": f"{ex['prop']}+{ex['souvenir']}+{'aging_open' if ex['aging_open'] else 'aging_closed'}"}
            ex_check["passed"] = ex_check["partial_alpha"] == 0 and empty_ok and image.size == (W, H)
            combos_passed &= ex_check["passed"]
            placements[lid].setdefault("examples", {})[ex["id"]] = {**ex, **ex_check}
            examples.append({"id": ex["id"], "label": ex["label"], "moment": ex["moment"],
                             "png": f"layouts/{ex['id']}-3x.png"})
        occ = occupancy_image(masks, layout, [alpha_of(i) for i in prop_images.values()],
                              [(s_alpha[sid], s_origin[sid]) for sid in SOUVENIRS])
        occ.save(LAYOUT_DIR / f"occupancy-{lid}.png")
        layout_summary.append({"id": lid, "title": layout["title"], "summary": layout["summary"],
                               "counter_origin": list(layout["counter_origin"]),
                               "souvenir_origins": " · ".join(f"{SOUVENIRS[sid].split(' · ')[1]} ({o[0]},{o[1]})" for sid, o in s_origin.items()),
                               "ground_row": first["ground_native_row"],
                               "ground_x": [min(c["ground_native_x"][0] for c in placements[lid]["combos"].values()),
                                            max(c["ground_native_x"][1] for c in placements[lid]["combos"].values())],
                               "occupancy": f"layouts/occupancy-{lid}.png", "examples": examples})

    props_passed = all(c["passed"] for c in prop_checks.values())
    souvenirs_ok = all(v["identical_to_approved_f22_sprite"] for v in souvenir_info.values())
    passed = bool(props_passed and combos_passed and souvenirs_ok)
    mini_right = MINI["size"][0] - (MINI["keeper_origin"][0] + 96)
    widths = sorted((b[2] - b[0]) * 3 for b in (v["opaque_bbox_native"] for v in souvenir_info.values()))
    heights = sorted((b[3] - b[1]) * 3 for b in (v["opaque_bbox_native"] for v in souvenir_info.values()))
    report = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False,
        "date": DATE, "scale": SCALE, "palette": "art/palette.hex", "ramps": "art/ramps.json", "new_palette_colors": 0,
        "pipeline_report": rel(PIPE / "validation.json"), "pipeline_status": pipe_report["status"],
        "rules": {"native_size": list(SIZE), "max_colors_including_outline": 5, "off_palette": 0, "partial_alpha": 0,
                  "outline": "every opaque pixel 4-adjacent to transparency (or the canvas edge) is #241C32",
                  "max_shades_per_ramp": 3, "dithering": "no 3x3 two-color checkerboards",
                  "lighting": "non-outline pixels on the top-left side brighter than the bottom-right side",
                  "grounding": f"lowest opaque row = {GROUND_ROW}, one continuous run of outline pixels, nothing below",
                  "overlap_unit": "display pixels (native x3) of decor opacity intersecting each element's union of all reachable pixels",
                  "checked_elements": FORBIDDEN, "must_be_zero": STRICT + ["furniture (except counter contact)", "decor vs decor"],
                  "stock_bottles": "must be zero except the listed leaf-brooch slot exception (decor is drawn behind stock bottles)",
                  "draw_order": "counter prop right after counter; souvenir at the aging-cask slot before stock bottles"},
        "exceptions": [{"what": "souvenir_leaf_brooch on the wall slot", "origin_native": list(s_origin["souvenir_leaf_brooch"]),
                        "stock_bottles_display_px": next(o["stock_bottles"] for o in brooch_options
                                                         if o["origin"] == list(s_origin["souvenir_leaf_brooch"])),
                        "why": "26 px diagonal sprite; between the cauldron HUD panel corner (x<73 from row 22) and the shelf-wrap stock "
                               "path (x>=97 at rows 0-44) only 24 columns are free, so no position clears both. The HUD is kept at 0; "
                               "the leaf's top-right tip lies on the wrap path, where the moving bottle is drawn in front of it.",
                        "alternatives_native": brooch_options}],
        "workshop_constants_verified_against_scripts": constants,
        "props": prop_checks, "souvenirs": souvenir_info,
        "element_pixels": {k: int(v.sum()) for k, v in masks.items()},
        "space_analysis": space, "layouts": placements,
        "mini_mode": {"size": list(MINI["size"]), "keeper_origin": list(MINI["keeper_origin"]), "pot_origin": list(MINI["pot_origin"]),
                      "free_width_right_of_keeper_px": mini_right, "souvenir_opaque_widths_px": widths,
                      "counter_present": False, "rendered": False},
        "passed": passed,
    }
    if not passed:
        report["final_outputs_from_this_run"] = False
    (MOCK / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    generation = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False, "date": DATE,
        "mode": "hand-authored native 32x32 pixel maps (no image generator); the .txt maps are the authoritative source",
        "reference": "docs/성장과-단골-꾸미기-기획안.md · 꾸미기와 영구 소장; color/pixel rules in AGENTS.md; counter/bottle scale from assets/pixel_v1",
        "sizing": "world scale: drawn to fit the counter-top band (native rows 64-70) that no sale/stock bottle, character or HUD reaches",
        "legend": {c: {"color": h, "ramp": r} for c, (h, r) in LEGEND.items()},
        "props": {p["id"]: {"name": p["name"], "price_candidate": p["price_candidate"], "slot": p["slot"],
                            "description": p["description"], "materials": {m: LEGEND[c][0] for c, m in p["materials"].items()}}
                  for p in PROPS},
        "souvenirs_used_read_only": {sid: v["published"] for sid, v in souvenir_info.items()},
        "new_palette_colors": 0, "postprocess_tool": "tools/process_pixel_art.py with manifest.json",
    }
    (MOCK / "generation.json").write_text(json.dumps(generation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    approval = {"schema_version": 1, "status": "candidate", "approved_by_user": False, "approved_on": None,
                "user_reply": None, "review": rel(MOCK / "review.html"), "runtime_integrated": False,
                "scope": {"decor_teacup": "판매대 소품 · 작은 찻잔", "decor_dried_vase": "판매대 소품 · 말린 꽃병",
                          "layout_A": LAYOUTS["A"]["title"], "layout_B": LAYOUTS["B"]["title"],
                          "souvenirs": "승인된 assets/pixel_v1/souvenirs/souvenir_*.png 그대로 사용(수정 없음)"},
                "pending_decisions": ["소품 디자인(찻잔·말린 꽃병) 승인 또는 수정 지시",
                                      "배치 A/B 선택(판매대 위치와 숙성통·기념품 우선순위는 따로 조합 가능)",
                                      "축소(캐릭터) 모드 표시 여부(권장: 숨김, 장착 상태 유지)"],
                "note": "사용자 승인 전 후보. assets/ 게시, 장착·구매 로직, 관리 화면 UI 연결은 승인 후 별도 작업으로 진행한다."}
    (MOCK / "approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    cols = space["counter_columns_free_from_row_64"]
    per = {sid: len(z["cask_hidden"]) for sid, z in zero.items()}
    per_drawn = {sid: len(z["cask_drawn"]) for sid, z in zero.items()}
    allz = [o for z in zero.values() for o in z["cask_hidden"]]
    zx = (min(o[0] for o in allz), max(o[0] for o in allz)) if allz else (None, None)
    zy = (min(o[1] for o in allz), max(o[1] for o in allz)) if allz else (None, None)
    b_opt = {tuple(o["origin"]): o for o in brooch_options}
    b_at = b_opt[tuple(s_origin["souvenir_leaf_brooch"])]
    b_left = b_opt[(SOUVENIR_SLOT["x"], -s_top["souvenir_leaf_brooch"])]
    summary = {
        "passed": passed,
        "band": f"원본 x{cols[0]}~{cols[1]}, 행 64~70(높이 7행)" if cols else "없음",
        "props": [{"id": p["id"], "name": p["name"], "slot": p["slot"], "price": p["price_candidate"], "description": p["description"],
                   "native": f"sprites/{p['id']}.png", "x3": f"sprites/{p['id']}-3x.png",
                   "materials": [{"name": m, "color": LEGEND[c][0]} for c, m in p["materials"].items()],
                   "color_count": prop_checks[p["id"]]["color_count"], "off_palette": prop_checks[p["id"]]["off_palette_colors"],
                   "partial_alpha": prop_checks[p["id"]]["partial_alpha_pixels"],
                   "outline_violations": len(prop_checks[p["id"]]["outline_violations"]),
                   "dither": len(prop_checks[p["id"]]["dither_3x3_blocks"]), "lit": prop_checks[p["id"]]["lighting"]["top_left_lit"],
                   "ground_row": prop_checks[p["id"]]["grounding"]["ground_row"], "ground_width": prop_checks[p["id"]]["grounding"]["ground_width"],
                   "ground_ok": prop_checks[p["id"]]["grounding"]["passed"], "opaque_size": prop_checks[p["id"]]["opaque_size"]}
                  for p in PROPS],
        "legend": [["주인공", "#C38EB5"], ["손님", "#F4AC68"], ["판매 병", "#DE7356"], ["입고 병", "#3BA8A3"], ["HUD", "#E9B95F"],
                   ["가구(숙성통 제외)", "#827589"], ["판매대 소품 2종", "#B5C77D"], ["기념품 4종", "#FFF0BC"]],
        "layouts": layout_summary, "rows": rows,
        "souvenir_note": (f"승인된 기념품은 원본 32×32를 3배로 그리면 불투명 부분이 표시 {min(widths)}~{max(widths)}px 폭, {min(heights)}~{max(heights)}px 높이입니다. "
                          f"주인공·손님·판매/입고 병·HUD·다른 가구 어느 것과도 겹치지 않는 원점(원본)을 그림마다 모두 찾으면, 숙성통이 없을 때 "
                          f"나침반 {per['souvenir_compass']}곳·책갈피 {per['souvenir_bookmark']}곳·은방울 {per['souvenir_silver_bell']}곳·브로치 {per['souvenir_leaf_brooch']}곳이고 "
                          f"모두 주인공 머리 위 숙성통 자리(원본 x{zx[0]}~{zx[1]}, y{zy[0]}~{zy[1]})입니다. 숙성통이 그려진 상태에서는 "
                          f"{sum(per_drawn.values())}곳입니다. 창문과 숙성통 사이 벽(솥 패널 위)은 높이가 원본 22행이라 "
                          f"{min(heights) // 3}~{max(heights) // 3}행인 기념품이 솥 상태 패널(HUD)에 걸리고, 창문 앞은 날씨 유리를 가립니다. "
                          f"그래서 두 안 모두 숙성통 자리를 쓰고(캔버스 왼쪽 x={SOUVENIR_SLOT['x']}, 각 그림의 불투명 윗줄을 y=0에 맞춰 매닮), "
                          f"숙성통과 함께 있을 때의 규칙만 A(숙성통 우선)·B(기념품 우선)로 나눴습니다.<br><b>예외 · 잎사귀 브로치</b>: 대각선으로 26칸이라 "
                          f"솥 패널 모서리(원본 x72까지, 22행부터)와 선반 왼쪽으로 돌아 올라가는 입고 병 길(원본 x97부터, 0~44행) 사이 24칸에 들어가지 않습니다. "
                          f"x={SOUVENIR_SLOT['x']}이면 핀 끝 {b_left['hud'] // 9}원본픽셀이 솥 패널(HUD) 모서리 뒤로 들어가므로, 브로치만 2칸 오른쪽(x={s_origin['souvenir_leaf_brooch'][0]})에 둡니다. "
                          f"그러면 HUD 겹침 {b_at['hud']}, 대신 잎 오른쪽 위 끝 {b_at['stock_bottles'] // 9}원본픽셀(표시 {b_at['stock_bottles']}px)이 "
                          f"‘아래 칸 병이 위 칸으로 옮겨 갈 때’ 지나가는 길 위에 놓입니다. 병이 기념품 앞에 그려지므로 병은 가려지지 않습니다. 이 자리를 허용할지도 함께 봐 주세요."
                          f"<br><b>크기 메모</b>: 기념품 그림은 관리 카드용 아이콘(32×32를 꽉 채움)이라 작업실 공통 3배에서는 솥과 비슷한 크기의 ‘벽 장식판’처럼 보입니다. "
                          f"실제 물건 크기로 작게 보이려면 작업실 전용 작은 그림을 따로 만들어야 하며(이번 범위 밖), 그 경우 숙성통과 함께 거는 자리도 다시 찾을 수 있습니다."),
        "mini_note": (f"축소 모드(256×228, 아트 177)에는 판매대·선반·벽이 없고 주인공(표시 117~213)과 솥만 있습니다. 주인공 오른쪽 빈 폭은 {mini_right}px로 "
                      f"기념품 3배 폭 {min(widths)}~{max(widths)}px보다 좁고, 판매대 소품은 올려놓을 면이 없습니다. 그래서 <b>숨김(장착 상태 유지)</b>을 권장합니다. "
                      f"이 판단은 <code>scripts/mini_workshop.gd</code> 상수로 계산했고 축소 모드 화면은 그려 보지 않았습니다."),
    }
    (MOCK / "review.html").write_text(REVIEW.replace("/*SUMMARY*/null", json.dumps(summary, ensure_ascii=False)), encoding="utf-8")

    print(json.dumps({"passed": passed, "props": {k: {"passed": c["passed"], "colors": c["color_count"],
                      "off_palette": c["off_palette_colors"], "partial_alpha": c["partial_alpha_pixels"],
                      "outline_violations": len(c["outline_violations"]), "dither": len(c["dither_3x3_blocks"]),
                      "opaque_size": c["opaque_size"], "ground": c["grounding"]["passed"], "lighting": c["lighting"]}
                      for k, c in prop_checks.items()},
                      "souvenirs_identical": souvenirs_ok, "counter_band": space["counter_columns_free_from_row_64"],
                      "souvenir_zero_origins_cask_hidden": per, "souvenir_zero_origins_cask_drawn": per_drawn,
                      "souvenir_origins": s_origin, "brooch_options": brooch_options,
                      "layouts": {lid: {"combos_passed": all(c["passed"] for c in p["combos"].values()),
                                        "max_strict": max(c["strict_overlap_total"] for c in p["combos"].values()),
                                        "max_stock": max(c["stock_overlap_total"] for c in p["combos"].values()),
                                        "max_furniture": max(c["furniture_overlap_total"] for c in p["combos"].values()),
                                        "min_rest_gap": min((c["rest_bottle_min_gap_rows"] for c in p["combos"].values()
                                                             if c["rest_bottle_min_gap_rows"] is not None), default=None),
                                        "examples": {e: v["passed"] for e, v in p["examples"].items()}}
                                  for lid, p in placements.items()}}, ensure_ascii=False, indent=1))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
