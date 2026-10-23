"""F22 regulars: four customer souvenir icons (candidate art only).

Reads hand-authored 32x32 native pixel maps
(art/mockups/f22-regulars-souvenirs-v1/source/*.txt), registers them as
native PNGs, runs the fixed tools/process_pixel_art.py pipeline with an
explicit per-color material manifest, then adds souvenir checks (outline,
palette, color count, partial alpha, canvas coverage, dithering, top-left
lighting) and writes the review page.

Candidate only: nothing under assets/ or scripts/ is written. Player saves,
the running game and Windows registration are untouched.

Run with Pillow + NumPy: python tools/build_f22_souvenirs_v1.py
"""
from __future__ import annotations

import colorsys
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MOCK = ROOT / "art/mockups/f22-regulars-souvenirs-v1"
SRC = MOCK / "source"
PIPE = MOCK / "pipeline"
SPRITES = MOCK / "sprites"
SCALE = 3
SIZE = (32, 32)
OUTLINE_HEX = "#241C32"
OUTLINE = (0x24, 0x1C, 0x32)
DATE = "2026-10-22"

# Map letter -> (approved color, ramp). Each souvenir declares the letters it
# may use and the semantic material each letter stands for.
LEGEND = {
    "#": ("#241C32", "outline"),
    "d": ("#A56A3D", "gold"), "g": ("#E9B95F", "gold"), "h": ("#FFF0BC", "gold"),
    "P": ("#50315F", "purple"), "p": ("#86548E", "purple"), "l": ("#C38EB5", "purple"),
    "L": ("#3D544D", "leaf"), "e": ("#718C59", "leaf"), "n": ("#B5C77D", "leaf"),
    "k": ("#4A3C52", "stone"), "m": ("#827589", "stone"),
    "r": ("#DE7356", "fire"),
}

SOUVENIRS = [
    {
        "id": "souvenir_compass", "customer": "traveler", "customer_name": "여행자", "name": "낡은 나침반",
        "story": "출발 전에 들르는 단골 가게",
        "description": "둥근 놋쇠 케이스와 위쪽 고리, 크림색 문자판, 북쪽(빨강)·남쪽(어둠) 바늘. 놋쇠는 금빛 중간·그림자 위주로 칠해 낡은 느낌을 내고 좌측 상단 테에만 크림 반짝임을 둔다.",
        "materials": {"#": "outline", "d": "brass_shadow", "g": "brass", "h": "dial_and_glint", "r": "needle_north"},
    },
    {
        "id": "souvenir_bookmark", "customer": "mage", "customer_name": "여마법사", "name": "별무늬 책갈피",
        "story": "밤 연구에 필요한 물약을 찾음",
        "description": "제비꼬리 끝의 보라 천 책갈피, 가운데 큰 금빛 별과 라일락 작은 별 3개, 위 구멍에서 나온 끈과 오른쪽 금빛 술. 왼쪽 가장자리 밝게, 오른쪽 가장자리 어둡게.",
        "materials": {"#": "outline", "P": "cloth_shadow", "p": "cloth", "l": "cloth_light_and_sparkle", "g": "star_and_tassel"},
    },
    {
        "id": "souvenir_leaf_brooch", "customer": "elf", "customer_name": "엘프", "name": "잎사귀 브로치",
        "story": "비 오는 날 정화 물약을 사러 옴",
        "description": "45도로 기운 큰 잎사귀와 금빛 잎맥 세공(가운데 줄기 + 위·오른쪽으로 곧게 뻗는 곁맥 3쌍), 왼쪽 아래 둥근 금 받침과 핀 머리. 잎은 좌상단 반쪽이 밝고 우하단 반쪽이 어둡다.",
        "materials": {"#": "outline", "L": "leaf_shadow", "e": "leaf", "n": "leaf_light", "g": "gold_filigree"},
    },
    {
        "id": "souvenir_silver_bell", "customer": "rogue", "customer_name": "고양이 도적", "name": "작은 은방울",
        "story": "야간 일을 앞두고 조용히 방문",
        "description": "고양이 목걸이형 둥근 은방울: 가운데 테, 아래쪽 양끝이 둥근 가로 홈과 세로 홈, 위에 고양이 도적의 붉은 목도리와 같은 산호색 리본. 은은 돌·금속 램프 2단, 좌측 상단 크림 반짝임.",
        "materials": {"#": "outline", "k": "silver_shadow", "m": "silver", "h": "metal_glint", "r": "ribbon"},
    },
]


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


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
        # Souvenir metadata (ignored by the pipeline, kept for review/runtime hand-off).
        "customer": item["customer"], "customer_name": item["customer_name"], "name_ko": item["name"],
    }


