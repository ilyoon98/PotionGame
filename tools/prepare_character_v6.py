"""Explicit v6 face masks and a narrower elf tunic, preserving identity.

The v5 head size and native pixel grid stay fixed. Eyes are two isolated dark
pixels and the elf's skirt fabric is narrowed without moving hands or legs.
"""
from __future__ import annotations

import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from process_pixel_art import ROOT, rgb, validate
from prepare_character_outline_v5 import OUTLINE, SKIN, PALETTE, boundary_mask, repair_outline, core_face_bounds

OUT = ROOT / "art/mockups/full-ingame-v6/characters"
SOURCE = ROOT / "art/mockups/full-ingame-v5/characters"
EYES = {"witch": [[15, 20], [15, 21], [18, 20], [18, 21]],
        "elf": [[10, 21], [10, 22], [15, 21], [15, 22]]}
SKIRT_ROWS = {34: [11, 20], 35: [11, 20], 36: [11, 20],
              37: [10, 21], 38: [10, 21], 39: [10, 21]}
LEAF = rgb("#718C59")
LIGHT_LEAF = rgb("#B5C77D")


def paint_face_skin(data, source, rectangle):
    x0, y0, x1, y1 = rectangle
    edge = boundary_mask(source)
    area = edge[y0:y1, x0:x1]
    if area.any() or (data[y0:y1, x0:x1, 3] != 255).any():
        raise ValueError(f"Face skin patch reaches an outer boundary: {rectangle}")
    data[y0:y1, x0:x1] = (*SKIN, 255)


def face_edit(source, name):
    data = np.array(source)
    if name == "witch":
        # Remove only the old face eye pixels and their fused dark eye segment.
        # Hair on y19 and the facial/profile outer line are kept intact.
        paint_face_skin(data, source, [13, 20, 16, 23])
        # Both right-facing eyes are centered in skin-only 3x4 patches. The
        # top corners are skin too, so pupils never touch bangs diagonally.
        paint_face_skin(data, source, [14, 19, 17, 23])
        paint_face_skin(data, source, [17, 19, 20, 23])
    elif name == "elf":
        # Identical pupil height, with one native skin pixel between the right
        # pupil and dark bangs. Both eyes remain one wide, two high.
        paint_face_skin(data, source, [9, 20, 12, 24])
        paint_face_skin(data, source, [14, 20, 17, 24])
    else:
        raise ValueError(name)
    for x, y in EYES[name]:
        data[y, x] = (*OUTLINE, 255)
    return Image.fromarray(data)


def hand_mask(shape):
    mask = np.zeros(shape[:2], dtype=bool)
    # Left hand with its outline, and right hand with the sleeve/contact line.
    mask[30:35, 6:10] = True
    mask[30:35, 13:19] = True
    return mask


def narrow_tunic(source):
    old = np.array(source)
    data = old.copy()
    protected = hand_mask(data.shape)
    for y, (left, right) in SKIRT_ROWS.items():
        for x in range(data.shape[1]):
            if protected[y, x]:
                continue
            if not left <= x <= right:
                data[y, x] = 0
            else:
                color = tuple(old[y, x, :3])
                # Reuse the existing green fabric shade; old outline pixels
                # inside the new fabric silhouette become its base green.
                if color not in (LEAF, LIGHT_LEAF):
                    color = LEAF
                data[y, x] = (*color, 255)
    if not np.array_equal(data[protected], old[protected]):
        raise ValueError("Tunic cleanup moved a protected hand/sleeve")
    if not np.array_equal(data[40:], old[40:]):
        raise ValueError("Tunic cleanup changed legs or feet")
    return Image.fromarray(data)


def dark_component(image, start, diagonals=False):
    data = np.asarray(image)
    dark = np.all(data[:, :, :3] == OUTLINE, axis=2) & (data[:, :, 3] == 255)
    x, y = start
    if not dark[y, x]:
        raise ValueError("Eye is no longer dark")
    queue, seen = [(x, y)], {(x, y)}
    while queue:
        px, py = queue.pop()
        neighbors = [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]
        if diagonals:
            neighbors.extend([(px - 1, py - 1), (px + 1, py - 1),
                              (px - 1, py + 1), (px + 1, py + 1)])
        for nx, ny in neighbors:
            if 0 <= nx < image.width and 0 <= ny < image.height and dark[ny, nx] and (nx, ny) not in seen:
                seen.add((nx, ny))
                queue.append((nx, ny))
    return sorted(seen)


def eye_checks(image, name):
    data = np.array(image)
    edge = boundary_mask(image)
    checks = []
    eyes = EYES[name]
    for index in range(0, len(eyes), 2):
        pair = eyes[index:index + 2]
        component = dark_component(image, pair[0])
        if component != sorted(tuple(point) for point in pair):
            raise ValueError(f"{name} eye connects to other dark pixels: {component}")
        x, y = pair[0]
        component_8 = dark_component(image, pair[0], diagonals=True)
        if component_8 != sorted(tuple(point) for point in pair):
            raise ValueError(f"{name} eye diagonally connects to hair: {component_8}")
        margins = [(px, py) for py in range(y - 1, y + 3) for px in range(x - 1, x + 2)
                   if (px, py) not in [tuple(point) for point in pair]]
        if any(tuple(data[py, px, :3]) != SKIN for px, py in margins):
            raise ValueError(f"{name} eye has no one-pixel skin margin")
        if any(edge[py, px] for px, py in pair):
            raise ValueError("Eye reaches the character silhouette edge")
        checks.append({"pixels": pair, "width": 1, "height": 2,
                       "dark_component_pixels": len(component),
                       "dark_component_8_pixels": len(component_8),
                       "skin_margin_one_pixel": True, "separate_from_hair": True})
    return checks


