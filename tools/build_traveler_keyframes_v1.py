"""Register a complete generated traveler sheet and run the fixed art pipeline.

The same uniform scale is used for all poses. Whole bodies are registered by
head and ground anchors; no torso/leg pieces are assembled from other poses.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from process_pixel_art import ROOT, clean_background, native_grid, rgb, validate
from prepare_character_v6 import dark_component

OUT = ROOT / "art/characters/keyframes-v1/traveler"
POSES = ["idle", "walk_contact_a", "walk_pass_a", "walk_contact_b", "walk_pass_b",
         "receive_extend", "receive_hold", "blink_idle"]
NAMES = ["대기", "걷기 · 접지 A", "걷기 · 통과 A", "걷기 · 접지 B", "걷기 · 통과 B",
         "받기 · 손 내밀기", "받기 · 손 모으기", "대기 · 깜빡임"]
INK, SKIN, SHIRT, BROWN, HONEY = "#241C32", "#F6D1AC", "#FFF0BC", "#916047", "#C99463"
PALETTE = {rgb(c) for c in (ROOT / "art/palette.hex").read_text().splitlines()}


def current_mockup_reference(name):
    latest=ROOT / "art/mockups/full-ingame-v7/characters" / f"{name}-native.png"
    return latest if latest.is_file() else ROOT / "art/mockups/full-ingame-v6/characters" / f"{name}-native.png"


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def boundary(data):
    full = data[:, :, 3] != 0
    p = np.pad(full, 1)
    inside = p[1:-1, :-2] & p[1:-1, 2:] & p[:-2, 1:-1] & p[2:, 1:-1]
    return full & ~inside


def register_source():
    generation = json.loads((OUT / "generation.json").read_text(encoding="utf-8"))
    source = Image.open(OUT / generation["selected_source"]).convert("RGBA")
    cells, bounds = [], []
    for i in range(8):
        x, y = i % 4, i // 4
        cell = source.crop((round(x*source.width/4), round(y*source.height/2),
                           round((x+1)*source.width/4), round((y+1)*source.height/2)))
        cleaned = clean_background(cell, 224)
        cells.append(cleaned)
        bounds.append(cleaned.size)
    # Source poses use the same pixel grid. A common scale and top anchor keep
    # the head stable; subpixel source-height noise is quantized on that grid.
    scale = 360 / max(cell.height for cell in cells)
    records = []
    for name, cell in zip(POSES, cells):
        pixels = np.array(cell)
        head_top = pixels[:round(cell.height*.24), :, 3] != 0
        yy, xx = np.where(head_top)
        head_center = (int(xx.min()) + int(xx.max()) + 1) / 2
        fitted = cell.resize((round(cell.width*scale), round(cell.height*scale)), Image.Resampling.NEAREST)
        canvas = Image.new("RGBA", (320, 480))
        x = round(140 - head_center*scale)
        y = 110
        if min(x, y) < 0 or x+fitted.width > 320 or y+fitted.height > 470:
            raise ValueError(f"Registered source leaves native frame: {name}")
        canvas.alpha_composite(fitted, (x,y))
        canvas = clean_background(canvas, 224, crop=False)
        grid = native_grid(canvas, [32,48], 0)
        grid.save(OUT / "source" / f"{name}-registered.png")
        records.append({"id":name,"source_crop_size":list(cell.size),"uniform_source_scale":scale,
            "source_offset":[x,y],"native_canvas":[32,48],"head_origin_row":11,"foot_target_row":46})
    dump(OUT / "registration.json", {"sheet_size":list(source.size),"grid":[4,2],
         "whole_body_registration":True,"uniform_scale_all_poses":scale,"frames":records})


def manifest():
    assets=[]
    for name in POSES:
        assets.append({"id":name,"source":f"art/characters/keyframes-v1/traveler/source/{name}-registered.png",
            "size":[32,48],"position":[0,0],"margin":0,"dark_value":.26,"preserve_native_frame":True,
            "materials":{"outline":[INK],"skin":[SKIN],"shirt":[SHIRT],"hair_leather":[BROWN],"cloth":[HONEY]},
            "material_ramps":{"outline":"outline","skin":"skin","shirt":"gold","hair_leather":"wood","cloth":"wood"},
            "rules":[{"material":"shirt","hue":[.105,.22],"value_min":.78,"saturation_max":.44},
                     {"material":"skin","hue":[.025,.105],"value_min":.76,"saturation_min":.15,"saturation_max":.50},
                     {"material":"cloth","x_max":.70,"y_min":.73,"y_max":.83}],
            "fallback_material":"hair_leather"})
        if name in ("idle","receive_extend","receive_hold","blink_idle"):
            # Quantization can pick a skin bucket across the extended shorts'
            # hem. This explicit material mask restores the generated v3
            # garment through torso row39 without moving any limb pixels.
            assets[-1]["material_rectangles"]=[{"rect":[10,38,20,40],"material":"cloth"}]
    data={"schema_version":1,"status":"candidate","approved_by_user":False,"compose":False,"scale":3,
        "alpha_threshold":224,"max_colors":5,"palette":"art/palette.hex","ramps":"art/ramps.json",
        "output":"art/characters/keyframes-v1/traveler/pipeline","scene":{"size":[32,48],"background":"#4A3C52"},"assets":assets}
    dump(OUT / "manifest.json",data)


def font(size):
    return ImageFont.truetype(str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"),size)


def text(image,xy,value,size=14,color=SHIRT):
    ImageDraw.Draw(image).text(xy,value,font=font(size),fill=color)


def blink_from_idle(idle):
    # Reuse the approved workflow's explicit native eye-state mask. The full
    # idle figure is identical; only four color pixels change for the blink.
    data=np.array(idle)
    for x in (10,14):
        data[22:24,x]=(*rgb(SKIN),255)
        data[23,x:x+2]=(*rgb(INK),255)
    return Image.fromarray(data)


def eyes(frame,closed=False):
    data=np.array(frame)
    result=[]
    for x in (10,14):
        points=[(x,23),(x+1,23)] if closed else [(x,22),(x,23)]
        component=dark_component(frame,points[0],diagonals=True)
        if component!=sorted(points):
            raise ValueError(f"Eye merges with hair/face: {component}")
        box=(x-1,22,x+3,25) if closed else (x-1,21,x+2,25)
        for yy in range(box[1],box[3]):
            for xx in range(box[0],box[2]):
                if (xx,yy) not in points and tuple(data[yy,xx])!=(*rgb(SKIN),255):
                    raise ValueError(f"Missing one-pixel skin gap at {xx,yy}")
        result.append({"pixels":points,"width":2 if closed else 1,"height":1 if closed else 2,
            "isolated_dark_component_pixels":2,"one_pixel_skin_gap":True})
    return result


def bottle_anchors(frames, anchors=None, grip_y_from_top=None):
    if anchors is None:
        anchors={"receive_extend":[5,31],"receive_hold":[12,35]}
    recipe_data=json.loads((ROOT / "art/mockups/full-ingame-v6/potions/recipes.json").read_text(encoding="utf-8"))
    tests=[]
    for pose,(gx,gy) in anchors.items():
        for row in recipe_data["recipes"]:
            bottle=Image.open(ROOT / "art/mockups/full-ingame-v6/potions" / row["bottle_path"]).convert("RGBA")
            local_y=bottle.height-6 if grip_y_from_top is None else grip_y_from_top
            bx,by=gx-bottle.width//2,gy-local_y
            if min(bx,by)<0 or bx+bottle.width>32 or by+bottle.height>48:
                raise ValueError(f"Bottle leaves receiving keyframe: {pose}/{row['id']}")
            mask=np.zeros((48,32),dtype=bool)
            mask[by:by+bottle.height,bx:bx+bottle.width]=np.array(bottle)[:,:,3]!=0
            # Even diagonal contact with a pupil's skin gap is disallowed.
            for x in (10,14):
                if mask[21:25,x-1:x+2].any():
                    raise ValueError(f"Bottle touches an eye's skin margin: {pose}/{row['id']}")
            if np.array(bottle)[local_y,bottle.width//2,3]==0:
                raise ValueError(f"Bottle grip is transparent: {pose}/{row['id']}")
            tests.append({"pose":pose,"recipe":row["id"],"eyes_and_skin_margin_clear":True,"inside_frame":True,
                "bottle_origin":[bx,by],"local_grip":[bottle.width//2,local_y],"grip_opaque":True})
    return {"hand_grip_anchors":anchors,"bottle_local_grip":"[width/2,height-6]" if grip_y_from_top is None else f"[width/2,{grip_y_from_top}]",
            "tested_recipes":36,"tested_pose_recipe_pairs":len(tests),"checks":tests}


def write_preview(frames,anchors):
    frame_data=[]
    for i,(name,label) in enumerate(zip(POSES,NAMES)):
        frame_data.append({"id":name,"name":label,"index":i,"path":f"frames/{name}.png",
            "native_size":[32,48],"sheet_rect":[(i%4)*32,(i//4)*48,32,48],
            "hand_grip_anchor":anchors["hand_grip_anchors"].get(name),"status":"candidate_keyframe"})
    dump(OUT / "keyframes.json",{"schema_version":1,"character":"traveler","status":"candidate_keyframes",
        "palette":"art/palettes/v1/characters/traveler.hex","frames":frame_data,
        "source":"generation.json","native_sheet":"traveler-keyframes-native.png","scale":3,
        "anatomy":{"head_frame":[3,11,25,27],"torso_rows":[27,39],"legs_and_boots_rows":[40,46],"foot_row":46},
        "eye_state":"blink_idle is idle with only four pupil pixels changed",
        "animations_status":"not_produced; these are key poses, not finished action animations",
        "runtime_integrated":False})
    cards=''.join(f'<button class="pose" data-pose="{i}" aria-pressed="{str(i==0).lower()}"><strong>{label}</strong><span class="sprite guide"><img src="frames/{name}.png" width="96" height="144" alt="여행자 {label}"></span></button>' for i,(name,label) in enumerate(zip(POSES,NAMES)))
    data=json.dumps(frame_data,ensure_ascii=False)
    page='''<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>여행자 · 키프레임 v1</title><style>
    @font-face{font-family:Pretendard;src:url('../../../../assets/fonts/pretendard/Pretendard-Regular.otf')}*{box-sizing:border-box}:root{color-scheme:dark}body{margin:0;background:#241c32;color:#fff0bc;font:15px/1.55 Pretendard,system-ui,sans-serif}main{max-width:1120px;margin:auto;padding:28px 24px}h1{font-size:27px;margin:0 0 8px}p{color:#c38eb5;margin:8px 0 18px}a{color:#e9b95f}header .palette{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0}.palette span{display:flex;align-items:center;gap:6px;font-size:12px}.palette i{width:20px;height:20px;background:var(--color);border:1px solid #827589}.controls{display:flex;gap:20px;flex-wrap:wrap;align-items:center;padding:12px 0;border-top:1px solid #827589;border-bottom:1px solid #827589}.controls label{cursor:pointer}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:22px 0}.pose{display:flex;flex-direction:column;align-items:center;background:#4a3c52;color:#fff0bc;border:1px solid #827589;padding:14px 8px;cursor:pointer;font:inherit;gap:12px}.pose[aria-pressed=true]{border-color:#e9b95f;box-shadow:inset 0 0 0 1px #e9b95f}.pose strong{font-size:14px}.sprite{display:block;position:relative;width:96px;height:144px}img{image-rendering:pixelated;object-fit:contain;display:block}.guide:after{content:"";position:absolute;inset:0;pointer-events:none;background:linear-gradient(to bottom,transparent 32px,#e9b95f 32px,#e9b95f 33px,transparent 33px,transparent 80px,#e9b95f 80px,#e9b95f 81px,transparent 81px,transparent 119px,#e9b95f 119px,#e9b95f 120px,transparent 120px,transparent 140px,#e9b95f 140px,#e9b95f 141px,transparent 141px)}.no-guide .guide:after{display:none}.review{display:grid;grid-template-columns:1fr 1fr;gap:20px}.panel{padding:18px;background:#30263f;border:1px solid #827589}.panel h2{font-size:18px;margin:0 0 12px}.selected-body{display:flex;gap:26px;align-items:center;justify-content:center}.selected-frame{background:#4a3c52;width:96px;height:144px;position:relative}.bottle{position:absolute;image-rendering:pixelated;pointer-events:none}.refs{display:flex;justify-content:space-evenly;gap:8px}.ref{text-align:center;font-size:13px}.ref img{margin:auto}.selected-text{max-width:260px}.tag{color:#e9b95f;font-size:13px}.notice{padding:12px 16px;border-left:3px solid #e9b95f;color:#c38eb5;margin-top:22px}.guide-key{font-size:13px;color:#c38eb5}.links{margin-top:22px;font-size:14px}@media(max-width:760px){.grid{grid-template-columns:repeat(2,1fr)}.review{grid-template-columns:1fr}.refs{flex-wrap:wrap}.selected-body{gap:12px}main{padding:22px 16px}}
    [hidden]{display:none!important}
    </style></head><body><main><header><h1>손님 01 · 여행자 키프레임</h1><p>정한 팔레트와 부위별 크기를 사용한8개 주요 포즈입니다. 각 그림은 같은32×48 원본과3배 배율로 표시합니다.</p><div class="palette"><span><i style="--color:#241c32"></i>테두리·눈</span><span><i style="--color:#f6d1ac"></i>피부</span><span><i style="--color:#fff0bc"></i>셔츠·침낭</span><span><i style="--color:#916047"></i>머리·가죽</span><span><i style="--color:#c99463"></i>반바지·배낭 밝은 면</span></div></header><div class="controls"><label><input id="guides" type="checkbox" checked> 부위 기준선</label><label><input id="show-bottle" type="checkbox"> 선택한 받기 포즈에 물약 접점 표시</label><span class="tag">5색 · 팔레트 밖0 · 반투명0 · 외곽선 위반0</span></div><p class="guide-key">기준선: 머리11~26행 / 몸통27~39행 / 다리·신발40~46행 / 발46행. 모자·배낭 같은 부착물은 머리 크기에 포함하지 않습니다.</p><div class="grid">__CARDS__</div><div class="review"><section class="panel"><h2 id="selected-name">대기</h2><div class="selected-body"><div class="selected-frame sprite guide"><img id="selected-image" src="frames/idle.png" width="96" height="144" alt="선택한 여행자 키프레임"><img class="bottle" id="bottle" hidden src="../../../mockups/full-ingame-v6/potions/bottles/health.png" width="24" height="36" alt="별도 체력 물약"></div><div class="selected-text"><p id="selected-description">같은 머리·몸통·다리 기준을 유지한 대기 포즈입니다.</p><p id="bottle-note">물약은 받기 포즈에서 별도로 합성해 접점을 확인합니다.</p></div></div></section><section class="panel"><h2>같은 크기의 승인된 캐릭터와 비교</h2><div class="refs"><div class="ref"><span class="sprite guide"><img src="../../../mockups/full-ingame-v6/characters/witch-native.png" width="96" height="144" alt="승인한 남자 주인공"></span>주인공 v6</div><div class="ref"><span class="sprite guide"><img src="../../../mockups/full-ingame-v6/characters/elf-native.png" width="96" height="144" alt="승인한 엘프"></span>엘프 v6</div><div class="ref"><span class="sprite guide"><img src="frames/idle.png" width="96" height="144" alt="새 여행자 대기"></span>여행자</div></div></section></div><div class="notice">현재는 키프레임 검토 단계입니다. 행동 사이의 중간 프레임·속도·호흡과 부분 움직임을 합친 완성 애니메이션은 다음 단계에서 제작합니다. 물약은 캐릭터 그림에 칠하지 않고 별도 병으로 합성합니다.</div><div class="links"><a href="keyframes-review.png">8포즈 확인표</a> · <a href="anatomy-comparison.png">부위·크기 비교</a> · <a href="traveler-keyframes-native.png">원본 시트</a> · <a href="validation.json">검사 기록</a> · <a href="../../../../art/palettes/v1/review.html">팔레트 확인표</a></div></main><script>
    const frames=__DATA__;const descriptions=['대기 · 갈색 머리와 배낭, 밝은 셔츠, 짧은 바지·부츠를 유지합니다.','걷기 A · 다리를 벌려 접지하는 주요 포즈입니다.','걷기 A · 지지 다리 아래로 반대쪽 다리가 지나갑니다.','걷기 B · A와 다른 다리·팔의 주요 포즈입니다.','걷기 B · 반대쪽 지지·통과 포즈입니다.','받기 · 물약을 받을 손을 앞으로 내밉니다.','받기 · 물약을 잡을 손을 몸 앞에 모읍니다.','깜빡임 · 대기와 같은 그림에서 눈4픽셀만 바뀝니다.'];let current=0;const bottle=document.getElementById('bottle');function update(){const frame=frames[current];document.getElementById('selected-name').textContent=frame.name;document.getElementById('selected-image').src=frame.path;document.getElementById('selected-description').textContent=descriptions[current];document.querySelectorAll('.pose').forEach(button=>button.setAttribute('aria-pressed',String(Number(button.dataset.pose)===current)));const show=document.getElementById('show-bottle').checked&&frame.hand_grip_anchor;bottle.hidden=!show;if(show){bottle.style.left=(frame.hand_grip_anchor[0]-4)*3+'px';bottle.style.top=(frame.hand_grip_anchor[1]-6)*3+'px';document.getElementById('bottle-note').textContent='별도 체력 물약 · 손 접점과 눈의 피부 여백을 확인하세요.';}else document.getElementById('bottle-note').textContent='물약은 받기 포즈에서 별도로 합성해 접점을 확인합니다.';}document.querySelectorAll('.pose').forEach(button=>button.addEventListener('click',()=>{current=Number(button.dataset.pose);update();}));document.getElementById('guides').addEventListener('change',event=>document.body.classList.toggle('no-guide',!event.target.checked));document.getElementById('show-bottle').addEventListener('change',update);update();
    </script></body></html>'''.replace('__CARDS__',cards).replace('__DATA__',data)
    if (ROOT / "art/mockups/full-ingame-v7/characters/witch-native.png").is_file():
        page=page.replace("../../../mockups/full-ingame-v6/characters/","../../../mockups/full-ingame-v7/characters/")
        page=page.replace("같은 크기의 승인된 캐릭터와 비교","같은 크기의 얼굴 수정 캐릭터와 비교")
        page=page.replace("승인한 남자 주인공","얼굴을 수정한 남자 주인공").replace("승인한 엘프","얼굴을 수정한 엘프")
        page=page.replace("주인공 v6","주인공 v7").replace("엘프 v6","엘프 v7")
    (OUT / "review.html").write_text(page,encoding="utf-8")


def review(frames):
    board=Image.new("RGBA",(1040,612),INK)
    text(board,(24,18),"손님 01 · 여행자 키프레임",26)
    text(board,(24,59),"원본32×48 · 공통3배 · 머리16행 / 몸통13행 / 다리·신발7행 · 같은 발 기준46행",15,"#C38EB5")
    for i,(name,label) in enumerate(zip(POSES,NAMES)):
        x,y=24+(i%4)*250,112+(i//4)*244
        ImageDraw.Draw(board).rectangle((x,y,x+232,y+225),fill="#4A3C52",outline="#827589")
        text(board,(x+12,y+12),label,16)
        frame=frames[name]
        board.alpha_composite(frame.resize((96,144),Image.Resampling.NEAREST),(x+64,y+54))
        for row in (11,27,40,47):
            ImageDraw.Draw(board).line((x+52,y+54+row*3,x+176,y+54+row*3),fill="#E9B95F")
        text(board,(x+12,y+204),name,10,"#C38EB5")
    board.convert("RGB").save(OUT / "keyframes-review.png")
    compare=Image.new("RGBA",(620,270),"#4A3C52")
    text(compare,(24,16),"같은32×48 · 모자 제외 비율 · 공통3배",19)
    refs=[Image.open(current_mockup_reference("witch")).convert("RGBA"),
          Image.open(current_mockup_reference("elf")).convert("RGBA"),frames["idle"]]
    for i,(frame,label) in enumerate(zip(refs,["주인공 최신","엘프 최신","여행자 새 기준"])):
        x=48+i*188
        compare.alpha_composite(frame.resize((96,144),Image.Resampling.NEAREST),(x,68))
        for row in (11,27,40,47):
            ImageDraw.Draw(compare).line((x-6,68+row*3,x+102,68+row*3),fill="#E9B95F")
        text(compare,(x-2,228),label,15)
    compare.convert("RGB").save(OUT / "anatomy-comparison.png")


def main():
    register_source()
    manifest()
    proc=subprocess.run([sys.executable,str(ROOT / "tools/process_pixel_art.py"),
        "art/characters/keyframes-v1/traveler/manifest.json"],capture_output=True,text=True,encoding="utf-8")
    if proc.returncode:
        print(proc.stdout);print(proc.stderr);raise SystemExit(proc.returncode)
    frames={name:Image.open(OUT / "pipeline" / f"{name}-native.png").convert("RGBA") for name in POSES}
    import refine_character_faces_v1 as faces
    frames={name:faces.apply(frame,"traveler") for name,frame in frames.items()}
    frames["blink_idle"]=blink_from_idle(frames["idle"])
    report={"status":"passed","character":"traveler","art_status":"candidate",
        "native_canvas":[32,48],"scale":3,"frame_count":8,"head_rows":[11,26],"torso_rows":[27,39],
        "legs_and_boots_rows":[40,46],"foot_row":46,"stage_order":["background_cleanup","native_grid","material_ramp_remap","validation"],"frames":{}}
    for name,frame in frames.items():
        data=np.array(frame)
        check=validate(frame,[32,48],PALETTE,5)
        check["outline_boundary_violations"]=int((boundary(data)&np.any(data[:,:,:3]!=rgb(INK),axis=2)).sum())
        ys,xs=np.where(data[:,:,3]!=0)
        check["opaque_bounds"]=[int(xs.min()),int(ys.min()),int(xs.max())+1,int(ys.max())+1]
        check["top_clear_rows"]=bool((data[:11,:,3]==0).all())
        check["foot_on_row46"]=bool((data[46,:,3]!=0).any() and (data[47,:,3]==0).all())
        check["eyes"]=eyes(frame,name=="blink_idle")
        head=data[11:27,3:24]
        head_y,head_x=np.where(head[:,:,3]!=0)
        check["head_bounds_excluding_backpack"]=[int(head_x.min())+3,int(head_y.min())+11,
                                                int(head_x.max())+4,int(head_y.max())+12]
        check["head_height"]=int(head_y.max()-head_y.min()+1)
        check["head_fits_22x16"]=bool(head_x.max()-head_x.min()+1<=22 and check["head_height"]==16)
        if name in ("idle","receive_extend","receive_hold","blink_idle"):
            check["standing_leg_skin_starts_at40"]=bool(not np.any(np.all(data[37:40,10:20,:3]==rgb(SKIN),axis=2)&(data[37:40,10:20,3]!=0)))
        if not check["passed"] or check["outline_boundary_violations"] or not check["top_clear_rows"] or not check["foot_on_row46"] or not check["head_fits_22x16"] or not check.get("standing_leg_skin_starts_at40",True):
            report["status"]="failed"
        report["frames"][name]=check
    a=np.array(frames["walk_contact_a"]);b=np.array(frames["walk_contact_b"])
    pa=np.array(frames["walk_pass_a"]);pb=np.array(frames["walk_pass_b"])
    report["walk_contact_leg_changed_pixels"]=int(np.any(a[40:]!=b[40:],axis=2).sum())
    report["walk_pass_leg_changed_pixels"]=int(np.any(pa[40:]!=pb[40:],axis=2).sum())
    report["walk_contact_arm_changed_pixels"]=int(np.any(a[27:36]!=b[27:36],axis=2).sum())
    changed=np.any(np.array(frames["idle"])!=np.array(frames["blink_idle"]),axis=2)
    eye_mask=np.zeros((48,32),dtype=bool)
    eye_mask[22:24,10:12]=True;eye_mask[22:24,14:16]=True
    report["blink_changed_pixels"]=int(changed.sum())
    report["blink_only_eye_pixels_changed"]=bool(not changed[~eye_mask].any() and changed.sum()==4)
    anchors=bottle_anchors(frames)
    report["bottle_anchor_validation"]={key:anchors[key] for key in ("tested_recipes","tested_pose_recipe_pairs")}
    if min(report["walk_contact_leg_changed_pixels"],report["walk_pass_leg_changed_pixels"],report["walk_contact_arm_changed_pixels"])==0 or not report["blink_only_eye_pixels_changed"]:
        report["status"]="failed"
    dump(OUT / "validation.json",report)
    if report["status"]!="passed":
        print(json.dumps(report,ensure_ascii=False,indent=2));raise SystemExit(1)
    (OUT / "frames").mkdir(exist_ok=True)
    sheet=Image.new("RGBA",(128,96))
    for i,(name,frame) in enumerate(frames.items()):
        frame.save(OUT / "frames" / f"{name}.png")
        sheet.alpha_composite(frame,((i%4)*32,(i//4)*48))
    sheet.save(OUT / "traveler-keyframes-native.png")
    sheet.resize((384,288),Image.Resampling.NEAREST).save(OUT / "traveler-keyframes-3x.png")
    review(frames)
    dump(OUT / "hand-anchors.json",anchors)
    write_preview(frames,anchors)
    print(json.dumps({key:report[key] for key in ("status","character","frame_count","walk_contact_leg_changed_pixels","walk_pass_leg_changed_pixels","blink_only_eye_pixels_changed")},ensure_ascii=False))


if __name__=="__main__":main()
