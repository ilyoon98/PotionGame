"""F27 10th region (오로라 설원) + four potions + one material: candidate art for approval.

Candidate only. Nothing under assets/, scripts/ or data/ is written; player saves, the running game and Windows
registration are untouched. Output: art/mockups/f27-region-potions-v1/.

Design rule for this batch (user feedback on F25/F26: freehand art "기존꺼랑 너무 다른데"): every sprite is derived
from approved pixels and only the part that has to change is redrawn.
  - Shelf bottles 8x12: rows of approved bottles (assets/pixel_v1/potions/*.png) stacked ("kitbash") so the
    silhouette is new but every row already exists in an approved bottle; the two liquid letters are recoloured to
    the new ramp by explicit letter (light/dark liquid), never by nearest RGB. A few snow/aurora pixels are listed
    one by one in EDITS.
  - Cauldron liquids: approved pot frames assets/pixel_v1/pots/health-{0,1,2}.png, only the 63-pixel liquid mask
    from assets/pixel_v1/catalog.json is recoloured (same as the runtime and F26).
  - 32x40 potion / recipe / material icons: the approved F26 icon letter maps
    (art/mockups/f26-region-potions-v1/source/*.txt, verified pixel-identical to the published assets) with the
    letters recoloured and only the emblem replaced by a small stamp.
  - 32x40 region icon: the approved dawn lighthouse ground rows (29..38) are copied; the pine and the aurora ribbon
    above them are new.
  - 64x80 growth sheet: the approved dawn bloom v2 sheet (assets/content_expansion_v1/materials/dawn_bloom_growth.png)
    copied; plant petals recoloured by the v2 plant letter maps, the pot emblem replaced (snowflake). Same out-of-rule
    exception as the existing growth sheets (not the 24-colour pipeline).
All 24-colour sprites go through the fixed tools/process_pixel_art.py pipeline with an explicit per-letter manifest.
Validation reuses the F26 check functions (palette, <=5 colours, outline, no partial alpha, dithering, lighting).

Run with Pillow + NumPy: python tools/build_f27_region_potions_v1.py
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


F26 = _load("f26_build", ROOT / "tools/build_f26_region_potions_v1.py")       # check helpers (same validation as F26)
G2 = _load("f26_growth_v2", ROOT / "tools/build_f26_dawn_bloom_growth_v2.py")  # approved v2 plant/emblem legend
rgb, hexs, delta_e, exact_rules = F26.rgb, F26.hexs, F26.delta_e, F26.exact_rules

MOCK = ROOT / "art/mockups/f27-region-potions-v1"
SRC, REG, PIPE, SPRITES, POTS, COMPARE, GROWTH = (MOCK / n for n in ("source", "registered", "pipeline", "sprites", "pots", "compare", "growth"))
F26SRC = ROOT / "art/mockups/f26-region-potions-v1/source"
SCALE, BIG = 3, 6
DATE = "2026-11-05"
OUTLINE_HEX = "#241C32"
CATALOG = json.loads((ROOT / "assets/pixel_v1/catalog.json").read_text(encoding="utf-8"))
PALETTE = F26.PALETTE
FIXED = {"#241C32": "#", "#916047": "c", "#FFF0BC": "h"}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def scaled(image: Image.Image, f: int) -> Image.Image:
    return image.resize((image.width * f, image.height * f), Image.Resampling.NEAREST)


# ---------------------------------------------------------------- potions
POTIONS = [
    {"id": "warmth", "name": "온기 물약", "short": "온기", "family_ko": "활력", "customer": "여행자",
     "light": ("#F6D1AC", "skin"), "dark": ("#C99463", "wood"), "liquid": "#F6D1AC",
     "bottle_segments": [("vigor", 0, 10), ("health", 10, 12)], "edits": [],
     "bottle": "활력 계열 `vigor`의 0~9행(각진 어깨·안쪽 반짝임, 꿀단지 몸통) + 첫 물약 `health`의 10~11행(작은 굽). 살구 크림 + 꿀빛.",
     "icon_base": "sun_moon_elixir_icon", "recipe_motif": "heart",
     "icon": "승인된 F26 일월의 물약 아이콘(받침 둥근 병) 실루엣 그대로, 몸통을 살구 크림으로, 해·달 문양 자리에 꿀빛 하트.",
     "recipe": "승인된 F26 레시피 두루마리 그대로, 인장 원을 꿀빛으로, 안쪽 문양을 살구 크림 하트로."},
    {"id": "thin_ice", "name": "살얼음 물약", "short": "살얼음", "family_ko": "기교", "customer": "고양이 도적",
     "light": ("#9BE2CF", "teal"), "dark": ("#3BA8A3", "teal"), "liquid": "#9BE2CF",
     "bottle_segments": [("vigor", 0, 8), ("shadow_elixir", 8, 12)], "edits": [],
     "bottle": "활력 `vigor`의 0~7행(넓은 어깨·안쪽 반짝임) + 그림자 `shadow_elixir`의 8~11행(뾰족한 아래) = 고드름처럼 아래로 좁아지는 병. 얼음 민트 + 청록.",
     "icon_base": "sea_spray_icon", "recipe_motif": "snowflake",
     "icon": "승인된 F26 물보라 아이콘(거꾸로 된 물방울) 실루엣 그대로, 몸통을 얼음 민트로, 물거품 띠를 크림 서리로, 소용돌이 자리에 청록 눈송이.",
     "recipe": "두루마리 그대로, 인장 원을 얼음 민트로, 문양을 청록 눈송이로."},
    {"id": "pine_wind", "name": "솔바람 물약", "short": "솔바람", "family_ko": "자연", "customer": "엘프",
     "light": ("#B5C77D", "leaf"), "dark": ("#3D544D", "leaf"), "liquid": "#B5C77D",
     "bottle_segments": [("antidote", 0, 7), ("antidote", 8, 9), ("antidote", 7, 8), ("antidote", 9, 12)],
     "edits": [(3, 6, "h"), (2, 7, "h"), (2, 9, "h"), (1, 10, "h")],
     "bottle": "해독 `antidote`(위로 좁은 병)의 7·8행 순서만 바꿔 2단 소나무 층을 만들고, 층마다 왼쪽 위 1픽셀을 크림 눈으로. 새싹 빛 + 그늘 잎.",
     "icon_base": "beacon_icon", "recipe_motif": "pine",
     "icon": "승인된 F26 등대불 아이콘(층층이 넓어지는 탑) 실루엣 그대로, 몸통을 그늘 잎·띠를 새싹 빛으로, 띠마다 첫 줄을 크림 눈으로.",
     "recipe": "두루마리 그대로, 인장 원을 그늘 잎으로, 문양을 새싹 빛 소나무로."},
    {"id": "aurora_elixir", "name": "오로라의 물약", "short": "오로라", "family_ko": "비술", "customer": "여마법사",
     "light": ("#B5C77D", "leaf"), "dark": ("#3BA8A3", "teal"), "liquid": "#3BA8A3",
     "bottle_segments": [("rare_forest_breath", 0, 10), ("iron_skin", 10, 12)],
     "edits": [(3, 6, "A"), (2, 7, "B"), (3, 7, "A"), (2, 8, "A"), (3, 8, "B"), (4, 8, "B"), (2, 9, "A"), (3, 9, "A"), (4, 9, "A"), (5, 9, "B"), (6, 9, "B"),
               (1, 10, "A"), (2, 10, "A"), (3, 10, "A"), (4, 10, "A"), (5, 10, "A"), (6, 10, "A")],
     "bottle": "특별 `rare_forest_breath`의 0~9행(종 모양 윗부분) + `iron_skin`의 10~11행(평평한 바닥) = 평평한 바닥의 종. 청록 몸통에 새싹 빛 띠 2줄(오로라).",
     "icon_base": "sunrise_icon", "recipe_motif": "aurora",
     "icon": "승인된 F26 해돋이 아이콘(평평한 바닥의 돔) 실루엣·왼쪽 반짝임 그대로, 몸통을 청록으로, 해·수평선 자리에 새싹 빛 물결 띠 2줄.",
     "recipe": "두루마리 그대로, 인장 원을 청록으로, 문양을 새싹 빛 물결 2줄로."},
]
MATERIAL = {"id": "frost_flower_icon", "name": "서리꽃 (재료)", "kind": "material", "base": "dawn_bloom_icon",
            "remap": {"#": ("#241C32", "outline", "outline"), "L": ("#9BE2CF", "teal", "petal_light"), "D": ("#3BA8A3", "teal", "petal_shade"),
                      "h": ("#FFF0BC", "gold", "flower_heart"), "G": ("#718C59", "leaf", "leaf_and_stem")},
            "description": "승인된 F26 여명초 아이콘 그대로(꽃잎 6장·꽃심·줄기·잎 2장), 꽃잎만 얼음 민트/청록으로 다시 칠함. 잎·꽃심 색은 그대로."}
REGION = {"id": "aurora_snowfield_icon", "name": "오로라 설원 (지역)", "kind": "region",
          "legend": {"#": ("#241C32", "outline", "outline"), "s": ("#FFF0BC", "gold", "snow"), "P": ("#3D544D", "leaf", "pine"),
                     "G": ("#B5C77D", "leaf", "aurora_and_needles"), "A": ("#3BA8A3", "teal", "aurora")},
          "description": "승인된 F26 새벽 등대 아이콘의 땅(29~38행)을 그대로 쓰고 돌색을 눈(크림)으로. 등대 자리에 눈 덮인 3층 소나무, 해 자리에 청록·새싹 빛 오로라 띠."}

STAMPS = {
    "heart": ["LLL.LLL.", "LLLLLLLL", "LLLLLLLL", ".LLLLLL.", "..LLLL..", "...LL..."],
    "heart_small": [".LL.LL.", "LLLLLLL", "LLLLLLL", ".LLLLL.", "..LLL..", "...L..."],
    "snowflake": ["....E....", ".E..E..E.", "..E.E.E..", "...EEE...", "EEEEEEEEE", "...EEE...", "..E.E.E..", ".E..E..E.", "....E...."],
    "snowflake_small": ["...L...", ".L.L.L.", "..LLL..", "LLLLLLL", "..LLL..", ".L.L.L.", "...L..."],
    "pine": ["...L...", "..LLL..", ".LLLLL.", "..LLL..", ".LLLLL.", "LLLLLLL", "...L...", "...L..."],
    "aurora": ["LL.......", ".LLL...LL", "...LLLLL.", ".........", "LL.......", ".LLL...LL", "...LLLLL."],
}


def bottle_map(pid: str) -> tuple[list[str], dict]:
    """Letter map of an approved bottle: '#', 'c', 'h' fixed; liquid light 'B', liquid dark 'A' (by luminance)."""
    path = ROOT / f"assets/pixel_v1/potions/{pid}.png"
    data = np.array(Image.open(path).convert("RGBA"))
    liquids = sorted({hexs(p) for p in data[data[:, :, 3] == 255]} - set(FIXED), key=lambda c: -F26.luminance(rgb(c)))
    letters = dict(FIXED)
    if liquids:
        letters[liquids[0]] = "B"
    if len(liquids) > 1:
        letters[liquids[1]] = "A"
    rows = ["".join("." if data[y, x, 3] == 0 else letters[hexs(data[y, x])] for x in range(data.shape[1])) for y in range(data.shape[0])]
    return rows, {"path": rel(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "letters": {v: k for k, v in letters.items()}}


def derive_bottle(p: dict) -> tuple[list[str], dict]:
    rows, prov = [], []
    for pid, a, b in p["bottle_segments"]:
        src, info = bottle_map(pid)
        rows.extend(src[a:b])
        prov.append({"bottle": pid, "rows": [a, b - 1], "source": info["path"], "source_sha256": info["sha256"], "source_liquids": info["letters"]})
    grid = [list(r) for r in rows]
    for x, y, letter in p["edits"]:
        if grid[y][x] in ".#":
            raise SystemExit(f"{p['id']}: edit {x},{y} would change the silhouette/outline")
        grid[y][x] = letter
    rows = ["".join(r) for r in grid]
    return rows, {"segments": prov, "edits": [{"x": x, "y": y, "letter": l} for x, y, l in p["edits"]],
                  "edited_pixels": len(p["edits"]), "note": "실루엣·외곽선·코르크·유리 반짝임은 위 승인 병의 행 그대로. 액체 두 글자만 새 램프로."}


def read_map(path: Path) -> list[str]:
    rows = [line.rstrip("\r\n") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not rows or any(len(r) != len(rows[0]) for r in rows):
        raise SystemExit(f"Map rows must share one width: {rel(path)}")
    return rows


def verify_f26_map(name: str, folder: str) -> dict:
    """The F26 letter map must render exactly to the published approved asset."""
    rows = read_map(F26SRC / f"{name}.txt")
    pub = {"potions": "assets/content_expansion_v1/potions", "recipes": "assets/content_expansion_v1/recipes",
           "materials": "assets/content_expansion_v1/materials", "regions": "assets/content_expansion_v1/regions"}[folder]
    pid = name.rsplit("_", 1)[0]
    path = ROOT / pub / (f"{pid}_icon.png" if name.endswith("_icon") else f"{pid}_recipe.png")
    data = np.array(Image.open(path).convert("RGBA"))
    item = next(i for i in F26.assets() if i["id"] == name)
    rendered = np.array(F26.render(rows, item["legend"]))
    return {"map": rel(F26SRC / f"{name}.txt"), "published": rel(path), "published_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "map_renders_published_pixels": bool(np.array_equal(rendered, data)), "rows": rows, "legend": item["legend"]}


def stamp(grid: list[list[str]], pattern: list[str], cx: float, cy: float, inside: set[str]) -> int:
    h, w = len(pattern), len(pattern[0])
    x0, y0 = int(round(cx - w / 2)), int(round(cy - h / 2))
    count = 0
    for dy, line in enumerate(pattern):
        for dx, ch in enumerate(line):
            if ch == ".":
                continue
            if grid[y0 + dy][x0 + dx] not in inside:
                raise SystemExit(f"stamp leaves the body at {x0 + dx},{y0 + dy}")
            grid[y0 + dy][x0 + dx] = ch
            count += 1
    return count


def body_bbox(grid, letters) -> tuple[int, int, int, int]:
    pts = [(x, y) for y, r in enumerate(grid) for x, c in enumerate(r) if c in letters]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def derive_icon(p: dict) -> tuple[list[str], dict, dict]:
    base = verify_f26_map(p["icon_base"], "potions")
    grid = [list(r) for r in base["rows"]]
    light, dark = p["light"][0], p["dark"][0]
    changed = 0
    if p["id"] == "warmth":       # body D -> cream, sun L + crescent h cleared -> body, honey heart
        for y in range(15, 30):
            for x in range(32):
                if grid[y][x] in "Lh":
                    grid[y][x] = "D"
                    changed += 1
        changed += stamp(grid, STAMPS["heart"], 15.5 + 0.5, 23, {"D"})
        legend = {"#": ("#241C32", "outline", "outline"), "c": ("#916047", "wood", "cork"), "h": ("#FFF0BC", "gold", "glass_glint"),
                  "D": (light, p["light"][1], "liquid_light"), "L": (dark, p["dark"][1], "emblem")}
    elif p["id"] == "thin_ice":   # spiral h cleared, snowflake E
        for y in range(22, 31):
            for x in range(32):
                if grid[y][x] == "h":
                    grid[y][x] = "D"
                    changed += 1
        changed += stamp(grid, STAMPS["snowflake"], 16, 26, {"D"})
        legend = {"#": ("#241C32", "outline", "outline"), "c": ("#916047", "wood", "cork"), "h": ("#FFF0BC", "gold", "glass_and_frost"),
                  "L": ("#FFF0BC", "gold", "glass_and_frost"), "D": (light, p["light"][1], "liquid_light"), "E": (dark, p["dark"][1], "snowflake")}
    elif p["id"] == "pine_wind":  # first row of each light band -> snow
        for y in (18, 26, 34):
            for x in range(32):
                if grid[y][x] == "L":
                    grid[y][x] = "h"
                    changed += 1
        legend = {"#": ("#241C32", "outline", "outline"), "c": ("#916047", "wood", "cork"), "h": ("#FFF0BC", "gold", "glass_and_snow"),
                  "L": (light, p["light"][1], "needles_light"), "D": (dark, p["dark"][1], "needles_dark")}
    else:                         # aurora: flatten sun/horizon/right shade into body, two wavy light bands
        for y in range(len(grid)):
            for x in range(32):
                if grid[y][x] == "D":
                    grid[y][x] = "L"
                    changed += 1
        wave = [0, 0, 1, 1, 2, 2, 1, 1]
        for y0 in (21, 28):
            for x in range(32):
                for t in (0, 1):
                    y = y0 + wave[x % 8] + t
                    if grid[y][x] == "L" and grid[y][x - 1] != "#" and x + 1 < 32 and grid[y][x + 1] != "#":
                        grid[y][x] = "G"
                        changed += 1
        legend = {"#": ("#241C32", "outline", "outline"), "c": ("#916047", "wood", "cork"), "h": ("#FFF0BC", "gold", "glass_glint"),
                  "L": (dark, p["dark"][1], "liquid_body"), "G": (light, p["light"][1], "aurora_band")}
    rows = ["".join(r) for r in grid]
    used = {c for r in rows for c in r} - {"."}
    legend = {k: v for k, v in legend.items() if k in used}
    prov = {"base": base["map"], "base_published": base["published"], "base_published_sha256": base["published_sha256"],
            "base_map_renders_published_pixels": base["map_renders_published_pixels"],
            "silhouette_identical_to_base": [[c != "." for c in r] for r in rows] == [[c != "." for c in r] for r in base["rows"]],
            "letters_changed": changed}
    return rows, legend, prov


RECIPE_DISK = {"warmth": ("#C99463", "wood", "#F6D1AC", "skin", "heart_small"), "thin_ice": ("#9BE2CF", "teal", "#3BA8A3", "teal", "snowflake_small"),
               "pine_wind": ("#3D544D", "leaf", "#B5C77D", "leaf", "pine"), "aurora_elixir": ("#3BA8A3", "teal", "#B5C77D", "leaf", "aurora")}


def derive_recipe(p: dict) -> tuple[list[str], dict, dict]:
    base = verify_f26_map("sun_moon_elixir_recipe", "recipes")
    grid = [list(r) for r in base["rows"]]
    x0, y0, x1, y1 = body_bbox(grid, "D")
    cleared = 0
    for y in range(y0, y1 + 1):
        row = grid[y]
        ds = [x for x in range(32) if row[x] == "D"]
        for x in range(min(ds), max(ds) + 1):
            if row[x] in "Lh":
                row[x] = "D"
                cleared += 1
    disk, disk_ramp, motif, motif_ramp, stamp_name = RECIPE_DISK[p["id"]]
    pattern = [line.replace("E", "L") for line in STAMPS[stamp_name]]
    painted = stamp(grid, pattern, (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2, {"D"})
    rows = ["".join(r) for r in grid]
    legend = {"#": ("#241C32", "outline", "outline"), "h": ("#FFF0BC", "gold", "parchment"), "g": ("#E9B95F", "gold", "scroll_roll"),
              "D": (disk, disk_ramp, "seal"), "L": (motif, motif_ramp, "seal_motif")}
    prov = {"base": base["map"], "base_published": base["published"], "base_published_sha256": base["published_sha256"],
            "base_map_renders_published_pixels": base["map_renders_published_pixels"],
            "scroll_pixels_identical": all((a == b) or (a in "DLh" and b in "DL" and y0 <= y <= y1) for y, (ra, rb) in enumerate(zip(base["rows"], rows)) for a, b in zip(ra, rb)),
            "seal_motif_cleared": cleared, "seal_motif_painted": painted, "stamp": stamp_name}
    return rows, legend, prov


def derive_material() -> tuple[list[str], dict, dict]:
    base = verify_f26_map("dawn_bloom_icon", "materials")
    prov = {"base": base["map"], "base_published": base["published"], "base_published_sha256": base["published_sha256"],
            "base_map_renders_published_pixels": base["map_renders_published_pixels"], "letters_changed": 0,
            "recoloured_letters": {"L": ["#F4AC68", "#9BE2CF"], "D": ["#DE7356", "#3BA8A3"]}}
    return base["rows"], MATERIAL["remap"], prov


def derive_region() -> tuple[list[str], dict]:
    base = verify_f26_map("dawn_lighthouse_icon", "regions")
    W, H = 32, 40
    grid = [["."] * W for _ in range(H)]
    for y in range(29, 39):                       # approved ground rows, stone -> snow
        grid[y] = list(base["rows"][y])
    grid[28] = list("." + "#" * 18 + "." * 13)    # ground top edge (lighthouse rows 26..28 held the tower foot)
    # 3-tier pine: (row, x0, x1) incl. outline; tiers separated by a full outline row; snow on each tier top.
    tiers = [[(10, 8, 9), (11, 7, 10), (12, 6, 11), (13, 5, 12)], [(15, 5, 12), (16, 4, 13), (17, 3, 14)], [(19, 3, 14), (20, 2, 15), (21, 1, 16), (22, 1, 16)]]
    closes = [(14, 5, 12), (18, 3, 14), (23, 1, 16)]
    for t, rows in enumerate(tiers):
        for i, (y, a, b) in enumerate(rows):
            for x in range(a, b + 1):
                edge = x in (a, b) or (t == 0 and i == 0)
                if edge:
                    grid[y][x] = "#"
                elif i == 0 or (i == 1 and x <= a + 2):
                    grid[y][x] = "s"          # snow cap
                elif x == a + 1:
                    grid[y][x] = "G"          # lit needles on the left
                else:
                    grid[y][x] = "P"
    for y, a, b in closes:
        for x in range(a, b + 1):
            grid[y][x] = "#"
    for y in range(24, 28):                       # trunk
        grid[y][7], grid[y][8], grid[y][9], grid[y][10] = "#", "P", "P", "#"
    # aurora ribbon: wavy 3-row band, top row light, then auto outline (4-neighbour ring)
    # two parallel gentle arches (aurora bands), drawn top light / body teal; separated by an outline gap
    ribbon = set()
    for x in range(13, 31):
        yc = 7 - round(3 * math.sin((x - 13) / 17 * math.pi))
        for t in range(3):
            ribbon.add((x, yc + t, "G" if t == 0 else "A"))
    for x in range(18, 31):
        yc = 13 - round(2 * math.sin((x - 18) / 12 * math.pi))
        for t in range(2):
            ribbon.add((x, yc + t, "G" if t == 0 else "A"))
    for x, y, c in ribbon:
        grid[y][x] = c
    for x, y, _c in list(ribbon):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H and grid[ny][nx] == ".":
                grid[ny][nx] = "#"
    rows = ["".join(r) for r in grid]
    ground_same = all(rows[y] == base["rows"][y] for y in range(29, 39))
    prov = {"base": base["map"], "base_published": base["published"], "base_published_sha256": base["published_sha256"],
            "base_map_renders_published_pixels": base["map_renders_published_pixels"],
            "ground_rows_29_38_identical_letters": ground_same, "ground_recolour": {"s": ["#827589", "#FFF0BC"]},
            "new": "소나무(10~27행)·오로라 띠(4~17행)·땅 윗선(28행)은 새로 그림"}
    return rows, prov


# ---------------------------------------------------------------- items
def build_items() -> list[dict]:
    items = []
    for p in POTIONS:
        rows, prov = derive_bottle(p)
        legend = {"#": ("#241C32", "outline", "outline"), "c": ("#916047", "wood", "cork"), "h": ("#FFF0BC", "gold", "glass_glint"),
                  "B": (p["light"][0], p["light"][1], "liquid_light"), "A": (p["dark"][0], p["dark"][1], "liquid_dark")}
        items.append({"id": p["id"] + "_bottle", "potion": p["id"], "kind": "bottle", "name": p["name"] + " · 진열 병", "size": [8, 12],
                      "rows": rows, "legend": legend, "provenance": prov, "description": p["bottle"],
                      "compare": [s[0] for s in p["bottle_segments"]]})
        rows, legend, prov = derive_icon(p)
        items.append({"id": p["id"] + "_icon", "potion": p["id"], "kind": "icon", "name": p["name"] + " · 물약 아이콘", "size": [32, 40],
                      "rows": rows, "legend": legend, "provenance": prov, "description": p["icon"], "compare": [prov["base_published"]]})
        rows, legend, prov = derive_recipe(p)
        items.append({"id": p["id"] + "_recipe", "potion": p["id"], "kind": "recipe", "name": p["name"] + " · 레시피 아이콘", "size": [32, 40],
                      "rows": rows, "legend": legend, "provenance": prov, "description": p["recipe"], "compare": [prov["base_published"]]})
    rows, legend, prov = derive_material()
    items.append({"id": MATERIAL["id"], "kind": "material", "name": MATERIAL["name"], "size": [32, 40], "rows": rows, "legend": legend,
                  "provenance": prov, "description": MATERIAL["description"], "compare": [prov["base_published"]]})
    rows, prov = derive_region()
    items.append({"id": REGION["id"], "kind": "region", "name": REGION["name"], "size": [32, 40], "rows": rows, "legend": REGION["legend"],
                  "provenance": prov, "description": REGION["description"], "compare": [prov["base_published"], "assets/content_expansion_v1/regions/star_garden_icon.png"]})
    return items


def run_pipeline(items: list[dict]) -> dict:
    manifest = {"output": rel(PIPE), "palette": "art/palette.hex", "ramps": "art/ramps.json", "status": "candidate",
                "approved_by_user": False, "scale": SCALE, "alpha_threshold": 128, "max_colors": 5, "compose": False,
                "scene": {"size": [32, 40], "background": OUTLINE_HEX},
                "assets": [F26.manifest_entry(item, REG / f"{item['id']}.png") for item in items]}
    path = MOCK / "manifest.json"
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    result = subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"), rel(path)], cwd=ROOT,
                            capture_output=True, text=True, encoding="utf-8")
    report = json.loads((PIPE / "validation.json").read_text(encoding="utf-8"))
    if result.returncode != 0 or report["status"] != "passed":
        raise SystemExit(f"process_pixel_art failed: {report.get('error')}\n{result.stderr}")
    return report


# ---------------------------------------------------------------- pots / colours / silhouettes
def make_pots() -> dict:
    mask = {tuple(p) for p in CATALOG["liquid_pixels"]}
    base_liquid = CATALOG["potions"]["health"]["liquid_color"].upper()
    report = {"source_frames": [], "liquid_mask_pixels": len(mask), "potions": {}}
    frames = []
    for i in range(3):
        path = ROOT / f"assets/pixel_v1/pots/health-{i}.png"
        report["source_frames"].append({"path": rel(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        frames.append(np.array(Image.open(path).convert("RGBA")))
    body_colors = sorted({hexs(frames[0][y, x]) for y in range(32) for x in range(32) if frames[0][y, x, 3] == 255 and (x, y) not in mask})
    report["body_colors"] = body_colors
    outside = np.ones((32, 32), dtype=bool)
    for (x, y) in mask:
        outside[y, x] = False
    for p in POTIONS:
        entry = {"liquid": p["liquid"], "frames": [], "outside_mask_identical": True}
        for i, data in enumerate(frames):
            out = data.copy()
            changed = 0
            for (x, y) in mask:
                if out[y, x, 3] == 255 and hexs(out[y, x]) == base_liquid:
                    out[y, x, :3] = rgb(p["liquid"])
                    changed += 1
            entry["outside_mask_identical"] &= bool(np.array_equal(out[outside], data[outside]))
            Image.fromarray(out).save(POTS / f"{p['id']}-{i}.png")
            scaled(Image.fromarray(out), SCALE).save(POTS / f"{p['id']}-{i}-3x.png")
            scaled(Image.fromarray(out), BIG).save(POTS / f"{p['id']}-{i}-6x.png")
            entry["frames"].append({"path": rel(POTS / f"{p['id']}-{i}.png"), "recoloured_pixels": changed})
        entry["is_pot_body_color"] = p["liquid"] in body_colors
        entry["delta_e_to_pot"] = {c: delta_e(p["liquid"], c) for c in body_colors}
        entry["large_surface_gap_ok"] = all(entry["delta_e_to_pot"][c] >= 25 for c in ("#86548E", "#827589"))
        entry["passed"] = entry["outside_mask_identical"] and not entry["is_pot_body_color"] and entry["large_surface_gap_ok"]
        report["potions"][p["id"]] = entry
    return report


F26_IDS = ["sunrise", "beacon", "sea_spray", "sun_moon_elixir"]


def colour_report() -> dict:
    old = {pid: row["liquid_color"].upper() for pid, row in CATALOG["potions"].items()}
    rows = {}
    for p in POTIONS:
        others = {pid: delta_e(p["liquid"], c) for pid, c in old.items()}
        nearest = min(others, key=others.get)
        f26 = {pid: others[pid] for pid in F26_IDS}
        siblings = {q["id"]: delta_e(p["liquid"], q["liquid"]) for q in POTIONS if q["id"] != p["id"]}
        rows[p["id"]] = {"liquid": p["liquid"], "bottle_colors": [p["light"][0], p["dark"][0]],
                         "delta_e_to_pot_body_86548E": delta_e(p["liquid"], "#86548E"),
                         "delta_e_to_f26": f26, "min_delta_e_to_f26": min(f26.values()),
                         "same_as_existing_liquid": [pid for pid, c in old.items() if c == p["liquid"]],
                         "nearest_existing": {"id": nearest, "color": old[nearest], "delta_e": others[nearest]},
                         "delta_e_to_new_siblings": siblings}
    unused = sorted(set(PALETTE) - set(old.values()) - {"#241C32", "#916047"})
    passed = all(r["delta_e_to_pot_body_86548E"] >= 40 and r["min_delta_e_to_f26"] >= 25 and min(r["delta_e_to_new_siblings"].values()) >= 20 for r in rows.values())
    return {"existing_liquids": old, "new": rows, "passed": passed,
            "palette_colours_never_used_as_liquid": {c: {"to_body": delta_e(c, "#86548E"), "nearest_f26": min(delta_e(c, old[q]) for q in F26_IDS)} for c in unused},
            "rule": "새 액체는 솥 몸체 #86548E와 ΔE 40 이상, F26 4종과 25 이상, 새 4종끼리 20 이상(CIE76).",
            "note": "24색 중 아직 액체로 쓰지 않은 색(꿀빛 #C99463·장밋빛 #A65D64·그늘 잎 #3D544D·#4A3C52·#50333B·#50315F)은 F26 액체와 ΔE 12~18로 가깝거나"
                    " 외곽선·솥 몸체에 가까운 어두운 색이라 솥 안에서 '빈 솥/솥 색'으로 읽힌다. 그래서 초기 단계 물약이 쓰던 밝은 색을 다시 쓰고 병 모양으로 구분한다."}


def silhouette_report(sprites: dict) -> dict:
    existing = {pid: np.array(Image.open(ROOT / f"assets/pixel_v1/potions/{pid}.png").convert("RGBA"))[:, :, 3] == 255 for pid in CATALOG["potions"]}
    result = {}
    for p in POTIONS:
        mask = np.array(sprites[p["id"] + "_bottle"])[:, :, 3] == 255
        same = [pid for pid, m in existing.items() if m.shape == mask.shape and np.array_equal(m, mask)]
        diffs = sorted(((int(np.sum(m != mask)), pid) for pid, m in existing.items() if m.shape == mask.shape))
        result[p["id"]] = {"identical_silhouettes": same, "closest_same_size": [{"id": pid, "differing_pixels": d} for d, pid in diffs[:3]]}
    masks = {p["id"]: np.array(sprites[p["id"] + "_bottle"])[:, :, 3] == 255 for p in POTIONS}
    dup = [(a, b) for a in masks for b in masks if a < b and np.array_equal(masks[a], masks[b])]
    return {"bottles": result, "new_duplicates": dup, "passed": all(not r["identical_silhouettes"] for r in result.values()) and not dup}


# ---------------------------------------------------------------- growth sheet (64x80, out-of-rule exception like v2)
GROWTH_PLANT_REMAP = {"H": "#FFF0BC", "O": "#9BE2CF", "C": "#3BA8A3", "D": "#24566A", "h": "#FFF0BC", "g": "#FFF0BC", "G": "#9BE2CF"}
SNOW_EMBLEM = ["y..y..y", ".y.y.y.", "yyyyyyy", ".y.y.y.", "y..y..y"]


def crescent_cream() -> str:
    """Cream of the approved moonflower pot crescent (the emblem the v2 pot replaced), used for the snowflake."""
    frame = np.array(G2.frames_of(G2.sheet_of("moonflower"))[0])
    x0, y0, x1, y1 = G2.EMBLEM_BOX
    cream = [hexs(frame[y, x]) for y in range(y0, y1) for x in range(x0, x1) if frame[y, x, 3] and frame[y, x, :3].astype(int).sum() > 600]
    return max(set(cream), key=cream.count)    # most frequent crescent pixel colour (an existing pixel, not an average)


def build_growth() -> tuple[Image.Image, dict]:
    src = ROOT / "assets/content_expansion_v1/materials/dawn_bloom_growth.png"
    sheet = np.array(Image.open(src).convert("RGBA"))
    out = sheet.copy()
    v2src = ROOT / "art/mockups/f26-dawn-bloom-growth-v2/source"
    mismatches, recoloured = 0, 0
    snow = crescent_cream()
    for i in range(4):
        ox, oy = (i % 2) * 32, (i // 2) * 40
        for y, line in enumerate(G2.read_map(v2src / f"dawn_bloom_plant_{i}.txt", G2.FRAME)):
            for x, ch in enumerate(line):
                if ch == ".":
                    continue
                if hexs(sheet[oy + y, ox + x]) != G2.PLANT[ch][0]:
                    mismatches += 1
                if ch in GROWTH_PLANT_REMAP:
                    out[oy + y, ox + x, :3] = rgb(GROWTH_PLANT_REMAP[ch])
                    recoloured += 1
        old = G2.read_map(v2src / "dawn_bloom_emblem.txt", (7, 5))
        ex, ey = G2.EMBLEM_AT
        for dy in range(5):
            y = oy + ey + dy
            body = [sheet[y, ox + x, :3] for x in range(16, 22) if sheet[y, ox + x, 3] and sheet[y, ox + x, :3].astype(int).sum() < 400]
            fill = np.median(np.array(body), axis=0).astype(np.uint8)
            for dx in range(7):
                x = ox + ex + dx
                if old[dy][dx] != "." and hexs(sheet[y, x]) != G2.EMBLEM[old[dy][dx]][0]:
                    mismatches += 1
                if SNOW_EMBLEM[dy][dx] != ".":
                    out[y, x] = (*rgb(snow), 255)
                elif old[dy][dx] != ".":
                    out[y, x, :3] = fill
    changed = np.any(out != sheet, axis=2)
    prov = {"source": rel(src), "source_sha256": hashlib.sha256(src.read_bytes()).hexdigest(),
            "source_note": "사용자가 2026-11-05 '연결해줘'로 승인한 여명초 성장 그림 v2(달꽃 화분 픽셀 그대로 + 손으로 그린 식물)",
            "plant_letter_maps": [rel(v2src / f"dawn_bloom_plant_{i}.txt") for i in range(4)],
            "plant_letters_match_published": mismatches == 0, "recoloured_plant_pixels": recoloured,
            "plant_remap": {k: [G2.PLANT[k][0], v] for k, v in GROWTH_PLANT_REMAP.items()},
            "leaves_stem_unchanged": "잎·줄기 글자(a b c e t #)는 바꾸지 않음",
            "emblem": f"해돋이 문양 7×5 → 눈송이 7×5(같은 자리, 색은 달꽃 화분 초승달 문양에서 가장 많은 크림 픽셀 {snow}, 비는 칸은 v2처럼 행의 몸통 중앙값)",
            "changed_pixels": int(changed.sum())}
    return Image.fromarray(out), prov


def growth_checks(image: Image.Image) -> dict:
    data = np.array(image)
    alpha = data[:, :, 3]
    frames = G2.frames_of(image)
    base = G2.frames_of(Image.open(ROOT / "assets/content_expansion_v1/materials/dawn_bloom_growth.png").convert("RGBA"))
    same_alpha = all(np.array_equal(np.array(a)[:, :, 3], np.array(b)[:, :, 3]) for a, b in zip(frames, base))
    colors = sorted({hexs(p) for p in data[alpha > 0]})
    return {"size_64x80": list(image.size) == [64, 80], "partial_alpha_pixels": int(((alpha > 0) & (alpha < 255)).sum()),
            "silhouette_identical_to_approved_v2": same_alpha, "rgb_colors": len(colors),
            "off_palette_colors": sum(1 for c in colors if c not in PALETTE),
            "passed": list(image.size) == [64, 80] and int(((alpha > 0) & (alpha < 255)).sum()) == 0 and same_alpha,
            "rule_exception": "기존 성장 그림 11종(여명초 v2 포함)과 같은 규칙 밖 예외: 승인 24색·물체당 5색·#241C32 외곽선을 따르지 않는다(화분·잎은 승인 v2 픽셀 그대로)."}


# ---------------------------------------------------------------- boards
def font(size: int):
    return ImageFont.truetype(str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"), size)


BG = (0x30, 0x26, 0x3F, 255)


def compare_board(rows: list[tuple[str, list[tuple[str, Image.Image]]]], f: int, path: Path) -> str:
    """rows: (title, [(label, image)]) ; all images drawn at the same integer scale f, bottoms aligned."""
    pad, label_h = 10, 18
    cell_w = max(max(img.width * f, 150) for _t, row in rows for _l, img in row) + 2 * pad
    heights = [max(img.height for _l, img in row) * f + label_h + pad for _t, row in rows]
    width = max(len(row) for _t, row in rows) * cell_w + pad
    board = Image.new("RGBA", (width, sum(h + 22 for h in heights) + pad), BG)
    draw = ImageDraw.Draw(board)
    y = 4
    for (title, row), cell_h in zip(rows, heights):
        draw.text((pad, y), title, font=font(13), fill="#FFF0BC")
        for c, (label, img) in enumerate(row):
            x = pad + c * cell_w
            big = scaled(img, f)
            top = y + 20 + (cell_h - label_h - pad) - big.height
            board.alpha_composite(big, (x + (cell_w - 2 * pad - big.width) // 2, top))
            draw.text((x, y + 20 + cell_h - label_h - 4), label, font=font(11), fill="#C38EB5")
        y += cell_h + 22
    board.save(path)
    return rel(path)


def shelf_and_cauldron(sprites: dict) -> dict:
    frame = Image.open(ROOT / "art/mockups/full-ingame-v4/potions/shelf_frame-native.png").convert("RGBA")
    centers, boards = [8, 18, 28, 38], {1: 22, 2: 43}
    out = {"frame": "art/mockups/full-ingame-v4/potions/shelf_frame-native.png", "layouts": {}}
    layouts = {"new4_over_f26": [p["id"] for p in POTIONS] + F26_IDS,
               "mixed": ["warmth", "sunrise", "thin_ice", "beacon", "pine_wind", "antidote", "aurora_elixir", "mana"]}
    new_ids = {p["id"] for p in POTIONS}
    for name, ids in layouts.items():
        scene = frame.copy()
        placed = []
        for index, pid in enumerate(ids):
            image = sprites[pid + "_bottle"] if pid in new_ids else Image.open(ROOT / f"assets/pixel_v1/potions/{pid}.png").convert("RGBA")
            row = 1 if index < 4 else 2
            x, y = centers[index % 4] - image.width // 2, boards[row] - image.height
            scene.alpha_composite(image, (x, y))
            placed.append({"id": pid, "origin": [x, y]})
        scene.save(COMPARE / f"shelf-{name}-native.png")
        scaled(scene, BIG).save(COMPARE / f"shelf-{name}-6x.png")
        out["layouts"][name] = placed
    # workshop strip: approved shelf + hearth fire + cauldron (pot frame 1) for each new liquid, next to F26 and the base pot.
    fire = Image.open(ROOT / "assets/pixel_v1/fire/0.png").convert("RGBA")
    pots = [("health", "기존 솥(체력)")] + [(q, q) for q in F26_IDS] + [(p["id"], p["short"] + " (새)") for p in POTIONS]
    # Offsets from scripts/workshop_layout.gd: pot Rect2(123,144), hearth Rect2(153,213) at 3x -> fire at pot + (10, 23) native.
    strip = Image.new("RGBA", (len(pots) * 36 + 4, 40), (0, 0, 0, 0))
    for i, (pid, _label) in enumerate(pots):
        path = POTS / f"{pid}-1.png" if pid in new_ids else ROOT / f"assets/pixel_v1/pots/{pid}-1.png"
        pot = Image.open(path).convert("RGBA")
        x = 4 + i * 36
        strip.alpha_composite(fire, (x + 10, 4 + 23))
        strip.alpha_composite(pot, (x, 4))
    strip.save(COMPARE / "cauldrons-native.png")
    scaled(strip, BIG).save(COMPARE / "cauldrons-6x.png")
    out["cauldrons"] = {"order": [p for p, _l in pots], "image": rel(COMPARE / "cauldrons-6x.png"),
                        "note": "불(assets/pixel_v1/fire/0.png)은 workshop_layout.gd의 화덕 위치(솥 원점 +10,+23, 원본 픽셀)에 솥보다 먼저 그린 검토용 합성. 게임 화면 캡처가 아니며 솥 앞 장식(cauldron_foreground)은 넣지 않았다."}
    return out


def page(items, checks, pots, colours, silhouettes, shelf, growth, gchecks, boards) -> str:
    def img(path: str, cls: str = "") -> str:
        return f'<img src="{Path(path).relative_to(rel(MOCK)).as_posix()}" class="{cls}" alt="">'

    def sw(color: str, label: str = "") -> str:
        return f'<span><i style="--c:{color}"></i>{color}{(" " + label) if label else ""}</span>'

    by_id = {i["id"]: i for i in items}
    cards = []
    for p in POTIONS:
        pid = p["id"]
        c = colours["new"][pid]
        pot = pots["potions"][pid]
        ok = all(checks[pid + k]["passed"] for k in ("_bottle", "_icon", "_recipe")) and pot["passed"]
        segs = " + ".join(f"<code>{s['bottle']}</code> {s['rows'][0]}~{s['rows'][1]}행" for s in by_id[pid + "_bottle"]["provenance"]["segments"])
        cards.append(f"""
