"""Build tiny, palette-only weather and flame loops for the v2 review mockup.

Effects are explicit integer-pixel shapes; existing source art is never resampled
or modified. Run from any directory with the bundled Python/Pillow runtime.
"""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw


PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "art/mockups/full-ingame-v2/effects"
WINDOW = PROJECT / "art/mockups/full-ingame-v1/window-native.png"
PALETTE = {
    tuple(bytes.fromhex(line.strip().lstrip("#")))
    for line in (PROJECT / "art/palette.hex").read_text().splitlines()
    if line.strip()
}
TRANSPARENT = (0, 0, 0, 0)


def rgba(code: str) -> tuple[int, int, int, int]:
    return (*tuple(bytes.fromhex(code.lstrip("#"))), 255)


def window_holes() -> tuple[Image.Image, list[dict]]:
    """Find transparent components enclosed by the opaque window frame."""
    source = Image.open(WINDOW).convert("RGBA")
    assert source.size == (32, 32), source.size
    alpha = source.getchannel("A")
    unseen = {
        (x, y)
        for y in range(source.height)
        for x in range(source.width)
        if alpha.getpixel((x, y)) == 0
    }
    interior = []
    while unseen:
        start = unseen.pop()
        component = {start}
        queue = deque([start])
        while queue:
            x, y = queue.popleft()
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        if not any(x in (0, 31) or y in (0, 31) for x, y in component):
            interior.append(component)
    interior.sort(key=lambda component: min(x for x, _ in component))
    assert len(interior) == 2, f"Expected two interior panes, found {len(interior)}"
    mask = Image.new("L", (32, 32), 0)
    descriptions = []
    for component in interior:
        for pixel in component:
            mask.putpixel(pixel, 255)
        descriptions.append(
            {
                "pixels": len(component),
                "bounds": [
                    min(x for x, _ in component),
                    min(y for _, y in component),
                    max(x for x, _ in component),
                    max(y for _, y in component),
                ],
            }
        )
    return mask, descriptions


def cloud(draw: ImageDraw.ImageDraw, x: int, y: int, color: str) -> None:
    draw.rectangle((x + 1, y, x + 3, y + 1), fill=rgba(color))
    draw.line((x, y + 2, x + 5, y + 2), fill=rgba(color))


WEATHER_COLORS = {
    "night_clear": {
        "sky": "50315F", "horizon": "24566A", "cloud": "86548E",
        "orb": "E9B95F", "accent": "FFF0BC",
    },
    "night_rain": {
        "sky": "241C32", "horizon": "24566A", "cloud": "4A3C52",
        "orb": "E9B95F", "rain": "827589",
    },
    "day_clear": {
        "sky": "9BE2CF", "horizon": "718C59", "cloud": "FFF0BC",
        "orb": "E9B95F",
    },
    "day_rain": {
        "sky": "3BA8A3", "horizon": "24566A", "cloud": "827589",
        "orb": "E9B95F", "rain": "9BE2CF",
    },
}


def weather_frame(mode: str, frame: int, mask: Image.Image) -> Image.Image:
    frame %= 12
    colors = WEATHER_COLORS[mode]
    canvas = Image.new("RGBA", (32, 32), rgba(colors["sky"]))
    draw = ImageDraw.Draw(canvas)
    # One-pixel changes have a symmetric twelve-frame period. Frame 11 -> 0
    # returns with no cloud jump; clouds pause naturally at either extreme.
    drift = (0, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 0)[frame]
    horizon = rgba(colors["horizon"])
    draw.rectangle((0, 24, 31, 31), fill=horizon)
    draw.line((6, 23, 7, 23), fill=horizon)
    draw.line((20, 23, 23, 23), fill=horizon)
    if mode.startswith("night"):
        # Compact crescent in the left pane; its sky cutout is hard-edged.
        draw.rectangle((8, 12, 10, 15), fill=rgba(colors["orb"]))
        draw.rectangle((9, 12, 11, 14), fill=rgba(colors["sky"]))
        if "accent" in colors:
            draw.point((8, 13), fill=rgba(colors["accent"]))
            # Static sparse stars stay quieter than a full twinkling layer.
            draw.point((23, 12), fill=rgba(colors["accent"]))
            draw.point((13, 20), fill=rgba(colors["accent"]))
    else:
        draw.rectangle((8, 12, 10, 14), fill=rgba(colors["orb"]))
        draw.point((9, 11), fill=rgba(colors["orb"]))
        draw.point((9, 15), fill=rgba(colors["orb"]))
        draw.point((7, 13), fill=rgba(colors["orb"]))
        draw.point((11, 13), fill=rgba(colors["orb"]))
    cloud(draw, 18 + drift, 15, colors["cloud"])
    cloud(draw, 11 - drift, 18, colors["cloud"])
    if mode.endswith("rain"):
        # Tiny vertical dashes wrap every twelve pixels. At the seam each dash
        # takes its normal one-pixel step, with entering drops clipped by mask.
        for x, phase in ((7, 0), (13, 6), (18, 3), (24, 9)):
            y = 10 + ((phase + frame) % 12)
            draw.line((x, y, x, y + 1), fill=rgba(colors["rain"]))
    canvas.putalpha(mask)
    # Canonical alpha-zero pixels make downstream color counting predictable.
    for y in range(32):
        for x in range(32):
            if mask.getpixel((x, y)) == 0:
                canvas.putpixel((x, y), TRANSPARENT)
    return canvas


