"""F23 workshop souvenirs: small (<=12x12 native) redraws of the four approved F22 souvenirs + slot spots A/B.

Candidate only. The approved 32x32 souvenirs (assets/pixel_v1/souvenirs) are management-window icons; at the
workshop's common x3 scale they would be as large as the cauldron. This build reads hand-authored small native
pixel maps (art/mockups/f23-souvenir-mini-v1/source/*.txt; redrawn on the small grid, never resampled from the
32x32 art), registers them as native PNGs, runs the fixed tools/process_pixel_art.py pipeline with an explicit
per-color material manifest, adds souvenir checks (size, outline, palette, colors, partial alpha, ramps,
dithering, lighting, ground row), then places them at two candidate workshop spots and counts opaque-pixel
overlaps against every element the F23 decor build already maps.

Occupancy is reused, not re-derived: tools/build_f23_decor_v1.py is imported and its build_masks() (keeper /
customer poses, sale and stock bottle paths, HUD panels, furniture, the aging cask at display 219,0) is called
as is, and its script-constant check (source_constants) must pass. The approved counter prop slot (layout A,
native canvas origin 96,40) is added as an obstacle with both approved props.

Nothing under assets/ or scripts/ is written. Player saves, the running game and Windows registration are
untouched.

Run with Pillow + NumPy: python tools/build_f23_souvenir_mini_v1.py
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "art/mockups/f23-souvenir-mini-v1"
SRC = MOCK / "source"
PIPE = MOCK / "pipeline"
SPRITES = MOCK / "sprites"
LAYOUT_DIR = MOCK / "layouts"
F22 = ROOT / "art/mockups/f22-regulars-souvenirs-v1"
F23 = ROOT / "art/mockups/f23-decor-v1"
SCALE = 3
MAX_NATIVE = 12  # native grid limit per side -> 36 display px at the workshop's x3
OUTLINE_HEX = "#241C32"
OUTLINE = (0x24, 0x1C, 0x32)
DATE = "2026-10-23"

_spec = importlib.util.spec_from_file_location("build_f23_decor_v1", ROOT / "tools/build_f23_decor_v1.py")
decor = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(decor)
W, H = decor.W, decor.H

# Same letters / approved colors / ramps as the F22 souvenir maps.
LEGEND = {
    "#": ("#241C32", "outline"),
    "d": ("#A56A3D", "gold"), "g": ("#E9B95F", "gold"), "h": ("#FFF0BC", "gold"),
    "P": ("#50315F", "purple"), "p": ("#86548E", "purple"), "l": ("#C38EB5", "purple"),
    "L": ("#3D544D", "leaf"), "e": ("#718C59", "leaf"), "n": ("#B5C77D", "leaf"),
    "k": ("#4A3C52", "stone"), "m": ("#827589", "stone"),
    "r": ("#DE7356", "fire"),
}

# hang = native pixel (x, y) in the mini canvas that rests under the wall peg in spot B.
MINIS = [
    {"id": "souvenir_compass_mini", "base": "souvenir_compass", "customer": "traveler", "customer_name": "여행자",
     "name": "낡은 나침반", "hang": (5, 0),
     "description": "위 고리(금 1픽셀)와 둥근 놋쇠 테, 크림색 문자판, 오른쪽 위를 가리키는 빨간 북쪽 바늘과 왼쪽 아래 어두운 남쪽 바늘, "
                    "가운데 축. 테는 왼쪽 위 금빛·오른쪽 아래 그림자, 왼쪽 위 테에 크림 반짝임 1픽셀. 원본의 눈금은 12칸에서 읽히지 않아 생략.",
     "materials": {"#": "outline", "d": "brass_shadow", "g": "brass", "h": "dial_and_glint", "r": "needle_north"}},
    {"id": "souvenir_bookmark_mini", "base": "souvenir_bookmark", "customer": "mage", "customer_name": "여마법사",
     "name": "별무늬 책갈피", "hang": (4, 0),
     "description": "제비꼬리 끝의 보라 천 띠(왼쪽 라일락 밝은 단·오른쪽 짙은 그림자 단), 가운데 금빛 십자 별, 아래 라일락 작은 별 1개, "
                    "위 끈 고리, 오른쪽 금빛 술. 원본의 작은 별 3개는 1개로 줄였다.",
     "materials": {"#": "outline", "P": "cloth_shadow", "p": "cloth", "l": "cloth_light_and_sparkle", "g": "star_and_tassel"}},
    {"id": "souvenir_leaf_brooch_mini", "base": "souvenir_leaf_brooch", "customer": "elf", "customer_name": "엘프",
     "name": "잎사귀 브로치", "hang": (8, 0),
     "description": "45도로 기운 넓은 잎과 끝까지 이어지는 금빛 가운데 잎맥, 왼쪽 아래 둥근 금 핀 머리. 잎은 왼쪽 위 반쪽이 밝은 연두, "
                    "오른쪽 아래로 갈수록 초록·짙은 초록. 원본의 곁맥 3쌍은 12칸에서 뭉개져 생략.",
     "materials": {"#": "outline", "L": "leaf_shadow", "e": "leaf", "n": "leaf_light", "g": "gold_filigree"}},
    {"id": "souvenir_silver_bell_mini", "base": "souvenir_silver_bell", "customer": "rogue", "customer_name": "고양이 도적",
     "name": "작은 은방울", "hang": (5, 2),
     "description": "위의 산호색 리본(고리 2개·가운데 매듭), 둥근 은방울과 가운데 가로 홈 띠, 아래 가로·세로 홈. 은은 돌·금속 램프 2단 "
                    "(왼쪽 밝게·오른쪽 그림자), 왼쪽 위 크림 반짝임 2픽셀.",
     "materials": {"#": "outline", "k": "silver_shadow", "m": "silver", "h": "metal_glint", "r": "ribbon"}},
]
PEG = {"id": "souvenir_wall_peg", "name": "벽 못 (B안 전용)",
       "description": "B안에서 기념품을 거는 3×3 쇠못 머리. 외곽선 4픽셀 + 가운데 쇠색 1픽셀.",
       "materials": {"#": "outline", "m": "iron"}}

APPROVED_PROP_ORIGIN = (96, 40)  # F23 layout A (approved): counter-prop canvas origin, native
PROP_IDS = ["decor_teacup", "decor_dried_vase"]

SPOTS = {
    "A": {"title": "A안 · 창틀 위에 올려 두기", "kind": "sit", "origin": (14, 0),
          "summary": "창문 윗테(원본 행 12, x6~33) 위, 양쪽 모서리 장식(x7~9·x30~32) 사이 가운데. 12×12 캔버스 원점 원본 (14,0), "
                     "바닥 행 y=11이 창틀 윗면 바로 위에 닿는다. 숙성통 그림과 {gap}칸 떨어져 숙성통이 열려 있어도 같이 보인다."},
    "B": {"title": "B안 · 창문과 숙성통 사이 벽 못에 걸기", "kind": "hang", "peg_origin": (53, 1),
          "summary": "창문 오른쪽 벽(원본 x34~73, 솥 패널 HUD 위 행 0~21)에 3×3 못을 박고 기념품 고리를 건다. 못 원점 원본 (53,1), "
                     "못 아래 끝 (54,3) 바로 밑에 각 그림의 걸이 점이 온다. 숙성통 그림과 {gap}칸 이상 떨어져 함께 보인다."},
}
SHORT = {"souvenir_compass_mini": "compass", "souvenir_bookmark_mini": "bookmark",
         "souvenir_leaf_brooch_mini": "leaf_brooch", "souvenir_silver_bell_mini": "silver_bell"}
WEATHER = {"souvenir_compass_mini": "day_clear", "souvenir_bookmark_mini": "night_clear",
           "souvenir_leaf_brooch_mini": "day_rain", "souvenir_silver_bell_mini": "night_rain"}
FORBIDDEN = decor.FORBIDDEN  # keeper, customers, sale_bottle, stock_bottles, hud
FURNITURE = ["weather_glass", "window", "herb", "poster", "shelf", "counter", "aging_cask", "cauldron", "fire", "floor"]


def rgb(value: str) -> tuple[int, int, int]:
    return decor.rgb(value)


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


# ---------------------------------------------------------------- source maps + pipeline
def read_map(path: Path) -> list[str]:
    rows = [line.rstrip("\r\n") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows or any(len(r) != len(rows[0]) for r in rows):
        raise SystemExit(f"Map rows must share one width: {rel(path)}")
    if len(rows) > MAX_NATIVE or len(rows[0]) > MAX_NATIVE:
        raise SystemExit(f"Map exceeds {MAX_NATIVE}x{MAX_NATIVE}: {rel(path)}")
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


def asset_entry(item: dict, source: Path, size: tuple[int, int]) -> dict:
    letters = {c: m for c, m in item["materials"].items() if c != "#"}
    materials = {"outline": [OUTLINE_HEX]}
    materials.update({m: [LEGEND[c][0]] for c, m in letters.items()})
    return {"id": item["id"], "source": rel(source), "size": list(size), "position": [0, 0], "margin": 0,
            "dark_value": 0.24, "preserve_native_frame": True, "materials": materials,
            "material_ramps": {m: LEGEND[c][1] for c, m in letters.items()},
            "rules": decor.exact_rules({m: LEGEND[c][0] for c, m in letters.items()}),
            "fallback_material": next(iter(letters.values())), "name_ko": item["name"]}


def run_pipeline(manifest_path: Path) -> dict:
    result = subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"), rel(manifest_path)],
                            cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    report = json.loads((PIPE / "validation.json").read_text(encoding="utf-8"))
    if result.returncode != 0 or report["status"] != "passed":
        raise SystemExit(f"process_pixel_art failed: {report.get('error')}\n{result.stderr}")
    return report


# ---------------------------------------------------------------- sprite checks
def ground(data: np.ndarray) -> dict:
    """The bottom canvas row is the contact row: opaque, all outline, nothing below (sitting in spot A)."""
    opaque = data[:, :, 3] == 255
    rows = np.where(opaque.any(axis=1))[0]
    bottom = int(rows.max())
    xs = np.where(opaque[bottom])[0]
    runs = int(np.sum(np.diff(np.concatenate([[0], opaque[bottom].astype(int), [0]])) == 1))
    result = {"ground_row": bottom, "canvas_bottom_row": data.shape[0] - 1, "ground_x": [int(xs.min()), int(xs.max())],
              "ground_pixels": int(len(xs)), "ground_runs": runs,
              "ground_all_outline": bool(np.all(data[bottom, xs, :3] == OUTLINE))}
    result["passed"] = bool(bottom == data.shape[0] - 1 and result["ground_all_outline"] and len(xs) >= 2)
    return result


def check_sprite(item: dict, image: Image.Image, registered: Image.Image, palette: set, ramps: dict, pipe: dict,
                 original: Image.Image | None) -> dict:
    data = np.array(image.convert("RGBA"))
    alpha = data[:, :, 3]
    opaque = alpha == 255
    colors = sorted({"#%02X%02X%02X" % tuple(p[:3]) for p in data[opaque]})
    ys, xs = np.where(opaque)
    by_ramp: dict[str, list[str]] = {}
    for c in item["materials"]:
        if c in LEGEND:
            by_ramp.setdefault(LEGEND[c][1], []).append(LEGEND[c][0])
    shades = {ramp: len(hexes) for ramp, hexes in by_ramp.items()}
    w, h = image.size
    check = {
        "name": item["name"], "native_size": [w, h], "display_size_x3": [w * SCALE, h * SCALE],
        "within_12x12": w <= MAX_NATIVE and h <= MAX_NATIVE, "display_within_36px": w * SCALE <= 36 and h * SCALE <= 36,
        "colors": colors, "color_count": len(colors), "max_colors": 5,
        "off_palette_colors": sum(1 for c in colors if rgb(c) not in palette),
        "partial_alpha_pixels": int(((alpha != 0) & (alpha != 255)).sum()),
        "outline_violations": decor.outline_violations(data), "outline_color_present": OUTLINE_HEX in colors,
        "materials": {m: {"color": LEGEND[c][0], "ramp": LEGEND[c][1]} for c, m in item["materials"].items()},
        "colors_in_declared_ramps": all(hx in ramps[r]["colors"] for r, hs in by_ramp.items() for hx in hs),
        "shades_per_ramp": shades, "max_3_shades_per_ramp": all(n <= 3 for n in shades.values()),
        "opaque_bbox": [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1],
        "opaque_size": [int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1)], "opaque_pixels": int(opaque.sum()),
        "dither_3x3_blocks": decor.dither_blocks(data),
        "pipeline_passed": pipe["passed"],
        "pipeline_preserved_source": bool(np.array_equal(np.array(registered.convert("RGBA")), data)),
        "native_sha256": hashlib.sha256(data.tobytes()).hexdigest(),
    }
    ok = (check["within_12x12"] and check["display_within_36px"] and check["color_count"] <= 5
          and check["outline_color_present"] and check["off_palette_colors"] == 0 and check["partial_alpha_pixels"] == 0
          and not check["outline_violations"] and check["colors_in_declared_ramps"] and check["max_3_shades_per_ramp"]
          and not check["dither_3x3_blocks"] and check["pipeline_passed"] and check["pipeline_preserved_source"]
          and set(colors) == {LEGEND[c][0] for c in item["materials"]})
    if original is not None:
        check["lighting"] = decor.lighting(data)
        check["ground"] = ground(data)
        odata = np.array(original.convert("RGBA"))
        ocolors = sorted({"#%02X%02X%02X" % tuple(p[:3]) for p in odata[odata[:, :, 3] == 255]})
        # Proof that the small map is a redraw, not a resample of the 32x32 icon.
        resampled = {}
        for name, method in (("nearest", Image.Resampling.NEAREST), ("box", Image.Resampling.BOX)):
            small = np.array(original.convert("RGBA").resize((w, h), method))
            either = (small[:, :, 3] > 0) | opaque  # cells opaque in either image; shared transparency is not agreement
            resampled[name] = round(float(np.mean(np.all(small[either] == data[either], axis=1))), 3)
        check["original"] = {"path": rel(F22 / "sprites" / f"{item['base']}.png"), "native_size": list(original.size),
                             "colors": ocolors, "same_color_set_as_original": ocolors == colors,
                             "pixel_agreement_with_downscaled_original": resampled,
                             "is_resample_of_original": any(v == 1.0 for v in resampled.values())}
        ok = ok and check["lighting"]["top_left_lit"] and check["ground"]["passed"] \
            and check["original"]["same_color_set_as_original"] and not check["original"]["is_resample_of_original"]
        hx, hy = item["hang"]
        check["hang_point"] = {"native": [hx, hy], "opaque": bool(opaque[hy, hx]),
                               "above_is_transparent_or_edge": bool(hy == 0 or not opaque[hy - 1, hx])}
        ok = ok and check["hang_point"]["opaque"] and check["hang_point"]["above_is_transparent_or_edge"]
    check["passed"] = bool(ok)
    return check


# ---------------------------------------------------------------- placement
def placed(alpha: np.ndarray, origin_native) -> np.ndarray:
    return decor.placed(alpha, origin_native)


def x3(image: Image.Image) -> Image.Image:
    return image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST)


def alpha_of(image: Image.Image) -> np.ndarray:
    return np.array(image)[:, :, 3] == 255


def spot_origins(spot: dict, item: dict) -> tuple[tuple[int, int], tuple[int, int] | None]:
    if spot["kind"] == "sit":
        return spot["origin"], None
    px, py = spot["peg_origin"]  # 3x3 peg; its bottom pixel is (px+1, py+2)
    hx, hy = item["hang"]
    return (px + 1 - hx, py + 3 - hy), (px, py)


def check_spot(spot_id: str, item: dict, mini: Image.Image, peg: Image.Image, prop_id: str, prop3: Image.Image,
               masks: dict, aging_open: bool) -> dict:
    spot = SPOTS[spot_id]
    origin, peg_origin = spot_origins(spot, item)
    ma, mn = alpha_of(x3(mini)), alpha_of(mini)
    souv = placed(ma, origin)
    peg_m = placed(alpha_of(x3(peg)), peg_origin) if peg_origin else np.zeros((H, W), bool)
    prop = placed(alpha_of(prop3), APPROVED_PROP_ORIGIN)
    r = {"spot": spot_id, "souvenir": item["id"], "prop": prop_id, "aging_open": aging_open, "aging_cask_drawn": aging_open,
         "souvenir_origin_native": list(origin), "souvenir_origin_display": [v * SCALE for v in origin],
         "peg_origin_native": list(peg_origin) if peg_origin else None,
         "souvenir_inside_art": int(souv.sum()) == int(ma.sum()),
         "peg_inside_art": (not peg_origin) or int(peg_m.sum()) == int(alpha_of(x3(peg)).sum()),
         "souvenir": {}, "peg": {}}
    for part, m in (("souvenir", souv), ("peg", peg_m)):
        for name in FORBIDDEN:
            r[part][name] = int((m & masks[name]).sum())
        for name in FURNITURE:
            if name == "aging_cask" and not aging_open:
                continue
            r[part][name] = int((m & masks["furniture_" + name]).sum())
        r[part]["counter_prop"] = int((m & prop).sum())
    r["souvenir_vs_peg"] = int((souv & peg_m).sum())
    # The cask overlap is also counted when the cask is closed, so "shown together" never depends on hiding.
    r["cask_overlap_if_drawn"] = int(((souv | peg_m) & masks["furniture_aging_cask"]).sum())
    if spot["kind"] == "sit":
        win = decor.native_blocks(masks["furniture_window"])
        ys, xs = np.where(mn)
        gy = int(ys.max())
        gx = xs[ys == gy] + origin[0]
        row = gy + origin[1]
        r["support"] = {"kind": "ground row on the window frame top", "ground_native_row": row,
                        "ground_native_x": [int(gx.min()), int(gx.max())],
                        "frame_directly_below_every_ground_pixel": bool(np.all(win[row + 1, gx])),
                        "ground_row_itself_clear_of_frame": bool(not np.any(win[row, gx]))}
        r["support"]["passed"] = r["support"]["frame_directly_below_every_ground_pixel"] and r["support"]["ground_row_itself_clear_of_frame"]
    else:
        hx, hy = item["hang"]
        pb = (peg_origin[0] + 1, peg_origin[1] + 2)
        r["support"] = {"kind": "hang point directly under the peg's bottom pixel", "peg_bottom_native": list(pb),
                        "hang_point_native": [origin[0] + hx, origin[1] + hy],
                        "touching": bool(origin[0] + hx == pb[0] and origin[1] + hy == pb[1] + 1)}
        r["support"]["passed"] = r["support"]["touching"] and r["souvenir_vs_peg"] == 0
    total = sum(v for part in ("souvenir", "peg") for v in r[part].values())
    r["overlap_total"] = total
    r["passed"] = bool(total == 0 and r["cask_overlap_if_drawn"] == 0 and r["souvenir_vs_peg"] == 0
                       and r["souvenir_inside_art"] and r["peg_inside_art"] and r["support"]["passed"])
    return r


# ---------------------------------------------------------------- composition
def compose(scene, example: dict, mini3: Image.Image, peg3: Image.Image | None, origin, peg_origin, prop3: Image.Image):
    """Static waiting frame in ShopArt workshop_commands order; the souvenir goes right after the counter prop and
    the aging cask (before stock bottles), so bottles, people and the HUD layer are always drawn above it."""
    cat = scene.catalog
    canvas = Image.new("RGBA", (W, H))
    drawn = np.zeros((H, W), bool)

    def put(image: Image.Image, point):
        canvas.alpha_composite(image, (int(point[0]), int(point[1])))
        decor.stamp(drawn, np.array(image)[:, :, 3] > 0, int(point[0]), int(point[1]))

    put(scene.x3(cat["weather"][example["weather"]][0]), decor.GEOMETRY["window"][0])
    for key in ("floor", "window", "herb", "poster", "counter"):
        put(scene.x3(cat["props"][key]), (0, 0) if key == "floor" else decor.GEOMETRY[key][0])
    put(prop3, (APPROVED_PROP_ORIGIN[0] * 3, APPROVED_PROP_ORIGIN[1] * 3))
    if example["aging_open"]:
        put(scene.x3(cat["props"]["aging_cask"]), decor.GEOMETRY["aging_cask"][0])
    if peg3 is not None:
        put(peg3, (peg_origin[0] * 3, peg_origin[1] * 3))
    put(mini3, (origin[0] * 3, origin[1] * 3))
    stock = scene.ids[::4][:8]
    for i, pid in enumerate(stock):
        b = scene.x3(cat["potions"][pid]["bottle"])
        cx, cy = scene.slot_center(i, pid)
        put(b, (round(cx - b.width / 2), round(cy - b.height / 2)))
    put(scene.x3(cat["props"]["shelf"]), decor.GEOMETRY["shelf"][0])
    put(scene.x3(cat["fire"][0]), decor.GEOMETRY["hearth"][0])
    put(scene.x3(cat["potions"][stock[1]]["pots"][0]), decor.GEOMETRY["pot"][0])
    put(scene.fine_cells("keeper", "idle")[0], decor.GEOMETRY["keeper"][0])
    wait = (decor.GEOMETRY["purchase_feet_x"][0] - 48, decor.GEOMETRY["customer_y"][0])
    put(scene.fine_cells(example["customer"], "idle")[0], wait)
    alpha = np.array(canvas)[:, :, 3]
    return canvas, bool(np.all(alpha[~drawn] == 0))


def occupancy_image(masks: dict, prop_alphas: list, footprints: list) -> Image.Image:
    """Review aid (not game art): flat palette colors per element, the aging cask, the counter props and the footprint."""
    colors = [("furniture", "#827589"), ("furniture_aging_cask", "#A56A3D"), ("hud", "#E9B95F"), ("stock_bottles", "#3BA8A3"),
              ("sale_bottle", "#DE7356"), ("customers", "#F4AC68"), ("keeper", "#C38EB5")]
    out = np.zeros((H, W, 4), np.uint8)
    furniture = np.zeros((H, W), bool)
    for k, v in masks.items():
        if k.startswith("furniture_") and k != "furniture_aging_cask":
            furniture |= v
    for name, hex_ in colors:
        m = furniture if name == "furniture" else masks[name]
        out[m] = (*rgb(hex_), 255)
    for a in prop_alphas:
        out[placed(a, APPROVED_PROP_ORIGIN)] = (*rgb("#B5C77D"), 255)
    for a, origin in footprints:
        out[placed(a, origin)] = (*rgb("#FFF0BC"), 255)
    return Image.fromarray(out)


def free_origins(alpha_native: np.ndarray, obstacles: np.ndarray) -> list[list[int]]:
    """Native origins (whole sprite inside the art) with no shared pixel. Sprites are drawn on whole native cells, so a
    display-pixel overlap exists exactly when an opaque native cell meets a native block holding any obstacle pixel."""
    blocks = decor.native_blocks(obstacles)
    h, w = alpha_native.shape
    found = []
    for oy in range(0, blocks.shape[0] - h + 1):
        for ox in range(0, blocks.shape[1] - w + 1):
            if not (blocks[oy:oy + h, ox:ox + w] & alpha_native).any():
                found.append([ox, oy])
    return found


# ---------------------------------------------------------------- review page
REVIEW = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>작업실 기념품 작은 그림</title><style>
@font-face{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}
:root{--bg:#241c32;--panel:#30263f;--line:#827589;--text:#fff0bc;--muted:#c38eb5;--accent:#e9b95f;--ok:#b5c77d;--bad:#de7356}
*{box-sizing:border-box}html,body{background:var(--bg)}body{margin:0;color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}
main{max-width:1210px;margin:auto;padding:18px 16px 48px}h1{font-size:23px;margin:0 0 6px}h2{font-size:17px;margin:28px 0 8px}h3{font-size:15px;margin:14px 0 6px}
p{margin:6px 0 10px}.muted{color:var(--muted)}code{font-size:13px;color:var(--muted)}
.note{border-left:3px solid #718c59;padding:8px 12px;background:var(--panel);margin:10px 0}.warn{border-left-color:var(--accent)}
.check{background-color:#4a3c52;background-image:linear-gradient(45deg,#3f3347 25%,transparent 25%),linear-gradient(-45deg,#3f3347 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#3f3347 75%),linear-gradient(-45deg,transparent 75%,#3f3347 75%);background-size:12px 12px;background-position:0 0,0 6px,6px -6px,-6px 0}
img{image-rendering:pixelated;image-rendering:crisp-edges;max-width:none;display:block}
.decide{display:grid;gap:8px}.decide div{background:var(--panel);padding:8px 12px;border-radius:4px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:12px}
.card{background:var(--panel);border:1px solid #4a3c52;border-radius:6px;padding:12px}.card h3{margin:0}
.sizes{display:flex;align-items:flex-end;gap:10px;margin:10px 0 6px;flex-wrap:wrap}.sizes figure{margin:0;text-align:center}.sizes .check{display:flex;align-items:center;justify-content:center;padding:4px}
.sizes .sep{width:1px;align-self:stretch;background:#4a3c52}
figcaption{font-size:11px;color:var(--muted);margin-top:3px}
.desc{font-size:13px;margin:6px 0}.sw{display:flex;flex-wrap:wrap;gap:6px;font-size:11px;color:var(--muted)}.sw span{display:flex;align-items:center;gap:3px}
.sw i{width:12px;height:12px;display:inline-block;border:1px solid #000;background:var(--c)}
.controls{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:8px 0}
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
.zoom{display:flex;gap:10px;flex-wrap:wrap;margin-top:8px}.zoom figure{margin:0}.zoom .z{width:500px;height:180px;max-width:100%;overflow:hidden;position:relative}
.zoom .z img{position:absolute;width:1080px;height:498px}
.legend{display:flex;flex-wrap:wrap;gap:10px;font-size:12px;color:var(--muted);margin:6px 0}.legend span{display:flex;gap:4px;align-items:center}.legend i{width:12px;height:12px;display:inline-block;background:var(--c);border:1px solid #000}
table{border-collapse:collapse;width:100%;font-size:12.5px}th,td{border-bottom:1px solid #4a3c52;padding:4px 6px;text-align:left;vertical-align:top}th{color:var(--muted);font-weight:normal}
.ok{color:var(--ok)}.bad{color:var(--bad)}.table-wrap{overflow-x:auto}
ul{margin:6px 0 10px;padding-left:20px}
</style></head><body><main>
<h1>작업실 기념품 · 작은 그림 4종과 자리 후보 v1</h1>
<p class="muted">후보 단계입니다. <code>assets/</code>·<code>scripts/</code>·저장은 바꾸지 않았고 게임에 연결하지 않았습니다. 승인된 32×32 기념품(관리 창 1배용)은 그대로 두고, 작업실 공통 3배에서 쓸 작은 그림을 작은 격자에서 새로 그렸습니다(축소 리샘플링 아님).</p>
<p id="overall"></p>

<h2>정해 주실 것</h2>
<div class="decide">
<div><b>1. 작은 기념품 4종 디자인</b>: 낡은 나침반 · 별무늬 책갈피 · 잎사귀 브로치 · 작은 은방울을 이대로 쓸지, 고칠 곳.</div>
<div><b>2. 자리 A/B</b>: <b>A 창틀 위에 올려 두기</b> 또는 <b>B 창문과 숙성통 사이 벽 못에 걸기</b>. 두 자리 모두 숙성통이 열려 있어도 기념품이 함께 보이며(숨김 규칙 불필요), 승인된 판매대 소품 A안 자리와 떨어져 있습니다. B는 3×3 벽 못 그림이 하나 더 들어갑니다.</div>
</div>

<h2>작은 기념품 4종 · 원본 32×32와 나란히</h2>
<div class="note">승인 24색·재질 램프만 사용 · 공통 외곽선 #241C32 1픽셀(투명에 닿는 모든 경계) · 물체당 최대 5색(4종 모두 원본과 같은 5색) · 반투명 0 · 좌측 상단 조명 · 디더링 없음 · 공통 3배 최근접. 원본 격자 최대 12×12 = 작업실 3배에서 36px 이하. 체크무늬는 페이지 CSS이고 PNG는 투명 배경입니다.</div>
<div class="cards" id="cards"></div>
<div class="note warn" id="size-note"></div>

<h2>자리 A/B 비교 · 작업실 540×249 아트(공통 3배) + HUD</h2>
<p class="muted">판매대 소품은 승인된 A안 자리(원본 캔버스 원점 96,40)에 작은 찻잔을 장착한 상태입니다. 기념품과 숙성통 상태를 골라 보세요.</p>
<div class="controls" id="global"><label class="tog"><input type="checkbox" id="tog-hud" checked>HUD 표시</label><label class="tog"><input type="checkbox" id="tog-occ">움직임·HUD·가구 영역 겹쳐 보기</label></div>
<div class="legend" id="legend"></div>
<div class="compare" id="compare"></div>
<p class="muted">HUD 상자·글자·하단 바는 위치 확인용 일반 DOM 글자이며 PNG에 들어 있지 않습니다. PNG의 빈 공간은 알파 0입니다. 아래 확대는 같은 PNG의 왼쪽 위 부분을 2배로 보여 줍니다.</p>

<h2>가림 검사</h2>
<p class="muted">숫자는 기념품(B는 못 포함)의 불투명 픽셀(표시 3배 기준)과 각 요소가 차지할 수 있는 모든 픽셀의 합집합이 겹치는 수입니다. 점유 영역은 <code>tools/build_f23_decor_v1.py</code>의 <code>build_masks()</code>를 그대로 불러 썼습니다: 주인공 공개 포즈 전부·수면 Z·기절 별·국자, 손님 4명의 대기/걷기/받기/병 든 퇴장(좌우 반전)·손바닥, 판매 병 선반 출고→판매대 쉼터→손님 손→퇴장(숙성 인장 포함), 입고 병 솥→선반·줄 바꿈·보관 칸 이동, HUD 패널·버튼·수확 알림, 가구 전부, 숙성통(219,0). 판매대 소품은 승인된 A안 자리에 찻잔과 말린 꽃병을 각각 놓고 셌습니다. ‘숙성통’ 열은 숙성통이 닫혀 있을 때도 그려졌다고 가정한 겹침입니다.</p>
<div class="table-wrap"><table id="table"></table></div>
<h3>다른 자리를 고르지 않은 이유</h3>
<div class="note" id="space-note"></div>

<h2>승인 후 연결 메모 (이번 작업에서 하지 않음)</h2>
<ul>
<li>그리는 순서: 판매대 소품 → (숙성통) → (B: 못) → 기념품 → <code>stock_start</code>. 모든 병·주인공·손님·HUD가 기념품 위에 그려지지만 겹침 자체가 0이라 순서와 무관하게 가려지지 않습니다.</li>
<li id="coords"></li>
<li>축소(캐릭터) 모드에는 창문·벽이 없어 판매대 소품과 같은 규칙(표시 안 함, 장착 상태 유지)을 권장합니다. 축소 모드·기본(전체 실내) 화면은 그려 보지 않았습니다.</li>
<li>저장·장착 로직과 관리 화면 UI는 승인 뒤 메인 세션이 붙입니다. 관리 창의 32×32 기념품 아이콘은 그대로 씁니다.</li>
</ul>
<p class="muted">재현: <code>python tools/build_f23_souvenir_mini_v1.py</code> → 원본 지도(<code>source/*.txt</code>) → 등록 PNG → <code>tools/process_pixel_art.py</code>(<code>manifest.json</code>) → 기념품 검사 → 작업실 배치·가림 검사(<code>validation.json</code>) → 이 페이지. 수치 검사는 디자인 승인을 대신하지 않습니다.</p>
</main><script>
const S=/*SUMMARY*/null;
const el=(t,a={},h='')=>{const e=document.createElement(t);for(const k in a)e.setAttribute(k,a[k]);e.innerHTML=h;return e};
const k=(v,good)=>`<span class="${good?'ok':'bad'}">${v}</span>`;
document.getElementById('overall').innerHTML=S.passed?'<span class="ok">수치 검사 통과</span> · 4종 모두 12×12 이하·5색·팔레트 밖 0·반투명 0·외곽선 위반 0·디더링 0 · 두 자리 모두 숙성통 열림/닫힘 × 판매대 소품 2종 조합에서 주인공·손님·판매/입고 병·HUD·가구·숙성통·판매대 소품과 겹침 0':'<span class="bad">검사 실패 항목이 있습니다</span>';
const cards=document.getElementById('cards');
for(const it of S.minis){
 const c=el('div',{class:'card'});c.append(el('div',{class:'muted'},`${it.customer} 단골 기념품`),el('h3',{},it.name));
 const sz=el('div',{class:'sizes'});
 const fig=(w,h,lab,src)=>{const f=el('figure');const b=el('div',{class:'check'});b.append(el('img',{src,width:w,height:h,alt:it.name+' '+lab}));f.append(b,el('figcaption',{},lab));return f};
 sz.append(fig(it.size[0],it.size[1],`작은 그림 1배 ${it.size.join('×')}`,it.native),fig(it.size[0]*3,it.size[1]*3,`작은 그림 3배 ${it.size[0]*3}×${it.size[1]*3} · 작업실`,it.x3),fig(it.size[0]*6,it.size[1]*6,'6배(확인용)',it.x3),el('div',{class:'sep'}),
   fig(32,32,'원본 32×32 1배 · 관리 창',it.orig),fig(96,96,'원본 3배 96px · 작업실에 그대로 걸면',it.orig3));
 c.append(sz,el('p',{class:'desc'},it.description));
 const sw=el('div',{class:'sw'});for(const m of it.materials)sw.append(el('span',{},`<i style="--c:${m.color}"></i>${m.color} ${m.name}`));c.append(sw);
 c.append(el('p',{class:'desc'},`${k(it.color_count+'색',it.color_count<=5)}(원본과 같은 색 ${k(it.same_colors?'예':'아니오',it.same_colors)}) · 팔레트 밖 ${k(it.off_palette,it.off_palette===0)} · 반투명 ${k(it.partial_alpha,it.partial_alpha===0)} · 외곽선 위반 ${k(it.outline_violations,it.outline_violations===0)} · 디더링 ${k(it.dither,it.dither===0)} · 좌상단 조명 ${k(it.lit?'예':'아니오',it.lit)} · 바닥 행 y=${it.ground_row} ${k(it.ground_ok?'통과':'실패',it.ground_ok)} · 불투명 ${it.opaque_size.join('×')} · 축소본과 픽셀 일치 ${Math.round(it.agreement*100)}%(리샘플링 아님) · <code>${it.id}</code>`));
 cards.append(c)}
document.getElementById('size-note').innerHTML=S.size_note;
const legend=document.getElementById('legend');for(const [n,c] of S.legend)legend.append(el('span',{},`<i style="--c:${c}"></i>${n}`));
const cmp=document.getElementById('compare');const stages=[];
function hud(){const h=el('div',{class:'hud'});const add=(cls,r,txt='')=>{const d=el('div',{class:cls},txt);Object.assign(d.style,{left:r[0]+'px',top:r[1]+'px',width:r[2]+'px',height:r[3]+'px'});h.append(d)};
 add('pn',[111,66,108,24],'&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;제조 중');add('btn',[114,69,18,18]);add('pn',[111,92,108,22],'상쾌 · 피로 12');add('pn',[6,114,102,24],'1종 재배 중');add('btn',[86,117,18,18]);
 add('cap',[375,152,84,18],'재고 8 / 12');add('cap',[483,41,30,12],'원정');add('cap',[483,55,30,12],'대기');add('btn',[487,68,16,16]);return h}
for(const L of S.spots){
 const col=el('div',{class:'col'});col.append(el('h3',{},L.title),el('p',{class:'desc muted'},L.summary),el('p',{class:'desc'},L.coords));
 const bar=el('div',{class:'controls'});const bar2=el('div',{class:'controls'});const wrap=el('div',{class:'wrap'});const st=el('div',{class:'stage check'});
 const img=el('img',{alt:L.title});const occ=el('img',{class:'occ',src:L.occupancy,alt:'겹침 확인 영역'});
 st.append(img,occ,hud(),el('div',{class:'bar'},'<span>☰</span><span>12,480 G</span><span>낮 · 맑음</span><span class="m">관리</span><span>－</span><span>□</span><span>✕</span>'));
 const zoom=el('div',{class:'zoom'});const zf=el('figure');const zb=el('div',{class:'z check'});const zi=el('img',{alt:'확대'});zb.append(zi);zf.append(zb,el('figcaption',{},'왼쪽 위 확대 · 2배 (창문·벽·숙성통 왼쪽, 표시 x0~250·y0~90)'));zoom.append(zf);
 const cap=el('p',{class:'muted desc'});let cur={s:L.examples[0].souvenir,open:false};
 function show(){const ex=L.examples.find(e=>e.souvenir===cur.s&&e.aging_open===cur.open);img.src=ex.png;zi.src=ex.png;zi.style.left='0px';zi.style.top='0px';cap.textContent=`${ex.id} · ${ex.label}`;
  bar.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',b.dataset.s===cur.s));bar2.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.o==='1')===String(cur.open)))}
 for(const m of S.minis){const b=el('button',{'data-s':m.id},m.name);b.onclick=()=>{cur.s=m.id;show()};bar.append(b)}
 for(const [o,lab] of [['0','숙성통 닫힘'],['1','숙성통 열림']]){const b=el('button',{'data-o':o},lab);b.onclick=()=>{cur.open=o==='1';show()};bar2.append(b)}
 wrap.append(st);col.append(bar,bar2,wrap,cap,zoom);cmp.append(col);stages.push(st);show()}
document.getElementById('tog-hud').onchange=e=>stages.forEach(s=>s.classList.toggle('hide-hud',!e.target.checked));
document.getElementById('tog-occ').onchange=e=>stages.forEach(s=>s.classList.toggle('show-occ',e.target.checked));
const t=document.getElementById('table');
t.append(el('tr',{},'<th>자리</th><th>기념품</th><th>숙성통</th><th>판매대 소품</th><th>주인공</th><th>손님</th><th>판매 병</th><th>입고 병</th><th>HUD</th><th>가구</th><th>숙성통</th><th>판매대 소품</th><th>못과 기념품</th><th>받침</th><th>판정</th>'));
for(const r of S.rows){t.append(el('tr',{},`<td>${r.spot}</td><td>${r.souvenir}</td><td>${r.aging}</td><td>${r.prop}</td>${['keeper','customers','sale_bottle','stock_bottles','hud','furniture','cask','counter_prop','peg_vs_souvenir'].map(n=>`<td>${k(r[n],r[n]===0)}</td>`).join('')}<td>${k(r.support?'통과':'실패',r.support)}</td><td>${k(r.passed?'통과':'실패',r.passed)}</td>`))}
document.getElementById('space-note').innerHTML=S.space_note;
document.getElementById('coords').innerHTML=S.coords_note;
</script></body></html>
"""


