"""Publish refined faces, before/after views and checks for all affected poses."""
from __future__ import annotations

import hashlib
import json
import numpy as np
from PIL import Image

from process_pixel_art import ROOT,validate
import refine_character_faces_v1 as faces
import build_traveler_keyframes_v1 as common

OUT=faces.ART
LABELS={"keeper":"남자 주인공","elf":"엘프","mage":"여마법사","traveler":"여행자"}


def dump(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def jaw_widths(frame,name):
    a=np.array(frame);skin=np.all(a==faces.SKIN,axis=2);skin[:11]=False;skin[27:]=False
    p=faces.PROFILES[name];seed=(p["eye_x"][0]+1,p["eye_y"])
    queue=[seed];seen=set()
    while queue:
        x,y=queue.pop()
        if not(0<=x<32 and 0<=y<48) or (x,y) in seen or not skin[y,x]:continue
        seen.add((x,y));queue.extend(((x-1,y),(x+1,y),(x,y-1),(x,y+1)))
    widths={}
    for y in range(23,27):
        xs=[x for x,yy in seen if yy==y]
        widths[str(y)]=max(xs)-min(xs)+1 if xs else 0
    return widths


def main():
    report={"status":"passed","art_status":"candidate","approved_by_user":False,"native_canvas":[32,48],"scale":3,
        "face_source":"generation.json","checks":{},"keyframe_checks":{},"game_assets_integrated":False}
    old_frames={};new_frames={}
    for name in faces.PROFILES:
        original=Image.open(OUT / "source/originals" / f"{name}.png").convert("RGBA")
        refined=faces.apply(original,name);closed=faces.blink(refined,name)
        a=np.array(refined);old=np.array(original)
        check=validate(refined,[32,48],faces.PALETTE,5)
        check.update(eyes=faces.eye_checks(refined,name),closed_eyes=faces.eye_checks(closed,name,True),
            body_from_row27_unchanged=bool(np.array_equal(a[27:],old[27:])),
            before_lower_face_skin_widths=jaw_widths(original,name),after_lower_face_skin_widths=jaw_widths(refined,name),
            native_sha256=hashlib.sha256(refined.tobytes()).hexdigest())
        if not check["passed"] or not check["body_from_row27_unchanged"]:raise ValueError(f"Face check failed: {name}")
        if name=="keeper":
            check["upper_right_fringe_filled"]=all(tuple(a[y,x])==(*faces.rgb("#916047"),255) for x,y in faces.PROFILES[name]["fringe_fill"])
            if not check["upper_right_fringe_filled"]:raise ValueError("Keeper fringe recess returned")
        report["checks"][name]=check
        refined.save(OUT / "faces" / f"{name}.png");closed.save(OUT / "faces" / f"{name}-blink.png")
        old_frames[name]=original;new_frames[name]=refined
    for name in ("elf","mage","traveler"):
        folder=ROOT / "art/characters/keyframes-v1" / name
        validation=json.loads((folder / "validation.json").read_text(encoding="utf-8"))
        if validation["status"]!="passed":raise ValueError(f"Customer keyframes have failed checks: {name}")
        checks=[]
        for pose in common.POSES:
            old=Image.open(OUT / "source/before-keyframes" / name / f"{pose}.png").convert("RGBA")
            frame=Image.open(folder / "frames" / f"{pose}.png").convert("RGBA")
            same_body=np.array_equal(np.array(frame)[27:],np.array(old)[27:])
            if not same_body:raise ValueError(f"Body changed while refining face: {name}/{pose}")
            faces.eye_checks(frame,name,pose=="blink_idle")
            checks.append({"pose":pose,"eyes_passed":True,"body_from_row27_unchanged":True})
        report["keyframe_checks"][name]={"frame_count":8,"checks":checks,"numeric_validation":str((folder / "validation.json").relative_to(ROOT)).replace("\\","/")}
        meta=json.loads((folder / "keyframes.json").read_text(encoding="utf-8"))
        meta["face_refinement"]="art/characters/face-refinement-v1/generation.json";meta["face_revision"]="rounded_v1"
        dump(folder / "keyframes.json",meta)
    motion=json.loads((ROOT / "art/mockups/full-ingame-v7/motion/frames.json").read_text(encoding="utf-8"))
    if not motion["passed"]:raise ValueError("Rounded-face motion failed")
    report["animated_mockup"]={"path":"art/mockups/full-ingame-v7/animated-preview.html","idle_frames_tested":len(motion["checks"]),"passed":True}
    eye_path=ROOT / "art/mockups/full-ingame-v7/motion/eye-fringe-validation.json"
    if eye_path.is_file():
        eye_report=json.loads(eye_path.read_text(encoding="utf-8"))
        if eye_report["status"]!="passed":raise ValueError("Motion eye/fringe inspection failed")
        report["animated_mockup"]["eyes_and_fringe_frames_tested"]=eye_report["frames_tested"]
    dump(OUT / "validation.json",report);dump(OUT / "profiles.json",faces.PROFILES)
    board=Image.new("RGBA",(720,510),"#4A3C52")
    common.text(board,(22,15),"얼굴 수정 전 / 후 · 같은32×48과3배",23)
    for row,(frames,label,y) in enumerate(((old_frames,"수정 전",86),(new_frames,"수정 후",324))):
        common.text(board,(22,y-32),label,17,"#C38EB5")
        for i,(name,frame) in enumerate(frames.items()):
            x=28+i*177;board.alpha_composite(frame.resize((96,144),Image.Resampling.NEAREST),(x,y))
            common.text(board,(x-4,y+153),LABELS[name],14)
    board.convert("RGB").save(OUT / "before-after.png")
    cards=[]
    descriptions={"keeper":"윗머리의 빈 부분을 갈색 앞머리로 잇고 볼·턱선을 다듬었습니다.","elf":"앞머리를 부드럽게 잇고 볼 아래에서 턱 끝까지 좁아지도록 바꿨습니다.",
        "mage":"모자가 머리에 앉은 상태를 유지하며 볼과 턱 끝을 둥글게 바꿨습니다.","traveler":"기존 의상·배낭을 유지하며 얼굴의 아래쪽 모서리를 다듬었습니다."}
    for name in faces.PROFILES:
        cards.append(f'<section class="card"><h2>{LABELS[name]}</h2><div class="pair"><figure><img src="source/originals/{name}.png" alt="{LABELS[name]} 수정 전"><figcaption>수정 전</figcaption></figure><figure><img class="after" data-name="{name}" src="faces/{name}.png" alt="{LABELS[name]} 수정 후"><figcaption>수정 후</figcaption></figure></div><p>{descriptions[name]}</p></section>')
    page='''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>얼굴과 앞머리 수정 · 비교</title><style>
    @font-face{font-family:Pretendard;src:url('../../../assets/fonts/pretendard/Pretendard-Regular.otf')}*{box-sizing:border-box}:root{color-scheme:dark;--scale:3}body{margin:0;background:#241c32;color:#fff0bc;font:15px/1.6 Pretendard,system-ui,sans-serif}main{max-width:1180px;margin:auto;padding:24px}h1{font-size:26px;margin:0 0 8px}p{color:#c38eb5;margin:8px 0 12px}a{color:#e9b95f}.controls{display:flex;gap:20px;align-items:center;flex-wrap:wrap;padding:14px 0;border-block:1px solid #827589;margin:18px 0}select{background:#4a3c52;color:#fff0bc;border:1px solid #827589;padding:7px;font:inherit}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.card{border:1px solid #827589;background:#4a3c52;padding:18px}.card h2{font-size:19px;margin:0 0 12px}.pair{display:flex;justify-content:center;gap:26px}.pair figure{margin:0;text-align:center}.pair img{display:block;image-rendering:pixelated;width:calc(32px*var(--scale));height:calc(48px*var(--scale))}.pair figcaption{font-size:13px;margin:8px 0}.card p{font-size:14px;max-width:480px;margin:auto}.links{display:flex;gap:14px;flex-wrap:wrap;margin:18px 0}.note{font-size:14px;margin-top:20px}@media(max-width:980px){.grid{grid-template-columns:1fr}main{padding:20px 16px}}@media(max-width:480px){.pair{gap:8px}}
    </style></head><body><main><h1>얼굴·앞머리 수정 비교</h1><p>볼과 턱을 계단 모양으로 둥글게 다듬고, 주인공의 앞머리를 자연스럽게 이어 붙였습니다.</p><div class="links"><a href="../../mockups/full-ingame-v7/animated-preview.html">움직이는 전체 목업 v7</a><a href="../keyframes-v1/elf/review.html">엘프8키프레임</a><a href="before-after.png">수정 전후 확인표</a><a href="validation.json">검사 기록</a></div><div class="controls"><label>공통 배율 <select id="zoom"><option value="3">3배</option><option value="6">6배 확대 검사</option></select></label><label><input id="blink" type="checkbox"> 수정 후 눈 감은 모습</label><span>원본32×48 · 캐릭터별5색 · 같은 높이의 두 눈</span></div><div class="grid">__CARDS__</div><p class="note">엘프·여마법사·여행자8포즈에도 반영했습니다. 두 눈은 각1×2픽셀이며 피부 여백1픽셀을 유지합니다. 전체 목업에는 상하 호흡·깜빡임과 모자·망토·머리 움직임이 함께 들어 있습니다. 새 얼굴 디자인은 검토 후보입니다.</p></main><script>
    document.getElementById('zoom').addEventListener('change',event=>document.documentElement.style.setProperty('--scale',event.target.value));document.getElementById('blink').addEventListener('change',event=>document.querySelectorAll('.after').forEach(img=>img.src='faces/'+img.dataset.name+(event.target.checked?'-blink':'')+'.png'));
    </script></body></html>'''.replace('__CARDS__',''.join(cards))
    (OUT / "review.html").write_text(page,encoding="utf-8")
    print(json.dumps({"status":"passed","refined_characters":4,"customer_keyframes":24,"idle_frames":len(motion["checks"])}))


if __name__=="__main__":main()
