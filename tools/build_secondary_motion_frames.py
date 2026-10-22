"""Deterministic cloth/hair/hat experiments for the corrected v3 characters.

grid: native-grid material/inner-contour substitutions with sparse endpoint edits.
fine: sharp one-display-pixel motion (one third of a native pixel) on free bands.
Neither mode moves the face, hands, torso or feet. This is a candidate mockup,
not a runtime sprite replacement. No interpolation or new art colors are used.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/mockups/full-ingame-v3"
OUT = ROOT / "art/mockups/full-ingame-v4/motion"
SCALE = 3
POSES = 16
FPS = 8
OUTLINE = (36, 28, 50, 255)
CLOTH = (134, 84, 142, 255)
HAIR = (145, 96, 71, 255)
SKIN = (246, 209, 172, 255)
TRANSPARENT = (0, 0, 0, 0)
REGION_BOUNDS = {
    "witch": {"hat_tip": [2, 0, 10, 10], "hair": [9, 15, 14, 19],
              "cape_left": [2, 31, 13, 44], "cape_right": [20, 37, 27, 43]},
    "elf": {"hair": [18, 23, 24, 26]},
}
COLORS = [tuple(bytes.fromhex(x.strip().lstrip("#"))) for x in
          (ROOT / "art/palette.hex").read_text().splitlines() if x.strip()]


def read(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


def same_color(array, color):
    return np.all(array == color, axis=2)


def enlarged(array):
    return np.repeat(np.repeat(array, SCALE, axis=0), SCALE, axis=1)


def selector(base, points):
    mask = np.zeros(base.shape[:2], dtype=bool)
    for x, y in points:
        if base[y, x, 3]:
            mask[y, x] = True
    return mask


def masks_for(name, base):
    """Masks are explicit materials plus anatomically bounded free areas."""
    masks = {}
    if name == "witch":
        hat = np.zeros((48, 32), dtype=bool)
        hat[1:9, 2:9] = True
        hat &= same_color(base, CLOTH) | same_color(base, OUTLINE)
        masks["hat_tip"] = hat
        for side in ("left", "right"):
            points = []
            for y in range(31 if side == "left" else 37, 44 if side == "left" else 43):
                occupied = np.flatnonzero(base[y, :, 3])
                edge = int(occupied[0] if side == "left" else occupied[-1])
                for x in (range(edge, min(edge + 2, 11)) if side == "left"
                          else range(max(edge - 1, 21), edge + 1)):
                    if tuple(base[y, x]) in (CLOTH, OUTLINE):
                        points.append((x, y))
            masks["cape_" + side] = selector(base, points)
        # Under-brim brown/outline cluster, outside the face. Only its inner
        # contour changes: a floating isolated hair pixel is never introduced.
        masks["hair"] = selector(base, [(12, 16), (13, 16), (10, 17), (11, 17)])
    else:
        masks["hair"] = selector(base, [(20, 24), (21, 24), (22, 24),
                                        (20, 25), (21, 25)])
    return masks


def wave_step(value, threshold=.38):
    return 1 if value > threshold else (-1 if value < -threshold else 0)


def row_band_shift(base, mask, amount, side, first_row, full_row):
    """Move an exterior band, retain its material at the inner attachment seam."""
    result = base.copy()
    target_mask = np.zeros(mask.shape, dtype=bool)
    ys, xs = np.where(mask)
    result[mask] = TRANSPARENT
    shifts = {}
    for y, x in zip(ys, xs):
        native_y = y // SCALE
        strength = (native_y - first_row) / max(1, full_row - first_row)
        delta = amount if strength >= .45 else 0
        shifts[y] = delta
        xx = x + delta
        if 0 <= xx < result.shape[1]:
            result[y, xx] = base[y, x]
            target_mask[y, xx] = True
    # Outward movement exposes the inner side of the extracted band. Fill it
    # with the same material; inward movement exposes transparent free space.
    for y, delta in shifts.items():
        outward = (side == "left" and delta < 0) or (side == "right" and delta > 0)
        if outward:
            vacated = mask[y] & ~target_mask[y]
            result[y, vacated] = CLOTH if side != "hair" else HAIR
    return result


def hat_tip_shift(base, mask, amount):
    result = base.copy()
    result[mask] = TRANSPARENT
    ys, xs = np.where(mask)
    for y, x in zip(ys, xs):
        # The crown at native x >= 9 is pinned; only the folded left tip moves.
        yy = y + amount
        if 0 <= yy < result.shape[0]:
            result[yy, x] = base[y, x]
    return result


def fine_pose(base, name, masks, phase):
    expanded = enlarged(base)
    result = expanded.copy()
    display_masks = {key: np.repeat(np.repeat(mask, SCALE, 0), SCALE, 1)
                     for key, mask in masks.items()}
    if name == "witch":
        left = -wave_step(math.sin(phase))
        right = wave_step(math.sin(phase + 1.3))
        result = row_band_shift(result, display_masks["cape_left"], left, "left", 31, 43)
        result = row_band_shift(result, display_masks["cape_right"], right, "right", 37, 42)
        result = hat_tip_shift(result, display_masks["hat_tip"],
                               wave_step(math.sin(phase + .7)))
        # Native-grid subpixel animation's contour substitution, refined to a
        # one-display-pixel inner-line translation. Brown fill closes the seam.
        mask = display_masks["hair"]
        hair = result.copy()
        hair[mask] = HAIR
        shift = wave_step(math.sin(phase + 2.2))
        ys, xs = np.where(mask)
        for y, x in zip(ys, xs):
            hair[y, x + shift] = result[y, x]
        result = hair
    else:
        # Short rear locks only; ears, face and the full body remain pinned.
        mask = display_masks["hair"]
        result[mask] = TRANSPARENT
        shift = wave_step(math.sin(phase + 2.2))
        ys, xs = np.where(mask)
        target = np.zeros(mask.shape, bool)
        for y, x in zip(ys, xs):
            result[y, x + shift] = expanded[y, x]
            target[y, x + shift] = True
        if shift > 0:
            result[mask & ~target] = HAIR
    return result


def swap_contour(array, old_point, new_point, material):
    ox, oy = old_point
    nx, ny = new_point
    if tuple(array[oy, ox]) != OUTLINE or tuple(array[ny, nx]) != material:
        raise ValueError(f"Wrong explicit contour pair {old_point} / {new_point}")
    array[oy, ox] = material
    array[ny, nx] = OUTLINE


def grid_pose(base, name, phase):
    result = base.copy()
    if name == "witch":
        cape = math.sin(phase)
        if cape > .35:
            swap_contour(result, (9, 38), (8, 38), CLOTH)
        elif cape < -.35:
            swap_contour(result, (9, 38), (10, 38), CLOTH)
        # The lower seam travels independently, reading as a cloth fold.
        right_fold = math.sin(phase + 1.3)
        if right_fold > .4:
            swap_contour(result, (9, 42), (8, 42), CLOTH)
            result[40, 23] = OUTLINE
        elif right_fold < -.4:
            result[40, 22] = OUTLINE
        hat = math.sin(phase + .7)
        if hat > .3:
            swap_contour(result, (6, 6), (5, 6), CLOTH)
        elif hat < -.3:
            swap_contour(result, (7, 7), (8, 7), CLOTH)
        if hat > .94:
            result[9, 3] = OUTLINE  # sparse extension of the curled endpoint
        elif hat < -.94:
            result[8, 2:5] = TRANSPARENT
            result[7, 3] = OUTLINE  # one-native-pixel curl contraction
        if math.sin(phase + 2.2) > .3:
            swap_contour(result, (10, 17), (11, 17), HAIR)
        elif math.sin(phase + 2.2) < -.3:
            swap_contour(result, (12, 16), (13, 16), HAIR)
    else:
        hair = math.sin(phase + 2.2)
        if hair > .3:
            swap_contour(result, (20, 24), (21, 24), HAIR)
        elif hair < -.3:
            swap_contour(result, (20, 25), (19, 25), HAIR)
        if hair > .95:
            result[24, 22] = HAIR
            result[24, 23] = OUTLINE  # rear lock endpoint, away from the ear
    return enlarged(result)


def check_frame(frame, source, name, blink, index, mode):
    rgb = {tuple(c[:3]) for c in frame[frame[:, :, 3] != 0]}
    outside = rgb - set(COLORS)
    partial = int(np.count_nonzero((frame[:, :, 3] != 0) & (frame[:, :, 3] != 255)))
    base = enlarged(source)
    # All original skin pixels and all body pixels outside the cape stay fixed.
    skin = same_color(base, SKIN)
    skin_ok = bool(np.array_equal(frame[skin], base[skin]))
    lower_from = (44 if name == "witch" else 27) * SCALE
    lower_ok = bool(np.array_equal(frame[lower_from:], base[lower_from:]))
    face_rect = ((12, 18, 22, 26) if name == "witch" else (8, 20, 19, 27))
    x0, y0, x1, y1 = (v * SCALE for v in face_rect)
    face_ok = bool(np.array_equal(frame[y0:y1, x0:x1], base[y0:y1, x0:x1]))
    changed = np.any(frame != base, axis=2)
    moving_regions = np.zeros(changed.shape, bool)
    region_counts = {}
    for key, bounds in REGION_BOUNDS[name].items():
        rx0, ry0, rx1, ry1 = (v * SCALE for v in bounds)
        region_counts[key] = int(changed[ry0:ry1, rx0:rx1].sum())
        moving_regions[ry0:ry1, rx0:rx1] = True
    outside_motion = int(np.count_nonzero(changed & ~moving_regions))
    passed = (not outside and not partial and len(rgb) <= 5 and skin_ok
              and lower_ok and face_ok and outside_motion == 0)
    return {"mode": mode, "character": name, "index": index,
            "blink": blink, "palette_colors": len(rgb), "off_palette": len(outside),
            "partial_alpha": partial, "skin_pinned": skin_ok,
            "body_and_ground_pinned": lower_ok, "face_pinned": face_ok,
            "changed_display_pixels": int(changed.sum()),
            "changed_display_pixels_by_region": region_counts,
            "changes_outside_motion_regions": outside_motion,
            "passed": passed}


def make_preview(frames):
    background = (74, 60, 82)
    font_path = ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"

    def board_at(i, ratio=1):
        board = Image.new("RGB", (432 * ratio, 204 * ratio), background)
        draw = ImageDraw.Draw(board)
        font = ImageFont.truetype(str(font_path), 12 * ratio)
        draw.text((14 * ratio, 9 * ratio), "GRID: internal contours", font=font, fill=(246, 209, 172))
        draw.text((230 * ratio, 9 * ratio), "FINE: 1/3 native pixel", font=font, fill=(246, 209, 172))
        for col, mode in enumerate(("grid", "fine")):
            for char_col, name in enumerate(("witch", "elf")):
                sprite = Image.fromarray(frames[mode][name][i])
                if ratio != 1:
                    sprite = sprite.resize((96 * ratio, 144 * ratio), Image.Resampling.NEAREST)
                board.paste(sprite, ((col * 216 + char_col * 96 + 8) * ratio, 38 * ratio), sprite)
        return board

    boards = [board_at(i) for i in range(POSES)]
    # Preserve all art colors exactly; ordinary text gets its own normal AA
    # palette entries. Text colors are not sprite colors or motion evidence.
    font_colors = sorted({tuple(pixel) for pixel in np.array(boards[0]).reshape(-1, 3)} - set(COLORS))
    palette_colors = COLORS + font_colors[:256 - len(COLORS)]
    palette = sum((list(c) for c in palette_colors), [])
    palette += [0] * (768 - len(palette))
    pal = Image.new("P", (1, 1)); pal.putpalette(palette)
    preview = [board.quantize(palette=pal, dither=Image.Dither.NONE) for board in boards]
    preview[0].save(OUT / "secondary-motion-comparison.gif", save_all=True,
                    append_images=preview[1:], duration=[120, 130] * 8,
                    loop=0, disposal=2, optimize=False)
    board_at(0, 2).save(OUT / "comparison-still-2x.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {"schema": 1, "art_status": "candidate", "approved_by_user": False,
                "pose_count": POSES, "fps": FPS, "loop_seconds": POSES / FPS,
                "size": [96, 144], "scale": SCALE, "modes": {},
                "index_contract": "0..15 open-eye poses, 16..31 matching closed-eye poses",
                "grid_method": "Native material/inner-contour substitutions; sparse native endpoint edits",
                "fine_method": "Nearest-neighbor 3x source; free-edge bands displaced 0/+-1 display pixel",
                "sources": {}, "regions": {}, "region_native_bounds": REGION_BOUNDS,
                "checks": []}
    frames = {}
    for mode in ("fine", "grid"):
        frames[mode] = {}
        manifest["modes"][mode] = {}
        for name in ("witch", "elf"):
            native_path = SOURCE / f"characters/{name}-native.png"
            closed_path = SOURCE / f"frames/{name}/frame-02.png"
            opened, closed = read(native_path), read(closed_path)
            if opened.shape != (48, 32, 4) or closed.shape != opened.shape:
                raise ValueError("Corrected native characters must be exactly 32 x 48")
            eye_change = np.any(opened != closed, axis=2)
            # Existing v3 frame 02 supplies the exact unlifted blink.
            if np.count_nonzero(eye_change) > 16:
                raise ValueError("Closed-eye source unexpectedly changes non-eye body pixels")
            manifest["sources"][name] = {
                "open": str(native_path.relative_to(ROOT)).replace("\\", "/"),
                "blink": str(closed_path.relative_to(ROOT)).replace("\\", "/")}
            masks = masks_for(name, opened)
            manifest["regions"][name] = {key: {"native_pixels": int(mask.sum()),
                "native_coordinates": [[int(x), int(y)] for y, x in zip(*np.where(mask))]}
                for key, mask in masks.items()}
            frame_dir = OUT / mode / name
            frame_dir.mkdir(parents=True, exist_ok=True)
            saved, paths = [], []
            for blink, source in ((False, opened), (True, closed)):
                for pose in range(POSES):
                    phase = 2 * math.pi * pose / POSES
                    frame = (fine_pose(source, name, masks, phase) if mode == "fine"
                             else grid_pose(source, name, phase))
                    index = pose + POSES * blink
                    check = check_frame(frame, source, name, blink, index, mode)
                    manifest["checks"].append(check)
                    if not check["passed"]:
                        raise ValueError(f"Secondary motion failed validation: {check}")
                    path = frame_dir / f"frame-{index:02d}.png"
                    Image.fromarray(frame).save(path)
                    paths.append(str(path.relative_to(OUT)).replace("\\", "/"))
                    saved.append(frame)
            frames[mode][name] = saved
            manifest["modes"][mode][name] = paths
            # Every pose's eye-only variants retain exactly the original blink.
            expected_blink = enlarged(closed)[enlarged(eye_change)]
            eye_mask = enlarged(eye_change)
            for pose in range(POSES):
                if not np.array_equal(saved[pose + POSES][eye_mask], expected_blink):
                    raise ValueError("The original closed-eye mask was altered")
            manifest.setdefault("loop_checks", {}).setdefault(mode, {})[name] = {
                "unique_open_frames": len({frame.tobytes() for frame in saved[:POSES]}),
                "last_to_first_changed_display_pixels": int(np.count_nonzero(
                    np.any(saved[POSES - 1] != saved[0], axis=2))),
                "open_closed_eye_mask_matches_v3": True}
    manifest["passed"] = all(c["passed"] for c in manifest["checks"])
    manifest["region_statistics"] = {}
    for mode in ("fine", "grid"):
        manifest["region_statistics"][mode] = {}
        for name in ("witch", "elf"):
            checks = [c for c in manifest["checks"] if c["mode"] == mode
                      and c["character"] == name and not c["blink"]]
            manifest["region_statistics"][mode][name] = {
                region: {"min_changed_display_pixels": min(c["changed_display_pixels_by_region"][region] for c in checks),
                         "max_changed_display_pixels": max(c["changed_display_pixels_by_region"][region] for c in checks),
                         "poses_with_movement": sum(c["changed_display_pixels_by_region"][region] > 0 for c in checks)}
                for region in REGION_BOUNDS[name]}
    (OUT / "frames.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    make_preview(frames)
    # Region overlays and a contact sheet make the material selection reviewable.
    for name in ("witch", "elf"):
        base = read(SOURCE / f"characters/{name}-native.png")
        mask = np.logical_or.reduce(list(masks_for(name, base).values()))
        overlay = enlarged(base)
        overlay[enlarged(mask)] = (233, 185, 95, 255)
        Image.fromarray(overlay).resize((192, 288), Image.Resampling.NEAREST).save(OUT / f"{name}-motion-mask.png")
    sheet = Image.new("RGBA", (16 * 96, 4 * 144), (74, 60, 82, 255))
    for row, (mode, name) in enumerate((("grid", "witch"), ("grid", "elf"),
                                      ("fine", "witch"), ("fine", "elf"))):
        for i, frame in enumerate(frames[mode][name][:POSES]):
            image = Image.fromarray(frame)
            sheet.alpha_composite(image, (i * 96, row * 144))
    sheet.save(OUT / "contact-sheet.png")
    print(json.dumps({"output": str(OUT), "frames": len(manifest["checks"]),
                      "passed": manifest["passed"], "loop_checks": manifest["loop_checks"]}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / "frames.json").write_text(json.dumps({
            "schema": 1, "passed": False, "status": "failed",
            "art_status": "candidate", "approved_by_user": False,
            "error": str(error),
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise
