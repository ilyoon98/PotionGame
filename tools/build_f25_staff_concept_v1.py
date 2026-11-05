"""F25 staff (직원 4명) concept candidates + workshop layout options A/B/C (+ D baseline) + workload estimate.

Candidate only. Reads hand-authored 32x48 native pixel maps (art/mockups/f25-staff-concept-v1/source/*.txt, one
waiting pose per employee in data/content_expansion.json), registers them as native PNGs, runs the fixed
tools/process_pixel_art.py pipeline with an explicit per-color material manifest, then adds character checks
(32x48, colors <= 5, approved palette and ramps, partial alpha, outline, two 1x2 eyes with a 1-pixel skin margin,
body rows, feet row 46, dithering) and distinctness checks against the approved keeper and four customers
(silhouette IoU, shared colors).

Layouts are measured in the real 540x249 workshop art area (native 180x83 x3). Occupancy is reused, not re-derived:
tools/build_f23_decor_v1.py is imported and its build_masks() (keeper poses / Zs / stars / spoon, customer walk /
wait / receive / carry, sale and stock bottle paths, HUD panels, furniture, aging cask) is called unchanged. The
approved counter props (native 96,40) and the approved workshop souvenir minis (native 14,0) are added as obstacles.

  A  one hired employee at a time (rotation) at one shared floor spot, drawn in front of furniture
  B  workshop widened to the left; all four stand in a new strip (front row + back row)
  C  all four near their own equipment, drawn behind floor furniture (herb station / cauldron / counter)
  D  no workshop figure; portrait in the management employee row only (baseline)

Nothing under assets/ or scripts/ is written. Player saves, the running game and Windows registration are untouched.

Run with Pillow + NumPy: python tools/build_f25_staff_concept_v1.py
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
MOCK = ROOT / "art/mockups/f25-staff-concept-v1"
SRC = MOCK / "source"
PIPE = MOCK / "pipeline"
SPRITES = MOCK / "sprites"
LAYOUT_DIR = MOCK / "layouts"
SCALE = 3
SIZE = (32, 48)
OUTLINE_HEX = "#241C32"
OUTLINE = (0x24, 0x1C, 0x32)
DATE = "2026-11-05"
FLOOR_ORIGIN_Y = 32  # native; same as the keeper and the customers, feet row 46 -> native row 78
EYES = {"x": [13, 18], "y": [22, 23]}

_spec = importlib.util.spec_from_file_location("build_f23_decor_v1", ROOT / "tools/build_f23_decor_v1.py")
decor = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(decor)
W, H = decor.W, decor.H
FORBIDDEN = decor.FORBIDDEN  # keeper, customers, sale_bottle, stock_bottles, hud
FURNITURE = ["weather_glass", "window", "herb", "poster", "shelf", "counter", "aging_cask", "cauldron", "fire", "floor"]
FLOOR_FURNITURE = ["herb", "counter", "cauldron", "fire"]  # drawn above "behind" staff in layout C

# Map letter -> (approved color, ramp). Every color is one of the approved 24.
LEGEND = {
    "#": ("#241C32", "outline"),
    "s": ("#F6D1AC", "skin"), "S": ("#DE9B88", "skin"), "r": ("#A65D64", "skin"),
    "c": ("#FFF0BC", "gold"), "g": ("#E9B95F", "gold"), "a": ("#A56A3D", "gold"),
    "w": ("#50333B", "wood"), "o": ("#C99463", "wood"),
    "L": ("#3D544D", "leaf"), "m": ("#827589", "stone"), "R": ("#9D4359", "fire"),
    "t": ("#9BE2CF", "teal"), "T": ("#24566A", "teal"),
}

STAFF = [
    {"id": "staff_sales_assistant", "employee": "sales_assistant", "name": "판매 보조", "concept": "단정한 앞치마 점원",
     "skin": "s", "short": "sales", "attachments": [[12, 5, 20, 11]],
     "summary": "판매대를 지키는 점원. 위로 올려 묶은 동그란 머리(크림 리본)와 장밋빛 원피스, 무릎까지 오는 크림색 앞치마. "
                "관리 화면의 판매 보조 아이콘(상점 앞치마)과 같은 소재를 몸에 입혔다.",
     "silhouette": "정수리 위 동그란 올림머리 + 아래로 퍼지는 A라인 치마. 모자·망토·꼬리·소품 없이 머리 위 작은 혹 하나로 읽힌다.",
     "pose": "양팔을 옆에 내린 대기. 손님 쪽 행동 후보는 가벼운 인사(허리 숙이기)·손 흔들기.",
     "distinct": "주인공(뾰족 모자·보라 망토)·여마법사(보라 모자·긴 머리)와 달리 모자가 없고, 여행자(크림 셔츠·배낭)와 달리 "
                 "장밋빛 치마가 주색이다. 크림색은 앞치마에만 써서 여행자와 면적이 다르다.",
     "materials": {"#": "outline", "s": "skin", "r": "dress_and_blush", "c": "apron_ribbon_cuffs", "w": "hair_and_shoes"}},
    {"id": "staff_cultivation_assistant", "employee": "cultivation_assistant", "name": "재배 보조", "concept": "밀짚모자 정원사",
     "skin": "S", "short": "cultivation", "attachments": [[2, 4, 30, 15], [26, 33, 31, 41]],
     "summary": "약초대를 돌보는 정원사 소년. 챙이 넓은 납작한 밀짚모자(꼭대기에 새싹 하나), 노란 셔츠에 짙은 초록 멜빵 작업복, "
                "구리 물뿌리개. 햇볕에 그을린 피부(복숭아 피부 램프의 중간 단)와 주근깨.",
     "silhouette": "머리보다 넓은 28픽셀 평평한 챙(뾰족 모자와 반대 형태) + 오른손 아래로 튀어나온 물뿌리개 주둥이.",
     "pose": "물뿌리개를 든 대기. 행동 후보는 약초대에 물 주기(기울이기 2장).",
     "distinct": "엘프의 밝은 잎 초록(#718C59·#B5C77D) 대신 그늘 잎(#3D544D)만 쓰고, 금빛 모자는 주인공 모자 장식보다 훨씬 넓은 면적이다. "
                 "4명 중 유일하게 다른 피부 단(#DE9B88)이다.",
     "materials": {"#": "outline", "S": "skin_tan", "g": "straw_hat_shirt", "a": "hair_boots_can_copper", "L": "overalls_sprout"}},
    {"id": "staff_brewing_assistant", "employee": "brewing_assistant", "name": "조제 보조", "concept": "고글 견습 조제사",
     "skin": "s", "short": "brewing", "attachments": [[26, 18, 30, 26], [21, 36, 28, 41]],
     "summary": "솥 옆에서 일하는 견습 조제사. 이마에 올린 둥근 고글(민트 렌즈), 짧은 와인색 머리와 옆으로 뻗은 꽁지머리, "
                "회색 조제 가운(가슴 주머니의 민트 시험관), 오른손의 둥근 민트 물약 플라스크.",
     "silhouette": "머리 오른쪽으로 뻗은 꽁지머리 + 무릎까지 곧게 떨어지는 가운 + 아래로 매달린 둥근 플라스크.",
     "pose": "플라스크를 든 대기. 행동 후보는 플라스크 흔들기·솥에 붓기(2장).",
     "distinct": "보라를 전혀 쓰지 않는다(주인공·여마법사와 분리). 와인색(#9D4359)은 고양이 도적 목도리와 같은 색이지만 "
                 "머리카락에만 쓰고 고양이 귀·꼬리가 없다. 회색 가운은 5명 누구도 쓰지 않은 돌 램프다.",
     "materials": {"#": "outline", "s": "skin", "m": "smock", "R": "hair_and_shoes", "t": "goggles_flask_tube"}},
    {"id": "staff_expedition_guide", "employee": "expedition_guide", "name": "원정 길잡이", "concept": "후드 등불 길잡이",
     "skin": "s", "short": "guide", "attachments": [[0, 2, 5, 47]],
     "summary": "원정을 이끄는 길잡이. 짙은 청록 후드 망토, 모래색 앞머리와 짧은 턱수염, 금빛 목수건, "
                "왼손에 쥔 머리보다 높은 지팡이와 그 끝의 금빛 등불.",
     "silhouette": "둥근 후드 + 아래로 넓게 퍼지는 망토 + 왼쪽으로 솟은 가는 지팡이(캔버스 2행까지).",
     "pose": "지팡이를 짚은 대기. 행동 후보는 등불 들어 올리기·원정 출발/귀환 걷기.",
     "distinct": "망토는 주인공의 앞이 열린 보라 망토와 달리 머리를 덮는 청록 후드다. 4명 중 유일하게 키보다 높은 소품을 든다. "
                 "여행자와 같은 모래색(#C99463)은 지팡이·장화·앞머리에만 쓴다.",
     "materials": {"#": "outline", "s": "skin", "T": "hood_cloak_trousers", "o": "staff_hair_beard_boots", "g": "lantern_scarf"}},
]
EXISTING = ["keeper", "traveler", "mage", "elf", "rogue"]
EXISTING_NAMES = {"keeper": "주인공", "traveler": "여행자", "mage": "여마법사", "elf": "엘프", "rogue": "고양이 도적"}

APPROVED_PROP_ORIGIN = (96, 40)
PROP_IDS = ["decor_teacup", "decor_dried_vase"]
APPROVED_SOUVENIR_ORIGIN = (14, 0)

# ---- layout definitions (native coordinates)
A_OY = range(26, 33)  # layout A: shared spot, feet row 72..78 (a little further back is allowed)
# Layout B: staff origin x inside the new left strip (native) and row; back row stands 5 rows further back.
B_POSITIONS = {"guide": (0, 32), "sales": (33, 32), "brewing": (15, 27), "cultivation": (48, 27)}
C_ZONES = {  # staff short id -> (title, ox range, oy range, equipment); centred on each piece of equipment
    "cultivation": ("약초대 뒤", range(0, 13), range(24, 33), "herb"),
    "brewing": ("솥 뒤", range(36, 47), range(24, 33), "cauldron"),
    "sales": ("판매대 뒤", range(104, 125), range(24, 33), "counter"),
    "guide": ("원정 표지판 아래", range(126, 149), range(24, 33), "poster"),
}

# ---- workload estimate per layout (counts of new drawings and the code scope)
WORKLOAD = {
    "A": {"keyframes": {"idle": 4, "role_action": 8, "walk_in_out": 0}, "derived_cells_note": "호흡·깜빡임 64칸 아틀라스 × (대기+행동 2) × 4명 = 768칸, 기존 파이프라인으로 파생",
          "other_art": "없음",
          "code": ["pixel_shop_scene.gd: 고용한 직원 중 1명을 고정 자리에 그리는 명령 1개(벽 소품 다음·바닥 가구 앞 순서, 솥이 하반신을 가림)",
                   "순번 규칙(예: 판매 N건 또는 몇 분마다 교대) · 저장 불필요(표시 전용)",
                   "축소·전체 실내 모드 정책(표시 안 함 권장) · 관리 화면 토글은 선택",
                   "검증: 모든 고용 조합 × 겹침 0 확인 스크립트"],
          "size": "중", "risk": "고정 자리가 약초대·HUD(약초 패널)와 겹친다 — 겹침 해소를 위해 HUD 이동 또는 자리 타협 필요"},
    "B": {"keyframes": {"idle": 4, "role_action": 8, "walk_in_out": 0}, "derived_cells_note": "A와 같음(768칸)",
          "other_art": "왼쪽 확장 띠 원본 {ext}×83(바닥 연장 + 벽 장식 최소 1~2점) — 기존 v9 배경 규칙대로 새로 그려야 함",
          "code": ["작업실 아트 폭 540→{width}(표시) · 창 크기·드래그 제한·창 위치 복원·클릭 통과 영역",
                   "workshop_layout.gd / pixel_shop_scene.gd / shop_art.gd / potion_display.gd / workshop_gauges.gd의 모든 표시 좌표(+{dx})",
                   "축소(캐릭터) 모드·전체 실내 모드 별도 판단 · 투명 배경·바닥 양끝 검증 재작성",
                   "기존 검증 스크립트(verify_pixel_*, verify_f2x_*)의 540 기준 상수 갱신"],
          "size": "대", "risk": "창이 {pct}% 넓어져 바탕화면 점유가 커진다. 모든 좌표 상수와 검증이 함께 바뀐다."},
    "C": {"keyframes": {"idle": 4, "role_action": 8, "walk_in_out": 0}, "derived_cells_note": "A와 같음(768칸) — 하반신이 가려져 행동은 상반신 위주로 그려도 됨",
          "other_art": "없음(단, 가려지는 경계가 어색하면 설비별 가림 마스크 조정)",
          "code": ["직원 4명을 각각 설비 앞 그리기 순서 사이에 끼워 넣기(가구 그리기 순서 재배치 필요)",
                   "고용 여부별 표시 · 겹치는 HUD(약초 패널·수확 알림·재고 글자)와 이동 병 경로 조정",
                   "손님 대기 자리·판매 병 경로와 겹치는 판매대/표지판 자리는 별도 규칙(예: 판매 순간 숨김)",
                   "검증: 16가지 고용 조합 × 겹침·가림 비율"],
          "size": "중~대", "risk": "판매대·표지판 쪽은 판매 병 비행 경로와 손님 자리를 피할 수 없다(겹침 수 참고)."},
    "D": {"keyframes": {"idle": 4, "role_action": 0, "walk_in_out": 0}, "derived_cells_note": "없음(대기 1장 그대로 1배 표시)",
          "other_art": "없음",
          "code": ["management_art.gd에 직원 초상 id 4개 · management_panel.gd 직원 행 아이콘을 32×48 초상으로 교체(또는 카드 추가)",
                   "assets 게시 스크립트(추가 전용) · 검증: 게시 픽셀 = 승인 스프라이트"],
          "size": "소", "risk": "작업실에서는 직원이 보이지 않는다(기획안의 '새 작업실 캐릭터는 필수 조건 아님'과 일치)."},
}


def rgb(value: str) -> tuple[int, int, int]:
    return decor.rgb(value)


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def x3(image: Image.Image) -> Image.Image:
    return image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST)


def alpha_of(image: Image.Image) -> np.ndarray:
    return np.array(image)[:, :, 3] == 255


# ---------------------------------------------------------------- source maps + pipeline
def read_map(path: Path) -> list[str]:
    rows = [line.rstrip("\r\n") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len(rows) != SIZE[1] or any(len(r) != SIZE[0] for r in rows):
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


def asset_entry(item: dict, source: Path) -> dict:
    letters = {c: m for c, m in item["materials"].items() if c != "#"}
    materials = {"outline": [OUTLINE_HEX]}
    materials.update({m: [LEGEND[c][0]] for c, m in letters.items()})
    return {"id": item["id"], "source": rel(source), "size": list(SIZE), "position": [0, 0], "margin": 0,
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


# ---------------------------------------------------------------- character checks
def eye_check(data: np.ndarray, skin_hex: str) -> dict:
    skin = rgb(skin_hex)
    color = data[:, :, :3]
    is_outline = np.all(color == OUTLINE, axis=2) & (data[:, :, 3] == 255)
    eyes = []
    for x in EYES["x"]:
        pix = [(x, y) for y in EYES["y"]]
        ok_eye = all(is_outline[y, x] for x, y in pix)
        ring = [(xx, yy) for yy in range(EYES["y"][0] - 1, EYES["y"][1] + 2) for xx in range(x - 1, x + 2) if (xx, yy) not in pix]
        margin_ok = all(data[yy, xx, 3] == 255 and tuple(color[yy, xx]) == skin for xx, yy in ring)
        eyes.append({"pixels": [list(p) for p in pix], "outline_color": bool(ok_eye), "skin_margin_1px_8_neighbours": bool(margin_ok)})
    same_rows = True
    return {"eyes": eyes, "same_rows": same_rows, "size_each": [1, 2], "skin_color": skin_hex,
            "passed": all(e["outline_color"] and e["skin_margin_1px_8_neighbours"] for e in eyes)}


def body_check(data: np.ndarray, skin_hex: str, attachments: list) -> dict:
    """Attachments (hat brim, ponytail, staff and lantern) are excluded from the head size, as in AGENTS.md."""
    opaque = data[:, :, 3] == 255
    rows = np.where(opaque.any(axis=1))[0]
    skin = np.all(data[:, :, :3] == rgb(skin_hex), axis=2) & opaque
    face_rows = [int(y) for y in np.where(skin[11:27].any(axis=1))[0] + 11]
    head = opaque.copy()
    for x0, y0, x1, y1 in attachments:
        head[y0:y1, x0:x1] = False
    head_row21 = np.where(head[21])[0]
    feet = np.where(opaque[46])[0]
    result = {"lowest_opaque_row": int(rows.max()), "feet_row_46": int(rows.max()) == 46,
              "feet_row_all_outline": bool(np.all(data[46, feet, :3] == OUTLINE)) if len(feet) else False,
              "face_skin_rows": [min(face_rows), max(face_rows)] if face_rows else None,
              "face_within_head_rows_11_26": bool(face_rows) and min(face_rows) >= 11 and max(face_rows) <= 26,
              "head_width_at_row_21": int(head_row21.max() - head_row21.min() + 1),
              "head_width_within_22": int(head_row21.max() - head_row21.min() + 1) <= 22,
              "body_rows_27_39_opaque": bool(all(opaque[y].any() for y in range(27, 40))),
              "leg_rows_40_46_opaque": bool(all(opaque[y].any() for y in range(40, 47))),
              "row_47_empty": not bool(opaque[47].any())}
    result["passed"] = bool(result["feet_row_46"] and result["feet_row_all_outline"] and result["face_within_head_rows_11_26"]
                            and result["head_width_within_22"] and result["body_rows_27_39_opaque"]
                            and result["leg_rows_40_46_opaque"] and result["row_47_empty"])
    return result


def check_sprite(item: dict, image: Image.Image, registered: Image.Image, palette: set, ramps: dict, pipe: dict) -> dict:
    data = np.array(image.convert("RGBA"))
    alpha = data[:, :, 3]
    opaque = alpha == 255
    colors = sorted({"#%02X%02X%02X" % tuple(p[:3]) for p in data[opaque]})
    ys, xs = np.where(opaque)
    by_ramp: dict[str, list[str]] = {}
    for c in item["materials"]:
        by_ramp.setdefault(LEGEND[c][1], []).append(LEGEND[c][0])
    shades = {ramp: len(hexes) for ramp, hexes in by_ramp.items()}
    skin_hex = LEGEND[item["skin"]][0]
    check = {
        "name": item["name"], "employee": item["employee"], "native_size": list(image.size), "native_32x48": image.size == SIZE,
        "display_size_x3": [image.width * SCALE, image.height * SCALE],
        "colors": colors, "color_count": len(colors), "max_colors": 5,
        "off_palette_colors": sum(1 for c in colors if rgb(c) not in palette),
        "partial_alpha_pixels": int(((alpha != 0) & (alpha != 255)).sum()),
        "outline_violations": decor.outline_violations(data), "outline_color_present": OUTLINE_HEX in colors,
        "materials": {m: {"color": LEGEND[c][0], "ramp": LEGEND[c][1]} for c, m in item["materials"].items()},
        "colors_in_declared_ramps": all(h in ramps[r]["colors"] for r, hs in by_ramp.items() for h in hs),
        "shades_per_ramp": shades, "max_3_shades_per_ramp": all(n <= 3 for n in shades.values()),
        "opaque_bbox": [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1],
        "opaque_pixels": int(opaque.sum()),
        "dither_3x3_blocks": decor.dither_blocks(data),
        "eyes": eye_check(data, skin_hex), "body": body_check(data, skin_hex, item["attachments"]),
        "attachments_excluded_from_head": item["attachments"],
        "pipeline_passed": pipe["passed"],
        "pipeline_preserved_source": bool(np.array_equal(np.array(registered.convert("RGBA")), data)),
        "native_sha256": hashlib.sha256(data.tobytes()).hexdigest(),
    }
    check["passed"] = bool(
        check["native_32x48"] and check["color_count"] <= 5 and check["outline_color_present"]
        and check["off_palette_colors"] == 0 and check["partial_alpha_pixels"] == 0 and not check["outline_violations"]
        and check["colors_in_declared_ramps"] and check["max_3_shades_per_ramp"] and not check["dither_3x3_blocks"]
        and check["eyes"]["passed"] and check["body"]["passed"] and check["pipeline_passed"] and check["pipeline_preserved_source"]
        and set(colors) == {LEGEND[c][0] for c in item["materials"]})
    return check


def existing_idle(scene) -> dict[str, Image.Image]:
    out = {}
    for cid in EXISTING:
        sheet = scene.load(scene.catalog["characters"][cid]["poses"]["idle"]["native"])
        out[cid] = sheet.crop((0, 0, 32, 48))
    return out


def distinctness(staff: dict[str, Image.Image], existing: dict[str, Image.Image]) -> dict:
    """Silhouette IoU (same canvas, feet aligned) and shared colors (outline and skin are shared by design)."""
    def cols(im):
        d = np.array(im)
        return {"#%02X%02X%02X" % tuple(p[:3]) for p in d[d[:, :, 3] == 255]}
    shared_ok = {OUTLINE_HEX, "#F6D1AC", "#DE9B88"}
    everyone = {**{k: v for k, v in existing.items()}, **staff}
    table = {}
    for sid, im in staff.items():
        a = alpha_of(im)
        row = {}
        for oid, other in everyone.items():
            if oid == sid:
                continue
            b = alpha_of(other)
            row[oid] = {"silhouette_iou": round(float((a & b).sum() / (a | b).sum()), 3),
                        "silhouette_iou_mirrored": round(float((a & b[:, ::-1]).sum() / (a | b[:, ::-1]).sum()), 3),
                        "shared_colors_excluding_outline_skin": sorted((cols(im) & cols(other)) - shared_ok)}
        def iou(kv):
            return max(kv[1]["silhouette_iou"], kv[1]["silhouette_iou_mirrored"])
        worst = max(row.items(), key=iou)
        worst_existing = max(((k, v) for k, v in row.items() if k in EXISTING), key=iou)
        table[sid] = {"against": row, "most_similar": worst[0], "max_iou": iou(worst),
                      "most_similar_approved": worst_existing[0], "max_iou_approved": iou(worst_existing)}
    # Reference: how similar the already-approved five are to each other.
    ref = []
    for i, p in enumerate(EXISTING):
        for q in EXISTING[i + 1:]:
            a, b = alpha_of(existing[p]), alpha_of(existing[q])
            ref.append(max(float((a & b).sum() / (a | b).sum()), float((a & b[:, ::-1]).sum() / (a | b[:, ::-1]).sum())))
    return {"staff": table, "approved_five_pairwise_max_iou": round(max(ref), 3),
            "approved_five_pairwise_mean_iou": round(float(np.mean(ref)), 3),
            "note": "IoU of opaque masks on the shared 32x48 canvas (feet row 46); mirrored = the other figure flipped. "
                    "Outline #241C32 and skin colors are shared by design and excluded from the shared-color list."}


# ---------------------------------------------------------------- layouts
def masks_with_extras(scene) -> dict[str, np.ndarray]:
    masks = decor.build_masks(scene)
    cat = scene.catalog
    prop = np.zeros((H, W), bool)
    for pid in PROP_IDS:
        prop |= decor.placed(alpha_of(x3(scene.load(cat["decor"][pid]))), APPROVED_PROP_ORIGIN)
    souv = np.zeros((H, W), bool)
    for path in cat["souvenirs_mini"].values():
        souv |= decor.placed(alpha_of(x3(scene.load(path))), APPROVED_SOUVENIR_ORIGIN)
    masks["furniture_counter_prop"] = prop
    masks["furniture_souvenir_mini"] = souv
    return masks


ALL_FURN = FURNITURE + ["counter_prop", "souvenir_mini"]


def overlaps(m: np.ndarray, masks: dict, skip_furniture=()) -> dict:
    r = {name: int((m & masks[name]).sum()) for name in FORBIDDEN}
    r["furniture"] = {f: int((m & masks["furniture_" + f]).sum()) for f in ALL_FURN if f not in skip_furniture}
    r["forbidden_total"] = sum(r[n] for n in FORBIDDEN)
    r["furniture_total"] = sum(r["furniture"].values())
    return r


def front_layer(masks: dict) -> np.ndarray:
    front = np.zeros((H, W), bool)
    for f in FLOOR_FURNITURE + ["counter_prop"]:
        front |= masks["furniture_" + f]
    return front


SKIP_BEHIND = tuple(FLOOR_FURNITURE + ["counter_prop", "floor"])


def layout_a(sprites3: dict, masks: dict) -> dict:
    """One shared spot for whichever employee is shown (drawn behind the floor furniture like layout C, so the
    cauldron / herb station are never painted over); minimise the worst employee's forbidden overlap."""
    front = front_layer(masks)
    scan = []
    for oy in A_OY:
        for ox in range(0, 180 - 32 + 1):
            per, vis = {}, []
            for sid, a in sprites3.items():
                m = decor.placed(a, (ox, oy))
                visible = m & ~front
                vis.append(float(visible.sum() / m.sum()))
                per[sid] = overlaps(visible, masks, skip_furniture=SKIP_BEHIND)
                per[sid]["visible_fraction"] = round(vis[-1], 3)
            if min(vis) < 0.6:
                continue
            worst = max(v["forbidden_total"] for v in per.values())
            total = sum(v["forbidden_total"] for v in per.values())
            furn = sum(v["furniture_total"] for v in per.values())
            scan.append({"ox": ox, "oy": oy, "worst_forbidden": worst, "sum_forbidden": total, "sum_furniture": furn,
                         "min_visible": round(min(vis), 3), "per": per})
    best = min(scan, key=lambda s: (s["worst_forbidden"], s["sum_forbidden"], s["sum_furniture"], -s["min_visible"]))
    profile = [{"ox": s["ox"], "oy": s["oy"], "worst_forbidden": s["worst_forbidden"], "sum_furniture": s["sum_furniture"]}
               for s in scan]
    return {"origin_native": [best["ox"], best["oy"]], "origin_display": [best["ox"] * 3, best["oy"] * 3],
            "draw_order": "behind floor furniture (herb, counter, counter prop, fire, cauldron), above wall items",
            "per_staff": best["per"], "worst_forbidden": best["worst_forbidden"], "sum_furniture": best["sum_furniture"],
            "min_visible": best["min_visible"],
            "zero_forbidden_spots": [[s["ox"], s["oy"]] for s in scan if s["worst_forbidden"] == 0], "scan_profile": profile}


