"""Candidate intermediate elf-head size and consistent native-pixel outlines.

Preserves the v3 male identity and both lower-body alpha silhouettes. The new
elf head alone is generated; it passes the existing fixed material pipeline.
"""
from __future__ import annotations

import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from process_pixel_art import (ROOT, STAGES, clean_background, native_grid,
                               material_remap, validate, rgb)

OUT = ROOT / "art/mockups/full-ingame-v5/characters"
V3 = ROOT / "art/mockups/full-ingame-v3/characters"
PALETTE = {rgb(line) for line in (ROOT / "art/palette.hex").read_text().splitlines()}
OUTLINE = rgb("#241C32")
SKIN = rgb("#F6D1AC")
HEAD_SIZE = [22, 16]
HEAD_POSITION = [5, 11]
BODY_START = 27
# Explicitly reviewed against the resulting native head. The x=8 dark pair is
# the ear/hair separation, so it must never be selected as the left eye.
ELF_EYES = [[10, 21], [10, 22], [15, 20], [15, 21]]

HEAD_CONFIG = {
    "source": "art/mockups/full-ingame-v5/characters/source/elf-head.png",
    "size": HEAD_SIZE, "margin": 0, "dark_value": .26,
    "preserve_source_outline": True,
    "materials": {"outline": ["#241C32"], "wood": ["#916047"],
                  "skin": ["#F6D1AC"], "leaf": ["#718C59"]},
    "rules": [{"material": "leaf", "hue": [.2, .48], "saturation_min": .15},
              {"material": "skin", "hue": [0, .18], "value_min": .7}],
    "fallback_material": "wood",
}


def boundary_mask(image):
    data = np.asarray(image.convert("RGBA"))
    opaque = data[:, :, 3] == 255
    padded = np.pad(opaque, 1)
    interior = (padded[1:-1, :-2] & padded[1:-1, 2:] &
                padded[:-2, 1:-1] & padded[2:, 1:-1])
    return opaque & ~interior


def repair_outline(image):
    data = np.array(image.convert("RGBA"))
    edge = boundary_mask(image)
    changed = edge & ~np.all(data[:, :, :3] == OUTLINE, axis=2)
    data[edge] = (*OUTLINE, 255)
    result = Image.fromarray(data)
    if not np.array_equal(data[:, :, 3], np.asarray(image)[:, :, 3]):
        raise ValueError("Outline repair changed the existing alpha silhouette")
    if outline_violations(result):
        raise ValueError("Repaired character still has an exposed non-outline pixel")
    return result, int(changed.sum())


def outline_violations(image):
    data = np.asarray(image.convert("RGBA"))
    return int(np.count_nonzero(boundary_mask(image) &
                               ~np.all(data[:, :, :3] == OUTLINE, axis=2)))


def save_and_check(image, name, max_colors=5):
    check = validate(image, list(image.size), PALETTE, max_colors)
    if not check["passed"]:
        raise ValueError(f"Pixel validation failed: {name}: {check}")
    image.save(OUT / f"{name}-native.png")
    image.resize((image.width * 3, image.height * 3), Image.Resampling.NEAREST).save(OUT / f"{name}-3x.png")
    check["outline_boundary_violations"] = outline_violations(image)
    return check


def process_head(ramps):
    source_path = ROOT / HEAD_CONFIG["source"]
    source = Image.open(source_path).convert("RGBA")
    clean = clean_background(source, 224)
    clean.save(OUT / "stages/elf-head-clean.png")
    grid = native_grid(clean, HEAD_SIZE, 0)
    grid.save(OUT / "stages/elf-head-grid.png")
    remapped, material_mask, mask_ids = material_remap(grid, HEAD_CONFIG, ramps)
    material_mask.save(OUT / "stages/elf-head-materials.png")
    remapped.save(OUT / "stages/elf-head-remapped.png")
    head, changed = repair_outline(remapped)
    check = save_and_check(head, "elf-head")
    check.update(source_sha256=hashlib.sha256(source_path.read_bytes()).hexdigest(),
                 material_mask_ids=mask_ids, repaired_boundary_pixels=changed)
    return head, check


def face_bounds(image, y0, y1, x0=0, x1=32):
    data = np.array(image)
    skin = np.all(data[:, :, :3] == SKIN, axis=2) & (data[:, :, 3] == 255)
    region = np.zeros(skin.shape, dtype=bool)
    region[y0:y1, x0:x1] = True
    yy, xx = np.where(skin & region)
    if not len(xx):
        return {"bounds": None, "width": 0, "height": 0, "skin_pixels": 0}
    return {"bounds": [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1],
            "width": int(xx.max() - xx.min() + 1), "height": int(yy.max() - yy.min() + 1),
            "skin_pixels": int(len(xx))}


def silhouette_bounds(image, y0=0, y1=None):
    data = np.array(image)
    opaque = data[:, :, 3] == 255
    opaque[:y0] = False
    if y1 is not None:
        opaque[y1:] = False
    yy, xx = np.where(opaque)
    if not len(xx):
        return {"bounds": None, "width": 0, "height": 0}
    return {"bounds": [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1],
            "width": int(xx.max() - xx.min() + 1), "height": int(yy.max() - yy.min() + 1)}