def main() -> int:
    palette = {rgb(v) for v in (ROOT / "art/palette.hex").read_text(encoding="utf-8").split()}
    ramp_data = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
    ramps = ramp_data["ramps"]
    for char, (hex_, ramp) in LEGEND.items():
        if rgb(hex_) not in palette or hex_ not in ramps[ramp]["colors"]:
            raise SystemExit(f"Legend {char} {hex_} is not an approved {ramp} color")
    constants = decor.source_constants()
    if not all(constants.values()):
        raise SystemExit(f"Workshop geometry drifted from scripts: {[k for k, v in constants.items() if not v]}")
    f23_approval = json.loads((F23 / "approval.json").read_text(encoding="utf-8"))
    if not (f23_approval.get("approved_by_user") and "96,40" in f23_approval["scope"]["layout_A"]):
        raise SystemExit("Approved F23 counter-prop slot A (96,40) not found in art/mockups/f23-decor-v1/approval.json")

    # ---- register hand-authored maps and run the fixed pipeline
    items = MINIS + [PEG]
    assets, registered, source_hashes = [], {}, {}
    for item in items:
        text_path = SRC / f"{item['id']}.txt"
        image = render_map(read_map(text_path), item["materials"])
        path = SRC / f"{item['id']}-registered.png"
        image.save(path)
        registered[item["id"]] = image
        source_hashes[item["id"]] = {"map": rel(text_path), "map_sha256": hashlib.sha256(text_path.read_bytes()).hexdigest(),
                                     "registered_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        assets.append(asset_entry(item, path, image.size))
    manifest = {"schema_version": 1, "status": "candidate", "approved_by_user": False, "compose": False,
                "scale": SCALE, "alpha_threshold": 224, "max_colors": 5,
                "palette": "art/palette.hex", "ramps": "art/ramps.json", "output": rel(PIPE),
                "scene": {"size": [MAX_NATIVE, MAX_NATIVE], "background": "#4A3C52"},
                "feature": "F23 workshop souvenir minis", "runtime_integrated": False, "assets": assets}
    manifest_path = MOCK / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    pipe_report = run_pipeline(manifest_path)

    SPRITES.mkdir(exist_ok=True)
    checks, natives = {}, {}
    for item in items:
        native = Image.open(PIPE / f"{item['id']}-native.png").convert("RGBA")
        original = Image.open(F22 / "sprites" / f"{item['base']}.png").convert("RGBA") if "base" in item else None
        check = check_sprite(item, native, registered[item["id"]], palette, ramps, pipe_report["assets"][item["id"]], original)
        big = x3(native)
        expected = np.repeat(np.repeat(np.array(native), SCALE, axis=0), SCALE, axis=1)
        check["integer_3x_nearest_verified"] = bool(np.array_equal(np.array(big), expected))
        check["passed"] = check["passed"] and check["integer_3x_nearest_verified"]
        check["source"] = source_hashes[item["id"]]
        checks[item["id"]] = check
        if check["passed"]:
            native.save(SPRITES / f"{item['id']}.png")
            big.save(SPRITES / f"{item['id']}-3x.png")
        natives[item["id"]] = native
    sprites_passed = all(c["passed"] for c in checks.values())
    # The published 32x32 souvenirs must still be the approved F22 sprites (read only).
    originals = {}
    for m in MINIS:
        pub, appr = ROOT / f"assets/pixel_v1/souvenirs/{m['base']}.png", F22 / "sprites" / f"{m['base']}.png"
        originals[m["base"]] = {"published": rel(pub), "approved": rel(appr), "identical": pub.read_bytes() == appr.read_bytes()}

    # ---- reuse the F23 occupancy masks
    scene = decor.Scene()
    masks = decor.build_masks(scene)
    f23_validation = json.loads((F23 / "validation.json").read_text(encoding="utf-8"))
    pixels = {k: int(v.sum()) for k, v in masks.items()}
    same_as_f23 = all(pixels.get(k) == v for k, v in f23_validation["element_pixels"].items() if k != "sale_rest")
    props3 = {pid: x3(Image.open(F23 / "sprites" / f"{pid}.png").convert("RGBA")) for pid in PROP_IDS}

    # ---- spot checks
    LAYOUT_DIR.mkdir(exist_ok=True)
    placements, rows, spot_summary = {}, [], []
    combos_passed = True
    peg = natives[PEG["id"]]
    for sid, spot in SPOTS.items():
        placements[sid] = {"title": spot["title"], "kind": spot["kind"], "combos": {}, "examples": {}}
        if spot["kind"] == "sit":
            placements[sid]["canvas_origin_native"] = list(spot["origin"])
        else:
            placements[sid]["peg_origin_native"] = list(spot["peg_origin"])
            placements[sid]["peg_origin_display"] = [v * 3 for v in spot["peg_origin"]]
        for item in MINIS:
            origin, peg_origin = spot_origins(spot, item)
            placements[sid].setdefault("souvenir_origins_native", {})[item["id"]] = list(origin)
            placements[sid].setdefault("souvenir_origins_display", {})[item["id"]] = [v * 3 for v in origin]
            for pid in PROP_IDS:
                for aging in (False, True):
                    r = check_spot(sid, item, natives[item["id"]], peg, pid, props3[pid], masks, aging)
                    placements[sid]["combos"][f"{item['id']}+{pid}+{'aging_open' if aging else 'aging_closed'}"] = r
                    combos_passed &= r["passed"]
                    furn = sum(r[p][f] for p in ("souvenir", "peg") for f in FURNITURE if f != "aging_cask" and f in r[p])
                    rows.append({"spot": sid, "souvenir": item["name"], "aging": "열림" if aging else "닫힘",
                                 "prop": "작은 찻잔" if pid == "decor_teacup" else "말린 꽃병",
                                 **{n: r["souvenir"][n] + r["peg"][n] for n in FORBIDDEN},
                                 "furniture": furn, "cask": r["cask_overlap_if_drawn"],
                                 "counter_prop": r["souvenir"]["counter_prop"] + r["peg"]["counter_prop"],
                                 "peg_vs_souvenir": r["souvenir_vs_peg"], "support": r["support"]["passed"], "passed": r["passed"]})
        examples = []
        for item in MINIS:
            origin, peg_origin = spot_origins(spot, item)
            for aging in (False, True):
                ex = {"id": f"{sid}-{SHORT[item['id']]}-{'open' if aging else 'closed'}", "souvenir": item["id"],
                      "aging_open": aging, "prop": "decor_teacup", "customer": item["customer"], "weather": WEATHER[item["id"]],
                      "label": f"{item['name']} · 숙성통 {'열림' if aging else '닫힘'} · 판매대 작은 찻잔 장착 · {item['customer_name']} 대기"}
                image, empty_ok = compose(scene, ex, x3(natives[item["id"]]), x3(peg) if peg_origin else None, origin, peg_origin,
                                          props3["decor_teacup"])
                alpha = np.array(image)[:, :, 3]
                path = LAYOUT_DIR / f"{ex['id']}-3x.png"
                image.save(path)
                image.resize((180, 83), Image.Resampling.NEAREST).save(LAYOUT_DIR / f"{ex['id']}-native.png")
                ex_check = {"png": rel(path), "size": list(image.size), "partial_alpha": int(((alpha != 0) & (alpha != 255)).sum()),
                            "empty_space_alpha_zero": empty_ok,
                            "combo": f"{item['id']}+decor_teacup+{'aging_open' if aging else 'aging_closed'}"}
                ex_check["passed"] = ex_check["partial_alpha"] == 0 and empty_ok and image.size == (W, H) \
                    and placements[sid]["combos"][ex_check["combo"]]["passed"]
                combos_passed &= ex_check["passed"]
                placements[sid]["examples"][ex["id"]] = {**ex, **ex_check}
                examples.append({"id": ex["id"], "label": ex["label"], "souvenir": item["id"], "aging_open": aging,
                                 "png": f"layouts/{ex['id']}-3x.png"})
        foot = []
        for item in MINIS:
            origin, peg_origin = spot_origins(spot, item)
            foot.append((alpha_of(x3(natives[item["id"]])), origin))
            if peg_origin:
                foot.append((alpha_of(x3(peg)), peg_origin))
        occupancy_image(masks, [alpha_of(p) for p in props3.values()], foot).save(LAYOUT_DIR / f"occupancy-{sid}.png")
        cask_cols = np.where(decor.native_blocks(masks["furniture_aging_cask"]).any(axis=0))[0]
        cask_gap = min(int(cask_cols.min()) - (o[0] + int(np.where(a.any(axis=0))[0].max()) // 3) - 1 for a, o in foot)
        placements[sid]["aging_cask_gap_native_columns"] = cask_gap
        coords = " · ".join(f"{m['name']} ({placements[sid]['souvenir_origins_native'][m['id']][0]},"
                            f"{placements[sid]['souvenir_origins_native'][m['id']][1]})" for m in MINIS)
        spot_summary.append({"id": sid, "title": spot["title"], "summary": spot["summary"].replace("{gap}", str(cask_gap)),
                             "coords": ("기념품 캔버스 원점(원본) " + coords
                                        + (f" · 못 원점 ({spot['peg_origin'][0]},{spot['peg_origin'][1]})" if spot["kind"] == "hang" else "")),
                             "occupancy": f"layouts/occupancy-{sid}.png", "examples": examples})

    # ---- free-space analysis (native): where else a mini could go with the cask drawn and the counter prop equipped
    obstacles = np.zeros((H, W), bool)
    for name in FORBIDDEN:
        obstacles |= masks[name]
    for name in FURNITURE:
        obstacles |= masks["furniture_" + name]
    for p in props3.values():
        obstacles |= placed(alpha_of(p), APPROVED_PROP_ORIGIN)
    free = {}
    for item in MINIS:
        o = free_origins(alpha_of(natives[item["id"]]), obstacles)
        xs = [p[0] for p in o]
        free[item["id"]] = {"count": len(o),
                            "x_range": [min(xs), max(xs)] if o else None,
                            "y_range": [min(p[1] for p in o), max(p[1] for p in o)] if o else None,
                            "right_of_x_75": len([p for p in o if p[0] >= 75])}
    space = {"note": "native canvas origins where the whole mini clears keeper, customers, sale/stock bottles, HUD, all furniture "
                     "including the drawn aging cask, and both approved counter props at 96,40",
             "zero_overlap_origins": free}

    passed = bool(sprites_passed and combos_passed and same_as_f23 and all(o["identical"] for o in originals.values()))
    report = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False,
        "date": DATE, "scale": SCALE, "palette": "art/palette.hex", "ramps": "art/ramps.json", "new_palette_colors": 0,
        "pipeline_report": rel(PIPE / "validation.json"), "pipeline_status": pipe_report["status"],
        "rules": {"native_max": [MAX_NATIVE, MAX_NATIVE], "display_max_px": 36, "max_colors_including_outline": 5,
                  "off_palette": 0, "partial_alpha": 0,
                  "outline": "every opaque pixel 4-adjacent to transparency (or the canvas edge) is #241C32",
                  "max_shades_per_ramp": 3, "dithering": "no 3x3 two-color checkerboards",
                  "lighting": "non-outline pixels on the top-left side brighter than the bottom-right side",
                  "ground": "bottom canvas row is the opaque contact row, all outline (sitting in spot A)",
                  "redraw": "same color set as the 32x32 original; not identical to a nearest/box downscale of it",
                  "overlap_unit": "display pixels (native x3) of souvenir (+peg) opacity intersecting each element's union of all reachable pixels",
                  "occupancy_source": "tools/build_f23_decor_v1.py build_masks() imported and called unchanged",
                  "must_be_zero": FORBIDDEN + ["all furniture incl. aging cask (counted even when closed)",
                                               "approved counter props at 96,40", "souvenir vs peg"],
                  "draw_order": "counter prop -> (aging cask) -> (peg) -> souvenir -> stock bottles"},
        "workshop_constants_verified_against_scripts": constants,
        "occupancy_masks_identical_to_f23_validation": same_as_f23, "element_pixels": pixels,
        "approved_counter_prop_slot": {"origin_native": list(APPROVED_PROP_ORIGIN), "props": PROP_IDS,
                                       "source": rel(F23 / "approval.json")},
        "originals_read_only": originals,
        "sprites": checks, "spots": placements, "space_analysis": space,
        "mini_mode": "not rendered; recommendation follows the approved F23 counter-prop rule (hidden in mini mode, equip state kept)",
        "passed": passed,
    }
    if not passed:
        report["final_outputs_from_this_run"] = False
    (MOCK / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    generation = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False, "date": DATE,
        "mode": "hand-authored small native pixel maps (no image generator, no resampling of the 32x32 icons); the .txt maps are the authoritative source",
        "request": "사용자: \"기념품은 작업실용 작은 그림을 따로 만들어줘\" (F23 꾸미기 승인 답변, 2026-10-23)",
        "reference": {"design": "art/mockups/f22-regulars-souvenirs-v1 (approved 32x32 souvenirs; silhouettes and colors kept)",
                      "occupancy": "tools/build_f23_decor_v1.py build_masks()", "rules": "AGENTS.md 색 문법 · 픽셀 규격"},
        "sizing": "native grid max 12x12 (36 display px at the workshop x3), roughly the size of a shelf bottle (8x12 / 8x16)",
        "legend": {c: {"color": h, "ramp": r} for c, (h, r) in LEGEND.items()},
        "souvenirs": {m["id"]: {"base": m["base"], "customer": m["customer"], "name": m["name"], "description": m["description"],
                                "hang_point_native": list(m["hang"]),
                                "materials": {mat: LEGEND[c][0] for c, mat in m["materials"].items()}} for m in MINIS},
        "peg": {"id": PEG["id"], "name": PEG["name"], "description": PEG["description"], "used_by": "spot B only",
                "materials": {mat: LEGEND[c][0] for c, mat in PEG["materials"].items()}},
        "new_palette_colors": 0, "postprocess_tool": "tools/process_pixel_art.py with manifest.json",
    }
    (MOCK / "generation.json").write_text(json.dumps(generation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    approval = {"schema_version": 1, "status": "candidate", "approved_by_user": False, "approved_on": None, "user_reply": None,
                "review": rel(MOCK / "review.html"), "runtime_integrated": False,
                "scope": {**{m["id"]: f"작업실용 작은 기념품 · {m['name']} ({checks[m['id']]['native_size'][0]}×{checks[m['id']]['native_size'][1]})" for m in MINIS},
                          "spot_A": SPOTS["A"]["title"], "spot_B": SPOTS["B"]["title"] + " (3×3 벽 못 그림 포함)",
                          "originals": "관리 창 32×32 기념품(assets/pixel_v1/souvenirs)은 그대로 유지"},
                "pending_decisions": ["작은 기념품 4종 디자인 승인 또는 수정 지시", "기념품 자리 A/B 선택"],
                "note": "사용자 승인 전 후보. assets/ 게시, 장착 로직·관리 UI 연결은 승인 후 별도 작업으로 진행한다."}
    (MOCK / "approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    sizes = {m["id"]: checks[m["id"]]["native_size"] for m in MINIS}
    dims = []
    for m in MINIS:
        b = Image.open(F22 / "sprites" / f"{m['base']}.png").convert("RGBA").getbbox()
        dims += [(b[2] - b[0]) * SCALE, (b[3] - b[1]) * SCALE]
    summary = {
        "passed": passed,
        "minis": [{"id": m["id"], "name": m["name"], "customer": m["customer_name"], "description": m["description"],
                   "size": sizes[m["id"]], "native": f"sprites/{m['id']}.png", "x3": f"sprites/{m['id']}-3x.png",
                   "orig": f"../../../assets/pixel_v1/souvenirs/{m['base']}.png", "orig3": f"../f22-regulars-souvenirs-v1/sprites/{m['base']}-3x.png",
                   "materials": [{"name": mat, "color": LEGEND[c][0]} for c, mat in m["materials"].items()],
                   "color_count": checks[m["id"]]["color_count"], "off_palette": checks[m["id"]]["off_palette_colors"],
                   "partial_alpha": checks[m["id"]]["partial_alpha_pixels"], "outline_violations": len(checks[m["id"]]["outline_violations"]),
                   "dither": len(checks[m["id"]]["dither_3x3_blocks"]), "lit": checks[m["id"]]["lighting"]["top_left_lit"],
                   "ground_row": checks[m["id"]]["ground"]["ground_row"], "ground_ok": checks[m["id"]]["ground"]["passed"],
                   "opaque_size": checks[m["id"]]["opaque_size"], "same_colors": checks[m["id"]]["original"]["same_color_set_as_original"],
                   "agreement": max(checks[m["id"]]["original"]["pixel_agreement_with_downscaled_original"].values())}
                  for m in MINIS],
        "size_note": (f"원본 32×32 기념품은 작업실 3배에서 불투명 부분의 폭·높이가 표시 {min(dims)}~{max(dims)}px로 솥(96px)에 가깝습니다. 작은 그림은 원본 격자 "
                      + ", ".join(f"{m['name']} {sizes[m['id']][0]}×{sizes[m['id']][1]}" for m in MINIS)
                      + "로, 3배에서 최대 36px(선반 물약병 8×12·8×16 → 24×36·24×48px과 비슷한 물건 크기)입니다. 원본의 실루엣·5색을 그대로 쓰되 "
                        "12칸에서 읽히지 않는 눈금·곁맥·작은 별은 줄이거나 뺐습니다."),
        "legend": [["주인공", "#C38EB5"], ["손님", "#F4AC68"], ["판매 병", "#DE7356"], ["입고 병", "#3BA8A3"], ["HUD", "#E9B95F"],
                   ["가구(숙성통 제외)", "#827589"], ["숙성통", "#A56A3D"], ["판매대 소품 2종(A안)", "#B5C77D"], ["기념품 4종(+못)", "#FFF0BC"]],
        "spots": spot_summary, "rows": rows,
        "space_note": ("<b>숙성통 자리</b>(F23 후보의 기념품 벽 자리)는 숙성통과 같이 보일 수 없어 제외했습니다. "
                       "<b>벽 선반 끝</b>: 물약 선반 왼쪽 위는 아래 칸 병이 위 칸으로 옮겨 갈 때 선반 왼쪽(원본 x97~104)으로 돌아 올라가 위를 지나가는 입고 병 길이고, "
                       "선반 오른쪽 기둥(원본 x152)과 원정 포스터(x155) 사이는 2칸뿐입니다. <b>포스터 옆 못</b>: 포스터(원본 x155~174, y2~31) 오른쪽은 화면 끝까지 5칸, 아래는 손님 머리(y35)까지 3행이라 12칸 그림이 들어가지 않습니다. "
                       "<b>창틀 아래·화분대·판매대 오른쪽</b>은 화분 패널·수확 알림 HUD·판매 병 길과 겹치거나 높이가 7행 이하입니다. "
                       "숙성통이 그려지고 판매대 소품이 장착된 상태에서 그림 전체가 아무것과도 겹치지 않는 원점(원본)을 모두 찾으면 "
                       + ", ".join(f"{m['name']} {free[m['id']]['count']}곳(x{free[m['id']]['x_range'][0]}~{free[m['id']]['x_range'][1]}, "
                                   f"y{free[m['id']]['y_range'][0]}~{free[m['id']]['y_range'][1]}, 숙성통 오른쪽 x≥75 {free[m['id']]['right_of_x_75']}곳)"
                                   for m in MINIS)
                       + "입니다. 이 영역은 사실상 창문 위·창문과 숙성통 사이 벽(솥 패널 HUD 위)과 화분·솥 사이 바닥뿐이라, 받침이 있는 창틀 위(A)와 못을 박는 벽(B)을 골랐습니다."),
        "coords_note": ("자리 좌표(원본, 표시 = ×3): A 캔버스 원점 (14,0) = 표시 (42,0), 네 그림 모두 같은 12×12 캔버스. "
                        "B 못 원점 (53,1) = 표시 (159,3), 기념품 원점 " + " · ".join(
                            f"{m['name']} ({placements['B']['souvenir_origins_native'][m['id']][0]},{placements['B']['souvenir_origins_native'][m['id']][1]})"
                            for m in MINIS) + "."),
    }
    (MOCK / "review.html").write_text(REVIEW.replace("/*SUMMARY*/null", json.dumps(summary, ensure_ascii=False)), encoding="utf-8")

    print(json.dumps({"passed": passed, "occupancy_identical_to_f23": same_as_f23,
                      "sprites": {k: {"passed": c["passed"], "size": c["native_size"], "colors": c["color_count"],
                                      "off_palette": c["off_palette_colors"], "partial_alpha": c["partial_alpha_pixels"],
                                      "outline_violations": len(c["outline_violations"]), "dither": len(c["dither_3x3_blocks"]),
                                      "lighting": c.get("lighting"), "ground": c.get("ground", {}).get("passed"),
                                      "agreement": c.get("original", {}).get("pixel_agreement_with_downscaled_original")}
                                  for k, c in checks.items()},
                      "spots": {sid: {"combos_passed": all(c["passed"] for c in p["combos"].values()),
                                      "max_overlap": max(c["overlap_total"] + c["cask_overlap_if_drawn"] for c in p["combos"].values()),
                                      "origins": p["souvenir_origins_native"],
                                      "examples": {e: v["passed"] for e, v in p["examples"].items()}} for sid, p in placements.items()},
                      "free": free}, ensure_ascii=False, indent=1))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
