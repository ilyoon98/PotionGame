"""Process a coherent four-character face refinement through approved ramps."""
from __future__ import annotations

import json
import subprocess
import sys

import numpy as np
from PIL import Image

from process_pixel_art import ROOT,clean_background,native_grid
import build_traveler_keyframes_v1 as common

OUT=ROOT / "art/characters/face-refinement-v1"
NAMES=("keeper","elf","mage","traveler")
COLORS={"keeper":{"outline":["#241C32"],"skin":["#F6D1AC"],"wood":["#916047"],"purple":["#86548E"],"gold":["#E9B95F"]},
    "elf":{"outline":["#241C32"],"skin":["#F6D1AC"],"wood":["#916047"],"leaf":["#718C59","#B5C77D"]},
    "mage":{"outline":["#241C32"],"skin":["#F6D1AC"],"purple":["#50315F","#86548E"],"wood":["#916047"]},
    "traveler":{"outline":["#241C32"],"skin":["#F6D1AC"],"shirt":["#FFF0BC"],"wood":["#916047","#C99463"]}}


def dump(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")


def main():
    sheet=Image.open(OUT / "source/generated-round-v1.png").convert("RGBA")
    cells=[clean_background(sheet.crop((round(i*sheet.width/4),0,round((i+1)*sheet.width/4),sheet.height)),224) for i in range(4)]
    scale=360/max(cells[i].height for i in (1,3))
    assets=[];records=[]
    for name,cell in zip(NAMES,cells):
        fit=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
        x=round((320-fit.width)/2);y=470-fit.height
        canvas=Image.new("RGBA",(320,480));canvas.alpha_composite(fit,(x,y))
        grid=native_grid(clean_background(canvas,224,crop=False),[32,48],0)
        grid.save(OUT / "source" / f"{name}-registered.png")
        records.append({"id":name,"source_size":list(cell.size),"common_scale":scale,"offset":[x,y]})
        rules=[]
        if name=="traveler":rules.append({"material":"shirt","hue":[.105,.22],"value_min":.78,"saturation_max":.44})
        if name=="keeper":rules.append({"material":"gold","hue":[.105,.20],"saturation_min":.30,"value_min":.85})
        rules.append({"material":"skin","hue":[.025,.15],"saturation_min":.12,"saturation_max":.50,"value_min":.73})
        rules.append({"material":"wood","hue":[.025,.16],"saturation_min":.05,"value_max":.90})
        assets.append({"id":name,"source":f"art/characters/face-refinement-v1/source/{name}-registered.png","size":[32,48],
            "position":[0,0],"margin":0,"dark_value":.25,"preserve_native_frame":True,"materials":COLORS[name],
            "material_ramps":{"shirt":"gold"} if name=="traveler" else {},"rules":rules,
            "fallback_material":"purple" if name in ("keeper","mage") else "leaf" if name=="elf" else "wood"})
    dump(OUT / "registration.json",{"common_scale":scale,"native_canvas":[32,48],"frames":records})
    dump(OUT / "manifest.json",{"schema_version":1,"status":"candidate","approved_by_user":False,"compose":False,"scale":3,
        "alpha_threshold":224,"max_colors":5,"palette":"art/palette.hex","ramps":"art/ramps.json",
        "output":"art/characters/face-refinement-v1/pipeline","scene":{"size":[32,48],"background":"#4A3C52"},"assets":assets})
    proc=subprocess.run([sys.executable,str(ROOT / "tools/process_pixel_art.py"),"art/characters/face-refinement-v1/manifest.json"],capture_output=True,text=True,encoding="utf-8")
    if proc.returncode:print(proc.stdout);print(proc.stderr);raise SystemExit(proc.returncode)
    board=Image.new("RGBA",(660,274),"#4A3C52")
    for i,(name,label) in enumerate(zip(NAMES,("주인공","엘프","여마법사","여행자"))):
        frame=Image.open(OUT / "pipeline" / f"{name}-native.png").convert("RGBA");x=22+i*162
        board.alpha_composite(frame.resize((96,144),Image.Resampling.NEAREST),(x,26));common.text(board,(x,194),label,16)
        frame.crop((0,11,32,27)).resize((128,64),Image.Resampling.NEAREST).save(OUT / "source" / f"{name}-face-diagnostic.png")
    board.convert("RGB").save(OUT / "source/native-diagnostic.png")
    print(json.dumps({"status":"processed_candidate","scale":scale,"frames":4}))


if __name__=="__main__":main()
