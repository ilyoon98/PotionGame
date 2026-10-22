"""Inspect both eyes and absence of forehead holes in every exported IDLE."""
from __future__ import annotations
import json
import numpy as np
from PIL import Image
from process_pixel_art import ROOT
import refine_character_faces_v1 as faces


def main():
    folder=ROOT / "art/mockups/full-ingame-v7/motion"
    motion=json.loads((folder / "frames.json").read_text(encoding="utf-8"));checks=[]
    for mode,characters in motion["modes"].items():
        for name,paths in characters.items():
            profile="keeper" if name=="witch" else "elf"
            original_y=faces.PROFILES[profile]["eye_y"]
            for index,path in enumerate(paths):
                lifted=index%32>=16;closed=index>=32
                image=Image.open(folder / path).convert("RGBA");a=np.array(image)[::3,::3]
                native=Image.fromarray(a)
                faces.PROFILES[profile]["eye_y"]=original_y-int(lifted)
                try:faces.eye_checks(native,profile,closed)
                finally:faces.PROFILES[profile]["eye_y"]=original_y
                if profile=="keeper":
                    allowed={(*faces.rgb("#916047"),255),faces.INK}
                    if not all(tuple(a[y-int(lifted),x]) in allowed for x,y in faces.PROFILES[profile]["fringe_fill"]):
                        raise ValueError(f"Forehead hole returned: {mode}/{index}")
                checks.append({"mode":mode,"character":name,"index":index,"two_eyes_and_skin_gap_passed":True,"forehead_hair_solid":profile=="keeper"})
    report={"status":"passed","frames_tested":len(checks),"checks":checks}
    (folder / "eye-fringe-validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":"passed","eyes_and_fringe_frames_tested":len(checks)}))


if __name__=="__main__":main()