<div class="card"><h3>{p['name']} <small>· {p['family_ko']} 계열 · {p['customer']} 선호</small></h3>
<p class="desc"><b>병</b> {p['bottle']}<br><b>아이콘</b> {p['icon']}<br><b>레시피</b> {p['recipe']}</p>
<div class="wide">{img(boards[pid])}</div>
<div class="sw">{sw(p['light'][0], '밝은 액체')}{sw(p['dark'][0], '어두운 액체')}<span>· 솥 액체 <b>{p['liquid']}</b></span></div>
<p class="desc">병 출처: {segs} · 손으로 바꾼 픽셀 {by_id[pid + '_bottle']['provenance']['edited_pixels']}개 ·
솥 몸체 #86548E와 ΔE <b>{c['delta_e_to_pot_body_86548E']}</b> · F26 4종과 최소 ΔE <b>{c['min_delta_e_to_f26']}</b> ·
같은 액체색 기존 물약 {', '.join(c['same_as_existing_liquid']) or '없음'} · 검사 <b class="{'ok' if ok else 'bad'}">{'통과' if ok else '실패'}</b></p>
</div>""")
    extra = []
    for key in (MATERIAL["id"], REGION["id"]):
        item = by_id[key]
        extra.append(f"""<div class="card"><h3>{item['name']}</h3><p class="desc">{item['description']}</p>
