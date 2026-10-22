"""Export complete generated customer poses and a review preview.

Only crops, registers, and scales whole sprites. Does not redraw body parts.
The game keeps consuming animations_v1 until the new designs are selected.
"""
import json
import shutil
import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "assets/source/customer_redesign_v1"
OUTPUT = PROJECT / "assets/characters/customer_redesign_v1"
CONFIG = {
    "mage": {"grid": (3, 2), "cells": (0, 1, 3, 5), "name": "여마법사"},
    "elf": {"grid": (2, 2), "cells": (0, 1, 2, 3), "name": "엘프"},
    "rogue": {"grid": (3, 2), "cells": (0, 1, 3, 5), "name": "고양이 도적"},
}
POSES = ("idle", "walk_1", "walk_2", "purchase_complete")
parser = argparse.ArgumentParser()
parser.add_argument("--version", choices=("v1", "v2", "v4"), default="v1")
VERSION = parser.parse_args().version
if VERSION != "v1":
    SOURCE = PROJECT / f"assets/source/customer_redesign_{VERSION}"
    OUTPUT = PROJECT / f"assets/characters/customer_redesign_{VERSION}"
    for config in CONFIG.values():
        config["grid"] = (2, 2)
        config["cells"] = (0, 1, 2, 3)


def bounds(image):
    mask = image.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
    result = mask.getbbox()
    if result is None:
        raise ValueError("Empty sprite cell")
    if VERSION == "v4":
        # Ignore detached generation specks when measuring the whole sprite.
        # Keep significant disconnected pieces such as a bow or tail.
        factor = min(1.0, 128 / max(image.size))
        small = mask.resize((max(1, round(image.width * factor)), max(1, round(image.height * factor))), Image.Resampling.NEAREST)
        width, height = small.size
        pixels = list(small.get_flattened_data())
        components = []
        for start in range(len(pixels)):
            if not pixels[start]:
                continue
            stack = [start]
            pixels[start] = 0
            area = 0
            low_x, low_y, high_x, high_y = width, height, 0, 0
            while stack:
                index = stack.pop()
                x, y = index % width, index // width
                area += 1
                low_x, low_y = min(low_x, x), min(low_y, y)
                high_x, high_y = max(high_x, x), max(high_y, y)
                for ny in range(max(0, y - 1), min(height, y + 2)):
                    for nx in range(max(0, x - 1), min(width, x + 2)):
                        neighbor = ny * width + nx
                        if pixels[neighbor]:
                            pixels[neighbor] = 0
                            stack.append(neighbor)
            components.append((area, (low_x, low_y, high_x + 1, high_y + 1)))
        if components:
            threshold = max(area for area, _ in components) * 0.03
            boxes = [box for area, box in components if area >= threshold]
            region = (
                max(0, int((min(box[0] for box in boxes) - 2) * image.width / width)),
                max(0, int((min(box[1] for box in boxes) - 2) * image.height / height)),
                min(image.width, int((max(box[2] for box in boxes) + 2) * image.width / width + 1)),
                min(image.height, int((max(box[3] for box in boxes) + 2) * image.height / height + 1)),
            )
            crop_box = mask.crop(region).getbbox()
            if crop_box:
                result = (region[0] + crop_box[0], region[1] + crop_box[1], region[0] + crop_box[2], region[1] + crop_box[3])
    return result


