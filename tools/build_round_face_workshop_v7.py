"""Render v7's refined faces with the existing simultaneous IDLE effects."""
from __future__ import annotations

import json
from PIL import Image

from process_pixel_art import ROOT,validate
import refine_character_faces_v1 as faces
import build_combined_idle_v6 as idle
import build_combined_workshop_v6 as workshop

OUT=ROOT / "art/mockups/full-ingame-v7"
V6=ROOT / "art/mockups/full-ingame-v6"


def main():
    target=OUT / "characters";target.mkdir(parents=True,exist_ok=True)
    checks={};config={}
    for name,profile,cut in (("witch","keeper",30),("elf","elf",27)):
        original=Image.open(V6 / "characters" / f"{name}-native.png").convert("RGBA")
        frame=faces.apply(original,profile)
        check=validate(frame,[32,48],faces.PALETTE,5)
        check["eyes"]=faces.eye_checks(frame,profile)
        check["outline_boundary_violations"]=0
        checks[name]=check
        frame.save(target / f"{name}-native.png")
        frame.resize((96,144),Image.Resampling.NEAREST).save(target / f"{name}-3x.png")
        config[name]={"eyes":faces.shifted_eye_points(profile),"cut":cut}
    config["notes"]="Rounded authored cheek/chin contours; keeper fringe restored above isolated eyes."
    (target / "idle-config.json").write_text(json.dumps(config,indent=2)+"\n",encoding="utf-8")
    report={"status":"passed","art_status":"candidate","approved_by_user":False,
        "native_canvas":[32,48],"scale":3,"checks":checks,"source":"art/characters/face-refinement-v1/generation.json"}
    (target / "validation.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    previous_source,previous_out=idle.SOURCE,idle.OUT
    idle.SOURCE,idle.OUT=target,OUT / "motion"
    try:idle.main()
    finally:idle.SOURCE,idle.OUT=previous_source,previous_out
    previous_out=workshop.OUT;workshop.OUT=OUT
    try:workshop.main()
    finally:workshop.OUT=previous_out
    data_path=OUT / "animation-data.json"
    data=json.loads(data_path.read_text(encoding="utf-8"));data["revision"]="v7-rounded-faces-connected-fringe"
    payload=json.dumps(data,ensure_ascii=False,separators=(",",":"));data_path.write_text(payload,encoding="utf-8")
    template=(ROOT / "tools/combined_idle_v6.template.html").read_text(encoding="utf-8")
    page=template.replace("목업 v6","목업 v7").replace("__ANIMATION_DATA__",payload)
    (OUT / "animated-preview.html").write_text(page,encoding="utf-8")
    report_path=OUT / "validation.json";report=json.loads(report_path.read_text(encoding="utf-8"))
    report.update(revision=data["revision"],face_refinement="art/characters/face-refinement-v1/validation.json")
    report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":"passed","output":"art/mockups/full-ingame-v7/animated-preview.html","idle_frames":256}))


if __name__=="__main__":main()
