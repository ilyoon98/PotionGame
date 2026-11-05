"""Join verified presentation fragments and build a self-contained art review.

No economy data, source sprites, player saves or running processes are changed.
Run after build_ui_pixel_v2.py and build_ui_pixel_v2_potions.py.
"""
from __future__ import annotations

import base64
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "art/mockups/ui-pixel-v2"
DEST = ROOT / "assets/ui_pixel_v2"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def local(path):
    return ROOT / path.removeprefix("res://")


def img(path, label, scale=3):
    from PIL import Image
    source = local(path)
    width, height = Image.open(source).size
    uri = "data:image/png;base64," + base64.b64encode(source.read_bytes()).decode("ascii")
    return f'<img src="{uri}" alt="{html.escape(label)}" width="{width*scale}" height="{height*scale}">'


def main():
    generated = read(REVIEW / "generated-icons.json")
    potions = read(REVIEW / "potion-icons.json")
    icons = dict(generated["icons"])
    icons.update(potions)
    icons.update({"recipe:" + key: value for key, value in potions.items()})
    for track, tiers in generated["equipment"].items():
        icons[track] = tiers[0]
        icons["growth:" + track] = tiers[0]
    for key in list(icons):
        if key.startswith("family_"):
            icons["growth:" + key] = icons[key]
    for alias, target in {"employee": "sales_assistant", "garden": "herb_pot",
                          "journey": "expedition", "mushroom": "moon_mushroom"}.items():
        icons[alias] = icons[target]
    content = read(ROOT / "data/content_expansion.json")
    for entry in content["employees"]:
        icons["growth:" + entry["id"]] = icons[entry["id"]]
    catalog = {
        "schema_version": 1,
        "status": "runtime_connected_user_requested_design_refresh",
        "date": "2026-11-05",
        "design_review": "art/mockups/ui-pixel-v2/review.html",
        "notes": ["Approved 24-color material ramps; no new palette colors.",
                  "Generated UI sprites: native32, <=5 colors, binary alpha, shared outline.",
                  "Potion icons package approved bottles at exactly2x without recoloring.",
                  "Existing character art and approved growth-sheet exceptions are preserved.",
                  "The user requested comprehensive improvement; this does not claim separate visual approval."],
        "icons": icons, "equipment": generated["equipment"],
    }
    for path in set(icons.values()) | {p for tiers in generated["equipment"].values() for p in tiers}:
        assert local(path).is_file(), path
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    names = {entry["id"]: entry["name"] for cat in ["regions", "materials", "employees", "potions"] for entry in content[cat]}
    sections = []
    for category, title in [("regions", "원정 9곳"), ("materials", "약초와 재료 12종"), ("employees", "직원 역할 4종")]:
        cards = []
        for entry in content[category]:
            key, name = entry["id"], entry["name"]
            old = entry["icon_candidate"]
            new = icons[key]
            cards.append(f'<article><h3>{html.escape(name)}</h3><div class="pair"><figure>{img(old,name+" 이전")}<figcaption>이전</figcaption></figure><figure>{img(new,name+" 개선")}<figcaption>개선</figcaption></figure></div><code>{key}</code></article>')
        sections.append(f'<section id="{category}"><h2>{title}</h2><div class="grid">{"".join(cards)}</div></section>')
    equipment_names = {"cauldron":"솥", "herb_pot":"기본 화분", "sales_counter":"판매대", "precision_filter":"정밀 여과기", "herb_storage":"약초 보관 선반", "potion_cabinet":"물약 보관장", "drying_rack":"건조대", "expedition_path":"원정 길 정비"}
    equipment = []
    for track, tiers in generated["equipment"].items():
        figures = "".join(f'<figure>{img(path,equipment_names[track]+label)}<figcaption>{label}</figcaption></figure>' for path,label in zip(tiers,["기본","개량","고급"]))
        equipment.append(f'<article><h3>{equipment_names[track]}</h3><div class="pair tiers">{figures}</div></article>')
    sections.append(f'<section id="equipment"><h2>설비 8계열 · 3단계</h2><div class="grid equipment">{"".join(equipment)}</div></section>')
    role_names = {"family_vitality":"활력", "family_arcane":"비술", "family_nature":"자연", "family_craft":"기교", "flow":"자동 운영", "basic":"레시피", "filter":"정밀 여과", "reputation":"명성", "coin":"골드", "visitors":"손님", "unknown_recipe":"미발견 레시피", "expedition":"원정"}
    cards = "".join(f'<article><h3>{name}</h3><div class="sample">{img(icons[key],name)}</div></article>' for key,name in role_names.items())
    sections.append(f'<section id="roles"><h2>계열과 공통 아이콘</h2><div class="grid roles">{cards}</div></section>')
    cards = "".join(f'<article><h3>{html.escape(names.get(key,key))}</h3><div class="sample">{img(path,names.get(key,key))}</div></article>' for key,path in potions.items())
    sections.append(f'<section id="potions"><h2>물약과 레시피 40종</h2><p>작업실의 승인된 병을 원본 그대로 2배로 담았습니다. 목록과 선반에서 같은 물약을 볼 수 있습니다.</p><div class="grid roles">{cards}</div></section>')
    captures = []
    for key, name in [("expeditions-top", "원정"), ("herbs-top", "약초"), ("potions-top", "물약"), ("upgrades-bottom", "직원")]:
        path = f"art/mockups/ui-pixel-v2/runtime/{key}.png"
        if local(path).is_file():
            captures.append(f'<article><h3>{name}</h3><div class="capture">{img(path,name+" 실제 엔진 렌더",1)}</div></article>')
    if captures:
        sections.append(f'<section id="runtime"><h2>실제 게임 렌더</h2><p>완성된 가게의 격리 검증 상태입니다. 사용자 저장을 불러오지 않았습니다.</p><div class="grid equipment">{"".join(captures)}</div></section>')
    document = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>달그늘 · 아이콘 디자인 개선</title>