def export():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "status": "design preview; not connected to game",
        "cell_size": [48, 64],
        "sheet_size": [96, 128],
        "poses": list(POSES),
        "walk_frames": [1, 2],
        "walk_fps": 6,
        "processing": "Whole-body crops with one uniform scale per character; no torso/leg compositing",
        "version": VERSION,
        "characters": {},
    }
    character_frames = {}
    for character, config in CONFIG.items():
        source = Image.open(SOURCE / f"{character}.png").convert("RGBA")
        columns, rows = config["grid"]
        cells, body_bounds, anchors = [], [], []
        for index in config["cells"]:
            column, row = index % columns, index // columns
            cell = source.crop((
                round(column * source.width / columns),
                round(row * source.height / rows),
                round((column + 1) * source.width / columns),
                round((row + 1) * source.height / rows),
            ))
            box = bounds(cell)
            head_fraction = 0.3 if VERSION == "v4" and character == "rogue" else 0.4
            upper = cell.crop((box[0], box[1], box[2], box[1] + round((box[3] - box[1]) * head_fraction)))
            head = bounds(upper)
            anchors.append(box[0] + (head[0] + head[2]) / 2)
            cells.append(cell)
            body_bounds.append(box)
        tallest = max(box[3] - box[1] for box in body_bounds)
        span = max(max(anchor - box[0], box[2] - anchor) for anchor, box in zip(anchors, body_bounds))
        target_height = {"mage": 56, "elf": 47, "rogue": 47}[character] if VERSION != "v1" else 60
        scale = min(target_height / tallest, 21 / span)
        sheet = Image.new("RGBA", (96, 128))
        frames = []
        for index, (cell, box, anchor, pose) in enumerate(zip(cells, body_bounds, anchors, POSES)):
            body = cell.crop(box)
            body = body.resize((round(body.width * scale), round(body.height * scale)), Image.Resampling.NEAREST)
            x = 24 - round((anchor - box[0]) * scale)
            y = 62 - body.height
            if not (0 <= x and x + body.width <= 48 and y >= 2):
                raise ValueError(f"Sprite does not fit: {character}/{pose}")
            frame = Image.new("RGBA", (48, 64))
            frame.paste(body, (x, y))
            sheet.paste(frame, ((index % 2) * 48, (index // 2) * 64))
            frames.append(frame)
        if VERSION != "v1":
            # One shared reduced palette for every pose of a character.
            # This is sprite export/quantization, not drawing replacement parts.
            sheet.putalpha(sheet.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
            sheet = sheet.quantize(colors=24, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert("RGBA")
            frames = [sheet.crop(((i % 2) * 48, (i // 2) * 64, (i % 2) * 48 + 48, (i // 2) * 64 + 64)) for i in range(4)]
        for frame, pose in zip(frames, POSES):
            frame.save(OUTPUT / f"{character}_{pose}_48x64.png")
        sheet.save(OUTPUT / f"{character}_animations_96x128.png")
        character_frames[character] = frames
        manifest["characters"][character] = {
            "source": f"../../source/customer_redesign_{VERSION}/{character}.png",
            "source_grid": list(config["grid"]),
            "source_cells": list(config["cells"]),
            "sheet": f"{character}_animations_96x128.png",
            "scale": scale,
            "maximum_visible_height": target_height,
        }
        print(f"{character}: four complete poses exported as transparent 48x64 frames")

    background = (41, 35, 49, 255)
    font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 18)
    board = Image.new("RGBA", (896, 864), background)
    draw = ImageDraw.Draw(board)
    for row, (character, frames) in enumerate(character_frames.items()):
        draw.text((8, row * 288 + 3), CONFIG[character]["name"], font=font, fill="white")
        for column, frame in enumerate(frames):
            enlarged = frame.resize((192, 256), Image.Resampling.NEAREST)
            board.alpha_composite(enlarged, (column * 224 + 16, row * 288 + 30))
    board.save(OUTPUT / "all_poses_4x.png")
    board.resize((448, 432), Image.Resampling.NEAREST).save(OUTPUT / "all_poses_2x.png")

    comparison_frames = {"traveler": [Image.open(PROJECT / "assets/characters/animations_v1" / f"traveler_{pose}_48x64.png").convert("RGBA") for pose in POSES], **character_frames}
    labels = {"traveler": "기존 여행자", **{name: config["name"] for name, config in CONFIG.items()}}
    for factor in (1, 2, 4):
        comparison = Image.new("RGBA", (224 * factor, 72 * factor), background)
        for column, frames in enumerate(comparison_frames.values()):
            comparison.alpha_composite(frames[0].resize((48 * factor, 64 * factor), Image.Resampling.NEAREST), ((4 + column * 56) * factor, 4 * factor))
        comparison.save(OUTPUT / f"traveler_comparison_{factor}x.png")

    walking = []
    for pose in (1, 2):
        stage = Image.new("RGBA", (896, 288), background)
        stage_draw = ImageDraw.Draw(stage)
        for column, (character, frames) in enumerate(comparison_frames.items()):
            stage_draw.text((column * 224 + 16, 3), labels[character], font=font, fill="white")
            stage.alpha_composite(frames[pose].resize((192, 256), Image.Resampling.NEAREST), (column * 224 + 16, 30))
        walking.append(stage.convert("RGB"))
    palette = Image.new("RGB", (896, 576))
    palette.paste(walking[0], (0, 0))
    palette.paste(walking[1], (0, 288))
    palette = palette.quantize(colors=256)
    indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in walking]
    indexed[0].save(OUTPUT / "walk_preview_4x.gif", save_all=True, append_images=indexed[1:], duration=167, loop=0, disposal=2)
    indexed_2x = [frame.resize((448, 144), Image.Resampling.NEAREST) for frame in indexed]
    indexed_2x[0].save(OUTPUT / "walk_preview_2x.gif", save_all=True, append_images=indexed_2x[1:], duration=167, loop=0, disposal=2)
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    shutil.copyfile(SOURCE / "generation.json", OUTPUT / "generation.json")


if __name__ == "__main__":
    export()