def run_pipeline(manifest_path: Path) -> dict:
    result = subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"), rel(manifest_path)],
                            cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    report = json.loads((PIPE / "validation.json").read_text(encoding="utf-8"))
    if result.returncode != 0 or report["status"] != "passed":
        raise SystemExit(f"process_pixel_art failed: {report.get('error')}\n{result.stderr}")
    return report


# ---------------------------------------------------------------- checks
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
    """3x3 two-color checkerboards of non-outline colors = dithering.

    A 2x2 test would also flag every clean 1px diagonal line (the leaf midrib),
    so a dithered patch must alternate over a full 3x3 window."""
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


def check_souvenir(item: dict, image: Image.Image, registered: Image.Image, palette: set, ramps: dict, pipe: dict) -> dict:
    data = np.array(image.convert("RGBA"))
    alpha = data[:, :, 3]
    opaque = alpha == 255
    colors = sorted({"#%02X%02X%02X" % tuple(p[:3]) for p in data[opaque]})
    ys, xs = np.where(opaque)
    bbox = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
    bw, bh = bbox[2] - bbox[0], bbox[3] - bbox[1]
    by_ramp: dict[str, list[str]] = {}
    for c, m in item["materials"].items():
        by_ramp.setdefault(LEGEND[c][1], []).append(LEGEND[c][0])
    ramp_ok = all(hex_ in ramps[ramp]["colors"] for ramp, hexes in by_ramp.items() for hex_ in hexes)
    shades = {ramp: len(hexes) for ramp, hexes in by_ramp.items()}
    light = lighting(data)
    check = {
        "customer": item["customer"], "customer_name": item["customer_name"], "name": item["name"],
        "size": list(image.size), "native_32x32": image.size == SIZE,
        "colors": colors, "color_count": len(colors), "max_colors": 5,
        "off_palette_colors": sum(1 for c in colors if rgb(c) not in palette),
        "partial_alpha_pixels": int(((alpha != 0) & (alpha != 255)).sum()),
        "outline_violations": outline_violations(data),
        "outline_color_present": OUTLINE_HEX in colors,
        "materials": {m: {"color": LEGEND[c][0], "ramp": LEGEND[c][1]} for c, m in item["materials"].items()},
        "colors_in_declared_ramps": ramp_ok, "shades_per_ramp": shades,
        "max_3_shades_per_ramp": all(n <= 3 for n in shades.values()),
        "opaque_bbox": bbox, "bbox_canvas_fraction": [round(bw / SIZE[0], 3), round(bh / SIZE[1], 3)],
        "opaque_fill_fraction": round(float(opaque.sum()) / (SIZE[0] * SIZE[1]), 3),
        "dither_2x2_blocks": dither_blocks(data), "lighting": light,
        "pipeline_passed": pipe["passed"],
        "pipeline_preserved_source": bool(np.array_equal(np.array(registered.convert("RGBA")), data)),
        "native_sha256": hashlib.sha256(data.tobytes()).hexdigest(),
    }
    check["canvas_coverage_ok"] = min(check["bbox_canvas_fraction"]) >= 0.6
    check["passed"] = bool(
        check["native_32x32"] and check["color_count"] <= 5 and check["outline_color_present"]
        and check["off_palette_colors"] == 0 and check["partial_alpha_pixels"] == 0
        and not check["outline_violations"] and check["colors_in_declared_ramps"]
        and check["max_3_shades_per_ramp"] and check["canvas_coverage_ok"] and not check["dither_2x2_blocks"]
        and light["top_left_lit"] and check["pipeline_passed"] and check["pipeline_preserved_source"]
        and set(colors) == {LEGEND[c][0] for c in item["materials"]})
    return check


