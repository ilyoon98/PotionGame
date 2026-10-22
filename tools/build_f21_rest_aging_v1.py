"""F21 rest/aging art candidates: keeper sleep/faint, aging cask, aged seal.

Candidate only. Reads hand-authored native pixel maps (art/.../source/*.txt),
registers them as native PNGs, runs the fixed tools/process_pixel_art.py
pipeline, then adds pose/prop checks and workshop mockups for review.
Nothing under assets/ or scripts/ is read for writing; runtime is untouched.

Run with Pillow + NumPy: python tools/build_f21_rest_aging_v1.py
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
KEEPER = ROOT / "art/characters/rest-v1/keeper"
MOCK = ROOT / "art/mockups/f21-rest-aging-v1"
PROPS = MOCK / "props"
IDLE = ROOT / "art/characters/keyframes-v4/keeper/frames/idle.png"
KEEPER_ACTIONS = ["idle", "brew_reach", "brew_stir_left", "brew_stir_right", "handover_extend", "handover_return"]
SCALE = 3

# Source map legend. Every letter is one approved palette color.
LEGEND = {
    "#": "#241C32", "s": "#F6D1AC", "w": "#916047", "p": "#86548E", "g": "#E9B95F",
    "a": "#50333B", "b": "#916047", "c": "#C99463", "m": "#827589",
    "h": "#FFF0BC", "d": "#A56A3D", "t": "#24566A", "u": "#3BA8A3", "v": "#9BE2CF",
}
OUTLINE = (0x24, 0x1C, 0x32)
SKIN = (0xF6, 0xD1, 0xAC)


def rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def read_map(path: Path) -> list[str]:
    rows = [line.rstrip("\n") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if len({len(row) for row in rows}) != 1:
        raise ValueError(f"Ragged map: {path}")
    return rows


def render_map(rows: list[str]) -> Image.Image:
    data = np.zeros((len(rows), len(rows[0]), 4), dtype=np.uint8)
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            if char != ".":
                data[y, x] = (*rgb(LEGEND[char]), 255)
    return Image.fromarray(data)


def breathing(rows: list[str], top: int, waist: int) -> list[str]:
    """Upper body (top..waist) rises one native row; the waist row repeats."""
    out = list(rows)
    for y in range(top - 1, waist):
        out[y] = rows[y + 1]
    return out


def save_sha(image: Image.Image, path: Path) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------- checks
def outline_violations(image: Image.Image) -> list[list[int]]:
    data = np.array(image)
    opaque = data[:, :, 3] == 255
    padded = np.pad(opaque, 1)
    boundary = opaque & ~(padded[1:-1, :-2] & padded[1:-1, 2:] & padded[:-2, 1:-1] & padded[2:, 1:-1])
    bad = boundary & ~np.all(data[:, :, :3] == OUTLINE, axis=2)
    return [[int(x), int(y)] for y, x in zip(*np.where(bad))]


def isolated_dark(image: Image.Image, region) -> list[list[int]]:
    """Outline-colored pixels whose 8 neighbours are all skin (eyes keep a 1px skin margin)."""
    data = np.array(image)
    x0, y0, x1, y1 = region
    found = []
    for y in range(max(1, y0), min(data.shape[0] - 1, y1)):
        for x in range(max(1, x0), min(data.shape[1] - 1, x1)):
            if tuple(data[y, x, :3]) != OUTLINE or data[y, x, 3] != 255:
                continue
            block = data[y - 1:y + 2, x - 1:x + 2].reshape(-1, 4)
            others = np.delete(block, 4, axis=0)
            if all(p[3] == 255 and tuple(p[:3]) == SKIN for p in others):
                found.append([x, y])
    return found


def colors_of(image: Image.Image) -> list[str]:
    data = np.array(image)
    opaque = data[data[:, :, 3] == 255]
    return sorted({"#%02X%02X%02X" % tuple(p[:3]) for p in opaque})


def partial_alpha(image: Image.Image) -> int:
    alpha = np.array(image)[:, :, 3]
    return int(((alpha != 0) & (alpha != 255)).sum())


def head_reuse(frame: Image.Image, idle: Image.Image, idle_rows, dx: int, dy: int) -> dict:
    """Compare a translated block of the approved idle head with the new frame."""
    f, i = np.array(frame), np.array(idle)
    same, changed = 0, []
    for y in range(*idle_rows):
        for x in range(32):
            tx, ty = x + dx, y + dy
            if not (0 <= tx < 32):
                continue
            if np.array_equal(f[ty, tx], i[y, x]):
                same += 1
            else:
                changed.append([tx, ty])
    return {"idle_rows": list(idle_rows), "offset": [dx, dy], "identical_pixels": same, "changed_pixels": changed}


# ---------------------------------------------------------------- manifests
KEEPER_RULES = json.loads((ROOT / "art/characters/keyframes-v4/keeper/manifest.json").read_text(encoding="utf-8"))["assets"][0]


def keeper_asset(asset_id: str, source: Path) -> dict:
    return {
        "id": asset_id, "source": rel(source), "size": [32, 48], "position": [0, 0], "margin": 0,
        "dark_value": KEEPER_RULES["dark_value"], "preserve_native_frame": True,
        "materials": KEEPER_RULES["materials"], "rules": KEEPER_RULES["rules"],
        "fallback_material": KEEPER_RULES["fallback_material"],
    }


def exact_rules(colors: dict[str, str]) -> list[dict]:
    """One material per exact approved color, keyed by its HSV point (no nearest-RGB search)."""
    import colorsys
    rules = []
    for material, value in colors.items():
        h, s, v = colorsys.rgb_to_hsv(*(np.array(rgb(value)) / 255.0))
        rules.append({"material": material, "hue": [round(h - .004, 4), round(h + .004, 4)],
                      "saturation_min": round(s - .01, 4), "saturation_max": round(s + .01, 4),
                      "value_min": round(v - .01, 4), "value_max": round(v + .01, 4)})
    return rules


RAMP_OF = {"#50333B": "wood", "#916047": "wood", "#C99463": "wood", "#827589": "stone",
           "#FFF0BC": "gold", "#E9B95F": "gold", "#A56A3D": "gold",
           "#24566A": "teal", "#3BA8A3": "teal", "#9BE2CF": "teal"}
NAME_OF = {"#50333B": "wood_shadow", "#916047": "wood_mid", "#C99463": "wood_light", "#827589": "iron",
           "#FFF0BC": "gold_light", "#E9B95F": "gold_mid", "#A56A3D": "gold_shadow",
           "#24566A": "teal_shadow", "#3BA8A3": "teal_mid", "#9BE2CF": "teal_light"}


def prop_asset(asset_id: str, source: Path, image: Image.Image) -> dict:
    used = [c for c in colors_of(image) if c != "#241C32"]
    materials = {"outline": ["#241C32"]}
    materials.update({NAME_OF[c]: [c] for c in used})
    return {
        "id": asset_id, "source": rel(source), "size": list(image.size), "position": [0, 0], "margin": 0,
        "dark_value": 0.24, "preserve_native_frame": True, "materials": materials,
        "material_ramps": {NAME_OF[c]: RAMP_OF[c] for c in used},
        "rules": exact_rules({NAME_OF[c]: c for c in used}), "fallback_material": NAME_OF[used[0]],
    }


def manifest(output: Path, assets: list[dict], size) -> dict:
    return {"schema_version": 1, "status": "candidate", "approved_by_user": False, "compose": False,
            "scale": SCALE, "alpha_threshold": 224, "max_colors": 5,
            "palette": "art/palette.hex", "ramps": "art/ramps.json", "output": rel(output),
            "scene": {"size": size, "background": "#4A3C52"}, "assets": assets}


def run_pipeline(manifest_path: Path) -> dict:
    result = subprocess.run([sys.executable, str(ROOT / "tools/process_pixel_art.py"), rel(manifest_path)],
                            cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    report = json.loads((ROOT / json.loads(manifest_path.read_text(encoding="utf-8"))["output"] / "validation.json").read_text(encoding="utf-8"))
    if result.returncode != 0 or report["status"] != "passed":
        raise SystemExit(f"process_pixel_art failed for {rel(manifest_path)}: {report.get('error')}")
    return report


# ---------------------------------------------------------------- scene
def load(path) -> Image.Image:
    return Image.open(ROOT / path).convert("RGBA")


def workshop_background() -> Image.Image:
    """Static native 180x83 workshop from published runtime art (read only)."""
    scene = Image.new("RGBA", (180, 83))
    for path, point in [("assets/pixel_v1/weather/day_clear-0.png", (4, 5)), ("assets/pixel_v1/floor.png", (0, 0)),
                        ("assets/pixel_v1/props/window.png", (4, 5)), ("assets/pixel_v1/props/herb.png", (4, 48)),
                        ("assets/pixel_v1/props/poster.png", (153, 1)), ("assets/pixel_v1/props/counter.png", (105, 64)),
                        ("assets/pixel_v1/props/shelf.png", (105, 1)), ("assets/pixel_v1/fire/0.png", (51, 71)),
                        ("assets/pixel_v1/pots/health-0.png", (41, 48))]:
        scene.alpha_composite(load(path), point)
    return scene


def opaque_box(image: Image.Image, origin) -> tuple[int, int, int, int] | None:
    box = image.getbbox()
    return None if box is None else (box[0] + origin[0], box[1] + origin[1], box[2] + origin[0], box[3] + origin[1])


def overlap_pixels(a: Image.Image, ao, b: Image.Image, bo) -> int:
    canvas_a, canvas_b = np.zeros((83, 180), bool), np.zeros((83, 180), bool)
    for canvas, image, (ox, oy) in ((canvas_a, a, ao), (canvas_b, b, bo)):
        alpha = np.array(image)[:, :, 3] == 255
        for y, x in zip(*np.where(alpha)):
            if 0 <= y + oy < 83 and 0 <= x + ox < 180:
                canvas[y + oy, x + ox] = True
    return int((canvas_a & canvas_b).sum())


def main() -> int:
    KEEPER.mkdir(parents=True, exist_ok=True)
    idle = Image.open(IDLE).convert("RGBA")
    keeper_palette = {rgb(v) for v in (ROOT / "art/palettes/v1/characters/keeper.hex").read_text().split()}

    # ---- keeper: register sources (breathing frame is derived, not redrawn)
    sit = read_map(KEEPER / "source/sleep_sit.txt")
    faint = read_map(KEEPER / "source/faint.txt")
    frames_src = {"sleep_sit": sit, "sleep_sit_breath": breathing(sit, 14, 41), "faint": faint}
    keeper_assets, keeper_hashes = [], {}
    for name, rows in frames_src.items():
        path = KEEPER / f"source/{name}-registered.png"
        keeper_hashes[name] = save_sha(render_map(rows), path)
        keeper_assets.append(keeper_asset(name, path))
    keeper_manifest = KEEPER / "manifest.json"
    keeper_manifest.write_text(json.dumps(manifest(KEEPER / "pipeline", keeper_assets, [32, 48]), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    keeper_report = run_pipeline(keeper_manifest)
    frames = {}
    for name in frames_src:
        frames[name] = Image.open(KEEPER / f"pipeline/{name}-native.png").convert("RGBA")
        save_sha(frames[name], KEEPER / f"frames/{name}.png")

    # ---- props
    props_src = {p.stem: read_map(p) for p in sorted((PROPS / "source").glob("*.txt"))}
    prop_assets = []
    for name, rows in props_src.items():
        path = PROPS / f"source/{name}-registered.png"
        image = render_map(rows)
        save_sha(image, path)
        prop_assets.append(prop_asset(name, path, image))
    props_manifest = PROPS / "manifest.json"
    props_manifest.write_text(json.dumps(manifest(PROPS / "pipeline", prop_assets, [32, 32]), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    props_report = run_pipeline(props_manifest)
    props = {name: Image.open(PROPS / f"pipeline/{name}-native.png").convert("RGBA") for name in props_src}

    # ---- keeper checks
    # Closed eyes keep only the lower pixel of the approved open 1x2 eyes.
    expected_eyes = {"sleep_sit": [[18, 32], [20, 32]], "sleep_sit_breath": [[18, 31], [20, 31]], "faint": [[15, 30], [17, 30]]}
    # The tucked chin loses the neck row, so its last skin pixel becomes outline.
    chin_edits = {"sleep_sit": [[19, 35]], "sleep_sit_breath": [[19, 34]], "faint": []}
    reuse = {"sleep_sit": head_reuse(frames["sleep_sit"], idle, (2, 24), 1, 12),
             "sleep_sit_breath": head_reuse(frames["sleep_sit_breath"], idle, (2, 24), 1, 11),
             "faint": head_reuse(frames["faint"], idle, (2, 24), -2, 10)}
    keeper_checks = {}
    for name, image in frames.items():
        data = np.array(image)
        alpha = data[:, :, 3] == 255
        eyes = isolated_dark(image, (0, 0, 32, 48))
        colors = colors_of(image)
        rows_used = np.where(alpha.any(axis=1))[0]
        check = {
            "pipeline_passed": keeper_report["assets"][name]["passed"],
            "pipeline_preserved_source": hashlib.sha256(np.array(Image.open(KEEPER / f"source/{name}-registered.png").convert("RGBA")).tobytes()).hexdigest()
            == hashlib.sha256(data.tobytes()).hexdigest(),
            "size": list(image.size), "colors": colors, "color_count": len(colors),
            "within_keeper_5": all(rgb(c) in keeper_palette for c in colors),
            "partial_alpha": partial_alpha(image), "outline_violations": outline_violations(image),
            "closed_eyes": eyes, "closed_eyes_expected": expected_eyes[name],
            "closed_eyes_ok": eyes == expected_eyes[name],
            "floor_row": int(rows_used.max()), "floor_row_ok": int(rows_used.max()) == 46 and bool(np.all(data[46][alpha[46]][:, :3] == OUTLINE)),
            "approved_head_reuse": reuse[name],
        }
        allowed = [[x, y - 1] for x, y in expected_eyes[name]] + chin_edits[name]
        check["head_changes_only_eyes_or_chin"] = sorted(reuse[name]["changed_pixels"]) == sorted(allowed)
        check["passed"] = (check["pipeline_passed"] and check["pipeline_preserved_source"] and check["within_keeper_5"]
                           and check["color_count"] <= 5 and not check["partial_alpha"] and not check["outline_violations"]
                           and check["closed_eyes_ok"] and check["floor_row_ok"] and check["head_changes_only_eyes_or_chin"])
        keeper_checks[name] = check
    a, b = np.array(frames["sleep_sit"]), np.array(frames["sleep_sit_breath"])
    breath = {"lower_body_rows_identical": bool(np.array_equal(a[41:], b[41:])),
              "upper_body_shift_rows": 1, "upper_body_matches_shift": bool(np.array_equal(a[14:41], b[13:40])),
              "changed_rows": [int(y) for y in np.where((a != b).any(axis=(1, 2)))[0]]}
    breath["passed"] = breath["lower_body_rows_identical"] and breath["upper_body_matches_shift"]

    # ---- prop checks
    prop_checks = {}
    for name, image in props.items():
        colors = colors_of(image)
        prop_checks[name] = {"pipeline_passed": props_report["assets"][name]["passed"], "size": list(image.size),
                             "colors": colors, "color_count": len(colors), "partial_alpha": partial_alpha(image),
                             "outline_violations": outline_violations(image)}
        prop_checks[name]["passed"] = (prop_checks[name]["pipeline_passed"] and colors and len(colors) <= 5
                                       and not prop_checks[name]["partial_alpha"] and not prop_checks[name]["outline_violations"])
    for name in ("aging_cask_wall", "aging_cask_floor", "bedroll_mat"):
        prop_checks[name]["native_32x32"] = props[name].size == (32, 32)
        prop_checks[name]["passed"] &= prop_checks[name]["native_32x32"]

    # ---- aged seal over the 36 published bottles (overlay only; bottles untouched)
    catalog = json.loads((ROOT / "assets/pixel_v1/catalog.json").read_text(encoding="utf-8"))
    seal = props["aged_seal"]
    seal_rows, sheet_cells = [], []
    for pid, info in catalog["potions"].items():
        bottle_path = ROOT / info["bottle"].replace("res://", "")
        bottle = Image.open(bottle_path).convert("RGBA")
        w, h = bottle.size
        anchor = (w - 3, h - 6)  # seal top-left in bottle space; 2 px hang past the right edge
        canvas = Image.new("RGBA", (w + 2, h))
        canvas.alpha_composite(bottle, (0, 0))
        canvas.alpha_composite(seal, anchor)
        bd = np.array(bottle)
        interior = (bd[:, :, 3] == 255) & ~np.all(bd[:, :, :3] == OUTLINE, axis=2)
        covered = np.zeros_like(interior)
        sa = np.array(seal)[:, :, 3] == 255
        for y, x in zip(*np.where(sa)):
            if 0 <= anchor[1] + y < h and 0 <= anchor[0] + x < w:
                covered[anchor[1] + y, anchor[0] + x] = True
        visible = float((interior & ~covered).sum() / interior.sum())
        cork_clear = anchor[1] >= 4
        seal_rows.append({"id": pid, "bottle": rel(bottle_path), "bottle_size": [w, h], "seal_anchor": list(anchor),
                          "bottle_sha256": hashlib.sha256(bottle_path.read_bytes()).hexdigest(),
                          "interior_visible": round(visible, 3), "cork_and_neck_clear": cork_clear,
                          "passed": visible >= 0.6 and cork_clear and partial_alpha(canvas) == 0})
        sheet_cells.append(canvas)
    cols = 12
    sheet = Image.new("RGBA", (cols * 14, 3 * 20))
    for i, cell in enumerate(sheet_cells):
        sheet.alpha_composite(cell, ((i % cols) * 14 + 2, (i // cols) * 20 + 2 + (16 - cell.height)))
    sheet.save(MOCK / "aged-seal-36-native.png")
    sheet.resize((sheet.width * SCALE, sheet.height * SCALE), Image.Resampling.NEAREST).save(MOCK / "aged-seal-36-3x.png")

    # ---- placements in the 180x83 native workshop (display = native x3)
    background = workshop_background()
    keeper_origin = (72, 32)
    actions = {n: Image.open(ROOT / f"art/characters/keyframes-v4/keeper/frames/{n}.png").convert("RGBA") for n in KEEPER_ACTIONS}
    all_keeper = {**actions, **frames}
    ui_rects = {"potPanel": (37, 22, 73, 30), "herbPanel": (2, 38, 36, 46), "shelf": (105, 1, 153, 49),
                "poster": (153, 1, 177, 33), "window": (4, 5, 36, 37)}
    placements = {}
    for name, origin in (("aging_cask_wall", (73, 0)), ("aging_cask_floor", (98, 47))):
        box = opaque_box(props[name], origin)
        ui_hits = [k for k, (x0, y0, x1, y1) in ui_rects.items() if box[0] < x1 and x0 < box[2] and box[1] < y1 and y0 < box[3]]
        keeper_overlap = {k: overlap_pixels(props[name], origin, img, keeper_origin) for k, img in all_keeper.items()}
        gaps = {}
        for k, img in all_keeper.items():
            kb = opaque_box(img, keeper_origin)
            gaps[k] = {"vertical": kb[1] - box[3], "horizontal": box[0] - kb[2]}
        placements[name] = {"native_origin": list(origin), "display_origin": [origin[0] * SCALE, origin[1] * SCALE],
                            "opaque_box_native": list(box), "ui_rect_overlaps": ui_hits,
                            "keeper_pose_overlap_pixels": keeper_overlap, "keeper_gaps_native": gaps,
                            "passed": not ui_hits and not any(keeper_overlap.values())}
    placements["aging_cask_floor"]["note"] = "Stands in front of the counter's left end (intentional overlap with the counter, not with the keeper)."

    # ---- mockup frames (8-step loops, 375 ms per step in review.html)
    z, star = props["sleep_z"], props["dizzy_star"]
    variants = {}

    def compose(keeper_img, korigin, cask=None, extra=()):
        scene = background.copy()
        if cask:
            scene.alpha_composite(props[cask[0]], cask[1])
        for img, point, front in extra:
            if not front:
                scene.alpha_composite(img, point)
        scene.alpha_composite(keeper_img, korigin)
        for img, point, front in extra:
            if front:
                scene.alpha_composite(img, point)
        return scene

    def z_points(step):
        return [((72 + 22 + step // 2, 32 + 16 - step), True), ((72 + 26 + (step + 4) % 8 // 2, 32 + 16 - (step + 4) % 8), True)]

    def stars(step):
        import math
        points = []
        for phase in (0, math.pi):
            angle = step / 8 * 2 * math.pi + phase
            # Back half of the orbit passes behind the hat.
            points.append(((round(72 + 11 + 10 * math.cos(angle)), round(32 + 13 + 2 * math.sin(angle))), math.sin(angle) >= 0))
        return points

    plans = {
        "sleep_a_wall": lambda s: compose(frames["sleep_sit_breath" if s >= 4 else "sleep_sit"], keeper_origin, ("aging_cask_wall", (73, 0)),
                                         [(z, p, f) for p, f in z_points(s)]),
        "sleep_b_wall": lambda s: compose(frames["sleep_sit_breath" if s >= 4 else "sleep_sit"], (72, 28), ("aging_cask_wall", (73, 0)),
                                         [(props["bedroll_mat"], (72, 47), False), (props["bedroll_blanket"], (72, 59), True)]
                                         + [(z, (p[0], p[1] - 4), f) for p, f in z_points(s)]),
        "faint_wall": lambda s: compose(frames["faint"], keeper_origin, ("aging_cask_wall", (73, 0)), [(star, p, f) for p, f in stars(s)]),
        "idle_cask_floor": lambda s: compose(actions["idle"], keeper_origin, ("aging_cask_floor", (98, 47))),
    }
    for vname, plan in plans.items():
        paths = []
        for step in range(8):
            scene = plan(step)
            if partial_alpha(scene):
                raise SystemExit(f"Partial alpha in mockup {vname}")
            path = MOCK / f"frames/{vname}-{step}.png"
            path.parent.mkdir(parents=True, exist_ok=True)
            scene.resize((540, 249), Image.Resampling.NEAREST).save(path)
            paths.append(rel(path).split("f21-rest-aging-v1/")[1])
        gif = [Image.open(MOCK / p).convert("RGBA") for p in paths]
        flat = []
        for frame in gif:
            base = Image.new("RGBA", frame.size, "#4A3C52")
            base.alpha_composite(frame)
            flat.append(base.convert("P", palette=Image.Palette.ADAPTIVE, colors=64))
        flat[0].save(MOCK / f"{vname}.gif", save_all=True, append_images=flat[1:], duration=375, loop=0)
        variants[vname] = paths

    # Native 3x sheets for the review page
    (MOCK / "sprites").mkdir(exist_ok=True)
    for name, image in {**frames, **props}.items():
        image.resize((image.width * SCALE, image.height * SCALE), Image.Resampling.NEAREST).save(MOCK / f"sprites/{name}-3x.png")

    report = {
        "schema_version": 1, "status": "candidate", "approved_by_user": False, "runtime_integrated": False,
        "date": "2026-10-21", "scale": SCALE, "palette": "art/palette.hex", "new_palette_colors": 0,
        "keeper": {"frames": {n: rel(KEEPER / f"frames/{n}.png") for n in frames}, "source_sha256": keeper_hashes,
                   "pipeline_report": rel(KEEPER / "pipeline/validation.json"), "checks": keeper_checks, "breathing": breath},
        "props": {"pipeline_report": rel(PROPS / "pipeline/validation.json"), "checks": prop_checks},
        "aged_seal": {"anchor_rule": "seal top-left = (bottle_w-3, bottle_h-6)", "bottles": seal_rows,
                      "passed": all(r["passed"] for r in seal_rows), "bottles_modified": 0},
        "placements": placements, "mockup_frames": variants,
    }
    report["passed"] = (all(c["passed"] for c in keeper_checks.values()) and breath["passed"]
                        and all(c["passed"] for c in prop_checks.values()) and report["aged_seal"]["passed"]
                        and all(p["passed"] for p in placements.values()))
    (MOCK / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (KEEPER / "validation.json").write_text(json.dumps({"passed": all(c["passed"] for c in keeper_checks.values()) and breath["passed"],
                                                        "checks": keeper_checks, "breathing": breath}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # Review page: template + embedded summary (file:// pages cannot fetch JSON)
    template = (ROOT / "tools/f21_rest_aging_review.template.html").read_text(encoding="utf-8")
    summary = {"passed": report["passed"], "variants": variants,
               "keeper": {n: {k: c[k] for k in ("passed", "color_count", "colors", "closed_eyes", "floor_row")} | {"outline_violations": len(c["outline_violations"]), "head_identical": c["approved_head_reuse"]["identical_pixels"], "head_changed": len(c["approved_head_reuse"]["changed_pixels"])} for n, c in keeper_checks.items()},
               "breathing": breath,
               "props": {n: {"passed": c["passed"], "size": c["size"], "colors": c["colors"], "outline_violations": len(c["outline_violations"])} for n, c in prop_checks.items()},
               "seal": {"passed": report["aged_seal"]["passed"], "count": len(seal_rows), "min_visible": min(r["interior_visible"] for r in seal_rows)},
               "placements": {n: {"passed": p["passed"], "display_origin": p["display_origin"], "ui_rect_overlaps": p["ui_rect_overlaps"],
                                  "keeper_frames": len(p["keeper_pose_overlap_pixels"]),
                                  "keeper_overlap": sum(p["keeper_pose_overlap_pixels"].values()),
                                  "min_vertical_gap": min(g["vertical"] for g in p["keeper_gaps_native"].values())} for n, p in placements.items()}}
    (MOCK / "review.html").write_text(template.replace("/*SUMMARY*/null", json.dumps(summary, ensure_ascii=False)), encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "keeper": {n: c["passed"] for n, c in keeper_checks.items()},
                      "breathing": breath["passed"], "props": {n: c["passed"] for n, c in prop_checks.items()},
                      "seal": report["aged_seal"]["passed"], "placements": {n: p["passed"] for n, p in placements.items()}}, indent=1))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