def core_face_bounds(image, y0, y1):
    """Largest connected skin region removes detached elf ears from face size."""
    data = np.array(image)
    skin = np.all(data[:, :, :3] == SKIN, axis=2) & (data[:, :, 3] == 255)
    skin[:y0] = False
    skin[y1:] = False
    seen, components = set(), []
    for y, x in zip(*np.where(skin)):
        if (x, y) in seen:
            continue
        queue, component = [(int(x), int(y))], []
        seen.add((x, y))
        while queue:
            px, py = queue.pop()
            component.append((px, py))
            for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                if 0 <= nx < image.width and 0 <= ny < image.height and skin[ny, nx] and (nx, ny) not in seen:
                    seen.add((nx, ny))
                    queue.append((nx, ny))
        components.append(component)
    if not components:
        return {"bounds": None, "width": 0, "height": 0, "skin_pixels": 0}
    chosen = max(components, key=len)
    xx, yy = zip(*chosen)
    return {"bounds": [min(xx), min(yy), max(xx) + 1, max(yy) + 1],
            "width": max(xx) - min(xx) + 1, "height": max(yy) - min(yy) + 1,
            "skin_pixels": len(chosen), "measurement": "largest 4-connected skin component, ears excluded"}


def eye_candidates(image, region):
    """Report interior vertical eye pairs that can blink without touching edge."""
    data = np.array(image)
    dark = np.all(data[:, :, :3] == OUTLINE, axis=2) & (data[:, :, 3] == 255)
    skin = np.all(data[:, :, :3] == SKIN, axis=2) & (data[:, :, 3] == 255)
    edge = boundary_mask(image)
    x0, y0, x1, y1 = region
    candidates = []
    for y in range(y0, min(y1, image.height - 1)):
        for x in range(max(1, x0), min(x1, image.width - 1)):
            if (dark[y, x] and dark[y + 1, x] and not edge[y, x] and not edge[y + 1, x]
                    and skin[y + 1, x + 1] and (skin[y, x + 1] or skin[y, x - 1])
                    and (skin[y, x - 1] or skin[y + 1, x - 1])):
                candidates.append([[x, y], [x, y + 1]])
    # Longer dark hair columns can produce adjacent pairs. Keep one per x.
    by_x = {}
    for pair in candidates:
        by_x.setdefault(pair[0][0], pair)
    return [by_x[x] for x in sorted(by_x)]


def old_eye_validity(image, eyes):
    data = np.array(image)
    edge = boundary_mask(image)
    details = []
    for index in range(0, len(eyes), 2):
        pair = eyes[index:index + 2]
        valid = (all(tuple(data[y, x, :3]) == OUTLINE and data[y, x, 3] == 255 and not edge[y, x]
                     for x, y in pair)
                 and tuple(data[pair[1][1], pair[1][0] + 1, :3]) == SKIN)
        details.append({"pair": pair, "valid_interior_eye_pair": bool(valid)})
    return details


