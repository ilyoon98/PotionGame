"""Restore the original male keeper and replace only the oversized elf head.

Uses the established background -> grid -> material ramp -> validation stages.
The keeper is simplified with its original approved male identity as reference.
The elf torso is retained pixel-for-pixel; the replacement head is an imagegen edit.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from process_pixel_art import ROOT, STAGES, clean_background, native_grid, material_remap, validate, rgb

OUT = ROOT / "art/mockups/full-ingame-v3/characters"
PALETTE = {rgb(line) for line in (ROOT / "art/palette.hex").read_text().splitlines()}

CONFIG = {
    "witch": {
        "source": "art/mockups/full-ingame-v3/characters/source/keeper.png",
        "size": [32, 48], "margin": 1, "dark_value": .24,
        "preserve_source_outline": True,
        "materials": {"outline": ["#241C32"], "purple": ["#86548E"],
                      "wood": ["#916047"], "skin": ["#F6D1AC"], "gold": ["#E9B95F"]},
        "rules": [
            {"material": "skin", "hue": [0, .17], "value_min": .7, "saturation_max": .5},
            {"material": "gold", "hue": [.1, .19], "value_min": .65, "saturation_min": .3},
            {"material": "wood", "hue": [0, .16], "saturation_min": .15},
        ], "fallback_material": "purple",
    },
    "elf_head": {
        "source": "art/mockups/full-ingame-v3/characters/source/elf-head.png",
        "size": [18, 13], "margin": 0, "dark_value": .26,
        "preserve_source_outline": True,
        "materials": {"outline": ["#241C32"], "wood": ["#916047"],
                      "skin": ["#F6D1AC"], "leaf": ["#718C59"]},
        "rules": [
            {"material": "leaf", "hue": [.2, .48], "saturation_min": .15},
            {"material": "skin", "hue": [0, .18], "value_min": .7},
        ], "fallback_material": "wood",
        # The dominant-cell reduction can erase tiny eye marks. These explicit
        # semantic masks retain the generated eyes as two native-pixel marks.
        "material_rectangles": [
            {"rect": [4, 8, 5, 10], "material": "outline"},
            {"rect": [8, 8, 9, 10], "material": "outline"},
        ],
    },
}


def process(name, asset, ramps):
    source_path = ROOT / asset["source"]
    source = Image.open(source_path).convert("RGBA")
    cleaned = clean_background(source, 224)
    cleaned.save(OUT / "stages" / f"{name}-clean.png")
    grid = native_grid(cleaned, asset["size"], asset["margin"])
    grid.save(OUT / "stages" / f"{name}-grid.png")
    result, mask, ids = material_remap(grid, asset, ramps)
    mask.save(OUT / "stages" / f"{name}-materials.png")
    check = validate(result, asset["size"], PALETTE, 5)
    check.update(source_sha256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
                 material_mask_ids=ids)
    if not check["passed"]:
        raise ValueError(f"Failed palette/grid checks: {name}: {check}")
    return result, check


def face_bounds(sprite, upper, lower, horizontal=None):
    data = np.array(sprite)
    skin = np.all(data[:, :, :3] == rgb("#F6D1AC"), axis=2) & (data[:, :, 3] == 255)
    skin[:upper] = False
    skin[lower:] = False
    if horizontal:
        skin[:, :horizontal[0]] = False
        skin[:, horizontal[1]:] = False
    rows, columns = np.where(skin)
    if not len(rows):
        raise ValueError("No face found in expected anatomy region")
    return {"bounds": [int(columns.min()), int(rows.min()), int(columns.max())+1, int(rows.max())+1],
            "width": int(columns.max()-columns.min()+1), "height": int(rows.max()-rows.min()+1),
            "skin_pixels": int(skin.sum())}


def comparison(keeper, elf):
    old_keeper = Image.open(ROOT / "art/mockups/cozy-witch-v1/witch-native.png").convert("RGBA")
    old_elf = Image.open(ROOT / "art/mockups/full-ingame-v1/elf-native.png").convert("RGBA")
    board = Image.new("RGB", (672, 266), "#241C32")
    draw = ImageDraw.Draw(board)
    font_path = str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf")
    label_font = ImageFont.truetype(font_path, 16)
    small = ImageFont.truetype(font_path, 13)
    draw.text((20, 16), "이전: 모자 끝 높이를 맞춤", font=label_font, fill="#F6D1AC")
    draw.text((348, 16), "수정: 얼굴·몸·발 기준을 맞춤", font=label_font, fill="#F6D1AC")
    draw.rectangle((16, 50, 321, 239), fill="#4A3C52")
    draw.rectangle((344, 50, 649, 239), fill="#4A3C52")
    draw.line((16, 233, 321, 233), fill="#827589")
    draw.line((344, 233, 649, 233), fill="#827589")
    for image, x in ((old_keeper, 25), (old_elf, 171), (keeper, 353), (elf, 499)):
        large = image.resize((128, 192), Image.Resampling.NEAREST)
        board.paste(large, (x, 47), large)
    draw.text((25, 245), "이전 목업", font=small, fill="#C38EB5")
    draw.text((353, 245), "남자 주인 복원 / 엘프 머리만 축소", font=small, fill="#C38EB5")
    board.save(OUT.parent / "character-comparison.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "stages").mkdir(exist_ok=True)
    ramps = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
    keeper, keeper_check = process("witch", CONFIG["witch"], ramps)
    head, head_check = process("elf_head", CONFIG["elf_head"], ramps)
    old_elf = Image.open(ROOT / "art/mockups/full-ingame-v1/elf-native.png").convert("RGBA")
    old_data = np.array(old_elf)
    elf_data = old_data.copy()
    elf_data[:27] = 0
    elf = Image.fromarray(elf_data)
    elf.alpha_composite(head, (7, 14))
    unchanged_body = np.array_equal(np.array(elf)[27:], old_data[27:])
    if not unchanged_body:
        raise ValueError("Replacing elf head changed torso/hands/feet")
    elf_check = validate(elf, [32, 48], PALETTE, 5)
    if not elf_check["passed"]:
        raise ValueError(f"Elf compositing failed palette check: {elf_check}")
    for name, im in (("witch", keeper), ("elf", elf), ("elf-head", head)):
        im.save(OUT / (name + "-native.png"))
        im.resize((im.width*3, im.height*3), Image.Resampling.NEAREST).save(OUT / (name + "-3x.png"))
    report = {
        "status": "passed", "art_status": "candidate", "approved_by_user": False,
        "stage_order": STAGES, "source_assets": CONFIG,
        "keeper_identity": "Original adult male: short brown hair, cream shirt, open purple cape, brown shorts and boots.",
        "keeper_identity_reference": "assets/source/character_idle_v2/keeper.png",
        "elf_torso_from_row_27_unchanged": unchanged_body,
        "elf_head_bounds": [7, 14, 25, 27],
        "keeper_face": face_bounds(keeper, 17, 24),
        "elf_face": face_bounds(elf, 14, 27, (10, 20)),
        "checks": {"witch": keeper_check, "elf_head": head_check, "elf": elf_check},
        "notes": "Compare anatomy beneath hat; do not stretch the hatless elf to fill its 32x48 canvas.",
    }
    (OUT / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    comparison(keeper, elf)
    print(json.dumps({"status": report["status"], "keeper_face": report["keeper_face"], "elf_face": report["elf_face"],
                      "elf_body_unchanged": unchanged_body}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
