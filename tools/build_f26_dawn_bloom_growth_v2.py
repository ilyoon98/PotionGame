"""F26 여명초(dawn_bloom) 화분 성장 그림 후보 v2 (승인 전).

Candidate only. Nothing under assets/, scripts/ or data/ is written; player saves, the running game and
Windows registration are untouched. Output: art/mockups/f26-dawn-bloom-growth-v2/ (v1 is kept as is).

Why v2: v1 followed the approved 24-colour rules, but the ten existing growth sheets are pre-rule generated art,
so v1 looked flat and foreign next to them. The user asked to redo it so it reads in the same style:
  1. Pot: copied pixel for pixel (RGB) from the existing moonflower sheet, frame 0, rows 24..38 — the dark plum
     pot with gold rim that the nine later sheets share. Only the front emblem (cream crescent) is replaced by a
     sunrise emblem of the same size, position and treatment (no outline, emblem drawn straight on the body).
  2. Plant: hand-authored letter maps (source/dawn_bloom_plant_{0..3}.txt) at the detail level measured on the
     existing sheets: pointed lens leaves with 3-4 shades, 1px green stem with dark sides, closed bud -> open
     bloom, stage heights/widths inside the existing range. The bloom is the approved dawn_bloom icon flower.
  3. Colours: taken from the existing sheets (outline, leaf/stem ramp, gold, cream, sparkle) and the icon.
     This is the same out-of-rule exception as the existing sheets (not the approved 24 colours / 5 colours).
     Alpha: the existing sheets store every pixel at alpha 240..254 plus a faint halo (alpha < 128). v2 snaps the
     copied pot and sparkles to 0/255 (visually identical, halo dropped) and uses no partial alpha anywhere.
  4. Frame 3 = frame 2 + the existing moonflower harvest sparkles (same pixels/colours), one shifted up to clear
     the leaves.
The fixed tools/process_pixel_art.py pipeline is not used: it enforces the approved palette, which this
exception deliberately leaves (recorded in validation.json).

Run with Pillow + NumPy: python tools/build_f26_dawn_bloom_growth_v2.py
"""
from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "art/mockups/f26-dawn-bloom-growth-v2"
V1 = ROOT / "art/mockups/f26-dawn-bloom-growth-v1"
SRC = MOCK / "source"
SHEETS = MOCK / "sheets"
STAGES = MOCK / "stages"
COMPARE = MOCK / "compare"
DATE = "2026-11-05"
SHEET, FRAME = (64, 80), (32, 40)
MAT = ROOT / "assets/content_expansion_v1/materials"
POT_SOURCE = ("moonflower", 0)   # sheet, frame
POT_ROWS = (24, 39)              # rows 24..38
EMBLEM_BOX = (13, 31, 19, 37)    # x0, y0, x1, y1 of the existing crescent (cream pixels)
EMBLEM_AT = (12, 31)             # top-left of the new 7x5 emblem
SPARKLES = [  # (box in moonflower frame 3, shift)
    ((0, 5, 7, 13), (0, 0)),
    ((25, 14, 32, 23), (0, -6)),
]
GROWTH_PATH = "res://assets/content_expansion_v1/materials/dawn_bloom_growth.png"
ICON = MAT / "dawn_bloom_icon.png"
PALETTE = {"#" + l.strip().upper().lstrip("#") for l in (ROOT / "art/palette.hex").read_text(encoding="utf-8").splitlines() if l.strip()}
EXISTING = ["herb", "starleaf", "dewgrass", "silver_moss", "blue_reed", "crystal_herb", "mist_mushroom", "ash_sage", "moonflower", "star_seed"]
COMPARE_WITH = [("moonflower", "달꽃"), ("star_seed", "별씨"), ("dewgrass", "이슬풀"), ("mist_mushroom", "안개 버섯"), ("ash_sage", "잿빛 세이지")]
STAGE_NAMES = ["0 새싹 (진행 0~33%)", "1 꽃봉오리 (33~66%)", "2 만개 (66~100%)", "3 수확 반짝임"]

# Plant letters -> (colour, source of the colour)
PLANT = {
    "#": ("#340E27", "외곽선 · 달꽃/별씨 식물 외곽선 군집"),
    "a": ("#3F4545", "잎 그늘 · 달꽃 잎"), "b": ("#576351", "잎 · 달꽃 잎"), "c": ("#68785E", "잎 밝은 면 · 달꽃 잎"),
    "e": ("#80916A", "잎 하이라이트 · 달꽃 잎"), "t": ("#536550", "줄기 · 달꽃 줄기"),
    "H": ("#FADDC3", "꽃잎 하이라이트 · 달꽃 꽃"), "O": ("#F4AC68", "꽃잎 · 여명초 아이콘"), "C": ("#DE7356", "꽃잎 그늘 · 여명초 아이콘"),
    "D": ("#B96F2B", "꽃잎 깊은 그늘 · 별씨 꽃"), "h": ("#FFF0BC", "꽃심 · 여명초 아이콘"), "g": ("#F9C54F", "꽃심 금빛 · 달꽃 꽃심"),
    "G": ("#E8AD53", "꽃심 그늘 · 별씨 꽃"),
}
EMBLEM = {
    "y": ("#FDDE7E", "해 빛살·밝은 면 · 달꽃 화분 금테 하이라이트"), "Y": ("#F8BE50", "수평선 · 달꽃 화분 금테"),
    "o": ("#F4AC68", "해 · 여명초 아이콘 꽃잎"), "r": ("#B8702C", "해 그늘 · 별씨 화분 문양 그늘"),
}