def layout_c(sprites3: dict, masks: dict, short: dict) -> dict:
    """Each employee near its own equipment, drawn before the floor furniture (furniture hides the lower body)."""
    front = front_layer(masks)
    result = {}
    for sid, a in sprites3.items():
        title, xs, ys, equipment = C_ZONES[short[sid]]
        best = None
        for oy in ys:
            for ox in xs:
                m = decor.placed(a, (ox, oy))
                if int(m.sum()) != int(a.sum()):
                    continue
                visible = m & ~front
                vis_frac = float(visible.sum() / m.sum())
                if vis_frac < 0.45:  # keep head and chest readable
                    continue
                ov = overlaps(visible, masks, skip_furniture=tuple(FLOOR_FURNITURE + ["counter_prop", "floor"]))
                key = (ov["forbidden_total"], ov["furniture_total"], -vis_frac, abs(oy - FLOOR_ORIGIN_Y))
                if best is None or key < best[0]:
                    best = (key, ox, oy, ov, vis_frac, int((m & front).sum()))
        _, ox, oy, ov, vis_frac, hidden = best
        result[sid] = {"zone": title, "equipment": equipment, "origin_native": [ox, oy], "origin_display": [ox * 3, oy * 3],
                       "feet_native_row": oy + 46, "visible_fraction": round(vis_frac, 3), "hidden_by_floor_furniture_px": hidden,
                       "overlap": ov}
    # staff vs staff
    placed = {sid: decor.placed(sprites3[sid], tuple(v["origin_native"])) & ~front for sid, v in result.items()}
    ids = list(placed)
    pairs = {f"{p}|{q}": int((placed[p] & placed[q]).sum()) for i, p in enumerate(ids) for q in ids[i + 1:]}
    return {"staff": result, "staff_vs_staff": pairs, "front_layers": FLOOR_FURNITURE + ["counter_prop"]}


