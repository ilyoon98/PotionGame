"""Build the v3 character correction using the existing v2 motion compositor.

The two reviewed native characters and their eye masks are explicit inputs.
Weather, fire, furniture, palette, and normal-text controls remain shared with
the v2 mockup. This script does not change runtime assets or v2 build sources.
"""
from __future__ import annotations

import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

import build_animated_ingame_mockup as motion


OUT = motion.ROOT / "art/mockups/full-ingame-v3"
REFERENCE = motion.ROOT / "art/mockups/full-ingame-v2"
CHARACTERS = OUT / "characters"
REVISION = "v3-character-proportions"
PROPORTIONS = {
    "native_canvas": [32, 48],
    "shared_scale": 3,
    "scale_reference": "Face and body anatomy; hats are additional silhouette height.",
    "head_target_excluding_hat": {"width_range": [14, 16], "height": 12},
    "face_target": {"width_range": [8, 11], "height_range": [7, 9]},
    "elf_body_and_hand_pixels_preserved": True,
    "ground_native_row": 46,
    "character_scene_y": 32,
    "player_identity": "male witch",
    "approval_status": "candidate",
}


def load_characters():
    config = json.loads((CHARACTERS / "idle-config.json").read_text(encoding="utf-8"))
    characters = {}
    checks = {}
    for name in ("witch", "elf"):
        image = motion.read(CHARACTERS / f"{name}-native.png")
        check = motion.validate(image, [32, 48], motion.PALETTE, 5)
        if not check["passed"]:
            raise ValueError(f"Native character failed validation: {name}")
        if image.getbbox() is None or image.getbbox()[3] != 47:
            raise ValueError(f"Character feet must end at native row 46: {name}")
        idle = config[name]
        eyes = idle["eyes"]
        cut = idle["cut"]
        if not isinstance(cut, int) or not 1 <= cut < image.height:
            raise ValueError(f"Invalid idle cut for {name}")
        if not isinstance(eyes, list) or not eyes or len(eyes) % 2:
            raise ValueError(f"Eye mask must contain vertical pixel pairs for {name}")
        for point in eyes:
            if (not isinstance(point, list) or len(point) != 2
                    or any(not isinstance(value, int) for value in point)
                    or not 0 <= point[0] < image.width - 1
                    or not 0 <= point[1] < cut):
                raise ValueError(f"Invalid eye coordinate for {name}: {point}")
        # Preflight the original eye/skin checks and static lower-body mask.
        motion.character_frames(image, eyes, cut)
        image.info["mockup_character"] = name
        characters[name] = image
        checks[name] = check
    return characters, config, checks


def main():
    started = datetime.now(timezone.utc).isoformat()
    OUT.mkdir(parents=True, exist_ok=True)
    try:
        characters, idle_config, character_checks = load_characters()
        if not (REFERENCE / "effects/frames.json").is_file():
            raise FileNotFoundError("Build the v2 weather/fire effects first")
        if not (REFERENCE / "static-art.png").is_file():
            raise FileNotFoundError("Build the v2 static workshop art first")
        shutil.copytree(REFERENCE / "effects", OUT / "effects", dirs_exist_ok=True)
    except Exception as error:
        (OUT / "validation.json").write_text(json.dumps({
            "status": "failed", "revision": REVISION, "built_at": started,
            "art_status": "candidate", "approved_by_user": False,
            "error": str(error),
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise

    original = {name: getattr(motion, name) for name in
                ("OUT", "POSITIONS", "read", "sprite", "character_frames", "static_art")}
    original_witch = motion.ROOT / motion.OLD / "witch-native.png"

    def read(path):
        if Path(path) == original_witch:
            return characters["witch"].copy()
        return original["read"](path)

    def sprite(name):
        if name == "elf":
            return characters["elf"].copy()
        return original["sprite"](name)

    def character_frames(source, unused_eyes, unused_cut):
        name = source.info.get("mockup_character")
        if name not in characters:
            raise ValueError("Motion character source lacks its explicit identity")
        idle = idle_config[name]
        return original["character_frames"](source, idle["eyes"], idle["cut"])

    motion.OUT = OUT
    motion.POSITIONS = {key: value.copy() for key, value in original["POSITIONS"].items()}
    motion.POSITIONS["elf"] = [148, 32]
    motion.POSITIONS["heldBottle"] = [154, 56]
    motion.read = read
    motion.sprite = sprite
    motion.character_frames = character_frames
    motion.static_art = lambda unused_scene: original["read"](REFERENCE / "static-art.png")
    try:
        motion.main()
        data_path = OUT / "animation-data.json"
        data = json.loads(data_path.read_text(encoding="utf-8"))
        metadata = {
            "revision": REVISION,
            "built_at": started,
            "proportions_spec": PROPORTIONS,
            "idle_config": idle_config,
            "native_character_sources": {
                name: f"characters/{name}-native.png" for name in characters
            },
            "reused_art_source": "../full-ingame-v2/",
        }
        data.update(metadata)
        payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        data_path.write_text(payload, encoding="utf-8")
        template = (motion.ROOT / "tools/animated_workshop.template.html").read_text(encoding="utf-8")
        if template.count("__ANIMATION_DATA__") != 1:
            raise ValueError("Preview data placeholder is missing or duplicated")
        (OUT / "animated-preview.html").write_text(
            template.replace("__ANIMATION_DATA__", payload), encoding="utf-8")
        report_path = OUT / "validation.json"
        report = json.loads(report_path.read_text(encoding="utf-8"))
        report.update(metadata)
        report["native_character_validation"] = character_checks
        report["ground_baseline_aligned"] = True
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps({"revision": REVISION, "output": str(OUT),
                          "male_player": True, "shared_ground_row": 78}, ensure_ascii=False))
    except Exception as error:
        # Never leave an older passed report representing a failed fresh run.
        (OUT / "validation.json").write_text(json.dumps({
            "status": "failed", "revision": REVISION, "built_at": started,
            "art_status": "candidate", "approved_by_user": False,
            "error": str(error),
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise
    finally:
        for name, value in original.items():
            setattr(motion, name, value)


if __name__ == "__main__":
    main()
