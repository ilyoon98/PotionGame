"""v5 secondary motion: pinned silhouettes and pinned one-native-pixel outlines.

Grid motion changes interior material clusters only. Fine motion translates
those same internal creases by one display pixel at native 3x. No exterior
edge, opaque footprint, face, hand, foot or whole head is ever translated.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/mockups/full-ingame-v5/characters"
OUT = ROOT / "art/mockups/full-ingame-v5/motion"
POSES, FPS, SCALE = 16, 8, 3
INK = (36, 28, 50, 255)
CLOTH = (134, 84, 142, 255)
HAIR = (145, 96, 71, 255)
SKIN = (246, 209, 172, 255)
PALETTE = {tuple(bytes.fromhex(line.strip().lstrip("#"))) for line in
           (ROOT / "art/palette.hex").read_text().splitlines() if line.strip()}


def grow(mask, diagonal=False):
    padded = np.pad(mask, 1)
    result = mask.copy()
    offsets = [(0, 1), (2, 1), (1, 0), (1, 2)]
    if diagonal:
        offsets += [(0, 0), (0, 2), (2, 0), (2, 2)]
    h, w = mask.shape
    for y, x in offsets:
        result |= padded[y:y+h, x:x+w]
    return result


def boundary_mask(alpha):
    padded = np.pad(alpha, 1, constant_values=False)
    h, w = alpha.shape
    inside = alpha.copy()
    for y, x in [(0, 1), (2, 1), (1, 0), (1, 2)]:
        inside &= padded[y:y+h, x:x+w]
    return alpha & ~inside


def zoom(data):
    return np.repeat(np.repeat(data, SCALE, 0), SCALE, 1)


def color_mask(base, color):
    return np.all(base == color, axis=2)


def blink_source(base, eye_points):
    closed = base.copy()
    for x, y in eye_points:
        if tuple(base[y, x]) != INK:
            raise ValueError(f"Eye point is not outline: {(x, y)}")
        closed[y, x] = SKIN
    for x, y in eye_points[1::2]:
        if tuple(base[y, x + 1]) != SKIN:
            raise ValueError("Closed eyelid would paint outside skin")
        closed[y, x] = INK
        closed[y, x + 1] = INK
    return closed


def choose_motion(base, protected, region, material, wanted, axis, phase):
    """An explicit material region yields one small pinned interior crease.

    Prefer an existing interior outline. When the material has no internal
    shading, use a single dark strand/fold; record this choice in the manifest.
    Both neighboring destinations must contain only the same material.
    """
    x0, y0, x1, y1 = region
    candidates = []
    dx, dy = axis
    for y in range(y0, y1):
        for x in range(x0, x1):
            if protected[y, x] or tuple(base[y, x]) not in (INK, material):
                continue
            points = [(x + dx * sign, y + dy * sign) for sign in (-1, 1)]
            if any(not (0 <= px < 32 and 0 <= py < 48)
                   or protected[py, px] or tuple(base[py, px]) != material
                   for px, py in points):
                continue
            existed = tuple(base[y, x]) == INK
            score = (0 if existed else 100) + abs(x-wanted[0]) + abs(y-wanted[1])
            candidates.append((score, y, x, existed))
    if not candidates:
        raise ValueError(f"No protected interior material cluster in {region}")
    _, y, x, existed = min(candidates)
    return {"center": [x, y], "axis": [dx, dy], "material": list(material),
            "phase": phase, "source_had_internal_crease": existed,
            "region": region}


def motion_specs(base, config, name):
    alpha = base[:, :, 3] != 0
    border = boundary_mask(alpha)
    # Protect the entire outline band, plus skin, facial features and their
    # immediate neighbors. Every motion source/destination is strictly inside.
    skin = color_mask(base, SKIN)
    # Also pin the material immediately inside the outer stroke so an internal
    # dark crease cannot briefly thicken that stroke when it moves nearby.
    protected = grow(border) | grow(skin, diagonal=True) | ~alpha
    eye_points = config[name]["eyes"]
    min_eye_y = min(point[1] for point in eye_points)
    cut = config[name]["cut"]
    specs = {}
    if name == "witch":
        specs["hat_crease"] = choose_motion(base, protected, [3, 3, 16, min_eye_y-5],
                                            CLOTH, [9, 7], [0, 1], .7)
        specs["cape_fold"] = choose_motion(base, protected, [4, cut+1, 11, 42],
                                            CLOTH, [8, 38], [1, 0], 0)
        specs["hair_strand"] = choose_motion(base, protected, [9, min_eye_y-6, 21, min_eye_y],
                                              HAIR, [13, min_eye_y-3], [1, 0], 2.2)
    else:
        specs["hair_strand"] = choose_motion(base, protected, [8, min_eye_y-7, 24, min_eye_y],
                                              HAIR, [15, min_eye_y-4], [1, 0], 2.2)
    return specs, border, protected


def pose(source, specs, phase, mode):
    result = zoom(source)
    for spec in specs.values():
        x, y = spec["center"]
        dx, dy = spec["axis"]
        wave = math.sin(phase + spec["phase"])
        step = 1 if wave > .4 else (-1 if wave < -.4 else 0)
        shift = step * (SCALE if mode == "grid" else 1)
        result[y*SCALE:(y+1)*SCALE, x*SCALE:(x+1)*SCALE] = spec["material"]
        xx, yy = x*SCALE + dx*shift, y*SCALE + dy*shift
        result[yy:yy+SCALE, xx:xx+SCALE] = INK
    return result


def validate(frame, source, border, protected, specs, mode, name, index, blink):
    native = zoom(source)
    silhouette = frame[:, :, 3] != 0
    alpha_equal = bool(np.array_equal(silhouette, native[:, :, 3] != 0))
    colors = {tuple(p) for p in frame[frame[:, :, 3] != 0][:, :3]}
    off_palette = len(colors - PALETTE)
    partial = int(np.count_nonzero((frame[:, :, 3] != 0) & (frame[:, :, 3] != 255)))
    border3 = zoom(border)
    border_equal = bool(np.array_equal(frame[border3], native[border3]))
    border_wrong = int(np.count_nonzero(np.any(frame[border3] != INK, axis=1)))
    border_wrong_native = int(np.count_nonzero(np.any(frame[::SCALE, ::SCALE][border] != INK, axis=1)))
    pinned = zoom(protected)
    pinned_equal = bool(np.array_equal(frame[pinned], native[pinned]))
    changed = np.any(frame != native, axis=2)
    permitted = np.zeros(changed.shape, bool)
    region_counts = {}
    for key, spec in specs.items():
        x, y = spec["center"]
        dx, dy = spec["axis"]
        x0, x1 = (x-abs(dx))*SCALE, (x+abs(dx)+1)*SCALE
        y0, y1 = (y-abs(dy))*SCALE, (y+abs(dy)+1)*SCALE
        region_counts[key] = int(changed[y0:y1, x0:x1].sum())
        permitted[y0:y1, x0:x1] = True
    outside_region = int(np.count_nonzero(changed & ~permitted))
    on_grid = bool(np.array_equal(frame, zoom(frame[::SCALE, ::SCALE])))
    passed = (alpha_equal and border_equal and border_wrong == 0 and pinned_equal
              and off_palette == 0 and partial == 0 and len(colors) <= 5
              and outside_region == 0 and (mode != "grid" or on_grid))
    return {"mode": mode, "character": name, "index": index, "blink": blink,
            "passed": passed, "palette_colors": len(colors), "off_palette": off_palette,
            "partial_alpha": partial, "fixed_silhouette": alpha_equal,
            "outer_outline_band_fixed": border_equal,
            "outer_boundary_violations_display_pixels": border_wrong,
            "outer_boundary_violations_native_pixels": border_wrong_native,
            "skin_face_and_attachments_fixed": pinned_equal,
            "changes_outside_motion_regions": outside_region,
            "native_grid_aligned": on_grid, "changed_by_region": region_counts}


def preview(frames):
    font_path = ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"
    def board(index, ratio=1):
        im = Image.new("RGB", (432*ratio, 204*ratio), (74, 60, 82))
        draw = ImageDraw.Draw(im)
        font = ImageFont.truetype(str(font_path), 12*ratio)
        for col, (mode, text) in enumerate((("grid", "GRID: pinned outline"),
                                             ("fine", "FINE: interior motion"))):
            draw.text(((col*216+10)*ratio, 9*ratio), text, font=font, fill=SKIN[:3])
            for slot, name in enumerate(("witch", "elf")):
                sprite = Image.fromarray(frames[mode][name][index])
                if ratio != 1:
                    sprite = sprite.resize((96*ratio, 144*ratio), Image.Resampling.NEAREST)
                im.paste(sprite, ((col*216+slot*96+8)*ratio, 38*ratio), sprite)
        return im
    boards = [board(i) for i in range(POSES)]
    extra = sorted({tuple(pixel) for pixel in np.array(boards[0]).reshape(-1, 3)} - PALETTE)
    colors = sorted(PALETTE) + extra[:256-len(PALETTE)]
    palette = sum((list(color) for color in colors), [])
    palette += [0] * (768-len(palette))
    pal = Image.new("P", (1, 1)); pal.putpalette(palette)
    gif = [im.quantize(palette=pal, dither=Image.Dither.NONE) for im in boards]
    gif[0].save(OUT/"secondary-motion-comparison.gif", save_all=True, append_images=gif[1:],
                duration=[120, 130]*8, loop=0, disposal=2, optimize=False)
    board(0, 2).save(OUT/"comparison-still-2x.png")
    sheet = Image.new("RGBA", (POSES*96, 144*4), (74, 60, 82, 255))
    for row, (mode, name) in enumerate((("grid", "witch"), ("grid", "elf"),
                                      ("fine", "witch"), ("fine", "elf"))):
        for i in range(POSES):
            sheet.alpha_composite(Image.fromarray(frames[mode][name][i]), (i*96, row*144))
    sheet.save(OUT/"contact-sheet.png")


def main():
    config = json.loads((SOURCE/"idle-config.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    report = {"schema": 2, "art_status": "candidate", "approved_by_user": False,
              "pose_count": POSES, "fps": FPS, "loop_seconds": POSES/FPS,
              "size": [96, 144], "scale": SCALE, "recommended_mode": "grid",
              "boundary_rule": "Opaque pixel with any transparent/outside cardinal neighbor",
              "grid_method": "Native-grid internal material folds; silhouette and outline fixed",
              "fine_method": "One-display-pixel internal crease motion; silhouette and full 3x outline band fixed",
              "index_contract": "0..15 open-eye poses, 16..31 matching closed-eye poses",
              "modes": {}, "sources": {}, "regions": {}, "checks": []}
    frames = {}
    for mode in ("grid", "fine"):
        report["modes"][mode] = {}; frames[mode] = {}
        for name in ("witch", "elf"):
            path = SOURCE/f"{name}-native.png"
            original = np.array(Image.open(path).convert("RGBA"))
            if original.shape != (48, 32, 4):
                raise ValueError("v5 native characters must be 32 x 48")
            closed = blink_source(original, config[name]["eyes"])
            specs, border, protected = motion_specs(original, config, name)
            if np.any(original[border] != INK):
                raise ValueError(f"{name} source does not have a complete dark 1-native-pixel outline")
            report["regions"][name] = specs
            report["sources"][name] = str(path.relative_to(ROOT)).replace("\\", "/")
            target = OUT/mode/name; target.mkdir(parents=True, exist_ok=True)
            paths, saved = [], []
            for blink, source in ((False, original), (True, closed)):
                for i in range(POSES):
                    result = pose(source, specs, i*2*math.pi/POSES, mode)
                    index = i + blink*POSES
                    check = validate(result, source, border, protected, specs, mode, name, index, blink)
                    report["checks"].append(check)
                    if not check["passed"]:
                        raise ValueError(f"Motion check failed: {check}")
                    output = target/f"frame-{index:02d}.png"
                    Image.fromarray(result).save(output)
                    paths.append(str(output.relative_to(OUT)).replace("\\", "/")); saved.append(result)
            frames[mode][name] = saved; report["modes"][mode][name] = paths
            eye_change = zoom(np.any(original != closed, axis=2))
            if any(not np.array_equal(saved[i+POSES][eye_change], zoom(closed)[eye_change]) for i in range(POSES)):
                raise ValueError("Blink mask no longer matches v5 eyes")
            report.setdefault("loop_checks", {}).setdefault(mode, {})[name] = {
                "unique_open_frames": len({f.tobytes() for f in saved[:POSES]}),
                "blink_source_preserved": True,
                "last_to_first_changed_display_pixels": int(np.count_nonzero(np.any(saved[POSES-1] != saved[0], axis=2)))}
            if mode == "grid":
                overlay = zoom(original)
                overlay[zoom(border)] = (233, 185, 95, 255)
                Image.fromarray(overlay).resize((192, 288), Image.Resampling.NEAREST).save(OUT/f"{name}-pinned-outline-mask.png")
    report["passed"] = all(check["passed"] for check in report["checks"])
    (OUT/"frames.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    preview(frames)
    print(json.dumps({"output": str(OUT), "passed": report["passed"],
                      "frames": len(report["checks"]), "regions": report["regions"],
                      "loop_checks": report["loop_checks"]}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT/"frames.json").write_text(json.dumps({"schema": 2, "passed": False,
            "status": "failed", "art_status": "candidate", "error": str(error)},
            ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        raise
