"""Deterministic candidate-art pipeline: alpha cleanup, grid, materials, validate.

Requires Pillow and NumPy. Paths in the manifest are relative to the project.
Material classification is explicit in the manifest; no global nearest-color
lookup is performed. Generated sources are retained and never overwritten.
"""
from __future__ import annotations

import argparse
import colorsys
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
STAGES = ["background_cleanup", "native_grid", "material_ramp_remap", "validation"]


def local_path(value: str) -> Path:
    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError(f"Path leaves project: {value}")
    return path


def rgb(hex_value: str) -> tuple[int, int, int]:
    value = hex_value.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"Invalid color: {hex_value}")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def luminance(color) -> float:
    values = np.asarray(color, dtype=float) / 255.0
    linear = np.where(values <= 0.04045, values / 12.92,
                      ((values + 0.055) / 1.055) ** 2.4)
    return float(linear @ np.array([0.2126, 0.7152, 0.0722]))


def clean_background(source: Image.Image, threshold: int, crop: bool = True) -> Image.Image:
    data = np.array(source.convert("RGBA"))
    opaque = data[:, :, 3] >= threshold
    data[~opaque] = 0
    data[opaque, 3] = 255
    result = Image.fromarray(data)
    bounds = result.getbbox()
    if bounds is None:
        raise ValueError("No opaque sprite after alpha cleanup")
    return result.crop(bounds) if crop else result