def layout_b(sprites: dict, short: dict) -> dict:
    """All four in a new strip left of the current x=0: front row (feet row 78) + back row (feet row 73) in the gaps."""
    pos = {sid: B_POSITIONS[short[sid]] for sid in sprites}
    right = 0
    for sid, im in sprites.items():
        xs = np.where(alpha_of(im).any(axis=0))[0]
        right = max(right, pos[sid][0] + int(xs.max()))
    return {"positions": pos, "strip_needed_native": right + 3}


def extended_floor(scene, extend: int) -> Image.Image:
    floor = scene.load(scene.catalog["props"]["floor"])
    out = Image.new("RGBA", (floor.width + extend, floor.height))
    out.paste(floor, (extend, 0))
    col = floor.crop((0, 0, 1, floor.height))
    for x in range(extend):
        out.paste(col, (x, 0))
    return out


def compose(scene, staff_draws: list, behind: bool, extend: int, customer: str, weather: str, staff_ids_order=None):
    """Static waiting frame. Base order follows ShopArt workshop_commands; non-overlapping static items are grouped so that
    "behind" staff (layout C) can sit between the wall layer and the floor furniture. extend = native columns added left."""
    cat = scene.catalog
    w = W + extend * 3
    canvas = Image.new("RGBA", (w, H))
    drawn = np.zeros((H, w), bool)
    dx = extend * 3

    def put(image: Image.Image, point):
        x, y = int(point[0]), int(point[1])
        canvas.alpha_composite(image, (x, y))
        a = np.array(image)[:, :, 3] > 0
        hh, ww = a.shape
        x0, y0, x1, y1 = max(0, x), max(0, y), min(w, x + ww), min(H, y + hh)
        drawn[y0:y1, x0:x1] |= a[y0 - y:y1 - y, x0 - x:x1 - x]

    def g(name):
        p = decor.GEOMETRY[name][0]
        return p[0] + dx, p[1]

    put(scene.x3(cat["weather"][weather][0]), g("window"))
    put(x3(extended_floor(scene, extend)), (0, 0))
    put(scene.x3(cat["props"]["window"]), g("window"))
    put(x3(scene.load(cat["souvenirs_mini"]["souvenir_compass_mini"])), (APPROVED_SOUVENIR_ORIGIN[0] * 3 + dx, APPROVED_SOUVENIR_ORIGIN[1] * 3))
    put(scene.x3(cat["props"]["poster"]), g("poster"))
    put(scene.x3(cat["props"]["aging_cask"]), g("aging_cask"))
    stock = scene.ids[::4][:8]
    for i, pid in enumerate(stock):
        b = scene.x3(cat["potions"][pid]["bottle"])
        cx, cy = scene.slot_center(i, pid)
        put(b, (round(cx - b.width / 2) + dx, round(cy - b.height / 2)))
    put(scene.x3(cat["props"]["shelf"]), g("shelf"))
    if behind:
        for img, (x, y) in staff_draws:
            put(img, (x + dx, y))
    put(scene.x3(cat["props"]["herb"]), g("herb"))
    put(scene.x3(cat["props"]["counter"]), g("counter"))
    put(x3(scene.load(cat["decor"]["decor_teacup"])), (APPROVED_PROP_ORIGIN[0] * 3 + dx, APPROVED_PROP_ORIGIN[1] * 3))
    put(scene.x3(cat["fire"][0]), g("hearth"))
    put(scene.x3(cat["potions"][stock[1]]["pots"][0]), g("pot"))
    if not behind:
        for img, (x, y) in staff_draws:
            put(img, (x + dx, y))
    put(scene.fine_cells("keeper", "idle")[0], g("keeper"))
    put(scene.fine_cells(customer, "idle")[0], (decor.GEOMETRY["purchase_feet_x"][0] - 48 + dx, decor.GEOMETRY["customer_y"][0]))
    alpha = np.array(canvas)[:, :, 3]
    return canvas, bool(np.all(alpha[~drawn] == 0)), int(((alpha != 0) & (alpha != 255)).sum())


