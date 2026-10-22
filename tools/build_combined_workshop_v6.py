"""V6 candidate: directed eyes, tapered elf tunic, breathing plus detail motion."""
from __future__ import annotations

import json
import shutil

from PIL import Image

import build_refined_workshop_mockup as workshop

ROOT = workshop.ROOT
OUT = ROOT / "art/mockups/full-ingame-v6"


def combined_index(seconds, phase=0):
    clock = seconds + phase
    return (int(clock*8) % 16
            + (16 if clock % 3 >= 1.5 else 0)
            + (32 if 3.6 <= clock % 4.5 < 3.85 else 0))


def refined_static(potions):
    image = workshop.floor_art()
    old = ROOT / "art/mockups/full-ingame-v1"
    placements = {"window":[4,5],"herb_station":[4,48],"poster":[153,1],"counter":[105,64]}
    for name, position in placements.items():
        source = OUT / "herb_station-native.png" if name == "herb_station" else old / f"{name}-native.png"
        if not source.is_file(): source = old / f"{name}-native.png"
        image.alpha_composite(workshop.read(source),tuple(position))
    image.alpha_composite(workshop.read(OUT / "potions" / potions["shelf_composite_path"]),(105,1))
    return image.resize((540,249),Image.Resampling.NEAREST)


def main():
    chars = json.loads((OUT / "characters/validation.json").read_text(encoding="utf-8"))
    if chars["status"] != "passed": raise ValueError("Character validation failed")
    OUT.mkdir(parents=True,exist_ok=True)
    shutil.copytree(ROOT / "art/mockups/full-ingame-v4/potions",OUT / "potions",dirs_exist_ok=True)
    keys = ("OUT","MOTION","POTIONS","PRIMARY_MODE","TEMPLATE","motion_index","static_art")
    original = {name:getattr(workshop,name) for name in keys}
    workshop.OUT, workshop.MOTION, workshop.POTIONS = OUT, OUT / "motion", OUT / "potions"
    workshop.PRIMARY_MODE = "grid"
    workshop.TEMPLATE = "combined_idle_v6.template.html"
    workshop.motion_index = combined_index
    workshop.static_art = refined_static
    try:
        workshop.main()
        path = OUT / "animation-data.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["revision"] = "v6-eye-direction-combined-idle"
        data["defaultMotion"] = "grid"
        data["timing"].update(breath_seconds=3,breath_poses_offset=16,blink_poses_offset=32)
        motion_manifest = json.loads((OUT / "motion/frames.json").read_text(encoding="utf-8"))
        for name in ("witch","elf"):
            data["sprites"][name] = [workshop.shared.uri(workshop.read(OUT / "motion" / motion_manifest["modes"]["grid"][name][index]).resize((32,48),Image.Resampling.NEAREST))
                                     for index in (0,16,32,48)]
        data["native_character_sources"] = {name:f"characters/{name}-native.png" for name in ("witch","elf")}
        data["idle_config"] = json.loads((OUT / "characters/idle-config.json").read_text(encoding="utf-8"))
        data["proportions_spec"].update(elf_head_box=[22,16],body_start_row=27,leg_start_row=40,
                                       ground_native_row=46,male_eye_count=2,elf_eye_count=2)
        data["outline_rule"] = "Continuous dark alpha boundary in every pose. Breath translates the upper body one native pixel while hands/feet remain fixed."
        payload = json.dumps(data,ensure_ascii=False,separators=(",",":"))
        path.write_text(payload,encoding="utf-8")
        template = (ROOT / "tools" / workshop.TEMPLATE).read_text(encoding="utf-8")
        (OUT / "animated-preview.html").write_text(template.replace("__ANIMATION_DATA__",payload),encoding="utf-8")
        report_path = OUT / "validation.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report.update(revision=data["revision"],default_motion="grid",character_validation="characters/validation.json",
                      native_character_source="characters/",combined_breath_and_detail_motion=True,
                      breath_native_pixels=1,breath_seconds=3,outer_silhouette_fixed_across_breath=False,
                      continuous_outline_per_pose=True,potion_shelf_retained=True)
        report["fine_mode_changes_only_free_fabric_edges_on_display_grid"] = False
        report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print(json.dumps({"revision":data["revision"],"breath_and_detail":True,"scene":"passed"}))
    finally:
        for name, value in original.items(): setattr(workshop,name,value)


if __name__ == "__main__":
    main()
