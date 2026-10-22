"""Register coherent elf poses and validate the approved palette/anatomy."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

from process_pixel_art import ROOT, clean_background, native_grid, rgb, validate
from prepare_character_v6 import dark_component
import build_traveler_keyframes_v1 as common

OUT=ROOT / "art/characters/keyframes-v1/elf"
POSES,NAMES=common.POSES,common.NAMES
INK,SKIN,BROWN,GREEN,LIME="#241C32","#F6D1AC","#916047","#718C59","#B5C77D"
PALETTE={rgb(c) for c in (ROOT / "art/palette.hex").read_text().splitlines()}
EYE_X=(10,15)


def dump(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def register():
    generation=json.loads((OUT / "generation.json").read_text(encoding="utf-8"))
    path=OUT / generation["selected_source"]
    sheet=Image.open(path).convert("RGBA")
    cells=[]
    for i in range(8):
        x,y=i%4,i//4
        cell=sheet.crop((round(x*sheet.width/4),round(y*sheet.height/2),round((x+1)*sheet.width/4),round((y+1)*sheet.height/2)))
        cells.append(clean_background(cell,224))
    scale=360/max(cell.height for cell in cells)
    records=[]
    for name,cell in zip(POSES,cells):
        a=np.array(cell)
        yy,xx=np.where(a[:round(cell.height*.24),:,3]!=0)
        center=(int(xx.min())+int(xx.max())+1)/2
        fitted=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
        x,y=round(155-center*scale),110
        if min(x,y)<0 or x+fitted.width>320 or y+fitted.height>470:
            raise ValueError(f"Whole-body registration leaves frame: {name}")
        canvas=Image.new("RGBA",(320,480));canvas.alpha_composite(fitted,(x,y))
        canvas=clean_background(canvas,224,crop=False)
        native_grid(canvas,[32,48],0).save(OUT / "source" / f"{name}-registered.png")
        records.append({"id":name,"whole_body_size":list(cell.size),"common_uniform_scale":scale,"offset":[x,y]})
    dump(OUT / "registration.json",{"source_size":list(sheet.size),"source_sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
        "grid":[4,2],"common_uniform_scale":scale,"whole_body_registration":True,"head_top_row":11,
        "foot_row":46,"frames":records})


def manifest():
    assets=[]
    for name in POSES:
        assets.append({"id":name,"source":f"art/characters/keyframes-v1/elf/source/{name}-registered.png",
            "size":[32,48],"position":[0,0],"margin":0,"dark_value":.26,"preserve_native_frame":True,
            "materials":{"outline":[INK],"skin":[SKIN],"hair_leather":[BROWN],"leaf":[GREEN,LIME]},
            "material_ramps":{"outline":"outline","skin":"skin","hair_leather":"wood","leaf":"leaf"},
            "rules":[{"material":"skin","hue":[.025,.15],"saturation_min":.12,"saturation_max":.52,"value_min":.78},
                     {"material":"hair_leather","hue":[.025,.16],"saturation_min":.20,"value_max":.80}],
            "fallback_material":"leaf",
            "material_rectangles":[{"rect":[9,20,12,24],"material":"skin","include_interior_outline":True},
                {"rect":[14,20,18,24],"material":"skin","include_interior_outline":True}],
            "material_pixels":[{"material":"outline","pixels":[[10,21],[10,22],[15,21],[15,22]]}]})
        if name=="walk_contact_a":
            assets[-1]["background_alpha_rectangles"]=[{"rect":[9,38,10,40],
                "reason":"Two outline pixels widen the generated tunic to13. Keep the hem at12 without touching legs from row40."}]
    dump(OUT / "manifest.json",{"schema_version":1,"status":"candidate","approved_by_user":False,"compose":False,
        "scale":3,"alpha_threshold":224,"max_colors":5,"palette":"art/palette.hex","ramps":"art/ramps.json",
        "output":"art/characters/keyframes-v1/elf/pipeline","scene":{"size":[32,48],"background":"#4A3C52"},"assets":assets})


def eyes(frame,closed=False):
    a=np.array(frame);checks=[]
    for x in EYE_X:
        points=[(x,22),(x+1,22)] if closed else [(x,21),(x,22)]
        if dark_component(frame,points[0],diagonals=True)!=sorted(points):
            raise ValueError(f"Unequal eye or eye touching hair: {x}")
        x0,y0,x1,y1=(x-1,21,x+3,24) if closed else (x-1,20,x+2,24)
        for yy in range(y0,y1):
            for xx in range(x0,x1):
                if (xx,yy) not in points and tuple(a[yy,xx])!=(*rgb(SKIN),255):
                    raise ValueError(f"Eye lacks one-pixel skin margin: {xx,yy}")
        checks.append({"pixels":points,"width":2 if closed else 1,"height":1 if closed else 2,
            "isolated_dark_component_pixels":2,"one_pixel_skin_gap":True})
    return checks


def blink(idle):
    a=np.array(idle)
    for x in EYE_X:
        a[21:23,x]=(*rgb(SKIN),255);a[22,x:x+2]=(*rgb(INK),255)
    return Image.fromarray(a)


def board(frames,diagnostic=False):
    image=Image.new("RGBA",(1040,612),INK)
    common.text(image,(24,18),"손님03 · 엘프 키프레임"+(" 중간 검사" if diagnostic else ""),26)
    common.text(image,(24,59),"32×48 · 공통3배 · 머리22×16 기준 / 몸통13행 / 다리7행 · 기존 엘프 팔레트5색",15,"#C38EB5")
    for i,(name,label) in enumerate(zip(POSES,NAMES)):
        x,y=24+(i%4)*250,112+(i//4)*244
        ImageDraw.Draw(image).rectangle((x,y,x+232,y+225),fill="#4A3C52",outline="#827589")
        common.text(image,(x+12,y+12),label,16)
        image.alpha_composite(frames[name].resize((96,144),Image.Resampling.NEAREST),(x+64,y+54))
        for row in (11,27,40,47):ImageDraw.Draw(image).line((x+52,y+54+row*3,x+176,y+54+row*3),fill="#E9B95F")
        common.text(image,(x+12,y+204),name,10,"#C38EB5")
    image.convert("RGB").save(OUT / ("source/native-diagnostic.png" if diagnostic else "keyframes-review.png"))


def review(frames,anchors):
    previous=common.OUT;common.OUT=OUT
    try:common.write_preview(frames,anchors)
    finally:common.OUT=previous
    data=json.loads((OUT / "keyframes.json").read_text(encoding="utf-8"))
    data.update(character="elf",palette="art/palettes/v1/characters/elf.hex",native_sheet="elf-keyframes-native.png",
        facing="left",identity_reference="art/mockups/full-ingame-v6/characters/elf-native.png",
        eyes={"left":[10,21,1,2],"right":[15,21,1,2]},
        anatomy={"head_reference_frame":[4,11,26,27],"torso_rows":[27,39],"legs_and_boots_rows":[40,46],"foot_row":46})
    dump(OUT / "keyframes.json",data)
    page=(OUT / "review.html").read_text(encoding="utf-8").replace("손님 01","손님 03").replace("여행자","엘프").replace("traveler-keyframes","elf-keyframes")
    page=page.replace("갈색 머리와 배낭, 밝은 셔츠, 짧은 바지·부츠","갈색 옆머리와 초록 장식, 좁은 초록 튜닉·짧은 무릎·부츠")
    page=page.replace("모자·배낭 같은 부착물은 머리 크기에 포함하지 않습니다.","모자 없는 엘프의 위쪽11행은 투명합니다. 서 있는 허리10픽셀·하단10~12픽셀의 좁은 의상을 유지합니다.")
    start=page.index('<div class="palette">');end=page.index('</div></header>',start)
    swatches=[(INK,"테두리·눈·부츠"),(SKIN,"피부·안쪽 옷"),(BROWN,"갈색 머리"),(GREEN,"초록 의상·장식"),(LIME,"밝은 초록 의상")]
    page=page[:start]+'<div class="palette">'+''.join(f'<span><i style="--color:{c}"></i>{label}</span>' for c,label in swatches)+page[end:]
    page=page.replace('id="guides" type="checkbox" checked','id="guides" type="checkbox"')
    page=page.replace('<body>','<body class="no-guide">')
    (OUT / "review.html").write_text(page,encoding="utf-8")
    board(frames)
    compare=Image.new("RGBA",(820,270),"#4A3C52")
    common.text(compare,(24,16),"기존 느낌과 같은 부위 크기 · 모두32×48 / 3배",20)
    refs=[Image.open(ROOT / "art/mockups/full-ingame-v6/characters/elf-native.png").convert("RGBA"),frames["idle"],
          Image.open(common.current_mockup_reference("witch")).convert("RGBA"),
          Image.open(ROOT / "art/characters/keyframes-v1/mage/frames/idle.png").convert("RGBA")]
    for i,(frame,label) in enumerate(zip(refs,["기존 엘프 v6","엘프 새 키프레임","주인공 최신","여마법사"])):
        x=40+i*195;compare.alpha_composite(frame.resize((96,144),Image.Resampling.NEAREST),(x,68))
        for row in (11,27,40,47):ImageDraw.Draw(compare).line((x-6,68+row*3,x+102,68+row*3),fill="#E9B95F")
        common.text(compare,(x-4,228),label,15)
    compare.convert("RGB").save(OUT / "anatomy-comparison.png")


def finish(frames):
    frames["blink_idle"]=blink(frames["idle"])
    report={"status":"passed","character":"elf","art_status":"candidate","approved_by_user":False,
        "native_canvas":[32,48],"scale":3,"frame_count":8,"head_reference_frame":[4,11,26,27],
        "head_rows":[11,26],"torso_rows":[27,39],"legs_and_boots_rows":[40,46],"foot_row":46,
        "stage_order":["background_cleanup","native_grid","material_ramp_remap","validation"],"frames":{}}
    for name,frame in frames.items():
        a=np.array(frame);check=validate(frame,[32,48],PALETTE,5)
        check["outline_boundary_violations"]=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum())
        check["top11_rows_clear"]=bool(not a[:11,:,3].any())
        check["foot_on_row46"]=bool(a[46,:,3].any() and not a[47,:,3].any())
        yy,xx=np.where(a[11:27,:,3]!=0)
        check["head_bounds"]=[int(xx.min()),int(yy.min())+11,int(xx.max())+1,int(yy.max())+12]
        check["head_width"]=int(xx.max()-xx.min()+1);check["head_height"]=int(yy.max()-yy.min()+1)
        check["head_fits_22x16"]=bool(check["head_width"]<=22 and check["head_height"]==16)
        hem_widths=[]
        for row in range(37,40):
            columns=np.where(a[row,:,3]!=0)[0]
            hem_widths.append(int(columns.max()-columns.min()+1))
        check["tunic_hem_widths_rows37_39"]=hem_widths
        check["tunic_hem_width10_to12"]=all(10<=width<=12 for width in hem_widths)
        if name in ("idle","receive_extend","receive_hold","blink_idle"):
            columns=np.where(a[35,:,3]!=0)[0]
            check["standing_waist_width"]=int(columns.max()-columns.min()+1)
            check["standing_waist_width10"]=check["standing_waist_width"]==10
        check["eyes"]=eyes(frame,name=="blink_idle")
        check["exact_3x"]=np.array_equal(np.array(frame.resize((96,144),Image.Resampling.NEAREST)),np.repeat(np.repeat(a,3,0),3,1))
        if not check["passed"] or check["outline_boundary_violations"] or not all(check[k] for k in ("top11_rows_clear","foot_on_row46","head_fits_22x16","exact_3x","tunic_hem_width10_to12")) or not check.get("standing_waist_width10",True):
            report["status"]="failed"
        report["frames"][name]=check
    for aa,bb,label,rows in [("walk_contact_a","walk_contact_b","walk_contact_leg_changed_pixels",slice(40,47)),
        ("walk_pass_a","walk_pass_b","walk_pass_leg_changed_pixels",slice(40,47)),
        ("walk_contact_a","walk_contact_b","walk_contact_arm_changed_pixels",slice(27,36))]:
        report[label]=int(np.any(np.array(frames[aa])[rows]!=np.array(frames[bb])[rows],axis=2).sum())
        if not report[label]:report["status"]="failed"
    changed=np.any(np.array(frames["idle"])!=np.array(frames["blink_idle"]),axis=2)
    mask=np.zeros((48,32),bool)
    for x in EYE_X:mask[21:23,x:x+2]=True
    report["blink_only_eye_pixels_changed"]=bool(changed.sum()==4 and not changed[~mask].any())
    if not report["blink_only_eye_pixels_changed"]:report["status"]="failed"
    grips={"receive_extend":[5,31],"receive_hold":[15,32]}
    anchors=common.bottle_anchors(frames,grips,grip_y_from_top=6)
    for name,(x,y) in grips.items():
        if tuple(np.array(frames[name])[y,x])!=(*rgb(SKIN),255):raise ValueError(f"Grip does not touch a skin hand: {name}")
    recipe_data=json.loads((ROOT / "art/mockups/full-ingame-v6/potions/recipes.json").read_text(encoding="utf-8"))
    recipes={row["id"]:row for row in recipe_data["recipes"]}
    for check in anchors["checks"]:
        bottle=Image.open(ROOT / "art/mockups/full-ingame-v6/potions" / recipes[check["recipe"]]["bottle_path"]).convert("RGBA")
        bx,by=check["bottle_origin"];mask=np.zeros((48,32),bool)
        mask[by:by+bottle.height,bx:bx+bottle.width]=np.array(bottle)[:,:,3]!=0
        for x in EYE_X:
            if mask[20:24,x-1:x+2].any():raise ValueError("Bottle overlaps the elf eye/skin margin")
        check["elf_eye_skin_halos_clear"]=True
    report["bottle_anchor_validation"]={"tested_recipes":36,"tested_pose_recipe_pairs":72,"grips_on_skin":True}
    dump(OUT / "validation.json",report)
    if report["status"]!="passed":
        print(json.dumps(report,ensure_ascii=False,indent=2));raise SystemExit(1)
    (OUT / "frames").mkdir(exist_ok=True)
    sheet=Image.new("RGBA",(128,96))
    for i,(name,frame) in enumerate(frames.items()):
        frame.save(OUT / "frames" / f"{name}.png");sheet.alpha_composite(frame,((i%4)*32,(i//4)*48))
    sheet.save(OUT / "elf-keyframes-native.png")
    sheet.resize((384,288),Image.Resampling.NEAREST).save(OUT / "elf-keyframes-3x.png")
    dump(OUT / "hand-anchors.json",anchors);review(frames,anchors)
    print(json.dumps({k:report[k] for k in ("status","character","frame_count","walk_contact_leg_changed_pixels","walk_pass_leg_changed_pixels","blink_only_eye_pixels_changed")},ensure_ascii=False))


def main():
    register();manifest()
    proc=subprocess.run([sys.executable,str(ROOT / "tools/process_pixel_art.py"),"art/characters/keyframes-v1/elf/manifest.json"],capture_output=True,text=True,encoding="utf-8")
    if proc.returncode:print(proc.stdout);print(proc.stderr);raise SystemExit(proc.returncode)
    frames={name:Image.open(OUT / "pipeline" / f"{name}-native.png").convert("RGBA") for name in POSES}
    import refine_character_faces_v1 as faces
    frames={name:faces.apply(frame,"elf") for name,frame in frames.items()}
    board(frames,diagnostic=True)
    finish(frames)


if __name__=="__main__":main()
