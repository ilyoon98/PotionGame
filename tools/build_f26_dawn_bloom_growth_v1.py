"""F26 여명초(dawn_bloom) 화분 성장 그림 후보 v1 (승인 전).

Candidate only. Nothing under assets/, scripts/ or data/ is written; player saves, the running game and
Windows registration are untouched. Output: art/mockups/f26-dawn-bloom-growth-v1/.

Existing format (measured below and recorded in validation.json): every cultivated material's growth sheet is a
64x80 RGBA PNG holding a 2x2 grid of 32x40 frames (ItemArt.growth_frame / herb_plant.gd: region
((i % 2) * 32, (i / 2) * 40, 32, 40)). Frames 0/1/2 are growth stages chosen by mini(2, int(progress * 3));
frame 3 is the harvest flash (herb_plant.gd, basic herb only). The nine later sheets share one plum pot with a
gold rim, dark soil and a per-material emblem on rows ~24..38; every frame's lowest opaque row is y=38.
These sheets are pre-24-colour generated art (1,300-2,000 RGB colours, ~2,000 partial-alpha pixels each).

The new sheet is hand-authored as four 32x40 letter maps (source/dawn_bloom_growth_{0..3}.txt). One set of maps
is rendered with two legends:
  A  rule-strict: approved 24 colours, <=5 colours (outline, plum pot, sage leaf, tangerine petal, cream heart).
     The coral petal shade, gold rim, soil and pot shade collapse into those 5.
  B  match-first: same maps, 10 approved colours (plum 2, gold 2, soil, leaf 2, petal 2, outline) so the pot
     reads like the nine existing pots and the bloom keeps the icon's coral lower-right shade. Exceeds the
     per-object 5-colour limit (AGENTS 색 문법 7) and therefore needs explicit user approval.
Both go through the fixed tools/process_pixel_art.py pipeline (explicit per-colour material rules, no nearest
colour lookup) and extra checks: 1px outline on every silhouette edge, no partial alpha, no off-palette colour,
<=3 shades per ramp, no 3x3 dithering, frame-cell containment, shared baseline/pot, stage growth.

Run with Pillow + NumPy: python tools/build_f26_dawn_bloom_growth_v1.py
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
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "art/mockups/f26-dawn-bloom-growth-v1"
SRC = MOCK / "source"
REG = MOCK / "registered"
PIPE = MOCK / "pipeline"
SHEETS = MOCK / "sheets"
STAGES = MOCK / "stages"
COMPARE = MOCK / "compare"
SCALE = 3
DATE = "2026-11-05"
FRAME = (32, 40)
SHEET = (64, 80)
OUTLINE_HEX = "#241C32"
OUTLINE = (0x24, 0x1C, 0x32)
PALETTE = ["#" + line.strip().upper().lstrip("#") for line in (ROOT / "art/palette.hex").read_text(encoding="utf-8").splitlines() if line.strip()]
RAMPS = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
ICON = ROOT / "assets/content_expansion_v1/materials/dawn_bloom_icon.png"
GROWTH_PATH = "res://assets/content_expansion_v1/materials/dawn_bloom_growth.png"
EXISTING = ["herb", "starleaf", "dewgrass", "silver_moss", "blue_reed", "crystal_herb", "mist_mushroom", "ash_sage", "moonflower", "star_seed"]
COMPARE_WITH = [("moonflower", "달꽃"), ("dewgrass", "이슬풀"), ("star_seed", "별씨"), ("mist_mushroom", "안개 버섯")]
POT_ROWS = (24, 39)  # rows 24..38 hold the pot in every frame (existing sheets and this one)
STAGE_NAMES = ["0 새싹 (진행 0~33%)", "1 꽃봉오리 (33~66%)", "2 만개 (66~100%)", "3 수확 반짝임 (화분 수확 연출 칸)"]

# letter -> (colour, ramp, material). One map, two legends.
LEGENDS = {
    "a": {
        "#": (OUTLINE_HEX, "outline", "outline"), "u": (OUTLINE_HEX, "outline", "outline"), "s": (OUTLINE_HEX, "outline", "outline"),
        "P": ("#86548E", "purple", "pot"), "q": ("#86548E", "purple", "pot"), "g": ("#86548E", "purple", "pot"),
        "h": ("#FFF0BC", "gold", "cream"), "y": ("#FFF0BC", "gold", "cream"),
        "O": ("#F4AC68", "fire", "petal"), "C": ("#F4AC68", "fire", "petal"),
        "l": ("#718C59", "leaf", "leaf"), "d": ("#718C59", "leaf", "leaf"),
    },
    "b": {
        "#": (OUTLINE_HEX, "outline", "outline"), "u": (OUTLINE_HEX, "outline", "outline"),
        "P": ("#50315F", "purple", "pot_body"), "q": ("#86548E", "purple", "pot_light"),
        "g": ("#E9B95F", "gold", "rim_and_sparkle"), "y": ("#E9B95F", "gold", "rim_and_sparkle"),
        "h": ("#FFF0BC", "gold", "cream_heart_glint"), "s": ("#50333B", "wood", "soil"),
        "l": ("#718C59", "leaf", "leaf"), "d": ("#3D544D", "leaf", "leaf_shade"),
        "O": ("#F4AC68", "fire", "petal_light"), "C": ("#DE7356", "fire", "petal_shade"),
    },
}
VARIANTS = {
    "a": {"name": "A안 · 규칙 엄수 (5색)", "max_colors": 5,
          "note": "승인 24색·물체당 5색·반투명 0·1픽셀 외곽선을 모두 지킨다. 화분은 승인된 작업실 약초 화분(assets/pixel_v1/props/herb.png)과 같은 "
                  "자두 보라 #86548E 한 색(금테·흙·밝은 면 없음, 흙은 외곽선색)이라 기존 9종의 어두운 화분보다 밝다. "
                  "꽃은 귤빛 한 색 + 크림 꽃심이라 아이콘의 산호색 오른쪽 아래 그늘이 빠진다."},
    "b": {"name": "B안 · 기존 성장 그림과 어울림 우선 (10색)", "max_colors": 10,
          "note": "승인 24색·반투명 0·1픽셀 외곽선·램프당 3단계 이하는 지킨다. 기존 9종 화분처럼 어두운 가지 보라 몸통(#50315F)+왼쪽 밝은 면(#86548E)·"
                  "금테·흙·테 아래 어두운 줄을 넣고 "
                  "꽃은 아이콘과 같은 귤빛/산호 그늘/크림 꽃심. 물체당 5색 상한을 넘으므로(10색) 사용자 승인이 필요한 예외다."},
}


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def hexs(color) -> str:
    return "#%02X%02X%02X" % tuple(int(c) for c in color[:3])


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def scaled(image: Image.Image, factor: int = SCALE) -> Image.Image:
    return image.resize((image.width * factor, image.height * factor), Image.Resampling.NEAREST)


def read_map(path: Path) -> list[str]:
    rows = [line.rstrip("\r\n") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if [len(rows[0]) if rows else 0, len(rows)] != list(FRAME) or any(len(r) != FRAME[0] for r in rows):
        raise SystemExit(f"{rel(path)} must be {FRAME[0]}x{FRAME[1]}")
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


def frames_of(sheet: Image.Image) -> list[Image.Image]:
    return [sheet.crop(((i % 2) * 32, (i // 2) * 40, (i % 2) * 32 + 32, (i // 2) * 40 + 40)) for i in range(4)]


def assemble(frames: list[Image.Image]) -> Image.Image:
    sheet = Image.new("RGBA", SHEET)
    for i, frame in enumerate(frames):
        sheet.paste(frame, ((i % 2) * 32, (i // 2) * 40))
    return sheet


# ---------------------------------------------------------------- pipeline
def exact_rules(colors: dict[str, str]) -> list[dict]:
    rules = []
    for material, value in colors.items():
        h, s, v = colorsys.rgb_to_hsv(*(np.array(rgb(value)) / 255.0))
        rules.append({"material": material, "hue": [round(h - .004, 4), round(h + .004, 4)],
                      "saturation_min": round(s - .01, 4), "saturation_max": round(s + .01, 4),
                      "value_min": round(v - .01, 4), "value_max": round(v + .01, 4)})
    return rules


def run_pipeline(variant: str) -> dict:
    legend = LEGENDS[variant]
    materials, ramps, by_material = {"outline": [OUTLINE_HEX]}, {}, {}
    for color, ramp, material in legend.values():
        if material == "outline":
            continue
        materials[material] = [color]
        ramps[material] = ramp
        by_material[material] = color
    out = PIPE / variant
    manifest = {"output": rel(out), "palette": "art/palette.hex", "ramps": "art/ramps.json", "status": "candidate",
                "approved_by_user": False, "scale": SCALE, "alpha_threshold": 128, "max_colors": VARIANTS[variant]["max_colors"],
                "compose": False, "scene": {"size": list(SHEET), "background": OUTLINE_HEX},
                "assets": [{"id": "dawn_bloom_growth", "source": rel(REG / variant / "dawn_bloom_growth.png"), "size": list(SHEET),
                            "position": [0, 0], "margin": 0, "dark_value": 0.24, "preserve_native_frame": True,
                            "preserve_source_outline": False, "materials": materials, "material_ramps": ramps,
                            "rules": exact_rules(by_material), "fallback_material": next(iter(ramps)),
                            "name_ko": "여명초 성장 그림 " + VARIANTS[variant]["name"]}]}
    path = MOCK / f"manifest-{variant}.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result = subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"), rel(path)], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8")
    report = json.loads((out / "validation.json").read_text(encoding="utf-8"))
    if result.returncode != 0 or report["status"] != "passed":
        raise SystemExit(f"process_pixel_art failed ({variant}): {report.get('error')}\n{result.stderr}")
    report["manifest"] = rel(path)
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


def frame_bbox(frame: np.ndarray, threshold: int = 128):
    ys, xs = np.where(frame[:, :, 3] >= threshold)
    return [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None


def existing_format() -> dict:
    rows = {}
    for name in EXISTING:
        path = ROOT / f"assets/content_expansion_v1/materials/{name}_growth.png"
        image = Image.open(path).convert("RGBA")
        data = np.array(image)
        alpha = data[:, :, 3]
        frames = [np.array(f) for f in frames_of(image)]
        pot = [frame_bbox(f[POT_ROWS[0]:POT_ROWS[1]]) for f in frames]
        rows[name] = {"path": rel(path), "size": list(image.size), "mode": Image.open(path).mode,
                      "rgb_colors": len({tuple(p[:3]) for p in data[alpha > 0]}),
                      "partial_alpha_pixels": int(((alpha > 0) & (alpha < 255)).sum()),
                      "opaque_255_pixels": int((alpha == 255).sum()),
                      "frame_bbox_alpha128": [frame_bbox(f) for f in frames],
                      "frame_bottom_row": [frame_bbox(f)[3] for f in frames],
                      "pot_rows_24_38_bbox_x": [[b[0], b[2]] if b else None for b in pot],
                      "frame3_minus_frame2_pixels": int(np.any(frames[3] != frames[2], axis=2).sum())}
    bottoms = sorted({b for r in rows.values() for b in r["frame_bottom_row"]})
    return {"sheets": rows, "common": {
        "size": [64, 80], "grid": "2x2 칸, 칸마다 32×40", "frame_order": "0 왼쪽 위·1 오른쪽 위·2 왼쪽 아래·3 오른쪽 아래",
        "stage_rule": "ItemArt.growth_frame: mini(2, int(progress*3)) → 0/1/2, herb_plant.gd 수확 연출 0.7초 동안 3",
        "frame_bottom_rows": bottoms,
        "pre_24_colour_rule": all(r["rgb_colors"] > 24 or r["partial_alpha_pixels"] > 0 for r in rows.values()),
        "note": "기존 10종은 승인 24색 규칙 이전의 생성 그림이다(1,300~2,000색, 칸 경계 안팎의 반투명 픽셀 약 1,600~2,600개). "
                "herb 한 종만 다리 달린 솥형 화분이고 나머지 9종은 같은 자두 보라 화분(금테·흙·재료별 문양)을 공유한다."}}


def check(variant: str, sheet: Image.Image, registered: Image.Image, pipe: dict) -> dict:
    legend = LEGENDS[variant]
    data = np.array(sheet.convert("RGBA"))
    alpha = data[:, :, 3]
    opaque = alpha == 255
    colors = sorted({hexs(p) for p in data[opaque]})
    by_ramp: dict[str, set] = {}
    for color, ramp, _m in legend.values():
        by_ramp.setdefault(ramp, set()).add(color)
    frames = [np.array(f) for f in frames_of(sheet)]
    cells = []
    for i, f in enumerate(frames):
        edge = np.concatenate([f[0, :, 3], f[-1, :, 3], f[:, 0, 3], f[:, -1, 3]])
        plant = f[:POT_ROWS[0]]
        cells.append({"frame": i, "stage": STAGE_NAMES[i], "bbox": frame_bbox(f), "bottom_row": frame_bbox(f)[3],
                      "touches_cell_edge": bool((edge > 0).any()), "opaque_pixels": int((f[:, :, 3] == 255).sum()),
                      "plant_pixels_above_pot": int((plant[:, :, 3] == 255).sum()),
                      "outline_violations": outline_violations(f),
                      "colors": sorted({hexs(p) for p in f[f[:, :, 3] == 255]})})
    pot_same = all(np.array_equal(frames[0][POT_ROWS[0]:POT_ROWS[1]], f[POT_ROWS[0]:POT_ROWS[1]]) for f in frames[1:])
    diff = np.any(frames[3] != frames[2], axis=2)
    flower_box = cells[2]["bbox"]
    ys, xs = np.where(diff)
    # Frame 3 = frame 2 plus sparkles: every changed pixel was transparent in frame 2 (pure additions).
    sparkle_outside_plant = bool(len(xs)) and all(frames[2][y, x, 3] == 0 for x, y in zip(xs, ys))
    icon = np.array(Image.open(ICON).convert("RGBA"))
    icon_colors = sorted({hexs(p) for p in icon[icon[:, :, 3] == 255]})
    flower = frames[2][3:18, 8:24]
    flower_colors = sorted({hexs(p) for p in flower[flower[:, :, 3] == 255]} - {OUTLINE_HEX})
    petal_icon = {c: int(np.all(icon[:, :, :3] == rgb(c), axis=2).sum()) for c in ("#F4AC68", "#DE7356", "#FFF0BC")}
    petal_new = {c: int(np.all(flower[:, :, :3] == rgb(c), axis=2).sum()) for c in ("#F4AC68", "#DE7356", "#FFF0BC")}
    result = {
        "variant": VARIANTS[variant]["name"], "native_size": list(sheet.size), "expected_size": list(SHEET),
        "grid": "2x2 × 32×40", "display_size_x3": [sheet.width * SCALE, sheet.height * SCALE],
        "colors": colors, "color_count": len(colors), "max_colors_rule": 5,
        "within_five_colour_limit": len(colors) <= 5,
        "off_palette_colors": sum(1 for c in colors if c not in PALETTE),
        "partial_alpha_pixels": int(((alpha != 0) & (alpha != 255)).sum()),
        "outline_violations": outline_violations(data), "dither_3x3_blocks": dither_blocks(data),
        "materials": {m: {"letters": "".join(k for k, v in legend.items() if v[2] == m), "color": c, "ramp": r}
                      for c, r, m in {v: None for v in legend.values()}},
        "colors_in_declared_ramps": all(col in RAMPS["ramps"][r]["colors"] for col, r, _m in legend.values()),
        "shades_per_ramp": {r: len(v) for r, v in by_ramp.items()},
        "frames": cells, "pot_rows_24_38_identical_in_all_frames": pot_same,
        "pot_rows_24_38_bbox_x": [[b[0], b[2]] for b in [frame_bbox(f[POT_ROWS[0]:POT_ROWS[1]]) for f in frames]],
        "all_frames_bottom_row_38": all(c["bottom_row"] == 38 for c in cells),
        "stage_growth_monotonic": cells[0]["plant_pixels_above_pot"] < cells[1]["plant_pixels_above_pot"] < cells[2]["plant_pixels_above_pot"],
        "frame3_minus_frame2_pixels": int(diff.sum()), "frame3_changes_only_sparkles_outside_plant": sparkle_outside_plant,
        "bloom_vs_icon": {"icon": rel(ICON), "icon_colors": icon_colors, "bloom_colors_without_outline": flower_colors,
                          "bloom_colors_subset_of_icon": set(flower_colors) <= set(icon_colors),
                          "icon_petal_pixels": petal_icon, "bloom_petal_pixels": petal_new,
                          "bloom_bbox_in_frame2": [8, 3, 23, 17], "stem": "세이지 잎색 1픽셀 줄기+양옆 외곽선. 아이콘의 외곽선색 줄기는 관리 화면 어두운 배경(#1D242B)에서 사라져 꽃이 떠 보여서 바꿨다."},
        "pipeline_passed": pipe["passed"],
        "pipeline_preserved_source": bool(np.array_equal(np.array(registered.convert("RGBA")), data)),
        "native_sha256": hashlib.sha256(data.tobytes()).hexdigest(),
    }
    ok = (result["native_size"] == result["expected_size"] and OUTLINE_HEX in colors and result["off_palette_colors"] == 0
          and result["partial_alpha_pixels"] == 0 and not result["outline_violations"] and not result["dither_3x3_blocks"]
          and result["colors_in_declared_ramps"] and all(n <= 3 for n in result["shades_per_ramp"].values())
          and not any(c["touches_cell_edge"] for c in cells) and pot_same and result["all_frames_bottom_row_38"]
          and result["stage_growth_monotonic"] and sparkle_outside_plant and result["bloom_vs_icon"]["bloom_colors_subset_of_icon"]
          and result["pipeline_passed"] and result["pipeline_preserved_source"] and set(colors) == {v[0] for v in legend.values()})
    result["technical_checks_passed"] = bool(ok)
    result["passed_without_exception"] = bool(ok and result["within_five_colour_limit"])
    result["status"] = ("passed" if result["passed_without_exception"] else
                        "passed_except_five_colour_limit (사용자 승인 필요)" if ok else "failed")
    return result


# ---------------------------------------------------------------- boards
def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    name = "Pretendard-SemiBold.otf" if bold else "Pretendard-Regular.otf"
    return ImageFont.truetype(str(ROOT / "assets/fonts/pretendard" / name), size)


def comparison_board(sheets: dict[str, Image.Image]) -> dict:
    """Existing four sheets and A/B side by side, 4 frames each, 3x, on the management background."""
    rows = [(name, label + " (기존)", Image.open(ROOT / f"assets/content_expansion_v1/materials/{name}_growth.png").convert("RGBA"))
            for name, label in COMPARE_WITH]
    rows += [("dawn_a", "여명초 A안 (새·5색)", sheets["a"]), ("dawn_b", "여명초 B안 (새·10색)", sheets["b"])]
    bg = (0x1D, 0x24, 0x2B)
    label_w, cell_w, cell_h, gap = 150, 32 * SCALE, 40 * SCALE, 8
    out = {}
    for mode in ("3x", "native"):
        f = 1 if mode == "native" else SCALE
        cw, ch = 32 * f, 40 * f
        lw = label_w if mode == "3x" else 112
        board = Image.new("RGBA", (lw + 4 * (cw + gap) + gap, len(rows) * (ch + gap) + gap + 24), bg + (255,))
        draw = ImageDraw.Draw(board)
        small = font(13 if mode == "3x" else 11)
        for i, title in enumerate(["0 새싹", "1 자라는 중", "2 다 자람", "3 수확"]):
            draw.text((lw + gap + i * (cw + gap), 4), title, font=small, fill="#ABB9BE")
        for r, (_key, label, sheet) in enumerate(rows):
            y = 24 + gap + r * (ch + gap)
            draw.text((8, y + ch // 2 - 8), label, font=small, fill="#F3EDE0")
            for i, frame in enumerate(frames_of(sheet)):
                board.alpha_composite(scaled(frame, f), (lw + gap + i * (cw + gap), y))
        path = COMPARE / f"growth-compare-{mode}.png"
        board.convert("RGB").save(path)
        out[mode] = rel(path)
    # Bloom next to the approved icon (3x): stage 2 frames A/B and icon.
    icon = Image.open(ICON).convert("RGBA")
    pair = Image.new("RGBA", (3 * (32 * SCALE + 16) + 16, 40 * SCALE + 40), bg + (255,))
    draw = ImageDraw.Draw(pair)
    for i, (img, text) in enumerate([(icon, "승인 아이콘 32×40"), (frames_of(sheets["a"])[2], "A안 만개"), (frames_of(sheets["b"])[2], "B안 만개")]):
        x = 16 + i * (32 * SCALE + 16)
        pair.alpha_composite(scaled(img), (x, 8))
        draw.text((x, 40 * SCALE + 14), text, font=font(13), fill="#F3EDE0")
    path = COMPARE / "bloom-vs-icon-3x.png"
    pair.convert("RGB").save(path)
    out["bloom_vs_icon"] = rel(path)
    return out


def readable(icon: Image.Image, box: int = 48) -> Image.Image:
    """ManagementArt.readable_icon (trim to used rect) + TextureRect KEEP_ASPECT_CENTERED in a 48x48 box, nearest."""
    trimmed = icon.crop(icon.getbbox())
    factor = min(box / trimmed.width, box / trimmed.height)
    size = (max(1, round(trimmed.width * factor)), max(1, round(trimmed.height * factor)))
    return trimmed.resize(size, Image.Resampling.NEAREST)


def management_rows(sheets: dict[str, Image.Image]) -> dict:
    """Approximate the HERBS tab row (management_panel.gd _row + growth_preview) at 1x, Python-drawn."""
    content = json.loads((ROOT / "data/content_expansion.json").read_text(encoding="utf-8"))
    by_id = {m["id"]: m for m in content["materials"]}
    bg, line, surface = (0x1D, 0x24, 0x2B), (0x40, 0x54, 0x5A), (0x26, 0x31, 0x39)
    ink, muted, accent = (0xF3, 0xED, 0xE0), (0xAB, 0xB9, 0xBE), (0xAA, 0xCB, 0xB0)
    entries = [("moonflower", "달꽃 (기존)", None), ("dewgrass", "이슬풀 (기존)", None),
               ("dawn_bloom", "여명초 · A안", sheets["a"]), ("dawn_bloom", "여명초 · B안", sheets["b"])]
    width, row_h = 458, 168
    title_f, body_f, aux_f = font(18, True), font(16), font(14)
    progress_values = [0.2, 0.5, 0.9]
    board = Image.new("RGBA", (width * len(progress_values) + 16 * (len(progress_values) + 1), len(entries) * row_h + 40), bg + (255,))
    draw = ImageDraw.Draw(board)
    for c, progress in enumerate(progress_values):
        frame_index = min(2, int(progress * 3))
        ox = 16 + c * (width + 16)
        draw.text((ox, 10), f"진행 {int(progress * 100)}% → 미리보기 칸 {frame_index}", font=aux_f, fill=muted)
        for r, (mid, title, sheet) in enumerate(entries):
            oy = 36 + r * row_h
            row = by_id[mid]
            icon = Image.open(ROOT / row["icon_candidate"].replace("res://", "")).convert("RGBA")
            ic = readable(icon)
            board.alpha_composite(ic, (ox + 8 + (48 - ic.width) // 2, oy + 8 + (48 - ic.height) // 2))
            bx = ox + 8 + 48 + 12
            draw.text((bx, oy + 13), title, font=title_f, fill=ink)
            draw.rounded_rectangle((ox + width - 8 - 52, oy + 8, ox + width - 8, oy + 40), 4, outline=accent)
            draw.text((ox + width - 8 - 42, oy + 14), "상세", font=body_f, fill=accent)
            seconds = float(row.get("growth_seconds", 1))
            env = {"clear": "맑음", "night_clear": "맑은 밤", "rain": "비", "night": "밤", "day": "낮", "cloudy": "흐림"}.get(row.get("environment", ""), row.get("environment", ""))
            draw.text((bx, oy + 46), f"재배 중 · {int(seconds)}초마다 1개 · {env} ×{row.get('favored_growth_multiplier', 1.5)}", font=body_f, fill=muted)
            for g, (cap, frac, count, colour) in enumerate([("작업", progress, f"{seconds * progress:.0f}초 / {int(seconds)}초", accent),
                                                         ("보유", 4 / float(row.get("capacity", 12)), f"4 / {row.get('capacity', 12)}", (0x90, 0xAD, 0x95))]):
                gy = oy + 74 + g * 22
                draw.text((bx, gy), cap, font=aux_f, fill=muted)
                x0, x1 = bx + 40, ox + width - 8 - 90
                draw.rounded_rectangle((x0, gy + 7, x1, gy + 14), 2, fill=surface)
                draw.rounded_rectangle((x0, gy + 7, x0 + max(4, int((x1 - x0) * frac)), gy + 14), 2, fill=colour)
                tw = draw.textlength(count, font=aux_f)
                draw.text((ox + width - 8 - tw, gy), count, font=aux_f, fill=muted)
            src = sheet if sheet is not None else Image.open(ROOT / f"assets/content_expansion_v1/materials/{mid}_growth.png").convert("RGBA")
            board.alpha_composite(frames_of(src)[frame_index], (bx, oy + 120))
            draw.line((ox, oy + row_h - 1, ox + width, oy + row_h - 1), fill=line)
    out = {}
    path = COMPARE / "management-herbs-rows-1x.png"
    board.convert("RGB").save(path)
    out["rows_1x"] = rel(path)
    path2 = COMPARE / "management-herbs-rows-2x.png"
    scaled(board.convert("RGB"), 2).save(path2)
    out["rows_2x"] = rel(path2)
    out["layout"] = ("관리 · 약초 탭 _row 근사: 패널 폭 458(CONTENT_WIDTH 480−22), 여백 8, 왼쪽 48×48 아이콘(readable_icon으로 여백을 자른 뒤 "
                     "KEEP_ASPECT 최근접 확대), 제목 18 SemiBold·상세 버튼 52×32, 상태 줄 16, 작업/보유 막대(높이 7), 그 아래 성장 미리보기 "
                     "TextureRect 32×40(원본 1배, 상세를 펼쳤을 때). 글자·막대 위치는 Python 근사이며 Godot 실제 캡처가 아니다.")
    return out


# ---------------------------------------------------------------- review page
def page(existing: dict, checks: dict, boards: dict, rows: dict) -> str:
    def img(path: str, cls: str = "") -> str:
        return f'<img src="{Path(path).relative_to(rel(MOCK)).as_posix()}" class="{cls}" alt="">'

    def sw(color: str) -> str:
        return f'<span><i style="--c:{color}"></i>{color}</span>'

    cards = []
    for v in ("a", "b"):
        c = checks[v]
        stages = "".join(f'<figure><div class="check">{img(rel(STAGES / v / f"frame_{i}-3x.png"))}</div><figcaption>{STAGE_NAMES[i]}</figcaption></figure>' for i in range(4))
        badge = "ok" if c["passed_without_exception"] else "warn" if c["technical_checks_passed"] else "bad"
        cards.append(f"""<div class="card"><h3>{VARIANTS[v]['name']}</h3>