<style>
:root{color-scheme:dark;--bg:#1c2222;--surface:#29312f;--ink:#eee6d5;--muted:#b9c2b2;--line:#414d45;--accent:#b5c77d}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 system-ui,'Malgun Gothic',sans-serif}main{max-width:1200px;margin:auto;padding:44px 28px 80px}header{border-bottom:1px solid var(--line);padding-bottom:28px}small,code,figcaption{color:var(--muted)}h1{font-size:32px;margin:8px 0 12px;letter-spacing:-1px}h2{font-size:23px;margin:0 0 20px}h3{font-size:16px;font-weight:600;margin:0 0 12px}p{max-width:790px;color:var(--muted)}nav{display:flex;gap:18px;flex-wrap:wrap;margin:22px 0 12px}a{color:var(--accent);text-underline-offset:4px}button{font:inherit;background:var(--surface);color:var(--ink);border:1px solid var(--line);padding:8px 14px;border-radius:4px;cursor:pointer}button:focus-visible,a:focus-visible{outline:2px solid var(--accent);outline-offset:4px}section{padding-top:42px;scroll-margin-top:16px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}article{padding:20px;background:var(--surface);border:1px solid var(--line);border-radius:5px}.pair{display:flex;align-items:end;justify-content:space-around;min-height:152px;gap:8px}figure{margin:0;text-align:center;flex:1}figcaption{margin-top:10px;font-size:12px}img{object-fit:contain;image-rendering:pixelated;max-width:none}.sample{height:110px;display:grid;place-items:center}.roles{grid-template-columns:repeat(5,minmax(0,1fr))}.roles article{padding:16px}.equipment{grid-template-columns:repeat(2,minmax(0,1fr))}.tiers{min-height:130px}.light{--bg:#d6decf;--surface:#e5eadf;--ink:#29312f;--muted:#4f6054;--line:#b8c4b0;--accent:#3d544d}footer{border-top:1px solid var(--line);margin-top:40px;padding-top:20px;color:var(--muted)}@media(max-width:850px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.roles{grid-template-columns:repeat(3,minmax(0,1fr))}.equipment{grid-template-columns:1fr}}@media(max-width:550px){main{padding:24px 14px}.grid{grid-template-columns:1fr}.roles{grid-template-columns:repeat(2,minmax(0,1fr))}h1{font-size:27px}}
</style><main><header><small>달그늘 물약상점 · 2026.11.05</small><h1>같은 상점의 그림으로</h1><p>원정·재료·직원·설비의 잔선을 줄이고 승인된 색상, 한 픽셀 외곽선, 선명한 원본 크기로 맞췄습니다. 비교 그림은 모두 원본의 3배입니다. 게임 목록에서는 32픽셀 원본을 정수 배율로 표시합니다.</p><nav><a href="#regions">원정</a><a href="#materials">약초</a><a href="#employees">직원</a><a href="#equipment">설비</a><a href="#roles">공통</a><a href="#potions">물약</a></nav><button type="button" onclick="document.body.classList.toggle('light')">밝은 배경 / 어두운 배경</button></header>'''
    document += "".join(sections)
    document += '<style>.capture img{max-width:100%;height:auto;image-rendering:auto}.capture{overflow:hidden}</style>'
    document += '<footer><strong>그대로 이어가는 디자인</strong><p>주인공과 손님 5명은 104개 시트·6,656프레임 검사에서 기존 규칙을 통과했습니다. 직원은 기존 결정대로 역할 아이콘으로 표시합니다. 약초의 화분 성장 그림 11종은 기존 승인 예외를 유지합니다. 물약병의 기존 코르크 경계 픽셀도 보존합니다.</p><p>이 페이지는 자산 비교표입니다. 실제 게임 캡처는 별도 검증 결과에 보관합니다. 생성 원본·프롬프트·재질 마스크·검사 결과를 같은 폴더에 기록했습니다.</p></footer></main></html>'
    (REVIEW / "review.html").write_text(document, encoding="utf-8")
    print(json.dumps({"icons":len(icons), "equipment_tracks":len(generated["equipment"]), "unique_pngs":len(set(icons.values()) | {p for tiers in generated["equipment"].values() for p in tiers}), "review":str(REVIEW/"review.html")},ensure_ascii=False))


if __name__ == "__main__":
    main()
