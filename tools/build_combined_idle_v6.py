"""Combine v6 breathing/blinking with v5-style protected secondary motion.

Each character/mode has 64 frames: open-rest, open-lifted, blink-rest,
blink-lifted; each group contains the same 16 hat/cape/hair poses. Breathing
raises the head/upper chest by one native pixel without moving hands or feet.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import build_secondary_motion_v5 as secondary

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art/mockups/full-ingame-v6/characters"
OUT = ROOT / "art/mockups/full-ingame-v6/motion"
POSES, SCALE, FPS = 16, 3, 8


def repair_display_outline(frame):
    """Preserve fractional internal details, pin a native-grid dark perimeter."""
    result = frame.copy()
    native_alpha = result[::SCALE, ::SCALE, 3] != 0
    boundary = secondary.boundary_mask(native_alpha)
    result[secondary.zoom(boundary)] = secondary.INK
    return result


def lifted_frame(frame, cut, lifted):
    result = frame.copy()
    if lifted:
        line = cut * SCALE
        # Same native operation as the original approved breathing prototype.
        result[:line] = frame[SCALE:line + SCALE]
    return repair_display_outline(result)


def count_components(mask):
    remaining = set(zip(*np.where(mask)))
    count = 0
    while remaining:
        count += 1
        stack = [remaining.pop()]
        while stack:
            y, x = stack.pop()
            for point in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
                if point in remaining:
                    remaining.remove(point); stack.append(point)
    return count


def count_holes(alpha):
    inverse = np.pad(~alpha, 1, constant_values=True)
    # Background always counts as one component; extra empty components are holes.
    return count_components(inverse) - 1


def enclosed_empty_pixels(alpha):
    empty = np.pad(~alpha, 1, constant_values=True)
    outside = np.zeros(empty.shape, bool)
    outside[0, 0] = True
    queue = [(0, 0)]
    while queue:
        y, x = queue.pop()
        for yy, xx in ((y-1, x), (y+1, x), (y, x-1), (y, x+1)):
            if (0 <= yy < empty.shape[0] and 0 <= xx < empty.shape[1]
                    and empty[yy, xx] and not outside[yy, xx]):
                outside[yy, xx] = True; queue.append((yy, xx))
    return ~alpha & ~outside[1:-1, 1:-1]


def phase_protection(reference):
    native = reference[::SCALE, ::SCALE]
    alpha = native[:, :, 3] != 0
    border = secondary.boundary_mask(alpha)
    skin = secondary.color_mask(native, secondary.SKIN)
    return border, secondary.grow(border) | secondary.grow(skin, diagonal=True) | ~alpha


def combined_index(seconds, phase=0):
    clock = seconds + phase
    pose = int(seconds*FPS) % POSES
    lifted = int(clock % 3 >= 1.5)
    blink = int(3.6 <= clock % 4.5 < 3.85)
    return pose + lifted*POSES + blink*POSES*2


def combined_preview(frames):
    """18 seconds shows simultaneous breathing, folds and actual blinking."""
    font = ImageFont.truetype(str(ROOT/"assets/fonts/pretendard/Pretendard-Regular.otf"), 12)
    boards = []
    for sample in range(144):
        seconds = sample / FPS
        board = Image.new("RGB", (432, 204), (74, 60, 82))
        draw = ImageDraw.Draw(board)
        for col, (mode, label) in enumerate((("grid", "GRID: breath + folds"),
                                             ("fine", "FINE: breath + folds"))):
            draw.text((col*216+10, 9), label, font=font, fill=secondary.SKIN[:3])
            for slot, name in enumerate(("witch", "elf")):
                index = combined_index(seconds, 1.5 if name == "elf" else 0)
                sprite = Image.fromarray(frames[mode][name][index])
                board.paste(sprite, (col*216+slot*96+8, 38), sprite)
        boards.append(board)
    extra = sorted({tuple(pixel) for pixel in np.array(boards[0]).reshape(-1, 3)} - secondary.PALETTE)
    colors = sorted(secondary.PALETTE) + extra[:256-len(secondary.PALETTE)]
    palette = sum((list(color) for color in colors), [])
    palette += [0]*(768-len(palette))
    pal = Image.new("P", (1, 1)); pal.putpalette(palette)
    gif = [board.quantize(palette=pal, dither=Image.Dither.NONE) for board in boards]
    gif[0].save(OUT/"combined-idle-comparison.gif", save_all=True, append_images=gif[1:],
                duration=[120, 130]*72, loop=0, disposal=2, optimize=False)


def check(frame, reference, original, specs, name, mode, index, cut, blink, lifted):
    base_native = reference[::SCALE, ::SCALE]
    border, protected = phase_protection(reference)
    shifted_specs = {}
    for key, spec in specs.items():
        adjusted = {**spec, "center": spec["center"].copy()}
        if lifted and adjusted["center"][1] < cut:
            adjusted["center"][1] -= 1
        shifted_specs[key] = adjusted
    report = secondary.validate(frame, base_native, border, protected, shifted_specs,
                                mode, name, index, blink)
    native_alpha = frame[::SCALE, ::SCALE, 3] != 0
    source_alpha = original[:, :, 3] != 0
    original_display = secondary.zoom(original)
    # Pin the lower body except for its explicitly selected interior cape fold.
    # The cape continues moving while the hands, waist and feet stay attached.
    lower_mask = np.zeros(frame.shape[:2], bool)
    lower_mask[cut*SCALE:] = True
    for spec in specs.values():
        x, y = spec["center"]
        dx, dy = spec["axis"]
        if y >= cut:
            x0, x1 = (x-abs(dx))*SCALE, (x+abs(dx)+1)*SCALE
            y0, y1 = (y-abs(dy))*SCALE, (y+abs(dy)+1)*SCALE
            lower_mask[y0:y1, x0:x1] = False
    lower_fixed = bool(np.array_equal(frame[lower_mask], original_display[lower_mask]))
    skin = secondary.color_mask(original_display, secondary.SKIN)
    skin[:cut*SCALE] = False
    hands_fixed = bool(np.array_equal(frame[skin], original_display[skin]))
    feet_fixed = bool(np.array_equal(frame[40*SCALE:], original_display[40*SCALE:]))
    bottom_rows = np.flatnonzero(np.any(native_alpha, axis=1))
    ground_row = int(bottom_rows[-1]) if len(bottom_rows) else -1
    components = count_components(native_alpha)
    holes = count_holes(native_alpha)
    source_components, source_holes = count_components(source_alpha), count_holes(source_alpha)
    # Enclosed spaces between the old legs are intentional and remain fixed.
    # Neck/chest joins receive a separate strict no-enclosed-gap check.
    neck_first_row = 23 if name == "witch" else 24
    neck_gap_pixels = int(enclosed_empty_pixels(native_alpha)[neck_first_row:cut+1].sum())
    source_neck_gap_pixels = int(enclosed_empty_pixels(source_alpha)[neck_first_row:cut+1].sum())
    # The lifted top row immediately above the pinned torso remains attached.
    contact_pixels = int(np.count_nonzero(native_alpha[cut-1] & native_alpha[cut]))
    report.update({"breath_lifted": lifted, "head_translation_native_pixels": int(lifted),
                   "silhouette_fixed_within_breath_phase": report["fixed_silhouette"],
                   "lower_body_fixed_outside_cape_fold": lower_fixed, "hands_fixed": hands_fixed,
                   "feet_fixed": feet_fixed, "ground_native_row": ground_row,
                   "opaque_components": components, "source_opaque_components": source_components,
                   "transparent_holes": holes, "source_transparent_holes": source_holes,
                   "new_transparent_holes": max(0, holes-source_holes),
                   "neck_enclosed_transparent_pixels": neck_gap_pixels,
                   "source_neck_enclosed_transparent_pixels": source_neck_gap_pixels,
                   "chest_contact_native_pixels": contact_pixels})
    report["passed"] = (report["passed"] and lower_fixed and hands_fixed and feet_fixed
                        and ground_row == 46 and components <= source_components
                        and holes <= source_holes and neck_gap_pixels == 0
                        and contact_pixels > 0)
    return report


def main():
    config = json.loads((SOURCE/"idle-config.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    report = {"schema": 3, "art_status": "candidate", "approved_by_user": False,
              "pose_count": POSES, "frames_per_character": 64, "fps": FPS,
              "loop_seconds": POSES/FPS, "size": [96, 144], "scale": SCALE,
              "recommended_mode": "grid",
              "breath_period_seconds": 3, "breath_lifted_when": "clock % 3 >= 1.5",
              "blink_period_seconds": 4.5, "blink_interval_seconds": [3.6, 3.85],
              "index_contract": "0..15 open-rest,16..31 open-lifted,32..47 blink-rest,48..63 blink-lifted",
              "boundary_rule": "4-neighbor opaque boundary; fixed dark 3x band within each breath phase",
              "grid_method": "Native interior folds plus 1-native-pixel vertical head/chest breathing",
              "fine_method": "One-display-pixel interior folds plus 3-display-pixel head/chest breathing",
              "modes": {}, "sources": {}, "regions": {}, "checks": []}
    frames = {}
    for mode in ("grid", "fine"):
        frames[mode] = {}; report["modes"][mode] = {}
        for name in ("witch", "elf"):
            path = SOURCE/f"{name}-native.png"
            original = np.array(Image.open(path).convert("RGBA"))
            if original.shape != (48, 32, 4):
                raise ValueError("v6 native characters must be exactly 32 x 48")
            closed = secondary.blink_source(original, config[name]["eyes"])
            cut = config[name]["cut"]
            if cut != {"witch": 30, "elf": 27}[name]:
                raise ValueError("v6 breathing cut must retain fixed hand/torso contacts")
            specs, border, _ = secondary.motion_specs(original, config, name)
            if np.any(original[border] != secondary.INK):
                raise ValueError(f"Source {name} has an incomplete native dark boundary")
            report["regions"][name] = specs
            report["sources"][name] = str(path.relative_to(ROOT)).replace("\\", "/")
            target = OUT/mode/name; target.mkdir(parents=True, exist_ok=True)
            saved, paths = [], []
            for blink, source in ((False, original), (True, closed)):
                for lifted in (False, True):
                    reference = lifted_frame(secondary.zoom(source), cut, lifted)
                    for pose in range(POSES):
                        initial = secondary.pose(source, specs, pose*2*np.pi/POSES, mode)
                        frame = lifted_frame(initial, cut, lifted)
                        index = pose + int(lifted)*POSES + int(blink)*POSES*2
                        result = check(frame, reference, original, specs, name, mode,
                                       index, cut, blink, lifted)
                        report["checks"].append(result)
                        if not result["passed"]:
                            raise ValueError(f"Combined v6 IDLE failed: {result}")
                        output = target/f"frame-{index:02d}.png"
                        Image.fromarray(frame).save(output)
                        saved.append(frame); paths.append(str(output.relative_to(OUT)).replace("\\", "/"))
            frames[mode][name] = saved; report["modes"][mode][name] = paths
            report.setdefault("loop_checks", {}).setdefault(mode, {})[name] = {
                "unique_open_rest_frames": len({f.tobytes() for f in saved[:POSES]}),
                "unique_open_lifted_frames": len({f.tobytes() for f in saved[POSES:POSES*2]}),
                "vertical_breathing_pixels_changed": int(np.count_nonzero(np.any(saved[0] != saved[POSES], axis=2))),
                "last_to_first_rest_changed_pixels": int(np.count_nonzero(np.any(saved[POSES-1] != saved[0], axis=2))),
                "hat_cape_hair_present": sorted(specs)}
    report["passed"] = all(result["passed"] for result in report["checks"])
    (OUT/"frames.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    # Use v5's normal-text comparison compositor for a rest-phase contact sheet.
    previous_out = secondary.OUT
    secondary.OUT = OUT
    try:
        secondary.preview(frames)
    finally:
        secondary.OUT = previous_out
    combined_preview(frames)
    # Separate both breathing banks so the changing silhouette is reviewable.
    sheet = Image.new("RGBA", (16*96, 144*4), (74, 60, 82, 255))
    for row, (name, offset) in enumerate((("witch", 0), ("witch", 16), ("elf", 0), ("elf", 16))):
        for i in range(POSES):
            sheet.alpha_composite(Image.fromarray(frames["grid"][name][offset+i]), (96*i, 144*row))
    sheet.save(OUT/"breathing-contact-sheet.png")
    print(json.dumps({"output": str(OUT), "passed": report["passed"],
                      "frames": len(report["checks"]), "loop_checks": report["loop_checks"]}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT/"frames.json").write_text(json.dumps({"schema": 3, "passed": False,
            "status": "failed", "art_status": "candidate", "error": str(error)},
            ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        raise