<div class="sizes"><figure><div class="check">{img(rel(SHEETS / f'dawn_bloom_growth_{v}-3x.png'))}</div><figcaption>시트 64×80 ×3</figcaption></figure>
<figure><div class="check">{img(rel(SHEETS / f'dawn_bloom_growth_{v}.png'))}</div><figcaption>원본 1배</figcaption></figure></div>
<div class="sizes">{stages}</div>
<p class="desc">{VARIANTS[v]['note']}</p>
<div class="sw">{''.join(sw(x) for x in c['colors'])}</div>
<p class="desc">{c['color_count']}색 · 팔레트 밖 {c['off_palette_colors']} · 반투명 {c['partial_alpha_pixels']} · 외곽선 위반 {len(c['outline_violations'])} ·
디더링 {len(c['dither_3x3_blocks'])} · 램프별 단계 {', '.join(f'{k} {n}' for k, n in c['shades_per_ramp'].items())} ·
모든 칸 바닥 행 38 {'예' if c['all_frames_bottom_row_38'] else '아니오'} · 화분 4칸 동일 {'예' if c['pot_rows_24_38_identical_in_all_frames'] else '아니오'} ·
판정 <b class="{badge}">{c['status']}</b></p></div>""")
    ex_rows = "".join(f"<tr><td>{n}</td><td>{r['size'][0]}×{r['size'][1]}</td><td>{r['rgb_colors']}</td><td>{r['partial_alpha_pixels']}</td>"
                      f"<td>{', '.join(str(b) for b in r['frame_bottom_row'])}</td><td>{' / '.join(f'{p[0]}~{p[1]}' for p in r['pot_rows_24_38_bbox_x'])}</td></tr>"
                      for n, r in existing["sheets"].items())
    new_rows = "".join(f"<tr><td>여명초 {v.upper()}안</td><td>64×80</td><td>{checks[v]['color_count']}</td><td>{checks[v]['partial_alpha_pixels']}</td>"
                       f"<td>{', '.join(str(f['bottom_row']) for f in checks[v]['frames'])}</td><td>{' / '.join(f'{p[0]}~{p[1]}' for p in checks[v]['pot_rows_24_38_bbox_x'])}</td></tr>"
                       for v in ("a", "b"))
    return f"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>여명초 성장 그림 후보</title><style>
@font-face{{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}}
:root{{--bg:#241c32;--panel:#30263f;--line:#827589;--text:#fff0bc;--muted:#c38eb5;--accent:#e9b95f;--ok:#b5c77d;--bad:#de7356}}
*{{box-sizing:border-box}}html,body{{background:var(--bg)}}body{{margin:0;color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}}
main{{max-width:1210px;margin:auto;padding:18px 16px 48px}}h1{{font-size:23px;margin:0 0 6px}}h2{{font-size:17px;margin:28px 0 8px}}h3{{font-size:15px;margin:0}}
p{{margin:6px 0 10px}}.muted{{color:var(--muted)}}.ok{{color:var(--ok)}}.bad{{color:var(--bad)}}.warn{{color:var(--accent)}}
.note{{border-left:3px solid #718c59;padding:8px 12px;background:var(--panel);margin:10px 0}}.note.warn{{border-left-color:var(--accent);color:var(--text)}}
.check{{background-color:#4a3c52;background-image:linear-gradient(45deg,#3f3347 25%,transparent 25%),linear-gradient(-45deg,#3f3347 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#3f3347 75%),linear-gradient(-45deg,transparent 75%,#3f3347 75%);background-size:12px 12px;background-position:0 0,0 6px,6px -6px,-6px 0}}
img{{image-rendering:pixelated;image-rendering:crisp-edges;max-width:none;display:block}}
.cards{{display:grid;grid-template-columns:repeat(auto-fill,minmax(540px,1fr));gap:12px}}@media(max-width:600px){{.cards{{grid-template-columns:1fr}}}}
.card{{background:var(--panel);border:1px solid #4a3c52;border-radius:6px;padding:12px;overflow-x:auto}}
.sizes{{display:flex;align-items:flex-end;gap:10px;margin:10px 0 6px;flex-wrap:wrap}}.sizes figure{{margin:0;text-align:center}}.sizes .check{{display:flex;align-items:center;justify-content:center;padding:4px}}
figcaption{{font-size:11px;color:var(--muted);margin-top:3px}}.desc{{font-size:13px;margin:6px 0}}
.sw{{display:flex;flex-wrap:wrap;gap:8px;font-size:11px;color:var(--muted)}}.sw span{{display:flex;align-items:center;gap:3px}}.sw i{{width:12px;height:12px;display:inline-block;border:1px solid #000;background:var(--c)}}
.wide{{overflow-x:auto;background:var(--panel);padding:8px;border-radius:6px}}
table{{border-collapse:collapse;font-size:13px;width:100%}}td,th{{border-bottom:1px solid #4a3c52;padding:5px 6px;text-align:left;vertical-align:top}}
</style></head><body><main>
<h1>여명초(dawn_bloom) 화분 성장 그림 후보 v1</h1>
<p class="muted">{DATE} · 상태 <b>후보(candidate)</b> · 게임 미연결 · 승인 전. 승인되면 <code>assets/content_expansion_v1/catalog.json</code>의 여명초 행에
<code>growth_path: {GROWTH_PATH}</code>만 더한다.</p>
<div class="note">기존 재배 재료 10종과 같은 형식: <b>64×80 시트 = 32×40 칸 2×2</b> (0 왼쪽 위 새싹 · 1 오른쪽 위 자라는 중 · 2 왼쪽 아래 다 자람 · 3 오른쪽 아래 수확 반짝임).
관리 · 약초 탭은 진행도로 칸 0/1/2를 원본 1배(32×40)로 보여 주고, 칸 3은 작업실 화분(기본 약초 전용)의 수확 연출에서만 쓰인다. 모든 칸의 가장 아래 불투명 행은 기존과 같이 y=38,
화분은 기존 9종과 같은 자리(행 24~38, 테 x7~24)에 두었다. 원본은 손으로 쓴 문자 지도 <code>source/*.txt</code> → <code>tools/process_pixel_art.py</code>. 체크무늬는 CSS 배경이다.</div>
<div class="note warn">기존 성장 그림 10종은 <b>승인 24색 규칙 이전의 생성 그림</b>이다(시트당 1,300~2,000색, 반투명 픽셀 약 1,600~2,600개). 그대로 흉내 내면 규칙 위반이고, 규칙대로 5색에 넣으면
기존 화분의 금테·흙·그늘이 빠진다. 그래서 같은 지도를 두 범례로 칠한 <b>A안(5색 규칙 엄수)</b>과 <b>B안(10색, 기존과 어울림 우선 · 5색 상한 예외 승인 필요)</b>을 함께 보여 준다.
두 안 모두 승인 24색만 쓰고 반투명 0, 1픽셀 외곽선, 램프당 3단계 이하다.</div>

<h2>1. 후보 A / B · 단계별 3배</h2>
<div class="cards">{''.join(cards)}</div>

<h2>2. 기존 성장 그림과 나란히 (관리 화면 배경 #1D242B, 3배)</h2>
<div class="wide">{img(boards['3x'])}</div>
<p class="desc muted">원본 1배 비교: <code>{Path(boards['native']).name}</code></p>
<div class="wide" style="margin-top:8px">{img(boards['native'])}</div>

<h2>3. 다 자란 꽃 대 승인된 여명초 아이콘</h2>
<div class="wide">{img(boards['bloom_vs_icon'])}</div>
<p class="desc">아이콘의 여섯 꽃잎 실루엣(위·좌우 위·좌우 아래·아래 꽃잎과 양옆 홈), 크림색 육각 꽃심을 16×15로 줄였다. 아이콘의 줄기는 외곽선색(#241C32) 2픽셀이지만 관리 화면 배경(#1D242B)에서는 보이지 않아 꽃이 떠 보였으므로,
성장 그림에서는 세이지 잎색(#718C59) 1픽셀 줄기에 양옆 외곽선을 둘렀다(기존 성장 그림도 초록 줄기). B안은 아이콘처럼 오른쪽 아래가 산호색(#DE7356) 그늘,
A안은 5색 제한 때문에 귤빛 한 색이다. 화분 앞 문양은 해돋이(귤빛 반원과 빛살)로, 다른 화분이 재료 색 문양(달·물방울·별)을 쓰는 방식과 같다.</p>

<h2>4. 관리 · 약초 탭 행에 넣었을 때 (원본 1배 · 근사)</h2>
<p class="desc">{rows['layout']}</p>
<div class="wide">{img(rows['rows_1x'])}</div>
<p class="desc muted">2배 확대본: <code>{Path(rows['rows_2x']).name}</code></p>

<h2>5. 형식 비교 수치</h2>
<div class="wide"><table><tr><th>시트</th><th>크기</th><th>RGB 색 수</th><th>반투명 픽셀</th><th>칸별 바닥 행</th><th>화분(행 24~38) x 범위, 칸 0/1/2/3</th></tr>{ex_rows}{new_rows}</table></div>

<h2>6. 결정 필요</h2>
<ul>
<li>A안(5색 규칙 엄수)과 B안(10색, 기존 9종 화분과 같은 금테·흙·그늘 · 물체당 5색 상한 예외) 중 하나. B안을 고르면 예외 사유와 승인을 <code>art/palette-log.md</code>에 기록한다.</li>
<li>꽃봉오리 단계(칸 1)의 잎을 다 자란 단계와 같게 둔 것, 수확 반짝임 3개의 위치.</li>
<li>연결 시 <code>tools/verify_f26_region_potions.gd</code>의 "No growth sheet stand-in for dawn bloom" 검사와 <code>tools/verify_workshop_followup.gd</code>의 여명초 예외를 함께 고쳐야 한다.</li>
</ul>
<p class="muted">검사 결과: <code>validation.json</code> · 후처리 보고: <code>pipeline/a/validation.json</code>, <code>pipeline/b/validation.json</code> · 승인 상태: <code>approval.json</code></p>
</main></body></html>
"""