def native_grid(cleaned: Image.Image, size: list[int], margin: int) -> Image.Image:
    """Reduce cells by dominant color bucket, avoiding invented blended RGBs."""
    width, height = size
    available = (width - 2 * margin, height - 2 * margin)
    factor = min(available[0] / cleaned.width, available[1] / cleaned.height)
    fitted = (max(1, round(cleaned.width * factor)),
              max(1, round(cleaned.height * factor)))
    data = np.array(cleaned)
    reduced = np.zeros((fitted[1], fitted[0], 4), dtype=np.uint8)
    for y in range(fitted[1]):
        y0, y1 = round(y * cleaned.height / fitted[1]), round((y + 1) * cleaned.height / fitted[1])
        for x in range(fitted[0]):
            x0, x1 = round(x * cleaned.width / fitted[0]), round((x + 1) * cleaned.width / fitted[0])
            block = data[y0:max(y0 + 1, y1), x0:max(x0 + 1, x1)].reshape(-1, 4)
            opaque = block[block[:, 3] == 255]
            if len(opaque) < len(block) / 2:
                continue
            # Bucket noise into 16-channel steps, then take an actual source
            # pixel in the dominant bucket. There is no bilinear interpolation.
            buckets = opaque[:, :3] // 16
            keys = buckets[:, 0].astype(int) * 256 + buckets[:, 1].astype(int) * 16 + buckets[:, 2]
            winner = np.bincount(keys, minlength=4096).argmax()
            choices = opaque[keys == winner]
            reduced[y, x] = choices[len(choices) // 2]
    result = Image.new("RGBA", (width, height))
    result.paste(Image.fromarray(reduced), ((width - fitted[0]) // 2, height - margin - fitted[1]))
    return result


def matches(rule, hue, saturation, value, x, y) -> bool:
    if "hue" in rule and not rule["hue"][0] <= hue <= rule["hue"][1]:
        return False
    for name, measurement in (("saturation", saturation), ("value", value), ("x", x), ("y", y)):
        if name + "_min" in rule and measurement < rule[name + "_min"]:
            return False
        if name + "_max" in rule and measurement > rule[name + "_max"]:
            return False
    return True


def material_remap(grid: Image.Image, asset, ramp_data):
    data = np.array(grid)
    material_names = list(asset["materials"])
    ids = {name: index + 1 for index, name in enumerate(material_names)}
    mask = np.zeros(data.shape[:2], dtype=np.uint8)
    opaque = data[:, :, 3] == 255
    # The cardinal silhouette boundary is one native pixel wide.
    padded = np.pad(opaque, 1)
    interior = (padded[1:-1, :-2] & padded[1:-1, 2:] &
                padded[:-2, 1:-1] & padded[2:, 1:-1])
    for y, x in zip(*np.where(opaque)):
        hue, saturation, value = colorsys.rgb_to_hsv(*(data[y, x, :3].astype(float) / 255))
        enforce_boundary = not asset.get("preserve_source_outline", False)
        if (enforce_boundary and not interior[y, x]) or value <= asset["dark_value"]:
            material = "outline"
        else:
            material = asset["fallback_material"]
            for rule in asset["rules"]:
                if matches(rule, hue, saturation, value, x / grid.width, y / grid.height):
                    material = rule["material"]
                    break
        mask[y, x] = ids[material]
    # Explicit reviewer-authored rectangles can correct uncertain semantic
    # assignments without changing the algorithm or doing nearest RGB matching.
    for override in asset.get("material_rectangles", []):
        x0, y0, x1, y1 = override["rect"]
        area = mask[y0:y1, x0:x1]
        if override.get("include_interior_outline", False):
            editable = (area != 0) & interior[y0:y1, x0:x1]
        else:
            editable = (area != 0) & (area != ids["outline"])
        area[editable] = ids[override["material"]]
    # Explicit semantic pixels standardize small features such as native eyes.
    # These assignments cannot erase transparency or replace the silhouette
    # boundary with a lighter material.
    for override in asset.get("material_pixels", []):
        for x, y in override["pixels"]:
            if not (0 <= x < grid.width and 0 <= y < grid.height and opaque[y, x]):
                raise ValueError("Material pixel is outside the opaque sprite")
            if not interior[y, x] and override["material"] != "outline":
                raise ValueError("Material pixel would break the outline boundary")
            mask[y, x] = ids[override["material"]]
    output = np.zeros_like(data)
    for material, colors in asset["materials"].items():
        ramp_name = asset.get("material_ramps", {}).get(material, material)
        if ramp_name not in ramp_data["ramps"]:
            raise ValueError(f"Undefined material ramp: {material}")
        approved_colors = ramp_data["ramps"][ramp_name]["colors"]
        if any(color not in approved_colors for color in colors):
            raise ValueError(f"Color outside its material ramp: {material}")
        indices = [approved_colors.index(color) for color in colors]
        if indices != sorted(set(indices)):
            raise ValueError(f"Material colors not in ramp order: {material}")
        positions = np.argwhere(mask == ids[material])
        if not len(positions):
            continue
        brightness = np.array([luminance(data[y, x, :3]) for y, x in positions])
        low, high = np.quantile(brightness, [0.1, 0.9])
        for (y, x), light in zip(positions, brightness):
            if high - low < 1e-8:
                index = len(colors) // 2
            else:
                normalized = float(np.clip((light - low) / (high - low), 0, 1))
                index = min(len(colors) - 1, int(normalized * len(colors)))
            output[y, x] = (*rgb(colors[index]), 255)
    return Image.fromarray(output), Image.fromarray(mask), ids


def validate(image: Image.Image, expected_size, palette, max_colors: int) -> dict:
    data = np.array(image.convert("RGBA"))
    opaque = data[data[:, :, 3] == 255]
    colors = sorted({tuple(pixel[:3]) for pixel in opaque})
    outside = [color for color in colors if color not in palette]
    partial = int(((data[:, :, 3] != 0) & (data[:, :, 3] != 255)).sum())
    problems = []
    if list(image.size) != list(expected_size):
        problems.append("native_size")
    if outside:
        problems.append("off_palette")
    if partial:
        problems.append("partial_alpha")
    if not colors:
        problems.append("empty_sprite")
    if len(colors) > max_colors:
        problems.append("color_limit")
    return {"passed": not problems, "size": list(image.size), "opaque_pixels": len(opaque),
            "colors": ["#%02X%02X%02X" % color for color in colors],
            "color_count": len(colors), "off_palette_colors": len(outside),
            "partial_alpha_pixels": partial, "problems": problems}


def save_board(images, config, output):
    size = tuple(config["scene"]["size"])
    scene = Image.new("RGBA", size)
    for asset in config["assets"]:
        scene.alpha_composite(images[asset["id"]], tuple(asset["position"]))
    scene.save(output / "mockup-native.png")
    scale = config["scale"]
    enlarged = scene.resize((size[0] * scale, size[1] * scale), Image.Resampling.NEAREST)
    enlarged.save(output / "mockup-transparent-3x.png")
    background = Image.new("RGBA", scene.size, config["scene"]["background"])
    background.alpha_composite(scene)
    background.resize(enlarged.size, Image.Resampling.NEAREST).save(output / "mockup-3x.png")

    # This explanation board is separate from the strictly paletted game art.
    board = Image.new("RGB", (enlarged.width + 64, enlarged.height + 130), "#241C32")
    draw = ImageDraw.Draw(board)
    font_path = Path("C:/Windows/Fonts/malgun.ttf")
    font = ImageFont.truetype(str(font_path), 16)
    title = ImageFont.truetype(str(font_path), 23)
    draw.text((28, 20), "달그늘 물약상점 · 픽셀 기준 목업 v1", font=title, fill="#FFF0BC")
    palette_label = "승인된 24색" if config["approved_by_user"] else "후보 24색"
    draw.text((28, 57), palette_label + " / 물체당 5색 / 공통 3배 확대", font=font, fill="#C38EB5")
    board.paste(background.resize(enlarged.size, Image.Resampling.NEAREST).convert("RGB"), (32, 90))
    for asset in config["assets"]:
        label = {"cauldron": "솥 32×32", "witch": "마녀 32×48", "shelf": "선반 64×64"}[asset["id"]]
        x = 32 + asset["position"][0] * scale
        draw.text((x, enlarged.height + 97), label, font=font, fill="#F6D1AC")
    board.save(output / "review-board.png")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", nargs="?", default="art/mockups/cozy-witch-v1/manifest.json")
    args = parser.parse_args()
    config = json.loads(local_path(args.manifest).read_text(encoding="utf-8"))
    output = local_path(config["output"])
    output.mkdir(parents=True, exist_ok=True)
    stages = output / "stages"
    stages.mkdir(exist_ok=True)
    report = {"status": "failed", "art_status": config["status"],
              "approved_by_user": config["approved_by_user"], "stage_order": STAGES,
              "scale": config["scale"], "assets": {}}
    try:
        scale = config["scale"]
        if not isinstance(scale, int) or scale < 1:
            raise ValueError("Scale must be a positive integer")
        palette_values = local_path(config["palette"]).read_text(encoding="utf-8").splitlines()
        palette = {rgb(value) for value in palette_values if value.strip()}
        if not 16 <= len(palette) <= 32 or len(palette) != len(palette_values):
            raise ValueError("Palette must contain 16-32 unique colors")
        ramp_data = json.loads(local_path(config["ramps"]).read_text(encoding="utf-8"))
        if config["status"] != "candidate" and not ramp_data["approved_by_user"]:
            raise ValueError("Unapproved palette may only produce candidate mockups")
        if rgb(config["scene"]["background"]) not in palette:
            raise ValueError("Scene background is outside palette")
        for ramp in ramp_data["ramps"].values():
            colors = [rgb(value) for value in ramp["colors"]]
            if not all(color in palette for color in colors):
                raise ValueError("Ramp contains off-palette color")
            if any(luminance(a) >= luminance(b) for a, b in zip(colors, colors[1:])):
                raise ValueError("Ramp is not in dark-to-light order")
        images = {}
        for asset in config["assets"]:
            source_path = local_path(asset["source"])
            source = Image.open(source_path).convert("RGBA")
            if "native_crop" in asset:
                x0, y0, x1, y1 = asset["native_crop"]
                if not (0 <= x0 < x1 <= source.width and 0 <= y0 < y1 <= source.height):
                    raise ValueError("Native crop leaves source frame")
                discarded = np.array(source)[:, :, 3].copy()
                discarded[y0:y1, x0:x1] = 0
                if (discarded >= config["alpha_threshold"]).any():
                    raise ValueError("Native crop would remove opaque sprite pixels")
                source = source.crop((x0, y0, x1, y1))
            preserve_frame = asset.get("preserve_native_frame", False)
            if preserve_frame and list(source.size) != asset["size"]:
                raise ValueError("Preserved native frame has unexpected dimensions")
            cleaned = clean_background(source, config["alpha_threshold"], not preserve_frame)
            # Reviewer-authored background masks may remove tiny silhouette
            # excesses on an already registered native frame. Boundary colors
            # are rebuilt by the material stage, never by copying other limbs.
            for rect in asset.get("background_alpha_rectangles", []):
                if not preserve_frame:
                    raise ValueError("Background alpha rectangles require a registered native frame")
                x0,y0,x1,y1=rect["rect"]
                if not (0<=x0<x1<=cleaned.width and 0<=y0<y1<=cleaned.height):
                    raise ValueError("Background alpha rectangle leaves native frame")
                pixels=np.array(cleaned);pixels[y0:y1,x0:x1]=0
                cleaned=Image.fromarray(pixels)
            cleaned.save(stages / (asset["id"] + "-clean.png"))
            grid = cleaned.copy() if preserve_frame else native_grid(cleaned, asset["size"], asset["margin"])
            grid.save(stages / (asset["id"] + "-grid.png"))
            result, mask, ids = material_remap(grid, asset, ramp_data)
            mask.save(stages / (asset["id"] + "-materials.png"))
            check = validate(result, asset["size"], palette, config["max_colors"])
            check["material_mask_ids"] = ids
            check["source_sha256"] = hashlib.sha256(source_path.read_bytes()).hexdigest()
            check["native_pixel_sha256"] = hashlib.sha256(result.tobytes()).hexdigest()
            report["assets"][asset["id"]] = check
            images[asset["id"]] = result
        if not all(check["passed"] for check in report["assets"].values()):
            raise ValueError("Asset validation failed; no final outputs published")
        # Validate scaling and scene bounds before publishing any final sprite.
        for asset in config["assets"]:
            result = images[asset["id"]]
            enlarged = result.resize((result.width * scale, result.height * scale), Image.Resampling.NEAREST)
            expected = np.repeat(np.repeat(np.array(result), scale, axis=0), scale, axis=1)
            if not np.array_equal(np.array(enlarged), expected):
                raise ValueError("Integer scale verification failed")
            x, y = asset["position"]
            if min(x, y) < 0 or x + result.width > config["scene"]["size"][0] or y + result.height > config["scene"]["size"][1]:
                raise ValueError("Sprite leaves mockup bounds")
        for asset in config["assets"]:
            result = images[asset["id"]]
            result.save(output / (asset["id"] + "-native.png"))
            result.resize((result.width * scale, result.height * scale), Image.Resampling.NEAREST).save(output / (asset["id"] + "-3x.png"))
        if config.get("compose", True):
            save_board(images, config, output)
        report["status"] = "passed"
        report["palette_color_count"] = len(palette)
        report["integer_scale_verified"] = True
        report["visual_review"] = "Required: material identity, outlines, feet, crescent and bottle count. Numeric validation does not approve design."
    except (ValueError, KeyError, OSError) as error:
        report["error"] = str(error)
        report["final_outputs_from_this_run"] = False
    (output / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
