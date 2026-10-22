"""Whole-body mage keyframe registration and the project's material pipeline."""
from __future__ import annotations

import json
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

from process_pixel_art import ROOT, clean_background, native_grid, rgb, validate
import build_traveler_keyframes_v1 as common

OUT=ROOT / "art/characters/keyframes-v1/mage"
POSES,NAMES=common.POSES,common.NAMES
INK,SKIN,DARK,PURPLE,BROWN="#241C32","#F6D1AC","#50315F","#86548E","#916047"
PALETTE={rgb(c) for c in (ROOT / "art/palette.hex").read_text().splitlines()}
# Attach the brim's inner seat to the crown, rather than to the frame origin.
HAT_HEAD_ANCHOR=(14,14)
HAT_LOCAL_ANCHOR=(14,10)
HAT_POSITION=tuple(a-b for a,b in zip(HAT_HEAD_ANCHOR,HAT_LOCAL_ANCHOR))


def dump(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def anatomy_guide():
    guide=Image.new("RGBA",(32,48),"#4A3C52")
    draw=ImageDraw.Draw(guide)
    draw.rectangle((0,0,31,10),outline="#E9B95F")
    draw.ellipse((3,11,24,26),fill=DARK,outline=INK)
    draw.rectangle((7,17,19,25),fill=SKIN)
    draw.rectangle((10,22,10,23),fill=INK);draw.rectangle((14,22,14,23),fill=INK)
    draw.rectangle((8,27,23,39),fill=PURPLE,outline=INK)
    draw.rectangle((6,29,9,34),fill=PURPLE,outline=INK)
    draw.rectangle((22,29,25,34),fill=PURPLE,outline=INK)
    draw.rectangle((8,40,23,43),fill=DARK,outline=INK)
    draw.rectangle((10,44,14,46),fill=BROWN,outline=INK)
    draw.rectangle((18,44,22,46),fill=BROWN,outline=INK)
    canvas=Image.new("RGBA",(720,300),INK)
    common.text(canvas,(20,14),"32×48 기준 · 머리/몸통/다리 크기",22)
    common.text(canvas,(20,50),"모자0~10행 / 머리11~26행 / 몸통27~39행 / 다리40~46행",15,"#C38EB5")
    refs=[guide,Image.open(ROOT / "art/mockups/full-ingame-v6/characters/witch-native.png").convert("RGBA"),
          Image.open(ROOT / "art/mockups/full-ingame-v6/characters/elf-native.png").convert("RGBA")]
    for i,(image,label) in enumerate(zip(refs,["범위 도식 · 형태 참고 아님","주인공 승인 기준","엘프 승인 기준"])):
        x,y=54+i*224,96
        canvas.alpha_composite(image.resize((96,144),Image.Resampling.NEAREST),(x,y))
        for row in (11,27,40,47):ImageDraw.Draw(canvas).line((x-8,y+row*3,x+104,y+row*3),fill="#E9B95F")
        common.text(canvas,(x-20,256),label,13)
    canvas.convert("RGB").save(OUT / "source/anatomy-guide.png")


def register():
    data=json.loads((OUT / "generation.json").read_text(encoding="utf-8"))
    sheet=Image.open(OUT / data["selected_source"]).convert("RGBA")
    cells=[]
    # The generated sheet's actual transparent row gutter is below the
    # arithmetic midpoint. Split in that gutter, avoiding clipped boots and
    # first-row fragments entering second-row crops.
    row_bounds=[0,574,sheet.height]
    for i in range(8):
        x,y=i%4,i//4
        cell=sheet.crop((round(x*sheet.width/4),row_bounds[y],round((x+1)*sheet.width/4),row_bounds[y+1]))
        cells.append(clean_background(cell,224))
    scale=360/max(cell.height for cell in cells)
    records=[]
    for name,cell in zip(POSES,cells):
        fitted=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
        pixels=np.array(cell)
        yy,xx=np.where(pixels[:round(cell.height*.24),:,3]!=0)
        head_center=(int(xx.min())+int(xx.max())+1)/2
        x=round(140-head_center*scale);y=110
        if min(x,y)<0 or x+fitted.width>320 or y+fitted.height>470:
            raise ValueError(f"Whole body leaves native frame: {name}")
        canvas=Image.new("RGBA",(320,480));canvas.alpha_composite(fitted,(x,y))
        canvas=clean_background(canvas,224,crop=False)
        grid=native_grid(canvas,[32,48],0)
        grid.save(OUT / "source" / f"{name}-registered.png")
        records.append({"id":name,"whole_body_size":list(cell.size),"common_uniform_scale":scale,"offset":[x,y]})
    hat=clean_background(Image.open(OUT / data["selected_hat_source"]).convert("RGBA"),224)
    hat_grid=native_grid(hat,[32,14],0)
    hat_grid.save(OUT / "source/hat-registered.png")
    dump(OUT / "registration.json",{"source_size":list(sheet.size),"grid":[4,2],"row_gutter":row_bounds,"common_uniform_scale":scale,
        "whole_body_registration":True,"head_top_row":11,"hat_layer_size":[32,14],
        "hat_head_anchor":list(HAT_HEAD_ANCHOR),"hat_local_seat_anchor":list(HAT_LOCAL_ANCHOR),
        "hat_placement":list(HAT_POSITION),"frames":records})


def make_manifest():
    assets=[]
    for name in POSES:
        assets.append({"id":name,"source":f"art/characters/keyframes-v1/mage/source/{name}-registered.png","size":[32,48],
            "position":[0,0],"margin":0,"dark_value":.20,"preserve_native_frame":True,
            "materials":{"outline":[INK],"skin":[SKIN],"purple":[DARK,PURPLE],"wood":[BROWN]},
            "rules":[{"material":"skin","hue":[.025,.16],"value_min":.76,"saturation_max":.5},
                     {"material":"wood","hue":[.025,.18],"saturation_min":.22,"value_max":.88}],
            "fallback_material":"purple",
            "material_rectangles":[{"rect":[8,21,17,25],"material":"skin","include_interior_outline":True}],
            "material_pixels":[{"material":"outline","pixels":[[10,22],[10,23],[14,22],[14,23]]}]})
    assets.append({"id":"hat","source":"art/characters/keyframes-v1/mage/source/hat-registered.png",
        "size":[32,14],"position":[0,0],"margin":0,"dark_value":.20,"preserve_native_frame":True,
        "materials":{"outline":[INK],"purple":[DARK,PURPLE],"wood":[BROWN]},
        "rules":[{"material":"wood","hue":[.025,.18],"saturation_min":.22,"value_max":.88}],"fallback_material":"purple"})
    dump(OUT / "manifest.json",{"schema_version":1,"status":"candidate","approved_by_user":False,"compose":False,"scale":3,
        "alpha_threshold":224,"max_colors":5,"palette":"art/palette.hex","ramps":"art/ramps.json",
        "output":"art/characters/keyframes-v1/mage/pipeline","scene":{"size":[32,48],"background":"#4A3C52"},"assets":assets})


def diagnostic(frames):
    board=Image.new("RGBA",(1040,612),INK)
    common.text(board,(24,18),"손님02 · 여마법사 원본 격자 점검",25)
    common.text(board,(24,59),"중간 검사 · 머리/몸통/다리 기준선과 모자 높이 비교",15,"#C38EB5")
    checks={}
    for i,(name,frame) in enumerate(frames.items()):
        x,y=24+(i%4)*250,112+(i//4)*244
        ImageDraw.Draw(board).rectangle((x,y,x+232,y+225),fill="#4A3C52",outline="#827589")
        common.text(board,(x+12,y+12),NAMES[i],15)
        board.alpha_composite(frame.resize((96,144),Image.Resampling.NEAREST),(x+64,y+54))
        for row in (11,27,40,47):ImageDraw.Draw(board).line((x+52,y+54+row*3,x+176,y+54+row*3),fill="#E9B95F")
        a=np.array(frame);skin=(np.all(a[:,:,:3]==rgb(SKIN),axis=2)&(a[:,:,3]!=0))
        sy,sx=np.where(skin[:27])
        checks[name]={"head_skin_bounds":[int(sx.min()),int(sy.min()),int(sx.max())+1,int(sy.max())+1],
            "size":list(frame.size),"outline_boundary_violations":int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum())}
    board.convert("RGB").save(OUT / "source/native-diagnostic.png")
    dump(OUT / "source/diagnostic.json",checks)
    print(json.dumps(checks,ensure_ascii=False))


def write_review(frames,anchors):
    # Reuse the existing review layout, while keeping traveler output intact.
    previous=common.OUT
    common.OUT=OUT
    try:
        common.review(frames)
        common.write_preview(frames,anchors)
    finally:
        common.OUT=previous
    data=json.loads((OUT / "keyframes.json").read_text(encoding="utf-8"))
    data.update(character="mage",palette="art/palettes/v1/characters/mage.hex",native_sheet="mage-keyframes-native.png",
        hat_layer="layers/hat.png",hat_layer_size=[32,14],hat_placement=list(HAT_POSITION),
        hat_head_anchor=list(HAT_HEAD_ANCHOR),hat_local_seat_anchor=list(HAT_LOCAL_ANCHOR),body_layers="body-frames/",facing="left",
        anatomy={"head_frame_excluding_hat_and_flowing_hair":[3,11,25,27],"torso_rows":[27,39],"legs_and_boots_rows":[40,46],"foot_row":46})
    dump(OUT / "keyframes.json",data)
    page=(OUT / "review.html").read_text(encoding="utf-8")
    page=page.replace("손님 01","손님 02").replace("여행자","여마법사").replace("traveler-keyframes","mage-keyframes")
    page=page.replace("갈색 머리와 배낭, 밝은 셔츠, 짧은 바지·부츠","긴 보라색 머리와 모자, 긴 로브·책·부츠")
    start=page.index('<div class="palette">');end=page.index('</div></header>',start)
    swatches=[(INK,"테두리·눈"),(SKIN,"피부"),(DARK,"머리·모자·로브 어두운 면"),(PURPLE,"보라색 밝은 면"),(BROWN,"모자 띠·허리띠·책·부츠")]
    palette='<div class="palette">'+''.join(f'<span><i style="--color:{c}"></i>{label}</span>' for c,label in swatches)
    page=page[:start]+palette+page[end:]
    page=page.replace("모자·배낭 같은 부착물","모자·어깨 아래로 흐르는 머리 같은 부착물")
    page=page.replace("정한 팔레트와 부위별 크기를 사용한8개 주요 포즈입니다.","모자 챙을 정수리에 내려 앉힌8개 주요 포즈입니다.")
    page=page.replace("5색 · 팔레트 밖0 · 반투명0 · 외곽선 위반0","모자 착용 위치 수정 · 5색 · 외곽선 위반0")
    page=page.replace('<a href="keyframes-review.png">8포즈 확인표</a>',
        '<a href="hat-fit-review.png">모자 수정 전후</a> · <a href="keyframes-review.png">8포즈 확인표</a>')
    (OUT / "review.html").write_text(page,encoding="utf-8")
    # Render character-specific boards directly, preserving exact common3×.
    board=Image.new("RGBA",(1040,612),INK)
    common.text(board,(24,18),"손님02 · 여마법사 키프레임",26)
    common.text(board,(24,59),"원본32×48 · 3배 · 머리 기준22×16 / 몸통13행 / 다리7행 · 별도 모자",15,"#C38EB5")
    for i,(name,label) in enumerate(zip(POSES,NAMES)):
        x,y=24+(i%4)*250,112+(i//4)*244
        ImageDraw.Draw(board).rectangle((x,y,x+232,y+225),fill="#4A3C52",outline="#827589")
        common.text(board,(x+12,y+12),label,16)
        board.alpha_composite(frames[name].resize((96,144),Image.Resampling.NEAREST),(x+64,y+54))
        for row in (11,27,40,47):ImageDraw.Draw(board).line((x+52,y+54+row*3,x+176,y+54+row*3),fill="#E9B95F")
        common.text(board,(x+12,y+204),name,10,"#C38EB5")
    board.convert("RGB").save(OUT / "keyframes-review.png")
    compare=Image.new("RGBA",(820,300),"#4A3C52")
    common.text(compare,(24,16),"같은32×48 · 모자 제외 머리22×16 기준 · 모두3배",19)
    refs=[Image.open(common.current_mockup_reference("witch")).convert("RGBA"),
          Image.open(common.current_mockup_reference("elf")).convert("RGBA"),
          Image.open(OUT / "body-frames/idle.png").convert("RGBA"),frames["idle"]]
    for i,(frame,label) in enumerate(zip(refs,["주인공 최신","엘프 최신","여마법사 몸 기준","모자 합성"])):
        x=48+i*195
        compare.alpha_composite(frame.resize((96,144),Image.Resampling.NEAREST),(x,78))
        for row in (11,27,40,47):ImageDraw.Draw(compare).line((x-6,78+row*3,x+102,78+row*3),fill="#E9B95F")
        common.text(compare,(x-8,244),label,15)
    compare.convert("RGB").save(OUT / "anatomy-comparison.png")
    before_path=OUT / "source/hat-floating-before-native.png"
    if before_path.is_file():
        fit=Image.new("RGBA",(460,246),"#4A3C52")
        common.text(fit,(20,14),"모자 착용 위치 · 챙이 정수리를 덮도록 수정",18)
        samples=[Image.open(before_path).convert("RGBA"),frames["idle"],refs[2]]
        for i,(frame,label) in enumerate(zip(samples,["수정 전","수정 후","모자 없는 몸"])):
            x=28+i*150
            fit.alpha_composite(frame.resize((96,144),Image.Resampling.NEAREST),(x,52))
            common.text(fit,(x+4,212),label,15)
        fit.convert("RGB").save(OUT / "hat-fit-review.png")


def finish(body_frames):
    body_frames["blink_idle"]=common.blink_from_idle(body_frames["idle"])
    hat=Image.open(OUT / "pipeline/hat-native.png").convert("RGBA")
    frames={}
    report={"status":"passed","character":"mage","art_status":"candidate","approved_by_user":False,
        "native_canvas":[32,48],"scale":3,"frame_count":8,"head_reference_frame":[3,11,25,27],
        "head_rows":[11,26],"torso_rows":[27,39],"legs_and_boots_rows":[40,46],"foot_row":46,
        "hat_layer_size":[32,14],"hat_placement":list(HAT_POSITION),"whole_body_uniform_registration":True,
        "hat_attachment":{"head_anchor":list(HAT_HEAD_ANCHOR),"hat_local_seat_anchor":list(HAT_LOCAL_ANCHOR),
            "rejected_previous_placement":[0,0],"reason":"The hat must sit over the crown, not merely connect at a few outline pixels."},
        "anatomy_note":"22×16 is the head reference frame. Hat and shoulder-length flowing hair are separate accessories; long robe covers upper leg rows40..43.",
        "stage_order":["background_cleanup","native_grid","material_ramp_remap","validation"],"frames":{}}
    for name,body in body_frames.items():
        common.eyes(body,name=="blink_idle")
        frame=body.copy();frame.alpha_composite(hat,HAT_POSITION);frames[name]=frame
        a=np.array(frame);b=np.array(body)
        check=validate(frame,[32,48],PALETTE,5)
        check["outline_boundary_violations"]=int((common.boundary(a)&np.any(a[:,:,:3]!=rgb(INK),axis=2)).sum())
        check["body_starts_on_row11"]=bool(not b[:11,:,3].any() and b[11,:,3].any())
        check["foot_on_row46"]=bool(a[46,:,3].any() and not a[47,:,3].any())
        check["head_reference_size"]=[22,16]
        check["head_crown_fits_width22"]=bool(not b[11:21,:3,3].any() and not b[11:21,25:,3].any())
        hat_mask=np.zeros((48,32),bool)
        hx,hy=HAT_POSITION
        hat_mask[hy:hy+hat.height,hx:hx+hat.width]=np.array(hat)[:,:,3]!=0
        overlap=hat_mask & (b[:,:,3]!=0)
        seat_x,seat_y=HAT_HEAD_ANCHOR
        check["hat_seat_touches_crown"]=bool(overlap[seat_y,seat_x])
        check["hat_crown_overlap_pixels"]=int(overlap[11:18,8:20].sum())
        check["hat_crown_overlap_sufficient"]=check["hat_crown_overlap_pixels"]>=40
        check["eyes_unchanged_by_hat"]=bool(np.array_equal(a[21:25,9:17],b[21:25,9:17]))
        check["body_eyes"]=common.eyes(body,name=="blink_idle")
        check["composite_eyes"]=common.eyes(frame,name=="blink_idle")
        check["exact_3x"]=np.array_equal(np.array(frame.resize((96,144),Image.Resampling.NEAREST)),np.repeat(np.repeat(a,3,0),3,1))
        if not check["passed"] or check["outline_boundary_violations"] or not all(check[k] for k in ("body_starts_on_row11","foot_on_row46","head_crown_fits_width22","exact_3x","hat_seat_touches_crown","hat_crown_overlap_sufficient","eyes_unchanged_by_hat")):
            report["status"]="failed"
        report["frames"][name]=check
    for a_name,b_name,label,rows in [("walk_contact_a","walk_contact_b","walk_contact_leg_changed_pixels",slice(40,47)),
        ("walk_pass_a","walk_pass_b","walk_pass_leg_changed_pixels",slice(40,47)),
        ("walk_contact_a","walk_contact_b","walk_contact_arm_changed_pixels",slice(27,36))]:
        report[label]=int(np.any(np.array(frames[a_name])[rows]!=np.array(frames[b_name])[rows],axis=2).sum())
        if report[label]==0:report["status"]="failed"
    changed=np.any(np.array(frames["idle"])!=np.array(frames["blink_idle"]),axis=2)
    eye_mask=np.zeros((48,32),bool);eye_mask[22:24,10:12]=True;eye_mask[22:24,14:16]=True
    report["blink_only_eye_pixels_changed"]=bool(changed.sum()==4 and not changed[~eye_mask].any())
    if not report["blink_only_eye_pixels_changed"]:report["status"]="failed"
    grips={"receive_extend":[5,29],"receive_hold":[12,32]}
    # Grip the upper bottle body six rows below its top. For a tall16-row
    # flask this keeps the neck below the face without moving the hand.
    anchors=common.bottle_anchors(frames,grips,grip_y_from_top=6)
    for name,(x,y) in grips.items():
        if tuple(np.array(body_frames[name])[y,x])!=(*rgb(SKIN),255):
            raise ValueError(f"Bottle grip does not touch a skin hand: {name}")
    report["bottle_anchor_validation"]={"tested_recipes":36,"tested_pose_recipe_pairs":72,"grips_on_skin":True}
    dump(OUT / "validation.json",report)
    if report["status"]!="passed":
        print(json.dumps(report,ensure_ascii=False,indent=2));raise SystemExit(1)
    for name in ("frames","body-frames","layers"):(OUT / name).mkdir(exist_ok=True)
    hat.save(OUT / "layers/hat.png")
    sheet=Image.new("RGBA",(128,96))
    for i,(name,frame) in enumerate(frames.items()):
        frame.save(OUT / "frames" / f"{name}.png")
        body_frames[name].save(OUT / "body-frames" / f"{name}.png")
        sheet.alpha_composite(frame,((i%4)*32,(i//4)*48))
    sheet.save(OUT / "mage-keyframes-native.png")
    sheet.resize((384,288),Image.Resampling.NEAREST).save(OUT / "mage-keyframes-3x.png")
    dump(OUT / "hand-anchors.json",anchors)
    write_review(frames,anchors)
    print(json.dumps({k:report[k] for k in ("status","character","frame_count","walk_contact_leg_changed_pixels","walk_pass_leg_changed_pixels","blink_only_eye_pixels_changed")},ensure_ascii=False))


def main():
    register();make_manifest()
    result=subprocess.run([sys.executable,str(ROOT / "tools/process_pixel_art.py"),"art/characters/keyframes-v1/mage/manifest.json"],capture_output=True,text=True,encoding="utf-8")
    if result.returncode:
        print(result.stdout);print(result.stderr);raise SystemExit(result.returncode)
    frames={name:Image.open(OUT / "pipeline" / f"{name}-native.png").convert("RGBA") for name in POSES}
    import refine_character_faces_v1 as faces
    frames={name:faces.apply(frame,"mage") for name,frame in frames.items()}
    diagnostic(frames)
    finish(frames)


if __name__=="__main__":main()
