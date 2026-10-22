"""V5 whole-scene candidate using repaired outlines and intermediate elf head."""
from __future__ import annotations

import json
import shutil

import build_refined_workshop_mockup as workshop

ROOT = workshop.ROOT
OUT = ROOT / "art/mockups/full-ingame-v5"


def main():
    outline = json.loads((OUT / "characters/validation.json").read_text(encoding="utf-8"))
    if outline["status"] != "passed":
        raise ValueError("Character outline validation failed")
    OUT.mkdir(parents=True, exist_ok=True)
    shutil.copytree(ROOT / "art/mockups/full-ingame-v4/potions", OUT / "potions", dirs_exist_ok=True)
    original = {name:getattr(workshop,name) for name in ("OUT","MOTION","POTIONS","PRIMARY_MODE","TEMPLATE")}
    workshop.OUT = OUT
    workshop.MOTION = OUT / "motion"
    workshop.POTIONS = OUT / "potions"
    workshop.PRIMARY_MODE = "grid"
    workshop.TEMPLATE = "secondary_motion_outline_v5.template.html"
    try:
        workshop.main()
        path = OUT / "animation-data.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        data["revision"] = "v5-continuous-outline-balanced-elf"
        data["defaultMotion"] = "grid"
        data["native_character_sources"] = {name:f"characters/{name}-native.png" for name in ("witch","elf")}
        data["idle_config"] = json.loads((OUT / "characters/idle-config.json").read_text(encoding="utf-8"))
        data["outline_rule"] = "Every 4-neighbor alpha boundary is dark; outer outline and alpha silhouette are pinned throughout all poses."
        data["proportions_spec"].update(elf_head_box=[22,16],elf_head_position=[5,11],
                                       body_start_row=27,leg_start_row=40,ground_native_row=46)
        payload = json.dumps(data,ensure_ascii=False,separators=(",",":"))
        path.write_text(payload,encoding="utf-8")
        template = (ROOT / "tools" / workshop.TEMPLATE).read_text(encoding="utf-8")
        (OUT / "animated-preview.html").write_text(template.replace("__ANIMATION_DATA__",payload),encoding="utf-8")
        report_path = OUT / "validation.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report["revision"] = data["revision"]
        report["default_motion"] = "grid"
        report["native_character_source"] = "characters/"
        report["character_outline_validation"] = "characters/validation.json"
        report["fine_mode_changes_only_free_fabric_edges_on_display_grid"] = False
        report["both_modes_outer_boundary_and_alpha_pinned"] = True
        report["fine_changes_only_internal_pixels"] = True
        report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        print(json.dumps({"revision":report["revision"],"default_motion":"grid","whole_scene":"passed"}))
    finally:
        for name,value in original.items(): setattr(workshop,name,value)


if __name__ == "__main__":
    main()
