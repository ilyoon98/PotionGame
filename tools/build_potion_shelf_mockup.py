"""Normalize existing bottle silhouettes and make a roomy candidate shelf.

This is deterministic cleanup of inspected native assets, not game integration.
Bottle bodies come from the earlier native silhouettes; their cap, glass and
one-pixel outline share a rule. Every recipe keeps its recorded liquid ramp.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from build_full_ingame_mockup import COLORS, LIQUIDS, PALETTE, SELECTED, content_rows
from process_pixel_art import ROOT, rgb, validate

OUT = ROOT / "art/mockups/full-ingame-v4/potions"
V1 = ROOT / "art/mockups/full-ingame-v1"
V3 = ROOT / "art/mockups/full-ingame-v3"
BOARDS = [22, 43]
CENTERS = [8, 18, 28, 38]


def rgba(value):
    return (*rgb(COLORS.get(value, value)), 255)


def inspect_and_save(image, path, max_colors=5):
    check = validate(image, list(image.size), PALETTE, max_colors)
    if not check["passed"]:
        raise ValueError(f"Palette validation failed for {path}: {check}")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return check


def normalized_bottle(row):
    """Retain the source body profile, give it one common cap/glass grammar."""
    old = Image.open(V1 / ("potion_" + row["id"] + "-native.png")).convert("RGBA")
    old_data = np.array(old)
    width, height = row["mock_native_size"]
    bounds = old.getbbox()
    if bounds is None or width != 8:
        raise ValueError("Every existing bottle needs an opaque 8-pixel frame")
    x0, y0, x1, y1 = bounds
    # The lower section is the existing body. Capping and necks are restored
    # separately, so tiny source cork speckles cannot become stray liquid pixels.
    body_start = max(y0 + 2, y1 - (9 if height == 16 else 7))
    body = Image.fromarray(old_data[body_start:y1, :, 3]).resize(
        (8, height - 5), Image.Resampling.NEAREST)
    occupied = np.array(body) == 255
    # A two-pixel tail cannot contain liquid inside a one-pixel outline. The
    # source's slim profile keeps its center, with a four-pixel minimum body
    # so long flasks read as bottles rather than pale sticks or candles.
    if height == 16:
        for y in range(occupied.shape[0]):
            columns = np.where(occupied[y])[0]
            if len(columns) and columns[-1] - columns[0] + 1 < 4:
                center = int(round((int(columns[0]) + int(columns[-1])) / 2))
                left = max(1, min(3, center - 2))
                occupied[y, left:left + 4] = True
    # Keep tall flask widths; use the old body's profile for every body row.
    # Top and bottom join points share the same two-pixel neck.
    full = np.zeros((height, width), dtype=bool)
    full[5:] = occupied
    full[0:5, 3:5] = True
    full[2:5, 2:6] = True
    full[5, 3:5] = True
    # Boundary is calculated against transparency, using the common outline.
    padded = np.pad(full, 1)
    interior = (padded[1:-1, :-2] & padded[1:-1, 2:] &
                padded[:-2, 1:-1] & padded[2:, 1:-1])
    result = np.zeros((height, width, 4), dtype=np.uint8)
    result[full] = rgba("outline")
    dark, light = LIQUIDS[row["id"]][1]
    for y, x in zip(*np.where(interior)):
        if y <= 2:
            color = "wood"
        elif y <= 4:
            color = "cream"
        else:
            color = light if x <= 3 or y == 5 else dark
            # Same sparse glass edge, never an all-over bright checker pattern.
            if x == 1 and y <= height - 3:
                color = "cream"
        result[y, x] = rgba(color)
    # A small, shared two-pixel cork stays brown on both 12 and 16-pixel flasks.
    result[1, 3:5] = rgba("wood")
    result[3:5, 3:5] = rgba("cream")
    # Cream only serves as glass/label, carrying a tiny retained identity mark
    # when a wide source body had cream in its lower portion.
    mark_row = height - 5
    if np.count_nonzero(interior[mark_row]) >= 4 and row["id"] in {
            "purify", "vigor", "nightwalk", "fortune", "wisdom", "eternity",
            "sage_elixir", "rare_nebula_distillate"}:
        result[mark_row, 3:5] = rgba("cream")
    result[~full] = 0
    return Image.fromarray(result)


def shelf_frame():
    image = Image.new("RGBA", (48, 48))
    draw = ImageDraw.Draw(image)
    # Reuse the existing two-post / two-board furniture grammar, with coherent
    # feet on y=47. The 21-row separation clears a complete tall flask.
    for x in (1, 44):
        draw.rectangle((x, 1, x + 2, 47), fill=COLORS["outline"])
        draw.line((x + 1, 2, x + 1, 46), fill=COLORS["wood"])
        draw.rectangle((x, 1, x + 2, 2), fill=COLORS["honey"])
    for y in BOARDS:
        draw.rectangle((0, y, 47, y + 3), fill=COLORS["outline"])
        draw.line((1, y + 1, 46, y + 1), fill=COLORS["honey"])
        draw.line((1, y + 2, 46, y + 2), fill=COLORS["wood"])
    # Brass brackets use the already-approved gold rather than new shades.
    for x in (2, 44):
        for y in BOARDS:
            draw.point((x, y + 1), fill=COLORS["gold"])
    return image


def normal_text(image, position, value, size=16, color="cream", anchor=None):
    font = ImageFont.truetype(str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"), size)
    ImageDraw.Draw(image).text(position, value, font=font,
                               fill=COLORS.get(color, color), anchor=anchor)


def review_sheet(rows, bottles, new_shelf):
    board = Image.new("RGBA", (780, 804), COLORS["outline"])
    normal_text(board, (24, 18), "물약 진열 후보 · 같은 병 규격, 넉넉한 선반", 23)
    normal_text(board, (24, 54), "8×12 / 긴 병 8×16 · 원본 1픽셀 외곽선 · 기존 몸통 실루엣과 레시피 색 유지", 14, "lilac")
    old_shelf = Image.open(V1 / "shelf_frame-native.png").convert("RGBA")
    old_boards = [23, 38]
    for index, id in enumerate(SELECTED):
        old = Image.open(V1 / ("potion_" + id + "-native.png")).convert("RGBA")
        old_shelf.alpha_composite(old, (5 + index % 4 * 10, old_boards[index // 4] - old.height))
    for image, x, title in ((old_shelf, 66, "이전"), (new_shelf, 390, "수정 후보")):
        normal_text(board, (x + 144, 89), title, 18, anchor="mt")
        board.alpha_composite(image.resize((288, 288), Image.Resampling.NEAREST), (x, 120))
    normal_text(board, (24, 428), "36종 확인 · 일반 32종 + 특별 4종", 19)
    normal_text(board, (24, 459), "솥 액체도 선택한 물약의 색을 사용합니다. 텍스트는 일반 글꼴입니다.", 14, "lilac")
    for index, row in enumerate(rows):
        x, y = 24 + index % 9 * 84, 502 + index // 9 * 72
        image = bottles[row["id"]]
        board.alpha_composite(image.resize((image.width * 3, image.height * 3), Image.Resampling.NEAREST),
                              (x + 25, y + 48 - image.height * 3))
        normal_text(board, (x + 37, y + 52), row["name"], 11, "gold" if row.get("rare") else "cream", anchor="mt")
    board.convert("RGB").save(OUT / "shelf-review.png")


def make_pots(rows):
    reference = np.array(Image.open(V1 / "cauldron_moon-native.png").convert("RGBA"))
    mask = np.all(reference[:, :, :3] == rgb(COLORS["lilac"]), axis=2) & (reference[:, :, 3] == 255)
    # Mask is the old exposed liquid's exact pixels, not any purple pot/body.
    yy, xx = np.where(mask)
    if not len(xx) or yy.min() < 8 or yy.max() > 12:
        raise ValueError("Liquid reference mask escapes the exposed surface")
    mask_image = Image.fromarray((mask.astype(np.uint8) * 255)).convert("L")
    mask_image.save(OUT / "pot-liquid-mask.png")
    frames = [np.array(Image.open(V3 / f"frames/pot/frame-{i:02}.png").convert("RGBA")) for i in range(3)]
    positions = [((13, 10), (21, 11)), ((12, 9), (19, 11)), ((16, 10), (21, 10))]
    result = {}
    checks = {}
    for row in rows:
        id = row["id"]
        result[id] = []
        checks[id] = []
        for index, old in enumerate(frames):
            data = old.copy()
            data[mask] = rgba(LIQUIDS[id][1][-1])
            for x, y in positions[index]:
                if not mask[y, x]:
                    raise ValueError("Bubble leaves the reference liquid mask")
                data[y, x] = rgba("outline")
            if not np.array_equal(data[~mask], old[~mask]):
                raise ValueError("Recipe recolor changed pot body/hearth")
            rel = f"pot/{id}/frame-{index:02}.png"
            check = inspect_and_save(Image.fromarray(data), OUT / rel)
            check["outside_liquid_mask_unchanged"] = True
            result[id].append(rel)
            checks[id].append(check)
    return result, checks, {"pixels": int(mask.sum()), "bounds": [int(xx.min()), int(yy.min()), int(xx.max()) + 1, int(yy.max()) + 1],
                            "reference": "art/mockups/full-ingame-v1/cauldron_moon-native.png", "mask_path": "pot-liquid-mask.png"}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = content_rows()
    bottles = {row["id"]: normalized_bottle(row) for row in rows}
    bottle_checks = {row["id"]: inspect_and_save(bottles[row["id"]], OUT / f"bottles/{row['id']}.png") for row in rows}
    frame = shelf_frame()
    frame_check = inspect_and_save(frame, OUT / "shelf_frame-native.png")
    composite = frame.copy()
    placements = []
    for index, id in enumerate(SELECTED):
        image = bottles[id]
        x = CENTERS[index % 4] - image.width // 2
        y = BOARDS[index // 4] - image.height
        composite.alpha_composite(image, (x, y))
        opaque = np.array(image)[:, :, 3] == 255
        ys, xs = np.where(opaque)
        bottom = y + int(ys.max())
        if bottom != BOARDS[index // 4] - 1:
            raise ValueError(f"{id}: opaque bottle bottom needs the shelf baseline")
        # Lower-row flask cannot touch the preceding board or post.
        if index >= 4 and y + int(ys.min()) <= BOARDS[0] + 3:
            raise ValueError(f"{id}: lower-row bottle overlaps the upper board")
        placements.append({"id": id, "position": [x, y], "center_x": CENTERS[index % 4],
                           "board_top": BOARDS[index // 4], "bottom_row": bottom,
                           "size": list(image.size)})
    composite_check = inspect_and_save(composite, OUT / "shelf-only-native.png", 24)
    composite.resize((144, 144), Image.Resampling.NEAREST).save(OUT / "shelf-only-3x.png")
    pot_frames, pot_checks, mask = make_pots(rows)
    review_sheet(rows, bottles, composite)
    recipes = [{"id": row["id"], "name": row["name"], "family": row["family"],
                "rare": bool(row.get("rare")), "liquid_ramp": LIQUIDS[row["id"]][0],
                "liquid_color": LIQUIDS[row["id"]][1][-1],
                "bottle_path": f"bottles/{row['id']}.png", "bottle_size": row["mock_native_size"],
                "body_silhouette_source": f"art/mockups/full-ingame-v1/potion_{row['id']}-native.png",
                "runtime_bottle_source": row["runtime_source"], "pot_frames": pot_frames[row["id"]]}
               for row in rows]
    validation = {"status": "passed", "bottles": bottle_checks, "shelf_frame": frame_check,
                  "shelf_composite": composite_check, "pot_frames": pot_checks,
                  "liquid_mask": mask, "visible_stock_count": 8,
                  "distinct_stock_ids": len(set(SELECTED)), "bottle_baselines_equal_board_top_minus_one": True,
                  "lower_row_tall_bottle_clears_upper_board": True,
                  "font_antialiasing_excluded_from_sprite_check": True}
    data = {"schema_version": 1, "status": "candidate", "approved_by_user": False,
            "scope": "Mockup only; runtime assets and saves are unchanged", "recipes": recipes,
            "visible_stock": SELECTED, "shelf_frame_path": "shelf_frame-native.png",
            "shelf_composite_path": "shelf-only-native.png", "shelf_positions": placements,
            "shelf_board_rows": BOARDS, "validation": validation}
    (OUT / "recipes.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "passed", "recipe_count": len(rows), "visible_stock": SELECTED,
                      "boards": BOARDS, "centers": CENTERS, "bottle_frames": len(bottles),
                      "pot_frames": len(rows) * 3, "liquid_mask": mask}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