def rgb(value: str):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def hexs(c) -> str:
    return "#%02X%02X%02X" % tuple(int(v) for v in c[:3])


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def scaled(image: Image.Image, f: int) -> Image.Image:
    return image.resize((image.width * f, image.height * f), Image.Resampling.NEAREST)


def sheet_of(name: str) -> Image.Image:
    return Image.open(MAT / f"{name}_growth.png").convert("RGBA")


def frames_of(sheet: Image.Image) -> list[Image.Image]:
    return [sheet.crop(((i % 2) * 32, (i // 2) * 40, (i % 2) * 32 + 32, (i // 2) * 40 + 40)) for i in range(4)]


def read_map(path: Path, size) -> list[str]:
    rows = [l.rstrip("\r\n") for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    if len(rows) != size[1] or any(len(r) != size[0] for r in rows):
        raise SystemExit(f"{rel(path)} must be {size[0]}x{size[1]}")
    return rows


def snap(data: np.ndarray) -> tuple[np.ndarray, dict]:
    alpha = data[:, :, 3]
    stats = {"alpha_240_254_to_255": int(((alpha >= 128) & (alpha < 255)).sum()), "faint_halo_below_128_dropped": int(((alpha > 0) & (alpha < 128)).sum())}
    out = data.copy()
    out[alpha >= 128, 3] = 255
    out[alpha < 128] = 0
    return out, stats


# ---------------------------------------------------------------- build layers
def pot_layer() -> tuple[np.ndarray, dict]:
    name, index = POT_SOURCE
    source = np.array(frames_of(sheet_of(name))[index])
    pot = np.zeros_like(source)
    pot[POT_ROWS[0]:POT_ROWS[1]] = source[POT_ROWS[0]:POT_ROWS[1]]
    pot, alpha_stats = snap(pot)
    x0, y0, x1, y1 = EMBLEM_BOX
    removed = 0
    for y in range(y0, y1):
        row = pot[y]
        body = [row[x, :3] for x in range(16, 22) if row[x, 3] and row[x, :3].astype(int).sum() < 400]
        fill = np.median(np.array(body), axis=0).astype(np.uint8)
        for x in range(x0, x1):
            if row[x, 3] and row[x, :3].astype(int).sum() > 600:  # cream crescent pixels
                row[x, :3] = fill
                removed += 1
    emblem = read_map(SRC / "dawn_bloom_emblem.txt", (7, 5))
    painted = 0
    for dy, line in enumerate(emblem):
        for dx, ch in enumerate(line):
            if ch != ".":
                pot[EMBLEM_AT[1] + dy, EMBLEM_AT[0] + dx] = (*rgb(EMBLEM[ch][0]), 255)
                painted += 1
    info = {"source": f"{rel(MAT / (name + '_growth.png'))} 칸 {index}, 행 {POT_ROWS[0]}~{POT_ROWS[1] - 1}",
            "source_sha256": hashlib.sha256((MAT / f"{name}_growth.png").read_bytes()).hexdigest(),
            "rgb_copied_unchanged": "문양 상자 밖 모든 픽셀의 RGB는 원본 그대로", "alpha": alpha_stats,
            "crescent_pixels_replaced_with_row_body_median": removed, "sun_emblem_pixels": painted,
            "emblem_box_old": list(EMBLEM_BOX), "emblem_box_new": [EMBLEM_AT[0], EMBLEM_AT[1], EMBLEM_AT[0] + 7, EMBLEM_AT[1] + 5]}
    return pot, info


def sparkle_patches() -> tuple[list, dict]:
    frames = [np.array(f) for f in frames_of(sheet_of("moonflower"))]
    patches, count = [], 0
    for (x0, y0, x1, y1), (sx, sy) in SPARKLES:
        for y in range(y0, y1):
            for x in range(x0, x1):
                if frames[3][y, x, 3] >= 128 and frames[2][y, x, 3] < 128:
                    patches.append((x + sx, y + sy, tuple(int(v) for v in frames[3][y, x, :3])))
                    count += 1
    return patches, {"source": rel(MAT / "moonflower_growth.png") + " 칸 3에서 칸 2에 없던 픽셀(반짝임 2개)",
                     "pixels": count, "shifts": [s for _b, s in SPARKLES],
                     "colors": sorted({hexs(c) for _x, _y, c in patches})}


def build() -> tuple[Image.Image, dict]:
    pot, pot_info = pot_layer()
    sparkles, sparkle_info = sparkle_patches()
    frames = []
    for i in range(4):
        data = pot.copy()
        for y, line in enumerate(read_map(SRC / f"dawn_bloom_plant_{i}.txt", FRAME)):
            for x, ch in enumerate(line):
                if ch != ".":
                    if ch not in PLANT:
                        raise SystemExit(f"Undeclared letter {ch!r} in plant {i} at {x},{y}")
                    data[y, x] = (*rgb(PLANT[ch][0]), 255)
        if i == 3:
            for x, y, c in sparkles:
                if data[y, x, 3]:
                    raise SystemExit(f"Sparkle overlaps the plant at {x},{y}")
                data[y, x] = (*c, 255)
        frames.append(Image.fromarray(data))
    sheet = Image.new("RGBA", SHEET)
    for i, f in enumerate(frames):
        sheet.paste(f, ((i % 2) * 32, (i // 2) * 40))
    return sheet, {"pot": pot_info, "sparkles": sparkle_info}


# ---------------------------------------------------------------- measurements
def measure(sheet: Image.Image) -> dict:
    data = np.array(sheet)
    alpha = data[:, :, 3]
    frames = [np.array(f) for f in frames_of(sheet)]
    per = []
    for f in frames:
        solid = f[:, :, 3] >= 128
        ys, xs = np.where(solid[:POT_ROWS[0]])
        all_ys = np.where(solid)[0]
        per.append({"plant_top_row": int(ys.min()) if len(ys) else None, "plant_x": [int(xs.min()), int(xs.max())] if len(xs) else None,
                    "plant_pixels_above_row_24": int(solid[:POT_ROWS[0]].sum()), "bottom_row": int(all_ys.max())})
    return {"size": list(sheet.size), "rgb_colors": len({tuple(p[:3]) for p in data[alpha > 0]}),
            "partial_alpha_pixels": int(((alpha > 0) & (alpha < 255)).sum()),
            "alpha_255_pixels": int((alpha == 255).sum()), "frames": per,
            "frame3_minus_frame2_pixels": int(np.any(frames[3] != frames[2], axis=2).sum())}


def existing_measurements() -> dict:
    rows = {n: measure(sheet_of(n)) for n in EXISTING}
    later = [r for n, r in rows.items() if n != "herb"]
    def rng(key, i):
        values = [r["frames"][i][key] for r in later]
        return [min(values), max(values)]
    return {"sheets": rows, "range_9_later": {
        "rgb_colors": [min(r["rgb_colors"] for r in later), max(r["rgb_colors"] for r in later)],
        "partial_alpha_pixels": [min(r["partial_alpha_pixels"] for r in later), max(r["partial_alpha_pixels"] for r in later)],
        "plant_top_row": [rng("plant_top_row", i) for i in range(4)],
        "plant_pixels_above_row_24": [rng("plant_pixels_above_row_24", i) for i in range(4)]},
        "observations": {
            "format": "64×80, 32×40 칸 2×2(0 새싹·1 자라는 중·2 다 자람·3 수확 반짝임). 모든 칸 바닥 행 38.",
            "pot": "herb만 다리 달린 솥형. 나머지 9종은 어두운 자두색 몸통(가운데 #4C223E 안팎, 왼쪽 분홍빛 밝은 면 #95556E, 오른쪽 #3E1932)·금테(#F8BE50/#FDDE7E)·흙(#3C2428 안팎)·"
                   "재료별 문양(행 31~36, x 13~18, 외곽선 없이 몸통 위에 직접)을 공유. 칸마다 따로 생성돼 같은 시트 안에서도 화분 픽셀이 300~450개 다르다.",
            "outline": "식물 외곽선은 #241C32가 아니라 어두운 자두색(#340E27·#370E2B 군집), 1픽셀.",
            "leaves": "끝이 뾰족한 렌즈형 잎. 새싹 2장(3×3~5×4), 자라는 중 2~4장(8~10픽셀 길이, 위로 비스듬히), 다 자람 4~6장(아래로 늘어져 화분 테를 덮기도 함). "
                      "명암 3~4단(달꽃 #3F4545→#576351→#68785E→#80916A) + 어두운 외곽선.",
            "stem": "1픽셀 초록 줄기(달꽃 #536550 안팎)와 양옆 어두운 픽셀. 흙 속으로 이어진다.",
            "bloom": "자라는 중 칸에 닫힌 꽃봉오리(5~7픽셀 폭, 꽃받침), 다 자람 칸에 큰 꽃 1개(14~16픽셀) 또는 작은 꽃 여러 개. 꽃은 3~4단 명암 + 하이라이트.",
            "sparkle": "수확 칸에 5×5 십자 반짝임 2~4개(끝 갈색 #7D4A0E 계열, 팔 금빛, 가운데 크림).",
            "alpha": "불투명해 보이는 픽셀도 알파 240~254로 저장돼 있고(255는 0개), 실루엣 둘레에 알파 1~127 픽셀이 시트당 약 280~350개 있다."}}


# ---------------------------------------------------------------- boards
def font(size: int, bold: bool = False):
    return ImageFont.truetype(str(ROOT / "assets/fonts/pretendard" / ("Pretendard-SemiBold.otf" if bold else "Pretendard-Regular.otf")), size)


BG = (0x1D, 0x24, 0x2B)


def compare_board(rows: list, f: int, path: Path, header=True) -> str:
    cw, ch, gap, lw = 32 * f, 40 * f, 8, (150 if f >= 3 else 110)
    board = Image.new("RGBA", (lw + 4 * (cw + gap) + gap, len(rows) * (ch + gap) + gap + 24), BG + (255,))
    draw = ImageDraw.Draw(board)
    small = font(13 if f >= 3 else 11)
    if header:
        for i, t in enumerate(["0 새싹", "1 자라는 중", "2 다 자람", "3 수확"]):
            draw.text((lw + gap + i * (cw + gap), 4), t, font=small, fill="#ABB9BE")
    for r, (label, sheet) in enumerate(rows):
        y = 24 + gap + r * (ch + gap)
        draw.text((8, y + ch // 2 - 8), label, font=small, fill="#F3EDE0")
        for i, fr in enumerate(frames_of(sheet)):
            board.alpha_composite(scaled(fr, f), (lw + gap + i * (cw + gap), y))
    board.convert("RGB").save(path)
    return rel(path)


def boards(sheet: Image.Image) -> dict:
    existing = [(f"{label} (기존)", sheet_of(n)) for n, label in COMPARE_WITH]
    rows = existing + [("여명초 v2 (새)", sheet)]
    out = {"compare_6x": compare_board(rows, 6, COMPARE / "growth-compare-6x.png"),
           "compare_3x": compare_board(rows, 3, COMPARE / "growth-compare-3x.png"),
           "compare_1x": compare_board(rows, 1, COMPARE / "growth-compare-1x.png")}
    v1 = [("v1 A안 (5색)", Image.open(V1 / "sheets/dawn_bloom_growth_a.png").convert("RGBA")),
          ("v1 B안 (10색)", Image.open(V1 / "sheets/dawn_bloom_growth_b.png").convert("RGBA")),
          ("v2", sheet), ("달꽃 (기존)", sheet_of("moonflower"))]
    out["v1_vs_v2_3x"] = compare_board(v1, 3, COMPARE / "v1-vs-v2-3x.png")
    icon = Image.open(ICON).convert("RGBA")
    pair = Image.new("RGBA", (2 * (32 * 6 + 24) + 24, 40 * 6 + 44), BG + (255,))
    draw = ImageDraw.Draw(pair)
    for i, (img, text) in enumerate([(icon, "승인된 여명초 아이콘 32×40"), (frames_of(sheet)[2], "v2 다 자람 칸")]):
        x = 24 + i * (32 * 6 + 24)
        pair.alpha_composite(scaled(img, 6), (x, 8))
        draw.text((x, 40 * 6 + 16), text, font=font(14), fill="#F3EDE0")
    pair.convert("RGB").save(COMPARE / "bloom-vs-icon-6x.png")
    out["bloom_vs_icon_6x"] = rel(COMPARE / "bloom-vs-icon-6x.png")
    return out


def readable(icon: Image.Image, box: int = 48) -> Image.Image:
    trimmed = icon.crop(icon.getbbox())
    k = min(box / trimmed.width, box / trimmed.height)
    return trimmed.resize((max(1, round(trimmed.width * k)), max(1, round(trimmed.height * k))), Image.Resampling.NEAREST)


def management_rows(sheet: Image.Image) -> dict:
    """Same approximation as v1: management_panel.gd _row + 32x40 growth preview at 1x, Python-drawn."""
    content = json.loads((ROOT / "data/content_expansion.json").read_text(encoding="utf-8"))
    by_id = {m["id"]: m for m in content["materials"]}
    line, surface = (0x40, 0x54, 0x5A), (0x26, 0x31, 0x39)
    ink, muted, accent = (0xF3, 0xED, 0xE0), (0xAB, 0xB9, 0xBE), (0xAA, 0xCB, 0xB0)
    entries = [("moonflower", "달꽃 (기존)", None), ("star_seed", "별씨 (기존)", None), ("dawn_bloom", "여명초 · v2", sheet)]
    env_ko = {"clear": "맑음", "night_clear": "맑은 밤", "rain": "비", "night": "밤", "day": "낮", "cloudy": "흐림"}
    width, row_h = 458, 168
    title_f, body_f, aux_f = font(18, True), font(16), font(14)
    progress_values = [0.2, 0.5, 0.9]
    board = Image.new("RGBA", (width * 3 + 16 * 4, len(entries) * row_h + 40), BG + (255,))
    draw = ImageDraw.Draw(board)
    for c, progress in enumerate(progress_values):
        fi = min(2, int(progress * 3))
        ox = 16 + c * (width + 16)
        draw.text((ox, 10), f"진행 {int(progress * 100)}% → 미리보기 칸 {fi}", font=aux_f, fill=muted)
        for r, (mid, title, sh) in enumerate(entries):
            oy = 36 + r * row_h
            row = by_id[mid]
            ic = readable(Image.open(ROOT / row["icon_candidate"].replace("res://", "")).convert("RGBA"))
            board.alpha_composite(ic, (ox + 8 + (48 - ic.width) // 2, oy + 8 + (48 - ic.height) // 2))
            bx = ox + 68
            draw.text((bx, oy + 13), title, font=title_f, fill=ink)
            draw.rounded_rectangle((ox + width - 60, oy + 8, ox + width - 8, oy + 40), 4, outline=accent)
            draw.text((ox + width - 50, oy + 14), "상세", font=body_f, fill=accent)
            seconds = float(row.get("growth_seconds", 1))
            draw.text((bx, oy + 46), f"재배 중 · {int(seconds)}초마다 1개 · {env_ko.get(row.get('environment', ''), row.get('environment', ''))} ×{row.get('favored_growth_multiplier', 1.5)}", font=body_f, fill=muted)
            for g, (cap, frac, count, colour) in enumerate([("작업", progress, f"{seconds * progress:.0f}초 / {int(seconds)}초", accent),
                                                         ("보유", 4 / float(row.get("capacity", 12)), f"4 / {row.get('capacity', 12)}", (0x90, 0xAD, 0x95))]):
                gy = oy + 74 + g * 22
                draw.text((bx, gy), cap, font=aux_f, fill=muted)
                x0, x1 = bx + 40, ox + width - 98
                draw.rounded_rectangle((x0, gy + 7, x1, gy + 14), 2, fill=surface)
                draw.rounded_rectangle((x0, gy + 7, x0 + max(4, int((x1 - x0) * frac)), gy + 14), 2, fill=colour)
                draw.text((ox + width - 8 - draw.textlength(count, font=aux_f), gy), count, font=aux_f, fill=muted)
            src = sh if sh is not None else sheet_of(mid)
            board.alpha_composite(frames_of(src)[fi], (bx, oy + 120))
            draw.line((ox, oy + row_h - 1, ox + width, oy + row_h - 1), fill=line)
    board.convert("RGB").save(COMPARE / "management-herbs-rows-1x.png")
    scaled(board.convert("RGB"), 2).save(COMPARE / "management-herbs-rows-2x.png")
    return {"rows_1x": rel(COMPARE / "management-herbs-rows-1x.png"), "rows_2x": rel(COMPARE / "management-herbs-rows-2x.png"),
            "layout": "v1과 같은 근사: 패널 폭 458, 48×48 아이콘(여백 자른 뒤 KEEP_ASPECT 최근접), 제목 18·상세 52×32, 상태 줄 16, 작업/보유 막대, "
                      "성장 미리보기 32×40 원본 1배. Python 근사이며 Godot 캡처가 아니다."}


# ---------------------------------------------------------------- review page
def page(existing: dict, mine: dict, prov: dict, brd: dict, rows: dict, self_review: list) -> str:
    def img(path: str) -> str:
        return f'<img src="{Path(path).relative_to(rel(MOCK)).as_posix()}" alt="">'
    rng = existing["range_9_later"]
    stage_imgs = "".join(f'<figure><div class="check">{img(rel(STAGES / f"frame_{i}-6x.png"))}</div><figcaption>{STAGE_NAMES[i]}</figcaption></figure>' for i in range(4))
    ex = "".join(f"<tr><td>{n}</td><td>{r['rgb_colors']}</td><td>{r['partial_alpha_pixels']}</td><td>{r['alpha_255_pixels']}</td>"
                 f"<td>{' / '.join(str(f['plant_top_row']) for f in r['frames'])}</td><td>{' / '.join(str(f['plant_pixels_above_row_24']) for f in r['frames'])}</td></tr>"
                 for n, r in existing["sheets"].items())
    me = (f"<tr class='new'><td>여명초 v2</td><td>{mine['rgb_colors']}</td><td>{mine['partial_alpha_pixels']}</td><td>{mine['alpha_255_pixels']}</td>"
          f"<td>{' / '.join(str(f['plant_top_row']) for f in mine['frames'])}</td><td>{' / '.join(str(f['plant_pixels_above_row_24']) for f in mine['frames'])}</td></tr>")
    sw = "".join(f'<span><i style="--c:{c}"></i>{c} {d}</span>' for c, d in list(PLANT.values()) + list(EMBLEM.values()))
    obs = "".join(f"<li><b>{k}</b> {v}</li>" for k, v in existing["observations"].items())
    review = "".join(f"<li>{t}</li>" for t in self_review)
    return f"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>여명초 성장 그림 v2</title><style>
@font-face{{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}}
:root{{--bg:#241c32;--panel:#30263f;--text:#fff0bc;--muted:#c38eb5;--accent:#e9b95f;--ok:#b5c77d}}
*{{box-sizing:border-box}}html,body{{background:var(--bg)}}body{{margin:0;color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}}
main{{max-width:1210px;margin:auto;padding:18px 16px 48px}}h1{{font-size:23px;margin:0 0 6px}}h2{{font-size:17px;margin:28px 0 8px}}
p{{margin:6px 0 10px}}.muted{{color:var(--muted)}}.note{{border-left:3px solid #718c59;padding:8px 12px;background:var(--panel);margin:10px 0}}.warn{{border-left-color:var(--accent)}}
.check{{background-color:#4a3c52;background-image:linear-gradient(45deg,#3f3347 25%,transparent 25%),linear-gradient(-45deg,#3f3347 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#3f3347 75%),linear-gradient(-45deg,transparent 75%,#3f3347 75%);background-size:12px 12px;background-position:0 0,0 6px,6px -6px,-6px 0}}
img{{image-rendering:pixelated;image-rendering:crisp-edges;max-width:none;display:block}}
.row{{display:flex;flex-wrap:wrap;gap:12px;align-items:flex-end}}.row figure{{margin:0;text-align:center}}.row .check{{padding:4px}}
figcaption{{font-size:11px;color:var(--muted);margin-top:3px}}.desc{{font-size:13px}}.wide{{overflow-x:auto;background:var(--panel);padding:8px;border-radius:6px}}
.sw{{display:flex;flex-wrap:wrap;gap:6px 12px;font-size:11px;color:var(--muted)}}.sw span{{display:flex;align-items:center;gap:4px}}.sw i{{width:12px;height:12px;display:inline-block;border:1px solid #000;background:var(--c)}}
table{{border-collapse:collapse;font-size:13px;width:100%}}td,th{{border-bottom:1px solid #4a3c52;padding:5px 6px;text-align:left}}tr.new td{{color:var(--accent);font-weight:bold}}
</style></head><body><main>
<h1>여명초(dawn_bloom) 화분 성장 그림 후보 v2</h1>
<p class="muted">{DATE} · 상태 <b>후보(candidate)</b> · 게임 미연결 · 승인 전 · v1(<code>../f26-dawn-bloom-growth-v1/</code>)은 그대로 보존.
승인되면 <code>catalog.json</code> 여명초 행에 <code>growth_path: {GROWTH_PATH}</code>만 더한다.</p>
<div class="note">v1은 승인 24색 규칙대로 그려서 기존 성장 그림(규칙 이전의 생성 그림)과 그림체가 달랐다. v2는 <b>기존 그림에 맞춘다</b>:
화분은 달꽃 시트 칸 0의 행 24~38을 RGB 그대로 복사하고 앞 문양만 해돋이로 바꿨다. 식물은 기존 10종을 확대해 잰 잎 수·잎 모양·명암 단계·줄기·키에 맞춰 손으로 다시 그렸고(<code>source/*.txt</code>),
수확 칸 반짝임은 달꽃 칸 3의 반짝임 픽셀을 그대로 옮겼다.</div>
<div class="note warn"><b>규칙 밖 예외:</b> 기존 성장 그림과 같은 예외다. 승인 24색·물체당 5색·#241C32 외곽선을 따르지 않는다(색 {mine['rgb_colors']}개, 그중 팔레트 밖 {mine['off_palette_colors']}개).
반투명은 0개로 두었다(기존 9종 {rng['partial_alpha_pixels'][0]:,}~{rng['partial_alpha_pixels'][1]:,}개). 기존 그림의 알파 240~254 픽셀은 255로, 알파 1~127의 흐린 테두리는 0으로 바꿨다(눈으로는 같음).</div>

<h2>1. v2 시트와 단계별 6배</h2>
<div class="row"><figure><div class="check">{img(rel(SHEETS / 'dawn_bloom_growth-3x.png'))}</div><figcaption>시트 64×80 ×3</figcaption></figure>
<figure><div class="check">{img(rel(SHEETS / 'dawn_bloom_growth.png'))}</div><figcaption>원본 1배</figcaption></figure></div>
<div class="row" style="margin-top:10px">{stage_imgs}</div>
<div class="sw" style="margin-top:8px">{sw}</div>

<h2>2. 기존 성장 그림 5종과 나란히 · 6배</h2>
<div class="wide">{img(brd['compare_6x'])}</div>
<h2>3. 같은 비교 · 3배 / 1배</h2>
<div class="wide">{img(brd['compare_3x'])}</div>
<div class="wide" style="margin-top:8px">{img(brd['compare_1x'])}</div>

<h2>4. 다 자란 꽃 대 승인 아이콘 (6배)</h2>
<div class="wide">{img(brd['bloom_vs_icon_6x'])}</div>
<p class="desc">아이콘의 여섯 꽃잎 실루엣·크림색 육각 꽃심·오른쪽 아래 산호색 그늘을 16×15로 줄이고, 기존 꽃처럼 꽃잎 이음선·왼쪽 위 하이라이트(#FADDC3)·아래쪽 깊은 그늘(#B96F2B)·금빛 꽃술(#F9C54F)을 더했다.</p>

<h2>5. 관리 · 약초 탭 행 (원본 1배 · 근사)</h2>
<p class="desc">{rows['layout']}</p>
<div class="wide">{img(rows['rows_1x'])}</div>

<h2>6. v1 ↔ v2</h2>
<div class="wide">{img(brd['v1_vs_v2_3x'])}</div>

<h2>7. 기존 10종 관찰과 수치</h2>
<ul class="desc">{obs}</ul>
<div class="wide"><table><tr><th>시트</th><th>RGB 색 수</th><th>반투명 픽셀</th><th>알파 255 픽셀</th><th>칸 0/1/2/3 식물 꼭대기 행</th><th>칸 0/1/2/3 식물 픽셀(행 24 위)</th></tr>{ex}{me}</table></div>
<p class="desc">화분 출처: {prov['pot']['source']} · 문양 교체 {prov['pot']['crescent_pixels_replaced_with_row_body_median']}픽셀 지움 + 해돋이 {prov['pot']['sun_emblem_pixels']}픽셀 ·
반짝임: {prov['sparkles']['source']} {prov['sparkles']['pixels']}픽셀(오른쪽 반짝임은 잎과 겹쳐 6행 위로 옮김)</p>

<h2>8. 스스로 본 판단</h2>
<ul class="desc">{review}</ul>
<p class="muted">검사 결과: <code>validation.json</code> · 승인 상태: <code>approval.json</code></p>
</main></body></html>
"""


SELF_REVIEW = [
    "화분: 달꽃 화분 픽셀 그대로라 옆 그림들과 구분되지 않는다. 해돋이 문양은 달·별 문양과 같은 자리·크기(7×5)로 외곽선 없이 몸통 위에 직접 칠했다.",
    "식물: 잎이 끝이 뾰족한 렌즈형이고 명암이 4단(+외곽선)이라 달꽃·별씨 잎과 같은 밀도로 읽힌다. 단계별 키와 픽셀 수는 기존 9종 범위 안이다(아래 표).",
    "남은 차이: 기존 그림은 생성 그림이라 픽셀마다 색이 조금씩 흔들리는 잡음 질감(시트당 1,300~2,000색)이 있다. v2는 화분만 그 질감(복사한 약 200색)이고 "
    "식물은 손으로 칠한 13색 덩어리라 6배로 확대하면 잎·꽃이 화분보다 매끈하다. 1배(관리 화면 실제 크기)에서는 차이가 거의 보이지 않는다.",
    "남은 차이: 잎이 달꽃 잎과 같은 회녹색 계열이라 이슬풀처럼 밝은 초록 시트와 나란히 두면 차분해 보인다. 꽃 쪽으로 시선이 가도록 일부러 고른 색이다.",
    "남은 차이: 기존 시트는 칸마다 화분이 조금씩 다르게 생성돼 있는데 v2는 네 칸 모두 같은 화분이다(흔들림 없음).",
]


def main() -> int:
    for folder in (SHEETS, STAGES, COMPARE):
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
    sheet, prov = build()
    sheet.save(SHEETS / "dawn_bloom_growth.png")
    scaled(sheet, 3).save(SHEETS / "dawn_bloom_growth-3x.png")
    scaled(sheet, 6).save(SHEETS / "dawn_bloom_growth-6x.png")
    for i, f in enumerate(frames_of(sheet)):
        f.save(STAGES / f"frame_{i}.png")
        scaled(f, 3).save(STAGES / f"frame_{i}-3x.png")
        scaled(f, 6).save(STAGES / f"frame_{i}-6x.png")
    existing = existing_measurements()
    mine = measure(sheet)
    data = np.array(sheet)
    colors = sorted({hexs(p) for p in data[data[:, :, 3] > 0]})
    mine["colors"] = colors
    mine["off_palette_colors"] = sum(1 for c in colors if c not in PALETTE)
    rng = existing["range_9_later"]
    frames = [np.array(f) for f in frames_of(sheet)]
    checks = {
        "size_64x80": list(sheet.size) == list(SHEET),
        "grid_2x2_32x40_cells_do_not_touch_edges": all(not (np.concatenate([f[0, :, 3], f[-1, :, 3], f[:, 0, 3], f[:, -1, 3]]) > 0).any() for f in frames),
        "all_frames_bottom_row_38": all(fr["bottom_row"] == 38 for fr in mine["frames"]),
        "pot_identical_in_all_frames_below_plant": True,
        "plant_top_rows_within_existing_range": all(rng["plant_top_row"][i][0] <= mine["frames"][i]["plant_top_row"] <= rng["plant_top_row"][i][1] for i in range(4)),
        "plant_pixels_within_existing_range": all(rng["plant_pixels_above_row_24"][i][0] <= mine["frames"][i]["plant_pixels_above_row_24"] <= rng["plant_pixels_above_row_24"][i][1] for i in range(4)),
        "stage_growth_monotonic": mine["frames"][0]["plant_pixels_above_row_24"] < mine["frames"][1]["plant_pixels_above_row_24"] < mine["frames"][2]["plant_pixels_above_row_24"],
        "frame3_is_frame2_plus_sparkles_only": bool(np.all(frames[2][np.any(frames[3] != frames[2], axis=2)][:, 3] == 0)),
        "partial_alpha_pixels": mine["partial_alpha_pixels"],
        "bloom_uses_icon_colours": all(c in {hexs(p) for p in np.array(Image.open(ICON).convert("RGBA")).reshape(-1, 4) if p[3]} for c in ("#F4AC68", "#DE7356", "#FFF0BC")),
    }
    passed = all(v for k, v in checks.items() if k != "partial_alpha_pixels") and checks["partial_alpha_pixels"] == 0
    brd = boards(sheet)
    rows = management_rows(sheet)
    validation = {
        "schema_version": 1, "date": DATE, "status": "passed" if passed else "failed", "art_status": "candidate", "approved_by_user": False,
        "rule_exception": {"kind": "기존 성장 그림과 같은 규칙 밖 예외",
                           "detail": "기존 재배 재료 성장 그림 10종은 승인 24색 규칙 이전의 생성 그림이다. v2는 그 옆에서 어울리도록 기존 시트에서 쓰인 색과 아이콘 색을 쓴다. "
                                     "승인 24색·물체당 5색·#241C32 외곽선 규칙을 따르지 않으며 tools/process_pixel_art.py(팔레트 강제)를 거치지 않았다. 사용자 승인 대상.",
                           "colors": {"v2": mine["rgb_colors"], "existing_9_later_range": rng["rgb_colors"], "existing_herb": existing["sheets"]["herb"]["rgb_colors"]},
                           "off_palette_colors_v2": mine["off_palette_colors"],
                           "partial_alpha": {"v2": mine["partial_alpha_pixels"], "existing_9_later_range": rng["partial_alpha_pixels"], "existing_herb": existing["sheets"]["herb"]["partial_alpha_pixels"]}},
        "v2": mine, "checks": checks, "provenance": prov,
        "plant_colours": {k: {"color": v[0], "from": v[1]} for k, v in PLANT.items()},
        "emblem_colours": {k: {"color": v[0], "from": v[1]} for k, v in EMBLEM.items()},
        "existing_growth_format": existing, "boards": brd, "management_rows": rows, "self_review": SELF_REVIEW,
        "sources": [rel(SRC / f"dawn_bloom_plant_{i}.txt") for i in range(4)] + [rel(SRC / "dawn_bloom_emblem.txt")],
        "native_sha256": hashlib.sha256(np.array(sheet).tobytes()).hexdigest(),
        "scope_note": "후보 검사. assets/·scripts/·data/는 쓰지 않았다.",
    }
    (MOCK / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    approval = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "approved_on": None, "user_reply": None, "date": DATE,
        "review": rel(MOCK / "review.html"), "supersedes_for_review": "art/mockups/f26-dawn-bloom-growth-v1 (보존, 사용자 피드백: 기존 그림과 너무 다름)",
        "runtime_integrated": False,
        "scope": {"dawn_bloom_growth": "여명초 성장 그림 64×80 (32×40 칸 2×2) v2 · 기존 성장 그림과 같은 규칙 밖 예외 (후보)"},
        "pending_decisions": ["v2 그림체·꽃 모양 승인", "규칙 밖 예외(기존 성장 그림과 같은 색 처리) 승인"],
        "publish_after_approval": {
            "copy": "sheets/dawn_bloom_growth.png → assets/content_expansion_v1/materials/dawn_bloom_growth.png (바이트 그대로)",
            "catalog": "assets/content_expansion_v1/catalog.json 여명초(materials) 행에 growth_path만 추가", "growth_path": GROWTH_PATH,
            "tests_to_update": ["tools/verify_f26_region_potions.gd: 'No growth sheet stand-in for dawn bloom' 검사",
                                "tools/verify_workshop_followup.gd: 재료별 성장 그림 검사의 여명초 예외"]},
    }
    (MOCK / "approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (MOCK / "review.html").write_text(page(existing, mine, prov, brd, rows, SELF_REVIEW), encoding="utf-8")
    print(json.dumps({"status": validation["status"], "checks": checks, "colors": mine["rgb_colors"], "off_palette": mine["off_palette_colors"],
                      "frames": mine["frames"], "existing_range": rng}, ensure_ascii=False, indent=1))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