<div class="wide">{img(boards[key])}</div><div class="sw">{''.join(sw(v[0], v[2]) for v in item['legend'].values())}</div>
<p class="desc">검사 <b class="{'ok' if checks[key]['passed'] else 'bad'}">{'통과' if checks[key]['passed'] else '실패'}</b></p></div>""")
    colour_rows = "".join(
        f"<tr><td>{p['name']}</td><td>{sw(p['liquid'])}</td><td>{colours['new'][p['id']]['delta_e_to_pot_body_86548E']}</td>"
        f"<td>{', '.join(f'{k} {v}' for k, v in colours['new'][p['id']]['delta_e_to_f26'].items())}</td>"
        f"<td>{', '.join(colours['new'][p['id']]['same_as_existing_liquid']) or '–'}</td>"
        f"<td>{', '.join(f'{k} {v}' for k, v in colours['new'][p['id']]['delta_e_to_new_siblings'].items())}</td></tr>" for p in POTIONS)
    unused = "".join(f"<li>{sw(c)} 솥 몸체와 ΔE {v['to_body']} · F26과 최소 ΔE {v['nearest_f26']}</li>" for c, v in colours["palette_colours_never_used_as_liquid"].items())
    sil = "".join(f"<li><b>{p['short']}</b>: 같은 실루엣 기존 병 {len(silhouettes['bottles'][p['id']]['identical_silhouettes'])}개 · 가장 가까운 병 "
                  + ", ".join(f"{d['id']}({d['differing_pixels']}픽셀 다름)" for d in silhouettes["bottles"][p["id"]]["closest_same_size"]) + "</li>" for p in POTIONS)
    status = "통과" if all(c["passed"] for c in checks.values()) and all(v["passed"] for v in pots["potions"].values()) and colours["passed"] and silhouettes["passed"] and gchecks["passed"] else "실패"
    return f"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>오로라 설원 후보</title><style>
@font-face{{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}}
:root{{--bg:#241c32;--panel:#30263f;--text:#fff0bc;--muted:#c38eb5;--accent:#e9b95f;--ok:#b5c77d;--bad:#de7356}}
*{{box-sizing:border-box}}html,body{{background:var(--bg)}}body{{margin:0;color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}}
main{{max-width:1240px;margin:auto;padding:18px 16px 48px}}h1{{font-size:23px;margin:0 0 6px}}h2{{font-size:17px;margin:30px 0 8px}}h3{{font-size:15px;margin:0}}h3 small{{color:var(--muted);font-weight:normal}}
p{{margin:6px 0 10px}}.muted{{color:var(--muted)}}.ok{{color:var(--ok)}}.bad{{color:var(--bad)}}code{{font-size:12px}}
.note{{border-left:3px solid #718c59;padding:8px 12px;background:var(--panel);margin:10px 0}}.warn{{border-left-color:var(--accent)}}
img{{image-rendering:pixelated;image-rendering:crisp-edges;max-width:none;display:block}}
.card{{background:var(--panel);border:1px solid #4a3c52;border-radius:6px;padding:12px;margin:12px 0}}
.wide{{overflow-x:auto;padding:4px 0}}.desc{{font-size:13px;margin:6px 0}}
.sw{{display:flex;flex-wrap:wrap;gap:8px 14px;font-size:11px;color:var(--muted)}}.sw span{{display:flex;align-items:center;gap:4px}}
.sw i{{width:12px;height:12px;display:inline-block;border:1px solid #000;background:var(--c)}}
.check{{background-color:#4a3c52;background-image:linear-gradient(45deg,#3f3347 25%,transparent 25%),linear-gradient(-45deg,#3f3347 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#3f3347 75%),linear-gradient(-45deg,transparent 75%,#3f3347 75%);background-size:12px 12px;background-position:0 0,0 6px,6px -6px,-6px 0;display:inline-block;padding:6px}}
.row{{display:flex;flex-wrap:wrap;gap:14px;align-items:flex-end}}.row figure{{margin:0}}figcaption{{font-size:11px;color:var(--muted);margin-top:3px}}
table{{border-collapse:collapse;font-size:13px;width:100%}}td,th{{border-bottom:1px solid #4a3c52;padding:5px 6px;text-align:left;vertical-align:top}}
ul{{padding-left:20px}}li{{margin:3px 0}}
</style></head><body><main>
<h1>10번째 원정 지역 「오로라 설원」 · 새 재료 서리꽃 · 새 물약 4종 아트 후보 v1</h1>
<p class="muted">{DATE} · 상태 <b>후보(candidate)</b> · 게임 미연결 · 승인 전 · 기획 <code>docs/새-원정-지역과-물약-F27-기획안.md</code> · 검사 <b class="{'ok' if status == '통과' else 'bad'}">{status}</b></p>
<div class="note"><b>이번 후보를 만든 방식:</b> 손으로 새로 그리지 않고 <b>이미 승인된 그림의 픽셀을 그대로 가져와 필요한 부분만 바꿨다.</b>
진열 병은 승인된 병들의 행을 이어 붙여 새 실루엣을 만들고(모든 행이 승인 병에 있는 행) 액체 두 색만 바꿨다. 솥은 승인 솥의 액체 63픽셀만 다시 칠했다.
32×40 아이콘은 승인된 F26 아이콘을 그대로 두고 색과 가운데 문양만 바꿨다. 성장 그림은 승인된 여명초 v2 시트에서 꽃잎 색과 화분 문양만 바꿨다.
아래 각 그림 옆에 출처가 된 승인 그림을 <b>같은 6배</b>로 놓았다. 체크무늬는 CSS 배경이다.</div>
<div class="note warn"><b>솥 액체색:</b> 솥 몸체 #86548E와 같은 색은 버그처럼 보인다는 지적에 따라 네 액체 모두 몸체와 ΔE 67 이상, F26 4종과 ΔE 26.9 이상으로 골랐다.
24색 중 아직 액체로 안 쓴 색은 F26과 너무 가깝거나 솥 안에서 어둡게 묻혀 쓰지 않았다(아래 6절). 그래서 초기 단계 물약이 쓰던 밝은 색을 다시 쓴다 — 결정 필요.</div>

<h2>1. 새 물약 4종 · 출처 승인 그림과 나란히 (6배)</h2>
{''.join(cards)}

<h2>2. 진열장 · 솥 합성</h2>
<p class="desc">승인 선반(v4 48×48) 위: 윗칸 새 4종, 아랫칸 F26 4종 / 섞어서 진열. 6배.</p>
<div class="row"><figure><div class="check">{img(rel(COMPARE / 'shelf-new4_over_f26-6x.png'))}</div><figcaption>윗칸 온기·살얼음·솔바람·오로라 · 아랫칸 해돋이·등대불·물보라·일월</figcaption></figure>
<figure><div class="check">{img(rel(COMPARE / 'shelf-mixed-6x.png'))}</div><figcaption>온기·해돋이·살얼음·등대불 / 솔바람·해독·오로라·마나</figcaption></figure></div>
<p class="desc">솥 + 화덕 불(검토용 근사 배치, 6배): 기존 체력 솥 · F26 4종 · 새 4종.</p>
<div class="wide"><div class="check">{img(shelf['cauldrons']['image'])}</div></div>

<h2>3. 재료·지역 아이콘 (6배)</h2>
{''.join(extra)}

<h2>4. 서리꽃 화분 성장 그림 64×80</h2>
<p class="desc">{growth['source_note']}를 그대로 복사하고, v2의 식물 글자 지도로 꽃잎 픽셀만 골라 다시 칠했다(잎·줄기·화분·반짝임은 그대로). 화분 앞 해돋이 문양은 같은 자리·같은 금빛의 눈송이로 바꿨다.
바뀐 픽셀 {growth['changed_pixels']}개 · 실루엣 v2와 동일 {'예' if gchecks['silhouette_identical_to_approved_v2'] else '아니오'} · 반투명 {gchecks['partial_alpha_pixels']}개 · 색 {gchecks['rgb_colors']}개(기존 성장 그림과 같은 규칙 밖 예외).</p>
<div class="wide">{img(boards['growth'])}</div>

<h2>5. 진열 병 실루엣</h2>
<ul class="desc">{sil}</ul>

<h2>6. 색 거리 (CIE76 ΔE)</h2>
<div class="wide"><table><tr><th>물약</th><th>솥 액체</th><th>솥 몸체 #86548E</th><th>F26 4종</th><th>같은 색을 쓰는 기존 물약</th><th>새 4종끼리</th></tr>{colour_rows}</table></div>
<p class="desc">아직 액체로 쓰지 않은 팔레트 색(쓰지 않은 이유):</p><ul class="desc">{unused}</ul>

<h2>7. 스스로 본 판단 · 결정 필요</h2>
<ul class="desc">
<li>병은 모두 승인 병의 행을 이어 붙였으므로 선반에서 기존 병과 같은 그림체로 보인다. 대신 실루엣 차이가 작다(가장 가까운 기존 병과 {min(silhouettes['bottles'][p['id']]['closest_same_size'][0]['differing_pixels'] for p in POTIONS)}~{max(silhouettes['bottles'][p['id']]['closest_same_size'][0]['differing_pixels'] for p in POTIONS)}픽셀 차이, 위 5절). 색과 함께 보면 구분되지만 실루엣만으로는 약하다. 특히 살얼음은 F26 물보라와 같은 '아래로 뾰족한' 계열이고, 오로라는 마나와 같은 종 모양 청록 계열이다. 온기와 살얼음은 둘 다 `vigor`의 윗부분(0~7행)을 쓴다.</li>
<li>32×40 아이콘 4종은 F26 아이콘과 실루엣이 같다(색·문양만 다름). 관리 화면 레시피 목록에서 해돋이↔오로라, 등대불↔솔바람, 물보라↔살얼음, 일월↔온기가 같은 모양으로 나란히 보인다. 그대로 둘지, 실루엣을 조금 바꾼 v2를 만들지 결정 필요.</li>
<li>서리꽃 재료 아이콘과 성장 그림은 여명초와 모양이 같고 꽃잎 색만 다르다.</li>
<li>지역 아이콘의 소나무·오로라 띠는 새로 그린 부분이다(땅만 승인 픽셀). 이 아이콘이 가장 '새 그림'에 가깝다.</li>
<li>살얼음(얼음 민트 #9BE2CF)과 오로라(청록 #3BA8A3)는 ΔE 24.2로 새 4종 중 가장 가깝다. 솥에서 둘 다 청록 계열로 보일 수 있다.</li>
</ul>
<p class="muted">검사 결과: <code>validation.json</code> · 후처리 원본 보고: <code>pipeline/validation.json</code> · 승인 상태: <code>approval.json</code> · 재현: <code>tools/build_f27_region_potions_v1.py</code></p>
</main></body></html>
"""