def occupancy_image(masks: dict, footprints: list, extend: int = 0) -> Image.Image:
    """Review aid (not game art): flat palette colors per element plus staff footprints (cream)."""
    colors = [("furniture", "#827589"), ("furniture_aging_cask", "#A56A3D"), ("hud", "#E9B95F"), ("stock_bottles", "#3BA8A3"),
              ("sale_bottle", "#DE7356"), ("customers", "#F4AC68"), ("keeper", "#C38EB5")]
    out = np.zeros((H, W + extend * 3, 4), np.uint8)
    dx = extend * 3
    furniture = np.zeros((H, W), bool)
    for k, v in masks.items():
        if k.startswith("furniture_") and k not in ("furniture_aging_cask", "furniture_floor"):
            furniture |= v
    for name, hex_ in colors:
        m = furniture if name == "furniture" else masks[name]
        out[:, dx:][m] = (*rgb(hex_), 255)
    for m in footprints:
        out[m] = (*rgb("#FFF0BC"), 255)
    return Image.fromarray(out)


def place_wide(alpha3: np.ndarray, origin_native, width_native: int) -> np.ndarray:
    m = np.zeros((H, width_native * 3), bool)
    x, y = origin_native[0] * 3, origin_native[1] * 3
    hh, ww = alpha3.shape
    x0, y0, x1, y1 = max(0, x), max(0, y), min(width_native * 3, x + ww), min(H, y + hh)
    m[y0:y1, x0:x1] |= alpha3[y0 - y:y1 - y, x0 - x:x1 - x]
    return m


