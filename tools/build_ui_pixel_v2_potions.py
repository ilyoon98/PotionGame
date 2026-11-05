"""Package approved shelf bottles for the UI and audit the current character sheets.

No painting, palette remapping, silhouette changes or new artwork occurs here.
Each approved bottle is copied at exactly 2x nearest-neighbour scale onto a
transparent 32x32 canvas. The inventory and recipe UI can share this identity;
the existing recipe-glyph files and all approved sources remain untouched.

The fixed process_pixel_art validator checks the already-processed sources and
the packaged outputs. Re-running its cleanup/remapping stages would change the
approved pixels, so this packaging step deliberately does not reprocess them.
The shared assets/ui_pixel_v2/catalog.json is owned by the integration task.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from process_pixel_art import ROOT, rgb, validate


REVIEW = ROOT / "art/mockups/ui-pixel-v2"
ICONS = ROOT / "assets/ui_pixel_v2/icons"
CANVAS = (32, 32)
SCALE = 2
OUTLINE = np.array(rgb("241C32"), dtype=np.uint8)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def palette(path: Path) -> set[tuple[int, int, int]]:
    return {rgb(line.strip()) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()}


def source_path(value: str) -> Path:
    if not value.startswith("res://assets/pixel_v1/"):
        raise ValueError(f"Expected an approved pixel_v1 source: {value}")
    path = (ROOT / value.removeprefix("res://")).resolve()
    if not path.is_relative_to((ROOT / "assets/pixel_v1").resolve()):
        raise ValueError(f"Source leaves pixel_v1: {value}")
    return path


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def outline_violations(image: Image.Image) -> int:
    data = np.asarray(image)
    opaque = data[:, :, 3] != 0
    padded = np.pad(opaque, 1)
    interior = padded[:-2, 1:-1] & padded[2:, 1:-1] & padded[1:-1, :-2] & padded[1:-1, 2:]
    return int(((opaque & ~interior) & np.any(data[:, :, :3] != OUTLINE, axis=2)).sum())


def boundary_exceptions(image: Image.Image) -> list[dict]:
    data = np.asarray(image)
    opaque = data[:, :, 3] != 0
    padded = np.pad(opaque, 1)
    interior = padded[:-2, 1:-1] & padded[2:, 1:-1] & padded[1:-1, :-2] & padded[1:-1, 2:]
    y, x = np.where((opaque & ~interior) & np.any(data[:, :, :3] != OUTLINE, axis=2))
    return [{"position": [int(xx), int(yy)], "color": "#%02X%02X%02X" % tuple(data[yy, xx, :3])} for yy, xx in zip(y, x)]


def import_settings(png: Path) -> None:
    settings = Path(str(png) + ".import")
    if settings.exists():
        return
    resource = "res://" + png.relative_to(ROOT).as_posix()
    destination = "res://.godot/imported/" + png.name + "-" + hashlib.md5(resource.encode()).hexdigest() + ".ctex"
    settings.write_text(
        '[remap]\nimporter="texture"\ntype="CompressedTexture2D"\npath="' + destination
        + '"\n\n[deps]\nsource_file="' + resource + '"\ndest_files=["' + destination
        + '"]\n\n[params]\ncompress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n',
        encoding="utf-8",
    )


def audit_characters(catalog: dict, global_palette: set) -> dict:
    rows = []
    for character_id, character in catalog["characters"].items():
        allowed = palette(ROOT / f"art/palettes/v1/characters/{character_id}.hex")
        if not allowed <= global_palette:
            raise ValueError(f"{character_id}: assigned character palette is outside approved colors")
        for pose, paths in character["poses"].items():
            for mode, resource in paths.items():
                source = source_path(resource)
                before = sha256(source)
                image = Image.open(source).convert("RGBA")
                cell = (32, 48) if mode == "native" else (96, 144)
                result = validate(image, (cell[0] * 16, cell[1] * 4), allowed, 5)
                boundary = outline_violations(image)
                unchanged = before == sha256(source)
                rows.append({
                    "character_id": character_id, "pose": pose, "mode": mode,
                    "path": resource, "sha256": before, "frame_size": list(cell),
                    "frame_count": 64, **result, "outline_boundary_violations": boundary,
                    "source_unchanged": unchanged,
                    "passed": result["passed"] and boundary == 0 and unchanged,
                })
    return {
        "status": "passed" if all(row["passed"] for row in rows) else "failed",
        "operation": "read-only audit of current published character atlases",
        "source_catalog": "assets/pixel_v1/catalog.json",
        "character_count": len(catalog["characters"]), "sheet_count": len(rows),
        "frame_count": sum(row["frame_count"] for row in rows),
        "max_color_count": max(row["color_count"] for row in rows),
        "off_palette_colors": sum(row["off_palette_colors"] for row in rows),
        "partial_alpha_pixels": sum(row["partial_alpha_pixels"] for row in rows),
        "outline_boundary_violations": sum(row["outline_boundary_violations"] for row in rows),
        "all_source_hashes_unchanged": all(row["source_unchanged"] for row in rows),
        "sheets": rows,
    }


def package_potions(catalog: dict, global_palette: set) -> tuple[dict, dict, dict]:
    images, index, rows = {}, {}, {}
    for potion_id, potion in catalog["potions"].items():
        source = source_path(potion["bottle"])
        before = sha256(source)
        bottle = Image.open(source).convert("RGBA")
        source_check = validate(bottle, potion["bottle_size"], global_palette, 5)
        expected_size = (bottle.width * SCALE, bottle.height * SCALE)
        if max(expected_size) > CANVAS[0]:
            raise ValueError(f"{potion_id}: source does not fit 32x32 at the common 2x scale")
        # Preserve the entire source, including transparent RGB and horizontal
        # padding. Center the unchanged bottle cell on the common icon canvas.
        offset = ((CANVAS[0] - expected_size[0]) // 2, (CANVAS[1] - expected_size[1]) // 2)
        enlarged = bottle.resize(expected_size, Image.Resampling.NEAREST)
        icon = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        icon.paste(enlarged, offset)
        x, y = offset
        expected = np.repeat(np.repeat(np.asarray(bottle), SCALE, axis=0), SCALE, axis=1)
        actual = np.asarray(icon)[y:y + expected_size[1], x:x + expected_size[0]]
        exact = np.array_equal(actual, expected)
        result = validate(icon, CANVAS, global_palette, 5)
        boundary = outline_violations(icon)
        # The approved bottles expose two brown cork pixels along the top.
        # Packaging preserves that existing design; record it, and reject any
        # newly introduced boundary mismatch instead of repainting the source.
        inherited_boundary = boundary_exceptions(bottle)
        expected_boundary = outline_violations(enlarged)
        unchanged = before == sha256(source)
        path = "res://assets/ui_pixel_v2/icons/" + potion_id + ".png"
        index[potion_id] = path
        images[potion_id] = icon
        rows[potion_id] = {
            "path": path, "source": potion["bottle"], "source_sha256": before,
            "source_size": list(bottle.size), "source_validation": source_check,
            "integer_scale": SCALE, "offset": list(offset),
            "bottle_rgba_exact_2x": bool(exact), "source_unchanged": unchanged,
            **result, "outline_boundary_violations": boundary,
            "inherited_source_boundary_exceptions": inherited_boundary,
            "new_outline_boundary_violations": max(0, boundary - expected_boundary),
            "passed": source_check["passed"] and result["passed"] and exact and boundary == expected_boundary and unchanged,
        }
    report = {
        "status": "passed" if all(row["passed"] for row in rows.values()) else "failed",
        "operation": "exact approved bottle pixels at common 2x on transparent 32x32 canvas",
        "source_catalog": "assets/pixel_v1/catalog.json",
        "validator": "tools/process_pixel_art.py:validate", "icon_count": len(rows),
        "recipe_identity": "same potion-id icon; original recipe glyph files are unchanged",
        "outline_note": "Approved source bottles expose brown cork on their top boundary. These exact existing pixels are retained; no claim of zero inherited outline violations is made.",
        "max_color_count": max(row["color_count"] for row in rows.values()),
        "all_bottles_rgba_exact_2x": all(row["bottle_rgba_exact_2x"] for row in rows.values()),
        "all_source_hashes_unchanged": all(row["source_unchanged"] for row in rows.values()),
        "icons": rows,
    }
    return images, index, report


def main() -> int:
    catalog = read_json(ROOT / "assets/pixel_v1/catalog.json")
    global_palette = palette(ROOT / "art/palette.hex")
    character_report = audit_characters(catalog, global_palette)
    write_json(REVIEW / "character-audit.json", character_report)
    images, index, report = package_potions(catalog, global_palette)
    write_json(REVIEW / "potion-validation.json", report)
    if character_report["status"] != "passed" or report["status"] != "passed":
        raise SystemExit("Validation failed; no potion icons or index were published.")
    ICONS.mkdir(parents=True, exist_ok=True)
    for potion_id, image in images.items():
        destination = ICONS / (potion_id + ".png")
        image.save(destination)
        # Confirm PNG serialization retained all RGBA bytes, not just appearance.
        saved = Image.open(destination).convert("RGBA")
        if saved.tobytes() != image.tobytes():
            raise RuntimeError(f"PNG roundtrip changed {potion_id}")
        import_settings(destination)
        report["icons"][potion_id]["png_rgba_roundtrip_exact"] = True
        report["icons"][potion_id]["output_sha256"] = sha256(destination)
    write_json(REVIEW / "potion-icons.json", index)
    write_json(REVIEW / "potion-validation.json", report)
    print(f"Packaged {len(index)} potion/recipe icons; audited {character_report['sheet_count']} character sheets / {character_report['frame_count']} frames.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