# ---------------------------------------------------------------- review page
REVIEW = r"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>F22 단골 기념품 후보</title><style>
@font-face{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}
:root{--bg:#241c32;--panel:#30263f;--line:#827589;--text:#fff0bc;--muted:#c38eb5;--accent:#e9b95f;--ok:#b5c77d;--bad:#de7356}
*{box-sizing:border-box}html,body{background:var(--bg)}body{margin:0;color:var(--text);font:15px/1.55 Pretendard,system-ui,sans-serif}
main{max-width:1000px;margin:auto;padding:18px 16px 40px}h1{font-size:23px;margin:0 0 6px}h2{font-size:17px;margin:26px 0 8px}
p{margin:6px 0 10px}.muted{color:var(--muted)}code{font-size:13px;color:var(--muted)}
.note{border-left:3px solid #718c59;padding:8px 12px;background:var(--panel);margin:10px 0}
.check{background-color:#4a3c52;background-image:linear-gradient(45deg,#3f3347 25%,transparent 25%),linear-gradient(-45deg,#3f3347 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#3f3347 75%),linear-gradient(-45deg,transparent 75%,#3f3347 75%);background-size:12px 12px;background-position:0 0,0 6px,6px -6px,-6px 0}
img{image-rendering:pixelated;image-rendering:crisp-edges;max-width:none;display:block}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:12px}
.card{background:var(--panel);border:1px solid #4a3c52;border-radius:6px;padding:12px}
.card h3{margin:0;font-size:16px}.card .who{color:var(--muted);font-size:13px}
.sizes{display:flex;align-items:flex-end;gap:10px;margin:10px 0 6px;flex-wrap:wrap}
.sizes figure{margin:0;text-align:center}.sizes .check{display:flex;align-items:center;justify-content:center;padding:4px}
figcaption{font-size:11px;color:var(--muted);margin-top:3px}
.desc{font-size:13px;margin:6px 0}.sw{display:flex;flex-wrap:wrap;gap:6px;font-size:11px;color:var(--muted)}.sw span{display:flex;align-items:center;gap:3px}
.sw i{width:12px;height:12px;display:inline-block;border:1px solid #000;background:var(--c)}
.panel{background:#30263f;border:2px solid #50315f;border-radius:6px;padding:6px;max-width:420px}
.row{display:flex;align-items:center;gap:8px;padding:5px 6px;border-bottom:1px solid #4a3c52}.row:last-child{border:0}
.row .ic{width:32px;height:32px;flex:none}.row .ic.s24{width:24px;height:24px}.row b{font-weight:normal}.row small{color:var(--muted);display:block;font-size:12px}
.row .tag{margin-left:auto;font-size:12px;color:#241c32;background:var(--accent);border-radius:3px;padding:1px 6px}
.strip{display:flex;gap:6px;flex-wrap:wrap;padding:8px}
table{border-collapse:collapse;width:100%;font-size:13px}th,td{border-bottom:1px solid #4a3c52;padding:5px 6px;text-align:left;vertical-align:top}th{color:var(--muted);font-weight:normal}
.ok{color:var(--ok)}.bad{color:var(--bad)}.table-wrap{overflow-x:auto}
</style></head><body><main>
<h1>F22 단골 기념품 후보 v1</h1>
<p class="muted">후보 단계입니다. <code>assets/</code>·<code>scripts/</code>·저장은 바꾸지 않았습니다. 승인 전에는 게임에 연결하지 않습니다.</p>
<p id="overall"></p>
<div class="note">원본 32×32 · 승인 24색과 재질 램프만 사용 · 공통 외곽선 #241C32 1픽셀 · 물체당 최대 5색 · 반투명 0 · 좌측 상단 조명 · 디더링 없음 · 공통 3배 최근접 확대. 체크무늬는 페이지 CSS이고 PNG는 투명 배경입니다.</div>

<h2>기념품 4종</h2>
<div class="cards" id="cards"></div>

<h2>관리 패널 크기 미리보기</h2>
<p class="muted">관리 패널의 작은 아이콘 칸(24px)과 주 아이콘 칸(32px = 원본 1배)에 놓은 모습입니다. 24px은 원본 32px의 0.75배 축소라 픽셀이 고르지 않게 보일 수 있습니다. 실제 적용 칸 크기는 승인 후 정합니다.</p>
<div class="panel" id="panel"></div>
<h2>같은 크기로 나란히 · 32px / 3배 96px</h2>
<div class="check strip" id="strip32"></div>
<div class="check strip" id="strip96" style="margin-top:8px"></div>

<h2>검사 결과</h2>
<div class="table-wrap"><table id="table"></table></div>
<p class="muted">재현: <code>python tools/build_f22_souvenirs_v1.py</code> → 원본 지도(<code>source/*.txt</code>) → 등록 PNG → <code>tools/process_pixel_art.py</code>(<code>manifest.json</code>) → 추가 검사(<code>validation.json</code>) → 이 페이지. 수치 검사는 디자인 승인을 대신하지 않습니다.</p>

<h2>정해 주실 것</h2>
<div class="note">1. 네 기념품의 모양과 색을 이대로 쓸지, 고칠 곳(예: 책갈피 끈, 은방울 리본 색).<br>2. 관리 패널 기념품 칸에 쓸 표시 크기(32px 원본 1배 권장, 24px 칸이면 축소 표시).</div>
</main><script>
const S=/*SUMMARY*/null;
const el=(t,a={},h='')=>{const e=document.createElement(t);for(const k in a)e.setAttribute(k,a[k]);e.innerHTML=h;return e};
document.getElementById('overall').innerHTML=S.passed?'<span class="ok">모든 검사 통과</span> (물체별 색 수·팔레트 밖 0·반투명 0·외곽선 위반 0·디더링 0)':'<span class="bad">검사 실패 항목이 있습니다</span>';
const cards=document.getElementById('cards'),panel=document.getElementById('panel'),s32=document.getElementById('strip32'),s96=document.getElementById('strip96');
for(const it of S.items){
 const c=el('div',{class:'card'});
 c.append(el('div',{class:'who'},it.customer_name+' 단골 기념품'),el('h3',{},it.name));
 const sz=el('div',{class:'sizes'});
 for(const [w,lab,src] of [[24,'24px',it.native],[32,'32px · 1배',it.native],[96,'96px · 3배',it.x3]]){
  const f=el('figure');const b=el('div',{class:'check'});b.append(el('img',{src,width:w,height:w,alt:it.name+' '+lab}));f.append(b,el('figcaption',{},lab));sz.append(f)}
 c.append(sz,el('p',{class:'desc'},it.description));
 const sw=el('div',{class:'sw'});for(const m of it.materials)sw.append(el('span',{},`<i style="--c:${m.color}"></i>${m.color} ${m.name}`));c.append(sw);
 c.append(el('p',{class:'desc muted'},`<code>${it.id}</code> · ${it.color_count}색`));cards.append(c);
 for(const [cls,w] of [['ic s24',24],['ic',32]]){
  const r=el('div',{class:'row'});const box=el('div',{class:'check '+cls});box.append(el('img',{src:it.native,width:w,height:w,alt:''}));
  r.append(box,el('div',{},`<b>${it.name}</b><small>${it.customer_name} · ${w}px 칸</small>`),el('span',{class:'tag'},'장착'));panel.append(r)}
 s32.append(el('img',{src:it.native,width:32,height:32,alt:it.name,title:it.customer_name+' · '+it.name}));
 s96.append(el('img',{src:it.x3,width:96,height:96,alt:it.name,title:it.customer_name+' · '+it.name}));
}
const t=document.getElementById('table');
t.append(el('tr',{},'<th>손님 · 기념품</th><th>색 수(외곽선 포함)</th><th>팔레트 밖</th><th>반투명</th><th>외곽선 위반</th><th>디더링</th><th>캔버스 사용(가로×세로)</th><th>조명 좌상단</th><th>판정</th>'));
for(const it of S.items){const k=(v,good)=>`<span class="${good?'ok':'bad'}">${v}</span>`;
 t.append(el('tr',{},`<td>${it.customer_name} · ${it.name}</td><td>${k(it.color_count+' / 5',it.color_count<=5)}</td><td>${k(it.off_palette,it.off_palette===0)}</td><td>${k(it.partial_alpha,it.partial_alpha===0)}</td><td>${k(it.outline_violations,it.outline_violations===0)}</td><td>${k(it.dither,it.dither===0)}</td><td>${k(Math.round(it.coverage[0]*100)+'% × '+Math.round(it.coverage[1]*100)+'%',Math.min(...it.coverage)>=0.6)}</td><td>${k(it.lit?'예':'아니오',it.lit)}</td><td>${k(it.passed?'통과':'실패',it.passed)}</td>`))}
</script></body></html>
"""


def main() -> int:
    palette = {rgb(v) for v in (ROOT / "art/palette.hex").read_text(encoding="utf-8").split()}
    ramp_data = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
    ramps = ramp_data["ramps"]
    for char, (hex_, ramp) in LEGEND.items():
        if rgb(hex_) not in palette or hex_ not in ramps[ramp]["colors"]:
            raise SystemExit(f"Legend {char} {hex_} is not an approved {ramp} color")

    # ---- register hand-authored maps as native PNGs
    assets, registered, source_hashes = [], {}, {}
    for item in SOUVENIRS:
        if item["materials"].get("#") != "outline":
            raise SystemExit("Every souvenir must declare the shared outline")
        text_path = SRC / f"{item['id']}.txt"
        rows = read_map(text_path)
        image = render_map(rows, item["materials"])
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
                "feature": "F22 regulars souvenirs", "runtime_integrated": False, "assets": assets}
    manifest_path = MOCK / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    pipe_report = run_pipeline(manifest_path)

    # ---- souvenir checks on the pipeline outputs, then publish candidate sprites
    SPRITES.mkdir(exist_ok=True)
    checks, items = {}, []
    for item in SOUVENIRS:
        native = Image.open(PIPE / f"{item['id']}-native.png").convert("RGBA")
        check = check_souvenir(item, native, registered[item["id"]], palette, ramps, pipe_report["assets"][item["id"]])
        big = native.resize((native.width * SCALE, native.height * SCALE), Image.Resampling.NEAREST)
        expected = np.repeat(np.repeat(np.array(native), SCALE, axis=0), SCALE, axis=1)
        check["integer_3x_nearest_verified"] = bool(np.array_equal(np.array(big), expected))
        check["passed"] = check["passed"] and check["integer_3x_nearest_verified"]
        check["source"] = source_hashes[item["id"]]
        checks[item["id"]] = check
        if check["passed"]:
            native.save(SPRITES / f"{item['id']}.png")
            big.save(SPRITES / f"{item['id']}-3x.png")
        items.append({"id": item["id"], "customer_name": item["customer_name"], "name": item["name"],
                      "description": item["description"],
                      "native": f"sprites/{item['id']}.png", "x3": f"sprites/{item['id']}-3x.png",
                      "materials": [{"name": m, "color": LEGEND[c][0]} for c, m in item["materials"].items()],
                      "color_count": check["color_count"], "off_palette": check["off_palette_colors"],
                      "partial_alpha": check["partial_alpha_pixels"], "outline_violations": len(check["outline_violations"]),
                      "dither": len(check["dither_2x2_blocks"]), "coverage": check["bbox_canvas_fraction"],
                      "lit": check["lighting"]["top_left_lit"], "passed": check["passed"]})

    passed = all(c["passed"] for c in checks.values())
    report = {"schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False,
              "date": DATE, "scale": SCALE, "palette": "art/palette.hex", "ramps": "art/ramps.json",
              "new_palette_colors": 0, "pipeline_report": rel(PIPE / "validation.json"),
              "pipeline_status": pipe_report["status"], "rules": {
                  "native_size": list(SIZE), "max_colors_including_outline": 5, "off_palette": 0, "partial_alpha": 0,
                  "outline": "every opaque pixel 4-adjacent to transparency (or the canvas edge) is #241C32",
                  "max_shades_per_ramp": 3, "dithering": "no 3x3 two-color checkerboards (1px diagonal lines are allowed)",
                  "canvas_coverage": "opaque bbox >= 60% of the canvas in both directions",
                  "lighting": "non-outline pixels on the top-left side brighter than the bottom-right side"},
              "souvenirs": checks, "passed": passed}
    if not passed:
        report["final_outputs_from_this_run"] = False
    (MOCK / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    generation = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False, "date": DATE,
        "mode": ("hand-authored native 32x32 pixel maps (no image generator). Base silhouettes were drafted with simple "
                 "circle/leaf shapes and an automatic 1px #241C32 silhouette outline, then details (needle, ticks, slot, "
                 "veins, star, tassel, glints) were placed by hand. The .txt maps are the authoritative source."),
        "reference": "docs/성장과-단골-꾸미기-기획안.md · 손님별 이야기와 기념품 후보; color/pixel rules in AGENTS.md",
        "legend": {c: {"color": h, "ramp": r} for c, (h, r) in LEGEND.items()},
        "souvenirs": {i["id"]: {"customer": i["customer"], "customer_name": i["customer_name"], "name": i["name"],
                                "story": i["story"], "description": i["description"],
                                "materials": {m: LEGEND[c][0] for c, m in i["materials"].items()}} for i in SOUVENIRS},
        "new_palette_colors": 0, "postprocess_tool": "tools/process_pixel_art.py with manifest.json",
    }
    (MOCK / "generation.json").write_text(json.dumps(generation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    approval = {"schema_version": 1, "status": "candidate", "approved_by_user": False, "approved_on": None,
                "user_reply": None, "review": rel(MOCK / "review.html"), "runtime_integrated": False,
                "scope": {i["id"]: f"{i['customer_name']} 단골 기념품 · {i['name']}" for i in SOUVENIRS},
                "pending_decisions": ["4종 모양·색 승인 또는 수정 지시", "관리 패널 기념품 칸 표시 크기(32px 원본 1배 / 24px 축소)"],
                "note": "사용자 승인 전 후보. assets/ 게시와 게임 연결은 승인 후 별도 작업으로 진행한다."}
    (MOCK / "approval.json").write_text(json.dumps(approval, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    summary = {"passed": passed, "items": items}
    (MOCK / "review.html").write_text(REVIEW.replace("/*SUMMARY*/null", json.dumps(summary, ensure_ascii=False)), encoding="utf-8")

    print(json.dumps({"passed": passed, "souvenirs": {k: {"passed": c["passed"], "colors": c["color_count"],
                      "off_palette": c["off_palette_colors"], "partial_alpha": c["partial_alpha_pixels"],
                      "outline_violations": len(c["outline_violations"]), "dither": len(c["dither_2x2_blocks"]),
                      "coverage": c["bbox_canvas_fraction"], "lighting": c["lighting"]} for k, c in checks.items()}},
                     ensure_ascii=False, indent=1))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