def main() -> int:
    palette = {rgb(v) for v in (ROOT / "art/palette.hex").read_text(encoding="utf-8").split()}
    ramp_data = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
    ramps = ramp_data["ramps"]
    for char, (hex_, ramp) in LEGEND.items():
        if rgb(hex_) not in palette or hex_ not in ramps[ramp]["colors"]:
            raise SystemExit(f"Legend {char} {hex_} is not an approved {ramp} color")
    constants = decor.source_constants()
    # The F23 souvenir connection moved the cask/souvenir lines; only geometry constants are required here.
    geometry_ok = all(v for k, v in constants.items() if k != "cask_drawn_before_stock")
    if not geometry_ok:
        raise SystemExit(f"Workshop geometry drifted from scripts: {[k for k, v in constants.items() if not v]}")
    content = json.loads((ROOT / "data/content_expansion.json").read_text(encoding="utf-8"))
    employees = {e["id"]: e for e in content["employees"]}
    if sorted(employees) != sorted(s["employee"] for s in STAFF):
        raise SystemExit(f"Employee ids changed: {sorted(employees)}")

    # ---- register hand-authored maps and run the fixed pipeline
    assets, registered, source_hashes = [], {}, {}
    for item in STAFF:
        text_path = SRC / f"{item['id']}.txt"
        image = render_map(read_map(text_path), item["materials"])
        path = SRC / f"{item['id']}-registered.png"
        image.save(path)
        registered[item["id"]] = image
        source_hashes[item["id"]] = {"map": rel(text_path), "map_sha256": hashlib.sha256(text_path.read_bytes()).hexdigest(),
                                     "registered_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        assets.append(asset_entry(item, path))
    manifest = {"schema_version": 1, "status": "candidate", "approved_by_user": False, "compose": False,
                "scale": SCALE, "alpha_threshold": 224, "max_colors": 5,
                "palette": "art/palette.hex", "ramps": "art/ramps.json", "output": rel(PIPE),
                "scene": {"size": list(SIZE), "background": "#4A3C52"},
                "feature": "F25 staff concept idle poses", "runtime_integrated": False, "assets": assets}
    manifest_path = MOCK / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    pipe_report = run_pipeline(manifest_path)

    SPRITES.mkdir(exist_ok=True)
    checks, natives = {}, {}
    for item in STAFF:
        native = Image.open(PIPE / f"{item['id']}-native.png").convert("RGBA")
        check = check_sprite(item, native, registered[item["id"]], palette, ramps, pipe_report["assets"][item["id"]])
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

    scene = decor.Scene()
    existing = existing_idle(scene)
    distinct = distinctness(natives, existing)
    # lineup: approved five + four candidates, native and x3
    lineup = Image.new("RGBA", (36 * 9, 48))
    for i, im in enumerate([existing[c] for c in EXISTING] + [natives[s["id"]] for s in STAFF]):
        lineup.alpha_composite(im, (i * 36 + 2, 0))
    lineup.save(SPRITES / "lineup-native.png")
    x3(lineup).save(SPRITES / "lineup-3x.png")
    portraits = Image.new("RGBA", (36 * 4, 48))
    for i, s in enumerate(STAFF):
        portraits.alpha_composite(natives[s["id"]], (i * 36 + 2, 0))
    portraits.save(SPRITES / "portraits-1x.png")

    # ---- layouts
    masks = masks_with_extras(scene)
    f23_validation = json.loads((ROOT / "art/mockups/f23-decor-v1/validation.json").read_text(encoding="utf-8"))
    pixels = {k: int(v.sum()) for k, v in masks.items()}
    same_as_f23 = all(pixels.get(k) == v for k, v in f23_validation["element_pixels"].items() if k != "sale_rest")
    sprites3 = {s["id"]: alpha_of(x3(natives[s["id"]])) for s in STAFF}
    short = {s["id"]: s["short"] for s in STAFF}
    names = {s["id"]: s["name"] for s in STAFF}
    LAYOUT_DIR.mkdir(exist_ok=True)
    customers = {"staff_sales_assistant": "traveler", "staff_cultivation_assistant": "elf",
                 "staff_brewing_assistant": "mage", "staff_expedition_guide": "rogue"}
    weathers = {"staff_sales_assistant": "day_clear", "staff_cultivation_assistant": "day_rain",
                "staff_brewing_assistant": "night_clear", "staff_expedition_guide": "night_rain"}
    examples_ok = True

    def save_example(name, image, empty_ok, partial):
        nonlocal examples_ok
        image.save(LAYOUT_DIR / f"{name}-3x.png")
        image.resize((image.width // 3, image.height // 3), Image.Resampling.NEAREST).save(LAYOUT_DIR / f"{name}-native.png")
        ok = empty_ok and partial == 0
        examples_ok &= ok
        return {"png": f"layouts/{name}-3x.png", "size": list(image.size), "empty_space_alpha_zero": empty_ok,
                "partial_alpha": partial, "passed": ok}

    # A
    A = layout_a(sprites3, masks)
    A["examples"] = {}
    for s in STAFF:
        img3 = x3(natives[s["id"]])
        canvas, empty_ok, partial = compose(scene, [(img3, tuple(A["origin_display"]))], True, 0, customers[s["id"]], weathers[s["id"]])
        A["examples"][s["id"]] = save_example(f"A-{s['short']}", canvas, empty_ok, partial)
    occupancy_image(masks, [decor.placed(sprites3[s["id"]], tuple(A["origin_native"])) & ~front_layer(masks) for s in STAFF]).save(LAYOUT_DIR / "occupancy-A.png")

    # B
    Bp = layout_b(natives, short)
    ext = Bp["strip_needed_native"]
    fmt = {"ext": ext, "width": W + ext * 3, "dx": ext * 3, "pct": round(ext * 3 / W * 100)}
    WORKLOAD["B"]["other_art"] = WORKLOAD["B"]["other_art"].format(**fmt)
    WORKLOAD["B"]["code"] = [c.format(**fmt) for c in WORKLOAD["B"]["code"]]
    WORKLOAD["B"]["risk"] = WORKLOAD["B"]["risk"].format(**fmt)
    order = sorted(Bp["positions"], key=lambda sid: Bp["positions"][sid][1])  # back row (smaller oy) first
    draws = [(x3(natives[sid]), (Bp["positions"][sid][0] * 3 - ext * 3, Bp["positions"][sid][1] * 3)) for sid in order]
    canvas, empty_ok, partial = compose(scene, draws, False, ext, "traveler", "day_clear")
    B = {"extend_native": ext, "extend_display": ext * 3, "art_size_display": [W + ext * 3, H],
         "positions_native_in_widened_art": {sid: list(p) for sid, p in Bp["positions"].items()},
         "rows": {sid: ("back" if p[1] < FLOOR_ORIGIN_Y else "front") for sid, p in Bp["positions"].items()},
         "examples": {"all": save_example("B-all", canvas, empty_ok, partial)}}
    widened = {}
    for k, v in masks.items():
        m = np.zeros((H, W + ext * 3), bool)
        m[:, ext * 3:] = v
        widened[k] = m
    staff_masks = {sid: place_wide(sprites3[sid], Bp["positions"][sid], 180 + ext) for sid in Bp["positions"]}
    B["per_staff"] = {}
    for sid, m in staff_masks.items():
        r = {name: int((m & widened[name]).sum()) for name in FORBIDDEN}
        r["furniture"] = {f: int((m & widened["furniture_" + f]).sum()) for f in ALL_FURN}
        r["forbidden_total"] = sum(r[n] for n in FORBIDDEN)
        r["furniture_total"] = sum(r["furniture"].values())
        r["inside_strip"] = bool(not m[:, ext * 3:].any())
        B["per_staff"][sid] = r
    ids = list(staff_masks)
    B["staff_vs_staff"] = {f"{p}|{q}": int((staff_masks[p] & staff_masks[q]).sum()) for i, p in enumerate(ids) for q in ids[i + 1:]}
    front_union = np.zeros_like(next(iter(staff_masks.values())))
    for sid in ids:
        if B["rows"][sid] == "front":
            front_union |= staff_masks[sid]
    B["back_row_hidden_fraction"] = {sid: round(float((staff_masks[sid] & front_union).sum() / staff_masks[sid].sum()), 3)
                                     for sid in ids if B["rows"][sid] == "back"}
    occupancy_image(masks, [m for m in staff_masks.values()], ext).save(LAYOUT_DIR / "occupancy-B.png")

    # C
    C = layout_c(sprites3, masks, short)
    draws = [(x3(natives[sid]), tuple(v["origin_display"])) for sid, v in C["staff"].items()]
    canvas, empty_ok, partial = compose(scene, draws, True, 0, "elf", "day_clear")
    C["examples"] = {"all": save_example("C-all", canvas, empty_ok, partial)}
    front = np.zeros((H, W), bool)
    for f in C["front_layers"]:
        front |= masks["furniture_" + f]
    occupancy_image(masks, [decor.placed(sprites3[sid], tuple(v["origin_native"])) & ~front for sid, v in C["staff"].items()]).save(LAYOUT_DIR / "occupancy-C.png")

    # D: unchanged workshop + 1x portraits
    canvas, empty_ok, partial = compose(scene, [], False, 0, "traveler", "day_clear")
    D = {"examples": {"workshop_unchanged": save_example("D-workshop", canvas, empty_ok, partial)},
         "portraits_png": "sprites/portraits-1x.png", "overlap_total": 0}

    # ---- summary rows for the comparison table
    def tot(ov):
        return ov["forbidden_total"], ov["furniture_total"]
    rows = []
    for s in STAFF:
        sid = s["id"]
        a_ov = A["per_staff"][sid]
        c_ov = C["staff"][sid]["overlap"]
        b_ov = B["per_staff"][sid]
        rows.append({"staff": s["name"],
                     "A": {n: a_ov[n] for n in FORBIDDEN} | {"furniture": a_ov["furniture_total"], "total": sum(tot(a_ov))},
                     "B": {n: b_ov[n] for n in FORBIDDEN} | {"furniture": b_ov["furniture_total"], "total": sum(tot(b_ov))},
                     "C": {n: c_ov[n] for n in FORBIDDEN} | {"furniture": c_ov["furniture_total"], "total": sum(tot(c_ov)),
                                                              "visible": C["staff"][sid]["visible_fraction"], "zone": C["staff"][sid]["zone"]},
                     "D": {n: 0 for n in FORBIDDEN} | {"furniture": 0, "total": 0}})

    for k, v in WORKLOAD.items():
        v["keyframes_total"] = sum(v["keyframes"].values())

    passed = bool(sprites_passed and examples_ok and same_as_f23)
    report = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False, "date": DATE,
        "scale": SCALE, "palette": "art/palette.hex", "ramps": "art/ramps.json", "new_palette_colors": 0,
        "pipeline_report": rel(PIPE / "validation.json"), "pipeline_status": pipe_report["status"],
        "rules": {"native": list(SIZE), "max_colors_including_outline": 5, "off_palette": 0, "partial_alpha": 0,
                  "outline": "every opaque pixel 4-adjacent to transparency (or the canvas edge) is #241C32",
                  "eyes": "two 1x2 #241C32 eyes at x13/x18, rows 22-23; all 8 neighbours of each eye are the character's skin color",
                  "body": "face skin within rows 11-26, head width at row 21 <= 22, body rows 27-39, legs 40-46, lowest row 46 all outline",
                  "max_shades_per_ramp": 3, "dithering": "no 3x3 two-color checkerboards",
                  "overlap_unit": "display pixels (native x3) of staff opacity intersecting each element's union of all reachable pixels",
                  "occupancy_source": "tools/build_f23_decor_v1.py build_masks() imported and called unchanged, plus the approved counter props (96,40) and workshop souvenir minis (14,0)"},
        "employees_source": "data/content_expansion.json employees",
        "employees": {k: {"name": v["name"], "cost": v["cost"], "effect": v["effect"], "completed_regions": v["completed_regions"],
                          "reputation": v["reputation"]} for k, v in employees.items()},
        "workshop_constants_verified_against_scripts": constants,
        "occupancy_masks_identical_to_f23_validation": same_as_f23, "element_pixels": pixels,
        "sprites": checks, "distinctness": distinct,
        "layouts": {"A": {k: v for k, v in A.items() if k != "scan_profile"}, "A_scan_profile": A["scan_profile"],
                    "B": B, "C": C, "D": D},
        "comparison_rows": rows, "workload": WORKLOAD, "passed": passed,
    }
    if not passed:
        report["final_outputs_from_this_run"] = False
    (MOCK / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    generation = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False, "date": DATE,
        "mode": "hand-authored 32x48 native pixel maps (no image generator); the .txt maps are the authoritative source",
        "request": "사용자: \"직원 4명은 들어가기 너무 빡센데 일단 배치안과 컨셉이 필요할 거 같아. 어렵지만 캐릭터들 추가되는 것도 좋다고 생각해.\"",
        "reference": {"characters": "assets/pixel_v1/characters/*/idle-native.png (approved keeper + 4 customers, read only)",
                      "spec": "AGENTS.md 색 문법 · 픽셀 규격 · 캐릭터 규격(32×48, 머리 11~26행, 몸통 27~39, 다리 40~46, 발 46)",
                      "planning": "docs/성장과-단골-꾸미기-기획안.md 종업원 상세안", "occupancy": "tools/build_f23_decor_v1.py build_masks()"},
        "legend": {c: {"color": h, "ramp": r} for c, (h, r) in LEGEND.items()},
        "staff": {s["id"]: {"employee": s["employee"], "name": s["name"], "concept": s["concept"], "summary": s["summary"],
                            "silhouette": s["silhouette"], "pose": s["pose"], "distinct": s["distinct"],
                            "materials": {mat: LEGEND[c][0] for c, mat in s["materials"].items()}} for s in STAFF},
        "new_palette_colors": 0, "postprocess_tool": "tools/process_pixel_art.py with manifest.json",
    }
    (MOCK / "generation.json").write_text(json.dumps(generation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    approval = {"schema_version": 1, "status": "candidate", "approved_by_user": False, "approved_on": None, "user_reply": None,
                "review": rel(MOCK / "review.html"), "runtime_integrated": False,
                "scope": {**{s["id"]: f"{s['name']} 컨셉 · {s['concept']} (대기 1장 32×48, 5색)" for s in STAFF},
                          "layout_A": "고용한 직원 중 1명만 순번으로 고정 자리에 등장",
                          "layout_B": f"작업실 왼쪽 확장(+{ext * 3}px) 띠에 4명 앞·뒷줄",
                          "layout_C": "4명이 각자 설비(약초대·솥·판매대·표지판) 근처, 바닥 가구 뒤에 반쯤 가려 서기",
                          "layout_D": "작업실에는 넣지 않고 관리 화면 직원 행에 초상만"},
                "pending_decisions": ["직원 4명 컨셉(외형·색) 승인 또는 수정 지시 — 인물별로 따로 답해도 됨",
                                      "배치안 A/B/C/D 중 선택(또는 'D 먼저, 나중에 A' 같은 단계 진행)",
                                      "작업실 등장을 고르면: 행동 애니메이션 범위(대기만 / 대기+역할 행동 2장)",
                                      "A를 고르면: 교대 규칙(판매 건수·시간)과 겹치는 약초 HUD 처리 방식"],
                "note": "사용자 승인 전 후보. assets/·scripts/는 바꾸지 않았다. 승인 뒤 게시·연결은 별도 작업."}
    (MOCK / "approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    summary = {
        "passed": passed,
        "staff": [{"id": s["id"], "employee": s["employee"], "name": s["name"], "concept": s["concept"], "summary": s["summary"],
                   "silhouette": s["silhouette"], "pose": s["pose"], "distinct": s["distinct"],
                   "native": f"sprites/{s['id']}.png", "x3": f"sprites/{s['id']}-3x.png",
                   "materials": [{"color": LEGEND[c][0], "name": m, "ramp": LEGEND[c][1]} for c, m in s["materials"].items()],
                   "effect": employees[s["employee"]]["effect"], "cost": employees[s["employee"]]["cost"],
                   "check": {"colors": checks[s["id"]]["color_count"], "off": checks[s["id"]]["off_palette_colors"],
                             "partial": checks[s["id"]]["partial_alpha_pixels"], "outline": len(checks[s["id"]]["outline_violations"]),
                             "eyes": checks[s["id"]]["eyes"]["passed"], "body": checks[s["id"]]["body"]["passed"],
                             "dither": len(checks[s["id"]]["dither_3x3_blocks"]), "passed": checks[s["id"]]["passed"]},
                   "similar": {"to": EXISTING_NAMES.get(distinct["staff"][s["id"]]["most_similar"], names.get(distinct["staff"][s["id"]]["most_similar"], "")),
                               "iou": distinct["staff"][s["id"]]["max_iou"],
                               "approved_to": EXISTING_NAMES[distinct["staff"][s["id"]]["most_similar_approved"]],
                               "approved_iou": distinct["staff"][s["id"]]["max_iou_approved"]}} for s in STAFF],
        "ref_iou": distinct["approved_five_pairwise_max_iou"], "ref_iou_mean": distinct["approved_five_pairwise_mean_iou"],
        "layouts": {
            "A": {"origin": A["origin_native"], "zero_spots": len(A["zero_forbidden_spots"]), "min_visible": A["min_visible"],
                  "examples": [{"id": s["short"], "name": s["name"], "png": A["examples"][s["id"]]["png"]} for s in STAFF],
                  "occupancy": "layouts/occupancy-A.png", "width": W},
            "B": {"extend": ext * 3, "width": W + ext * 3, "png": B["examples"]["all"]["png"], "occupancy": "layouts/occupancy-B.png",
                  "staff_vs_staff": sum(B["staff_vs_staff"].values()), "back_hidden": B["back_row_hidden_fraction"]},
            "C": {"png": C["examples"]["all"]["png"], "occupancy": "layouts/occupancy-C.png", "width": W,
                  "staff_vs_staff": sum(C["staff_vs_staff"].values()),
                  "spots": [{"name": names[sid], "zone": v["zone"], "origin": v["origin_native"], "visible": v["visible_fraction"]} for sid, v in C["staff"].items()]},
            "D": {"png": D["examples"]["workshop_unchanged"]["png"], "portraits": "sprites/portraits-1x.png", "width": W},
        },
        "rows": rows, "workload": WORKLOAD,
    }
    html = REVIEW_HTML.replace("/*SUMMARY*/null", json.dumps(summary, ensure_ascii=False))
    (MOCK / "review.html").write_text(html, encoding="utf-8")
    print(json.dumps({"passed": passed, "sprites": {k: v["passed"] for k, v in checks.items()},
                      "A_origin": A["origin_native"], "A_worst": A["worst_forbidden"], "B_extend": ext,
                      "C": {names[k]: (v["origin_native"], v["overlap"]["forbidden_total"], v["visible_fraction"]) for k, v in C["staff"].items()},
                      "rows": rows}, ensure_ascii=False, indent=1))
    return 0 if passed else 1


REVIEW_HTML = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>직원 컨셉·배치안</title><style>
@font-face{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}
:root{--bg:#241c32;--panel:#30263f;--line:#827589;--text:#fff0bc;--muted:#c38eb5;--accent:#e9b95f;--ok:#b5c77d;--bad:#de7356}
*{box-sizing:border-box}html,body{background:var(--bg)}body{margin:0;color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}
main{max-width:1240px;margin:auto;padding:18px 16px 48px}h1{font-size:23px;margin:0 0 6px}h2{font-size:18px;margin:30px 0 8px}h3{font-size:15px;margin:14px 0 6px}
p{margin:6px 0 10px}.muted{color:var(--muted)}code{font-size:13px;color:var(--muted)}
.note{border-left:3px solid #718c59;padding:8px 12px;background:var(--panel);margin:10px 0}.warn{border-left-color:var(--accent)}
.check{background-color:#4a3c52;background-image:linear-gradient(45deg,#3f3347 25%,transparent 25%),linear-gradient(-45deg,#3f3347 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#3f3347 75%),linear-gradient(-45deg,transparent 75%,#3f3347 75%);background-size:12px 12px;background-position:0 0,0 6px,6px -6px,-6px 0}
img{image-rendering:pixelated;image-rendering:crisp-edges;max-width:none;display:block}
.decide{display:grid;gap:8px}.decide div{background:var(--panel);padding:8px 12px;border-radius:4px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:12px}
.card{background:var(--panel);border:1px solid #4a3c52;border-radius:6px;padding:12px}.card h3{margin:2px 0 0}
.sizes{display:flex;align-items:flex-end;gap:10px;margin:10px 0 6px;flex-wrap:wrap}.sizes figure{margin:0;text-align:center}.sizes .check{display:flex;align-items:flex-end;justify-content:center;padding:4px}
figcaption{font-size:11px;color:var(--muted);margin-top:3px}
.desc{font-size:13px;margin:6px 0}.sw{display:flex;flex-wrap:wrap;gap:6px;font-size:11px;color:var(--muted)}.sw span{display:flex;align-items:center;gap:3px}
.sw i{width:12px;height:12px;display:inline-block;border:1px solid #000;background:var(--c)}
.wrap{overflow-x:auto;max-width:100%}.lineup figure{margin:0}.lineup .labels{display:flex;font-size:11px;color:var(--muted)}.lineup .labels span{width:108px;text-align:center}
.stage{position:relative;height:300px}.stage>img{position:absolute;left:0;top:0;height:249px}.stage .occ{opacity:.55;display:none}.stage.show-occ .occ{display:block}
.hud{position:absolute;top:0;bottom:0;pointer-events:none}.stage.hide-hud .hud{display:none}
.hud .pn{position:absolute;background:#281f33;border:1px solid #766180;color:#efc77c;font-size:12px;line-height:1;display:flex;align-items:center;padding:0 5px;white-space:nowrap;overflow:hidden}
.hud .cap{position:absolute;color:#efc77c;font-size:13px;line-height:1;white-space:nowrap}
.hud .btn{position:absolute;background:#281f33;border:1px solid #766180}
.bar{position:absolute;left:0;top:249px;height:51px;background:#30263f;border-top:2px solid #e9b95f;display:flex;align-items:center;gap:14px;padding:0 10px;font-size:13px;color:#efc77c}
.bar .m{margin-left:auto;background:#e9b95f;color:#241c32;border-radius:3px;padding:4px 8px}
.controls{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:8px 0}
button,label.tog{font:inherit;font-size:13px;color:var(--text);background:#4a3c52;border:1px solid var(--line);padding:5px 9px;cursor:pointer;border-radius:4px}
button[aria-pressed=true]{border-color:var(--accent);background:#50315f}label.tog input{margin-right:5px}
.opt{background:var(--panel);border-radius:6px;padding:12px;margin:12px 0}.opt h3{margin:0 0 4px}
.pc{display:grid;grid-template-columns:1fr 1fr;gap:10px}.pc ul{margin:4px 0;padding-left:18px;font-size:13px}.pc h4{margin:4px 0;font-size:13px}
.legend{display:flex;flex-wrap:wrap;gap:10px;font-size:12px;color:var(--muted);margin:6px 0}.legend span{display:flex;gap:4px;align-items:center}.legend i{width:12px;height:12px;display:inline-block;background:var(--c);border:1px solid #000}
table{border-collapse:collapse;width:100%;font-size:12.5px}th,td{border-bottom:1px solid #4a3c52;padding:4px 6px;text-align:left;vertical-align:top}th{color:var(--muted);font-weight:normal}
.ok{color:var(--ok)}.bad{color:var(--bad)}.mid{color:var(--accent)}.table-wrap{overflow-x:auto}
ul{margin:6px 0 10px;padding-left:20px}.portraits{display:flex;gap:14px;flex-wrap:wrap;align-items:flex-end}.portraits figure{margin:0;text-align:center}
@media (max-width:640px){.pc{grid-template-columns:1fr}}
</style></head><body><main>
<h1>직원 4명 · 캐릭터 컨셉과 작업실 배치안 v1</h1>
<p class="muted">후보 단계입니다. <code>assets/</code>·<code>scripts/</code>·저장은 바꾸지 않았고 게임에 연결하지 않았습니다. 직원 4명(<code>data/content_expansion.json</code>의 판매 보조·재배 보조·조제 보조·원정 길잡이)마다 대기 포즈 1장(32×48)을 원본 픽셀 지도로 직접 그렸습니다.</p>
<p id="overall"></p>

<h2>정해 주실 것</h2>
<div class="decide">
<div><b>1. 4명 컨셉</b>: 외형·색을 이대로 갈지, 인물별 수정 지시(따로 답해도 됩니다).</div>
<div><b>2. 배치안</b>: A(1명 순번) · B(작업실 왼쪽 확장) · C(설비 뒤 반신) · D(관리 화면 초상만) — 또는 “D 먼저, 나중에 A”처럼 단계로.</div>
<div><b>3. 작업실에 넣는다면</b>: 대기만 할지, 역할 행동 2장(인사·물주기·붓기·등불)까지 할지.</div>
</div>
<div class="note warn" id="reco"></div>

<h2>컨셉 4명 · 승인된 5명과 같은 줄에</h2>
<p class="muted">왼쪽 5명은 승인된 주인공·손님 대기 첫 칸(읽기 전용), 오른쪽 4명이 이번 후보입니다. 같은 32×48 캔버스·발 46행·공통 3배입니다.</p>
<div class="wrap lineup"><figure><div class="check" style="display:inline-block;padding:6px"><img src="sprites/lineup-3x.png" width="972" height="144" alt="승인된 5명과 직원 후보 4명"></div>
<div class="labels"><span>주인공</span><span>여행자</span><span>여마법사</span><span>엘프</span><span>고양이 도적</span><span>판매 보조</span><span>재배 보조</span><span>조제 보조</span><span>원정 길잡이</span></div></figure></div>
<div class="cards" id="cards"></div>
<div class="note" id="distinct-note"></div>

<h2>작업실 배치안 비교 · 540×249 아트(원본 180×83 × 3) + HUD</h2>
<div class="controls"><label class="tog"><input type="checkbox" id="tog-hud" checked>HUD 표시</label><label class="tog"><input type="checkbox" id="tog-occ">움직임·HUD·가구 영역 겹쳐 보기</label></div>
<div class="legend" id="legend"></div>
<div id="opts"></div>

<h2>겹침 픽셀 수</h2>
<p class="muted">직원 불투명 픽셀(표시 3배 기준)과 각 요소가 닿을 수 있는 모든 픽셀의 합집합이 겹치는 수입니다. 점유 영역은 <code>tools/build_f23_decor_v1.py</code>의 <code>build_masks()</code>를 그대로 불러 썼고(주인공 모든 포즈·수면 Z·기절 별·국자, 손님 4명 대기/걷기/받기/병 든 퇴장, 판매 병 경로, 입고 병 경로, HUD, 가구, 숙성통), 승인된 판매대 소품(96,40)·창틀 기념품(14,0)을 더했습니다. C는 바닥 가구(약초대·솥·불·판매대·소품)에 가려진 부분을 빼고 센 값이며, 가구 칸에는 그 바닥 가구를 넣지 않았습니다.</p>
<div class="table-wrap"><table id="table"></table></div>

<h2>필요 작업량 추정</h2>
<p class="muted">“빡세다”를 판단할 근거입니다. 키프레임은 사람이 그리는 전신 장수, 파생 칸은 기존 파이프라인(호흡 3초·깜빡임 4.5초)으로 만드는 칸입니다. 이번 후보의 대기 4장은 승인되면 그대로 키프레임 4장으로 씁니다.</p>
<div class="table-wrap"><table id="work"></table></div>

<p class="muted">재현: <code>python tools/build_f25_staff_concept_v1.py</code> → 원본 지도(<code>source/*.txt</code>) → 등록 PNG → <code>tools/process_pixel_art.py</code>(<code>manifest.json</code>) → 캐릭터 검사 → 배치·겹침 검사(<code>validation.json</code>) → 이 페이지. 수치 검사는 디자인 승인을 대신하지 않습니다. 체크무늬·HUD 상자·하단 바는 페이지 CSS/DOM이며 PNG는 투명 배경입니다.</p>
</main><script>
const S=/*SUMMARY*/null;
const el=(t,a={},h='')=>{const e=document.createElement(t);for(const k in a)e.setAttribute(k,a[k]);e.innerHTML=h;return e};
const k=(v,good)=>`<span class="${good?'ok':'bad'}">${v}</span>`;
const n=(v)=>`<span class="${v===0?'ok':(v<500?'mid':'bad')}">${v}</span>`;
document.getElementById('overall').innerHTML=S.passed?'<span class="ok">수치 검사 통과</span> · 4명 모두 32×48·5색·승인 팔레트·반투명 0·외곽선 위반 0·두 눈 1×2와 피부 여백·발 46행·디더링 0':'<span class="bad">검사 실패 항목이 있습니다 — validation.json 참고</span>';
const cards=document.getElementById('cards');
for(const it of S.staff){
 const c=el('div',{class:'card'});c.append(el('div',{class:'muted'},`${it.name} · <code>${it.employee}</code> · ${it.cost} G`),el('h3',{},it.concept));
 const sz=el('div',{class:'sizes'});
 const fig=(w,h,lab,src)=>{const f=el('figure');const b=el('div',{class:'check'});b.append(el('img',{src,width:w,height:h,alt:it.name+' '+lab}));f.append(b,el('figcaption',{},lab));return f};
 sz.append(fig(32,48,'1배 32×48',it.native),fig(96,144,'3배 · 작업실',it.x3));
 c.append(sz,el('p',{class:'desc'},it.summary),el('p',{class:'desc'},'<b>실루엣</b> '+it.silhouette),el('p',{class:'desc'},'<b>포즈</b> '+it.pose),el('p',{class:'desc muted'},'<b>겹치지 않게</b> '+it.distinct));
 const sw=el('div',{class:'sw'});for(const m of it.materials)sw.append(el('span',{},`<i style="--c:${m.color}"></i>${m.color} ${m.name}`));c.append(sw);
 const ck=it.check;c.append(el('p',{class:'desc'},`${k(ck.colors+'색',ck.colors<=5)} · 팔레트 밖 ${k(ck.off,ck.off===0)} · 반투명 ${k(ck.partial,ck.partial===0)} · 외곽선 위반 ${k(ck.outline,ck.outline===0)} · 눈 ${k(ck.eyes?'통과':'실패',ck.eyes)} · 몸 행 ${k(ck.body?'통과':'실패',ck.body)} · 디더링 ${k(ck.dither,ck.dither===0)} · 승인 5명 중 가장 비슷한 실루엣 ${it.similar.approved_to} IoU ${it.similar.approved_iou} · 9명 전체 중 ${it.similar.to} IoU ${it.similar.iou}`));
 cards.append(c)}
document.getElementById('distinct-note').innerHTML=`실루엣 IoU(같은 캔버스·발 맞춤 불투명 영역의 교집합/합집합, 좌우 반전 포함 최댓값): 4명 각자의 최댓값은 위 카드에 있습니다. 참고로 이미 승인된 5명끼리의 최댓값은 ${S.ref_iou}, 평균 ${S.ref_iou_mean}입니다. 사람 형태라 몸통·다리는 원래 겹치므로 IoU는 모자·머리·소품 차이를 보는 보조 지표입니다. 직원끼리는 판매 보조와 조제 보조가 가장 비슷합니다(둘 다 모자·큰 소품 없는 짧은 몸). 둘을 더 떼어 놓으려면 판매 보조 치마를 더 넓히거나 조제 보조 가운을 길게 늘이는 수정이 후보입니다.`;
const legend=document.getElementById('legend');for(const [nm,c] of [['가구','#827589'],['숙성통','#A56A3D'],['HUD','#E9B95F'],['입고 병 경로','#3BA8A3'],['판매 병 경로','#DE7356'],['손님','#F4AC68'],['주인공','#C38EB5'],['직원','#FFF0BC']])legend.append(el('span',{},`<i style="--c:${c}"></i>${nm}`));
const stages=[];
function hud(dx){const h=el('div',{class:'hud'});h.style.left=dx+'px';h.style.width='540px';const add=(cls,r,txt='')=>{const d=el('div',{class:cls},txt);Object.assign(d.style,{left:r[0]+'px',top:r[1]+'px',width:r[2]+'px',height:r[3]+'px'});h.append(d)};
 add('pn',[111,66,108,24],'&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;제조 중');add('btn',[114,69,18,18]);add('pn',[111,92,108,22],'상쾌 · 피로 12');add('pn',[6,114,102,24],'1종 재배 중');add('btn',[86,117,18,18]);
 add('cap',[375,152,84,18],'재고 8 / 12');add('cap',[483,41,30,12],'원정');add('cap',[483,55,30,12],'대기');add('btn',[487,68,16,16]);return h}
const OPT={
 A:{title:'A안 · 고용한 직원 중 1명만 순번으로',pros:['그림·코드가 가장 적은 작업실 등장안(한 자리, 한 명)','창 크기·기존 좌표를 바꾸지 않는다','고용 수와 무관하게 화면 밀도가 같다'],cons:['빈 바닥이 없어 어느 자리든 약초대·약초 HUD 등과 겹친다(표 참고)','4명을 한 번에 볼 수 없다 — 교대 규칙이 필요','직원이 자기 설비와 떨어진 자리에 선다']},
 B:{title:'B안 · 작업실 왼쪽 확장 + 앞·뒷줄',pros:['기존 요소와 겹침 0 — 손님·병·HUD를 전혀 가리지 않는다','4명을 동시에 보여 줄 수 있다'],cons:['창(아트)이 넓어진다: 바탕화면 점유 증가','모든 표시 좌표·창 크기·드래그 제한·검증 상수가 바뀌는 대공사','확장 띠의 바닥·벽 그림을 새로 그려야 한다(예시는 바닥 열 복사 임시)','뒷줄은 앞줄에 일부 가려진다']},
 C:{title:'C안 · 각자 설비 근처, 바닥 가구 뒤 반신',pros:['역할이 바로 읽힌다(약초대·솥·판매대·표지판)','창 크기 유지, 4명 동시 표시','하반신이 가려져 행동은 상반신 위주로 그려도 된다'],cons:['판매대·표지판 쪽은 판매 병 경로·손님 자리와 겹친다','약초대 쪽은 약초 HUD·수확 알림과 겹친다','그리기 순서를 설비 사이에 끼워 넣어야 하고 16가지 고용 조합을 검증해야 한다']},
 D:{title:'D안 · 작업실에는 넣지 않고 관리 화면 초상만',pros:['작업실 겹침 0, 새 그림 0장(이번 대기 4장을 그대로 1배로)','코드가 가장 작다(관리 직원 행 아이콘 교체)','기획안 “새 작업실 캐릭터는 필수 조건 아님”과 맞다'],cons:['작업실에서 직원이 보이지 않아 “가게가 커졌다”는 느낌이 약하다']},
};
const opts=document.getElementById('opts');
function stage(width,dx,png,occ){const st=el('div',{class:'stage check'});st.style.width=width+'px';const img=el('img',{src:png,alt:'배치 예시'});img.style.width=width+'px';const oc=el('img',{class:'occ',src:occ,alt:'겹침 확인 영역'});oc.style.width=width+'px';
 st.append(img,oc,hud(dx),Object.assign(el('div',{class:'bar'},'<span>☰</span><span>12,480 G</span><span>낮 · 맑음</span><span class="m">관리</span><span>－</span><span>□</span><span>✕</span>'),{style:`width:${width}px`}));stages.push(st);return {st,img}}
for(const id of ['A','B','C','D']){
 const L=S.layouts[id],o=OPT[id];const box=el('div',{class:'opt'});box.append(el('h3',{},o.title));
 const pc=el('div',{class:'pc'});pc.append(el('div',{},'<h4 class="ok">장점</h4><ul>'+o.pros.map(x=>`<li>${x}</li>`).join('')+'</ul>'),el('div',{},'<h4 class="bad">단점</h4><ul>'+o.cons.map(x=>`<li>${x}</li>`).join('')+'</ul>'));box.append(pc);
 const wrap=el('div',{class:'wrap'});
 if(id==='A'){const ctr=el('div',{class:'controls'});const {st,img}=stage(L.width,0,L.examples[0].png,L.occupancy);
  for(const e of L.examples){const b=el('button',{'aria-pressed':String(e===L.examples[0])},e.name);b.onclick=()=>{img.src=e.png;ctr.querySelectorAll('button').forEach(x=>x.setAttribute('aria-pressed',String(x===b)))};ctr.append(b)}
  box.append(el('p',{class:'desc'},`고정 자리 원본 (${L.origin[0]},${L.origin[1]}) = 표시 (${L.origin[0]*3},${L.origin[1]*3}). 원본 x 0~148 · 발 72~78행의 모든 자리를 훑어(바닥 가구 뒤에 그려 솥·약초대를 덮지 않음, 4명 모두 60% 이상 보임) 4명 중 최악의 금지 요소 겹침이 가장 작은 곳을 골랐습니다. 금지 요소(주인공·손님·판매 병·입고 병·HUD) 겹침이 0인 자리 수: ${L.zero_spots}. 가장 적게 보이는 직원 ${Math.round(L.min_visible*100)}%.`),ctr);wrap.append(st)}
 else if(id==='B'){const {st}=stage(L.width,L.extend,L.png,L.occupancy);box.append(el('p',{class:'desc'},`왼쪽에 표시 ${L.extend}px(원본 ${L.extend/3}) 띠를 더해 아트 폭 ${L.width}px. 앞줄(발 78행): 원정 길잡이·판매 보조, 뒷줄(발 73행, 사이 틈): 조제 보조·재배 보조. 직원끼리 겹침 ${L.staff_vs_staff}px(의도한 앞뒤 겹침), 뒷줄 가림 비율 ${Object.values(L.back_hidden).map(v=>Math.round(v*100)+'%').join(' / ')}. 확장 띠 바닥은 기존 바닥 왼쪽 끝 열을 복사한 임시 그림입니다.`));wrap.append(st)}
 else if(id==='C'){const {st}=stage(L.width,0,L.png,L.occupancy);box.append(el('p',{class:'desc'},'자리(원본 원점·보이는 비율): '+L.spots.map(s=>`${s.name} ${s.zone} (${s.origin.join(',')}) ${Math.round(s.visible*100)}%`).join(' · ')+`. 각 설비 범위 안에서 보이는 부분이 45% 이상인 자리 중 금지 요소 겹침이 가장 작은 곳. 직원끼리 겹침 ${L.staff_vs_staff}px.`));wrap.append(st)}
 else {const {st}=stage(L.width,0,L.png,L.png);box.append(el('p',{class:'desc'},'작업실은 지금과 같습니다. 관리 화면 가구·직원 구역의 직원 행 아이콘 자리에 아래 대기 초상(1배 32×48)을 씁니다. 단골 카드가 손님 대기 첫 칸을 1배로 쓰는 방식과 같습니다.'));
  const pt=el('div',{class:'portraits'});const f=el('figure');const b=el('div',{class:'check'});b.style.padding='6px';b.append(el('img',{src:L.portraits,width:144,height:48,alt:'관리 화면 초상 1배'}));f.append(b,el('figcaption',{},'관리 화면 1배 초상 4명'));pt.append(f);box.append(pt)}
 box.append(wrap);opts.append(box)}
document.getElementById('tog-hud').onchange=e=>stages.forEach(s=>s.classList.toggle('hide-hud',!e.target.checked));
document.getElementById('tog-occ').onchange=e=>stages.forEach(s=>s.classList.toggle('show-occ',e.target.checked));
const t=document.getElementById('table');
t.append(el('tr',{},'<th>안</th><th>직원</th><th>주인공</th><th>손님</th><th>판매 병</th><th>입고 병</th><th>HUD</th><th>가구</th><th>합계</th><th>비고</th>'));
for(const id of ['A','B','C','D'])for(const r of S.rows){const v=r[id];t.append(el('tr',{},`<td>${id}</td><td>${r.staff}</td>${['keeper','customers','sale_bottle','stock_bottles','hud','furniture','total'].map(x=>`<td>${n(v[x])}</td>`).join('')}<td>${id==='C'?`${v.zone} · 보임 ${Math.round(v.visible*100)}%`:(id==='B'?'확장 띠 안':(id==='D'?'작업실에 없음':'한 번에 1명'))}</td>`))}
const w=document.getElementById('work');
w.append(el('tr',{},'<th>안</th><th>새 키프레임(사람이 그림)</th><th>파생 칸</th><th>그 밖의 그림</th><th>코드 범위</th><th>규모</th><th>위험</th>'));
for(const id of ['A','B','C','D']){const v=S.workload[id];w.append(el('tr',{},`<td>${id}</td><td>${v.keyframes_total}장 (대기 ${v.keyframes.idle}: 이번 후보를 그대로 · 역할 행동 ${v.keyframes.role_action}: 새로)</td><td>${v.derived_cells_note}</td><td>${v.other_art}</td><td><ul>${v.code.map(x=>`<li>${x}</li>`).join('')}</ul></td><td>${v.size}</td><td>${v.risk}</td>`))}
const A=S.rows.map(r=>r.A.total),C=S.rows.map(r=>r.C.total);
document.getElementById('reco').innerHTML=`<b>추천: D를 먼저, 그 다음 A.</b> 지금 작업실에는 직원이 설 빈 바닥이 없습니다(A의 최선 자리도 4명 겹침 합 ${A.reduce((a,b)=>a+b,0)}px, C 합 ${C.reduce((a,b)=>a+b,0)}px). D는 새 그림 없이 이번 대기 4장만으로 “직원이 생겼다”를 보여 주고, 작업실 등장은 A(한 명 순번)로 범위를 줄여 다음 단계에서 판단하는 편이 “빡센” 부분을 나눠서 진행할 수 있습니다. B는 겹침 0이지만 창 폭·좌표 전체를 바꾸는 대공사입니다.`;
</script></body></html>
"""


if __name__ == "__main__":
    raise SystemExit(main())