def main() -> int:
    for folder in (REG, SHEETS, STAGES, COMPARE, PIPE):
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
    maps = [read_map(SRC / f"dawn_bloom_growth_{i}.txt") for i in range(4)]
    existing = existing_format()
    registered, pipes, checks, sheets = {}, {}, {}, {}
    for v in ("a", "b"):
        (REG / v).mkdir(parents=True)
        sheet = assemble([render(rows, LEGENDS[v]) for rows in maps])
        sheet.save(REG / v / "dawn_bloom_growth.png")
        registered[v] = sheet
        pipes[v] = run_pipeline(v)
        result = Image.open(PIPE / v / "dawn_bloom_growth-native.png").convert("RGBA")
        sheets[v] = result
        result.save(SHEETS / f"dawn_bloom_growth_{v}.png")
        scaled(result).save(SHEETS / f"dawn_bloom_growth_{v}-3x.png")
        (STAGES / v).mkdir(parents=True)
        for i, frame in enumerate(frames_of(result)):
            frame.save(STAGES / v / f"frame_{i}.png")
            scaled(frame).save(STAGES / v / f"frame_{i}-3x.png")
        checks[v] = check(v, result, registered[v], pipes[v]["assets"]["dawn_bloom_growth"])
        checks[v]["source"] = [rel(SRC / f"dawn_bloom_growth_{i}.txt") for i in range(4)]
        checks[v]["sheet"] = rel(SHEETS / f"dawn_bloom_growth_{v}.png")
        checks[v]["pipeline"] = {"manifest": pipes[v]["manifest"], "report": rel(PIPE / v / "validation.json"),
                                 "status": pipes[v]["status"], "stage_order": pipes[v]["stage_order"]}
    boards = comparison_board(sheets)
    rows = management_rows(sheets)
    technical = all(c["technical_checks_passed"] for c in checks.values())
    validation = {"schema_version": 1, "date": DATE, "status": "passed" if technical else "failed", "art_status": "candidate",
                  "approved_by_user": False, "scale": SCALE, "palette": "art/palette.hex (approved 24)",
                  "existing_growth_format": existing, "variants": checks, "boards": boards, "management_rows": rows,
                  "summary": {v: {"colors": c["color_count"], "off_palette": c["off_palette_colors"], "partial_alpha": c["partial_alpha_pixels"],
                                  "outline_violations": len(c["outline_violations"]), "status": c["status"]} for v, c in checks.items()},
                  "visual_review": "수치 검사는 디자인 승인이 아니다. 꽃이 아이콘과 같은 꽃으로 읽히는지, 기존 화분 옆에서 어색하지 않은지는 사용자가 본다.",
                  "scope_note": "후보 검사. assets/·scripts/·data/는 쓰지 않았다."}
    (MOCK / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    approval = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "approved_on": None, "user_reply": None,
        "date": DATE, "review": rel(MOCK / "review.html"), "plan": "docs/새-원정-지역과-물약-F26-기획안.md",
        "runtime_integrated": False,
        "scope": {"dawn_bloom_growth_a": "여명초 성장 그림 64×80 (32×40 칸 2×2) A안 · 5색 규칙 엄수 (후보)",
                  "dawn_bloom_growth_b": "여명초 성장 그림 64×80 (32×40 칸 2×2) B안 · 10색, 물체당 5색 상한 예외 (후보)"},
        "pending_decisions": ["A안/B안 선택 (B안은 5색 상한 예외 승인과 palette-log 기록 필요)", "봉오리 단계 잎·수확 반짝임 위치"],
        "publish_after_approval": {
            "copy": "선택한 sheets/dawn_bloom_growth_{a|b}.png → assets/content_expansion_v1/materials/dawn_bloom_growth.png (바이트 그대로)",
            "catalog": "assets/content_expansion_v1/catalog.json 여명초(materials) 행에 growth_path만 추가",
            "growth_path": GROWTH_PATH,
            "tests_to_update": ["tools/verify_f26_region_potions.gd: 'No growth sheet stand-in for dawn bloom' 검사",
                                "tools/verify_workshop_followup.gd: 재료별 성장 그림 검사의 여명초 예외"]},
    }
    (MOCK / "approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (MOCK / "review.html").write_text(page(existing, checks, boards, rows), encoding="utf-8")
    print(json.dumps({"status": validation["status"], "summary": validation["summary"]}, ensure_ascii=False, indent=1))
    return 0 if technical else 1


if __name__ == "__main__":
    raise SystemExit(main())