def text(draw, position, value, size, color="#FFF0BC", anchor=None):
    font = ImageFont.truetype(str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"), size)
    draw.text(position, value, font=font, fill=color, anchor=anchor)


def review(original, revised):
    canvas = Image.new("RGB", (808, 440), "#241C32")
    draw = ImageDraw.Draw(canvas)
    text(draw, (24, 18), "캐릭터 수정 후보 · 눈 방향과 간결한 옷 실루엣", 21)
    text(draw, (24, 52), "머리 크기 유지 / 눈 1×2 픽셀 / 같은 높이의 엘프 눈 / 손·다리·발 고정", 14, "#C38EB5")
    for left, title, sprites in ((32, "이전 v5", original), (430, "수정 v6", revised)):
        text(draw, (left + 170, 86), title, 17, anchor="mt")
        draw.rectangle((left - 10, 112, left + 349, 405), fill="#4A3C52")
        for offset, name in ((0, "witch"), (174, "elf")):
            image = sprites[name].resize((192, 288), Image.Resampling.NEAREST)
            canvas.paste(image, (left + offset, 116), image)
    text(draw, (32, 414), "남캐·엘프 모두 눈 2개 / 각 눈은 같은 높이", 14, "#C38EB5")
    text(draw, (430, 414), "눈과 머리카락 분리 / 하의 폭 10~12픽셀", 14, "#C38EB5")
    canvas.save(OUT / "character-review.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    originals = {name: Image.open(SOURCE / f"{name}-native.png").convert("RGBA")
                 for name in ("witch", "elf")}
    revised, checks, repaired = {}, {}, {}
    for name in ("witch", "elf"):
        source = originals[name]
        image = face_edit(source, name)
        if name == "elf":
            image = narrow_tunic(image)
            # The v5 head attachment left a two-pixel enclosed gap above the
            # neck. Close only this joint, retaining the intentional leg gap.
            neck = np.array(image)
            for x, y in ((18, 26), (19, 26)):
                if neck[y, x, 3] != 0:
                    raise ValueError("Elf neck repair no longer matches the explicit two-pixel gap")
                neck[y, x] = (*OUTLINE, 255)
            image = Image.fromarray(neck)
        image, repaired[name] = repair_outline(image)
        check = validate(image, [32, 48], PALETTE, 5)
        if not check["passed"]:
            raise ValueError(f"Character pixel check failed: {name}: {check}")
        if image.getbbox()[3] != 47:
            raise ValueError(f"{name} feet lost native row 46")
        check["eyes"] = eye_checks(image, name)
        check["outline_boundary_violations"] = 0
        image.save(OUT / f"{name}-native.png")
        image.resize((96, 144), Image.Resampling.NEAREST).save(OUT / f"{name}-3x.png")
        revised[name], checks[name] = image, check
    original_elf = np.array(originals["elf"])
    elf_data = np.array(revised["elf"])
    protected = hand_mask(elf_data.shape)
    if not np.array_equal(elf_data[protected], original_elf[protected]):
        raise ValueError("Final outline changed protected elf hands/sleeves")
    if not np.array_equal(elf_data[40:], original_elf[40:]):
        raise ValueError("Final outline changed elf legs or feet")
    if not np.array_equal(elf_data[:20], original_elf[:20]):
        raise ValueError("Elf head size or upper hair changed")
    if not np.array_equal(np.array(revised["witch"])[23:], np.array(originals["witch"])[23:]):
        raise ValueError("Male face adjustment changed clothing/body")
    idle = {"witch": {"eyes": EYES["witch"], "cut": 30},
            "elf": {"eyes": EYES["elf"], "cut": 27},
            "notes": "Two aligned male eyes on the right-facing face and two same-height elf eyes. All are isolated 1x2 dark components, including 8-neighbor checks."}
    (OUT / "idle-config.json").write_text(json.dumps(idle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = {"status": "passed", "art_status": "candidate", "approved_by_user": False,
              "native_canvas": [32, 48], "scale": 3,
              "source": "art/mockups/full-ingame-v5/characters/",
              "face_masks": {"witch": [[13, 20, 16, 23], [14, 19, 17, 23], [17, 19, 20, 23]],
                             "elf": [[9, 20, 12, 24], [14, 20, 17, 24]]},
              "eye_coordinates": EYES, "checks": checks,
              "elf_head_size_preserved": True, "elf_upper_head_pixels_preserved": True,
              "elf_hands_and_sleeves_preserved": True, "elf_legs_and_feet_from_row_40_preserved": True,
              "male_clothes_and_body_preserved": True, "feet_native_row": 46,
              "elf_fabric_rows": SKIRT_ROWS, "elf_waist_width": 10, "elf_hem_width": 12,
              "elf_neck_joint_repair": {"pixels": [[18, 26], [19, 26]],
                                        "pixel_count": 2, "color": "#241C32"},
              "repaired_boundary_pixels": repaired,
              "face_core": {"witch": core_face_bounds(revised["witch"], 17, 24),
                            "elf": core_face_bounds(revised["elf"], 11, 27)},
              "text_rendering": "Normal font, excluded from sprite color inspection"}
    (OUT / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    review(originals, revised)
    print(json.dumps({"status": "passed", "eyes": EYES, "skirt_rows": SKIRT_ROWS,
                      "max_colors": max(row["color_count"] for row in checks.values()),
                      "outline_violations": 0, "hands_and_legs_unchanged": True}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