def anatomy_guide(keeper, old_elf, elf, report):
    canvas = Image.new("RGB", (816, 428), "#241C32")
    draw = ImageDraw.Draw(canvas)
    font_path = str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf")
    title = ImageFont.truetype(font_path, 21)
    label = ImageFont.truetype(font_path, 15)
    small = ImageFont.truetype(font_path, 13)
    draw.text((24, 18), "캐릭터 비율 후보 · 얼굴 크기와 연결된 외곽선", font=title, fill="#F6D1AC")
    draw.text((24, 52), "모자 높이와 얼굴 크기를 분리 / 같은 발 접지 y=46 / 원본 1픽셀 외곽선", font=small, fill="#C38EB5")
    top, scale = 98, 6
    columns = [(30, keeper, "남자 주인 · 기존 형상"),
               (282, old_elf, "이전 엘프 · 18×13 머리"),
               (534, elf, "수정 엘프 · 22×16 머리")]
    for left, image, caption in columns:
        draw.rectangle((left - 8, top - 8, left + 199, top + 293), fill="#4A3C52")
        draw.text((left, 76), caption, font=label, fill="#FFF0BC")
        enlarged = image.resize((192, 288), Image.Resampling.NEAREST)
        canvas.paste(enlarged, (left, top), enlarged)
        for row, color in ((27, "#827589"), (40, "#916047"), (46, "#E9B95F")):
            draw.line((left - 6, top + row * scale, left + 197, top + row * scale), fill=color)
        draw.text((left, 396), "27 어깨 · 40 다리 · 46 발", font=small, fill="#C38EB5")
    draw.rectangle((534 + 5 * scale, top + 11 * scale,
                    534 + 27 * scale - 1, top + 27 * scale - 1), outline="#9BE2CF")
    canvas.save(OUT / "anatomy-guide.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "stages").mkdir(exist_ok=True)
    ramps = json.loads((ROOT / "art/ramps.json").read_text(encoding="utf-8"))
    try:
        head, head_check = process_head(ramps)
        old_keeper = Image.open(V3 / "witch-native.png").convert("RGBA")
        old_elf = Image.open(V3 / "elf-native.png").convert("RGBA")
        keeper, keeper_changed = repair_outline(old_keeper)
        elf_data = np.array(old_elf)
        elf_data[:BODY_START] = 0
        before_outline = Image.fromarray(elf_data)
        before_outline.alpha_composite(head, tuple(HEAD_POSITION))
        body_preserved_before = np.array_equal(np.array(before_outline)[BODY_START:], np.array(old_elf)[BODY_START:])
        if not body_preserved_before:
            raise ValueError("New elf head changed existing torso before outline repair")
        elf, elf_changed = repair_outline(before_outline)
        keeper_check = save_and_check(keeper, "witch")
        elf_check = save_and_check(elf, "elf")
        for name, image, original in (("witch", keeper, old_keeper), ("elf", elf, old_elf)):
            if image.getbbox()[3] != 47:
                raise ValueError(f"{name} feet need native row 46")
            if not np.array_equal(np.array(image)[BODY_START:, :, 3], np.array(original)[BODY_START:, :, 3]):
                raise ValueError(f"{name} outline grew lower-body alpha silhouette")
        old_idle = json.loads((V3 / "idle-config.json").read_text(encoding="utf-8"))
        keeper_eye_checks = old_eye_validity(keeper, old_idle["witch"]["eyes"])
        keeper_candidates = eye_candidates(keeper, [9, 17, 23, 24])
        elf_candidates = eye_candidates(elf, [7, 17, 26, 26])
        keeper_eyes = old_idle["witch"]["eyes"] if all(row["valid_interior_eye_pair"] for row in keeper_eye_checks) else [point for pair in keeper_candidates[:2] for point in pair]
        elf_eye_checks = old_eye_validity(elf, ELF_EYES)
        if not all(row["valid_interior_eye_pair"] for row in elf_eye_checks):
            raise ValueError("Explicit reviewed elf eyes no longer match the source")
        elf_eyes = ELF_EYES
        idle = {"witch": {"eyes": keeper_eyes, "cut": 30},
                "elf": {"eyes": elf_eyes, "cut": 27},
                "inference_notes": "Elf eyes explicitly reviewed: x10 at y21/22, x15 at y20/21. Excludes the x8 ear/hair boundary candidate.",
                "eye_candidates": {"witch": keeper_candidates, "elf": elf_candidates}}
        (OUT / "idle-config.json").write_text(json.dumps(idle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        report = {"status": "passed", "art_status": "candidate", "approved_by_user": False,
                  "stage_order": STAGES + ["inside_alpha_boundary_outline"],
                  "head_source_config": HEAD_CONFIG, "elf_head_frame_size": HEAD_SIZE,
                  "elf_head_position": HEAD_POSITION, "elf_body_start_row": BODY_START,
                  "elf_body_pixels_preserved_before_outline": body_preserved_before,
                  "elf_lower_body_alpha_preserved": True, "keeper_alpha_silhouette_preserved": True,
                  "feet_native_row": 46,
                  "keeper_identity": "Existing v3 male keeper with short brown hair, open purple cape, shorts and boots",
                  "repaired_boundary_pixels": {"witch": keeper_changed, "elf": elf_changed},
                  "checks": {"witch": keeper_check, "elf": elf_check, "elf_head": head_check},
                  "face_bounds": {"witch": core_face_bounds(keeper, 17, 24),
                                  "elf": core_face_bounds(elf, 11, 27)},
                  "skin_bounds_including_ears": {"witch": face_bounds(keeper, 17, 24, 11, 22),
                                                "elf": face_bounds(elf, 11, 27, 10, 24)},
                  "elf_head_silhouette": silhouette_bounds(head),
                  "elf_body_silhouette": silhouette_bounds(elf, BODY_START),
                  "elf_face_target": {"width_range": [10, 12], "height_range": [8, 10]},
                  "old_male_eye_pair_checks": keeper_eye_checks,
                  "elf_eye_pair_checks": elf_eye_checks,
                  "elf_eye_candidates_need_visual_confirmation": False,
                  "idle_config": idle,
                  "notes": "Outline repair recolors exposed opaque pixels inside the same silhouette, including holes; animation deformations must repair their own frame boundaries."}
        report["elf_head_to_body_ratio"] = {
            "width": round(report["elf_head_silhouette"]["width"] / report["elf_body_silhouette"]["width"], 3),
            "height": round(report["elf_head_silhouette"]["height"] / report["elf_body_silhouette"]["height"], 3)}
        (OUT / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        anatomy_guide(keeper, old_elf, elf, report)
        print(json.dumps({"status": "passed", "face_bounds": report["face_bounds"],
                          "repaired_boundary_pixels": report["repaired_boundary_pixels"],
                          "eye_candidates": idle["eye_candidates"], "old_male_eyes_valid": all(row["valid_interior_eye_pair"] for row in keeper_eye_checks)},
                         ensure_ascii=False, indent=2))
    except Exception as error:
        (OUT / "validation.json").write_text(json.dumps({"status": "failed", "error": str(error)}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise


if __name__ == "__main__":
    main()