def boards_for(items, sprites, growth_img) -> dict:
    out = {}
    for p in POTIONS:
        pid = p["id"]
        bottle = sprites[pid + "_bottle"]
        srcs = [(s, Image.open(ROOT / f"assets/pixel_v1/potions/{s}.png").convert("RGBA")) for s in dict.fromkeys(x[0] for x in p["bottle_segments"])]
        icon_base = next(i for i in items if i["id"] == pid + "_icon")["provenance"]["base_published"]
        rec_base = next(i for i in items if i["id"] == pid + "_recipe")["provenance"]["base_published"]
        pot = Image.open(POTS / f"{pid}-1.png").convert("RGBA")
        rows = [("진열 병 8×12 (새 ★ / 출처 승인 병)", [("★ " + p["short"], bottle)] + [(f"출처 {s}", im) for s, im in srcs]),
                ("솥 32×32 (새 ★ / 출처 승인 솥)", [("★ " + p["short"] + " 솥 1", pot), ("출처 health 솥 1", Image.open(ROOT / "assets/pixel_v1/pots/health-1.png").convert("RGBA"))]),
                ("32×40 물약·레시피 아이콘 (새 ★ / 출처 승인 F26 아이콘)", [("★ 물약", sprites[pid + "_icon"]), ("출처 " + Path(icon_base).stem, Image.open(ROOT / icon_base).convert("RGBA")),
                                                                ("★ 레시피", sprites[pid + "_recipe"]), ("출처 " + Path(rec_base).stem, Image.open(ROOT / rec_base).convert("RGBA"))])]
        out[pid] = compare_board(rows, BIG, COMPARE / f"{pid}-compare-6x.png")
    for key in (MATERIAL["id"], REGION["id"]):
        item = next(i for i in items if i["id"] == key)
        row = [("★ 새", sprites[key])] + [("출처/비교 " + Path(c).stem, Image.open(ROOT / c).convert("RGBA")) for c in item["compare"]]
        out[key] = compare_board([(item["name"] + " 32×40", row)], BIG, COMPARE / f"{key}-compare-6x.png")
    base = Image.open(ROOT / "assets/content_expansion_v1/materials/dawn_bloom_growth.png").convert("RGBA")
    moon = Image.open(ROOT / "assets/content_expansion_v1/materials/moonflower_growth.png").convert("RGBA")
    rows = [("서리꽃 (새 ★)", [(f"★ 칸 {i}", f) for i, f in enumerate(G2.frames_of(growth_img))]),
            ("여명초 v2 (출처, 승인)", [(f"칸 {i}", f) for i, f in enumerate(G2.frames_of(base))]),
            ("달꽃 (기존)", [(f"칸 {i}", f) for i, f in enumerate(G2.frames_of(moon))])]
    out["growth"] = compare_board(rows, BIG, COMPARE / "frost_flower_growth-compare-6x.png")
    return out