FIRE_COLORS = {
    "r": "9D4359", "o": "DE7356", "a": "F4AC68", "y": "E9B95F"
}
FIRE_ROWS = (
    (
        "............", ".....o......", ".....ao.....", "...ooao.....",
        "...oaayo....", "..roayyoo...", "..roayyar...", "...rrrrrr...",
    ),
    (
        "............", "............", "....o.......", "....aoo.....",
        "...oayo.....", "..roayaoo...", "..roayyar...", "...rrrrrr...",
    ),
    (
        "............", "......o.....", ".....oa.....", ".....aoo....",
        "...ooayo....", "..roaayoo...", "..roayyar...", "...rrrrrr...",
    ),
    (
        "............", "............", ".....o......", "....oao.....",
        "...oaayo....", "..roayaoo...", "..roayyar...", "...rrrrrr...",
    ),
)


def fire_frame(frame: int) -> Image.Image:
    canvas = Image.new("RGBA", (12, 8), TRANSPARENT)
    for y, row in enumerate(FIRE_ROWS[frame % 4]):
        assert len(row) == 12
        for x, symbol in enumerate(row):
            if symbol != ".":
                canvas.putpixel((x, y), rgba(FIRE_COLORS[symbol]))
    return canvas


def validate(image: Image.Image, size: tuple[int, int], mask=None) -> dict:
    pixels = list(image.getdata())
    visible = {pixel[:3] for pixel in pixels if pixel[3] > 0}
    outside = sorted(visible - PALETTE)
    partial = sum(pixel[3] not in (0, 255) for pixel in pixels)
    outside_mask = 0
    if mask is not None:
        outside_mask = sum(
            image.getpixel((x, y))[3] > 0 and mask.getpixel((x, y)) == 0
            for y in range(image.height)
            for x in range(image.width)
        )
    assert image.size == size, image.size
    assert len(visible) <= 5, f"Exceeded color budget: {len(visible)}"
    assert not outside, outside
    assert partial == 0, partial
    assert outside_mask == 0, outside_mask
    return {
        "size": list(size), "color_count": len(visible),
        "colors": sorted("#" + bytes(color).hex().upper() for color in visible),
        "outside_palette_colors": len(outside), "partial_alpha_pixels": partial,
        "outside_window_hole_pixels": outside_mask,
    }


def contact_sheet(groups: dict[str, list[Image.Image]], path: Path, scale: int) -> None:
    """Contact sheet uses palette-only backdrops and nearest-neighbor scaling."""
    rows = list(groups.values())
    width = max(sum(frame.width + 2 for frame in row) for row in rows) + 2
    height = sum(max(frame.height for frame in row) + 4 for row in rows) + 2
    canvas = Image.new("RGBA", (width, height), rgba("4A3C52"))
    y = 2
    for row in rows:
        x = 2
        for frame in row:
            canvas.alpha_composite(frame, (x, y))
            x += frame.width + 2
        y += max(frame.height for frame in row) + 4
    canvas.resize((width * scale, height * scale), Image.Resampling.NEAREST).save(path)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    mask, holes = window_holes()
    source_window = Image.open(WINDOW).convert("RGBA")
    manifest = {
        "schema_version": 1,
        "weather": {}, "fire": [], "fps": {"weather": 8, "fire": 8},
        "validation": {"passed": True, "window_holes": holes, "weather": {}, "fire": []},
    }
    weather_groups = {}
    for mode in ("night_rain", "night_clear", "day_rain", "day_clear"):
        destination = OUTPUT / "weather" / mode
        destination.mkdir(parents=True, exist_ok=True)
        paths, checks, composited = [], [], []
        for index in range(12):
            frame = weather_frame(mode, index, mask)
            checks.append(validate(frame, (32, 32), mask))
            path = destination / f"frame-{index:02d}.png"
            frame.save(path)
            paths.append(path.relative_to(OUTPUT).as_posix())
            review = frame.copy()
            review.alpha_composite(source_window)
            composited.append(review)
        assert weather_frame(mode, 12, mask).tobytes() == weather_frame(mode, 0, mask).tobytes()
        manifest["weather"][mode] = paths
        manifest["validation"]["weather"][mode] = {
            "frame_count": 12, "checks": checks, "periodic_at_frame_12": True,
        }
        weather_groups[mode] = composited
    contact_sheet(weather_groups, OUTPUT / "weather/contact-sheet.png", 3)
    fire_destination = OUTPUT / "fire"
    fire_destination.mkdir(parents=True, exist_ok=True)
    fire_frames = []
    for index in range(4):
        frame = fire_frame(index)
        manifest["validation"]["fire"].append(validate(frame, (12, 8)))
        path = fire_destination / f"frame-{index:02d}.png"
        frame.save(path)
        manifest["fire"].append(path.relative_to(OUTPUT).as_posix())
        fire_frames.append(frame)
    assert len({frame.crop((0, 7, 12, 8)).tobytes() for frame in fire_frames}) == 1
    assert fire_frame(4).tobytes() == fire_frame(0).tobytes()
    manifest["validation"]["fire_base_fixed"] = True
    manifest["validation"]["fire_periodic_at_frame_4"] = True
    manifest["validation"]["summary"] = {
        "weather_frame_count": 48, "fire_frame_count": 4,
        "maximum_weather_colors": max(
            check["color_count"]
            for mode in manifest["validation"]["weather"].values()
            for check in mode["checks"]
        ),
        "maximum_fire_colors": max(check["color_count"] for check in manifest["validation"]["fire"]),
        "outside_palette_colors": 0, "partial_alpha_pixels": 0,
        "outside_window_hole_pixels": 0,
    }
    contact_sheet({"fire": fire_frames}, OUTPUT / "fire/contact-sheet.png", 8)
    (OUTPUT / "frames.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(manifest["validation"]["summary"], ensure_ascii=False))


if __name__ == "__main__":
    main()