def main() -> int:
    for folder in (REG, SPRITES, POTS, COMPARE, GROWTH, SRC):
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
    items = build_items()
    registered = {}
    for item in items:
        (SRC / f"{item['id']}.txt").write_text("\n".join(item["rows"]) + "\n", encoding="utf-8")
        if [len(item["rows"][0]), len(item["rows"])] != list(item["size"]):
            raise SystemExit(f"{item['id']}: map size {len(item['rows'][0])}x{len(item['rows'])}")
        image = F26.render(item["rows"], item["legend"])
        image.save(REG / f"{item['id']}.png")
        registered[item["id"]] = image
    pipe = run_pipeline(items)
    checks, sprites = {}, {}
    for item in items:
        image = Image.open(PIPE / f"{item['id']}-native.png").convert("RGBA")
        sprites[item["id"]] = image
        image.save(SPRITES / f"{item['id']}.png")
        scaled(image, SCALE).save(SPRITES / f"{item['id']}-3x.png")
        scaled(image, BIG).save(SPRITES / f"{item['id']}-6x.png")
        check = F26.check_sprite(item, image, registered[item["id"]], pipe["assets"][item["id"]])
        check["source"] = rel(SRC / f"{item['id']}.txt")
        check["description"] = item["description"]
        check["provenance"] = item["provenance"]
        if "base_map_renders_published_pixels" in item["provenance"]:
            check["passed"] = check["passed"] and item["provenance"]["base_map_renders_published_pixels"]
        checks[item["id"]] = check
    pots = make_pots()
    colours = colour_report()
    silhouettes = silhouette_report(sprites)
    shelf = shelf_and_cauldron(sprites)
    growth_img, growth = build_growth()
    growth_img.save(GROWTH / "frost_flower_growth.png")
    scaled(growth_img, SCALE).save(GROWTH / "frost_flower_growth-3x.png")
    scaled(growth_img, BIG).save(GROWTH / "frost_flower_growth-6x.png")
    gchecks = growth_checks(growth_img)
    gchecks["passed"] = gchecks["passed"] and growth["plant_letters_match_published"]
    boards = boards_for(items, sprites, growth_img)
    passed = all(c["passed"] for c in checks.values()) and all(p["passed"] for p in pots["potions"].values()) \
        and colours["passed"] and silhouettes["passed"] and gchecks["passed"]
    validation = {"schema_version": 1, "date": DATE, "status": "passed" if passed else "failed", "art_status": "candidate",
                  "approved_by_user": False, "scale": SCALE, "review_scale": BIG, "palette": "art/palette.hex (approved 24)",
                  "pipeline": {"tool": "tools/process_pixel_art.py", "manifest": rel(MOCK / "manifest.json"),
                               "report": rel(PIPE / "validation.json"), "status": pipe["status"], "stage_order": pipe["stage_order"]},
                  "derivation_rule": "모든 그림은 승인된 그림의 픽셀에서 파생(병: 승인 병 행 이어 붙이기 + 액체 글자 재색, 솥: 액체 마스크만, 아이콘: F26 승인 아이콘 + 문양 교체, 성장: 여명초 v2 + 꽃잎 재색·문양 교체). provenance에 출처 파일 해시를 기록.",
                  "sprites": checks, "pots": pots, "liquid_colours": colours, "silhouettes": silhouettes, "shelf_and_cauldron": shelf,
                  "growth": {"image": rel(GROWTH / "frost_flower_growth.png"), "provenance": growth, "checks": gchecks,
                             "native_sha256": hashlib.sha256(np.array(growth_img).tobytes()).hexdigest()},
                  "boards": boards, "scope_note": "후보 검사. assets/·scripts/·data/는 쓰지 않았다."}
    (MOCK / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    approval = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "approved_on": None, "user_reply": None,
        "date": DATE, "review": rel(MOCK / "review.html"), "plan": "docs/새-원정-지역과-물약-F27-기획안.md", "runtime_integrated": False,
        "scope": {
            **{f"{p['id']}_bottle": f"{p['name']} 진열 병 8×12 (후보, 승인 병 행 파생)" for p in POTIONS},
            **{f"{p['id']}_pot": f"{p['name']} 솥 액체 {p['liquid']} · 승인 솥 3프레임의 액체 마스크만 재색 (후보)" for p in POTIONS},
            **{f"{p['id']}_icon": f"{p['name']} 물약 아이콘 32×40 (후보, F26 아이콘 파생)" for p in POTIONS},
            **{f"{p['id']}_recipe": f"{p['name']} 레시피 아이콘 32×40 (후보, F26 레시피 두루마리 파생)" for p in POTIONS},
            "frost_flower_icon": "서리꽃 재료 아이콘 32×40 (후보, 여명초 아이콘 재색)",
            "aurora_snowfield_icon": "오로라 설원 지역 아이콘 32×40 (후보, 새벽 등대 땅 + 새 소나무·오로라)",
            "frost_flower_growth": "서리꽃 화분 성장 그림 64×80 (후보, 여명초 v2 꽃잎 재색·문양 교체, 기존 성장 그림과 같은 규칙 밖 예외)",
        },
        "not_in_scope": ["원정 카드 큰 그림", "게임 연결(assets/·catalog·scripts·data)"],
        "pending_decisions": ["이름 6개", "액체색 4종(초기 물약 색 재사용)", "병 실루엣(승인 병 행 파생, 차이 작음)",
                              "32×40 아이콘이 F26 아이콘과 같은 실루엣인 점", "서리꽃 아이콘·성장 그림이 여명초 재색인 점", "지역 아이콘의 새로 그린 소나무·오로라"],
        "publish_after_approval": "추가 전용 게시 스크립트(F26과 같은 방식)로 assets/pixel_v1/potions·pots, content_expansion_v1 아이콘·성장 그림, catalog 행만 더한다(기존 자산 재생성 금지).",
    }
    (MOCK / "approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (MOCK / "review.html").write_text(page(items, checks, pots, colours, silhouettes, shelf, growth, gchecks, boards), encoding="utf-8")
    print(json.dumps({"status": validation["status"], "sprites": {k: v["passed"] for k, v in checks.items()},
                      "pots": {k: v["passed"] for k, v in pots["potions"].items()}, "colours": colours["passed"],
                      "silhouettes": silhouettes["passed"], "growth": gchecks}, ensure_ascii=False, indent=1))
    if not passed:
        for k, v in checks.items():
            if not v["passed"]:
                print("FAILED", k, {kk: v[kk] for kk in ("color_count", "off_palette_colors", "outline_violations", "dither_3x3_blocks", "lighting", "pipeline_preserved_source", "shades_per_ramp")})
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
