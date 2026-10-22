"""Composite actual headless Control/glyph exports; no GUI, screen or game capture."""
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".verification/expedition-cards-20261013"
IMAGE_CACHE = {}


def image(path):
    if path not in IMAGE_CACHE:
        IMAGE_CACHE[path] = Image.open(path).convert("RGBA")
    return IMAGE_CACHE[path].copy()


def color(value):
    return "#" + value


def command(canvas, item):
    x, y, w, h = item["rect"]
    x, y, w, h = map(round, (x, y, w, h))
    if w <= 0 or h <= 0:
        return
    if item["kind"] in ("style", "solid"):
        art = Image.new("RGBA", (w, h))
        draw = ImageDraw.Draw(art)
        if item["kind"] == "solid":
            draw.rectangle((0, 0, w-1, h-1), fill=color(item["color"]))
        else:
            borders = list(map(round, item.get("border_widths", [item.get("border_width", 0)]*4)))
            fill = color(item["color"]) if item.get("draw_center", True) else None
            if len(set(borders)) == 1:
                draw.rounded_rectangle((0, 0, w-1, h-1), radius=item["radius"], fill=fill,
                                       outline=color(item["border_color"]) if borders[0] else None,
                                       width=borders[0] or 1)
            else:
                if fill is not None:
                    draw.rectangle((0, 0, w-1, h-1), fill=fill)
                left, top, right, bottom = borders
                border_color = color(item["border_color"])
                for thickness, box in [(left, (0, 0, left-1, h-1)), (top, (0, 0, w-1, top-1)),
                                       (right, (w-right, 0, w-1, h-1)), (bottom, (0, h-bottom, w-1, h-1))]:
                    if thickness:
                        draw.rectangle(box, fill=border_color)
    else:
        art = image(item["image"])
        interpolation = Image.Resampling.NEAREST if item["filter"] == "nearest" else Image.Resampling.BILINEAR
        if art.size != (w, h):
            art = art.resize((w, h), interpolation)
        art = ImageChops.multiply(art, Image.new("RGBA", art.size, color(item["color"])))
    if "clip" in item:
        cx, cy, cw, ch = map(round, item["clip"])
        left, top = max(0, cx-x), max(0, cy-y)
        right, bottom = min(w, cx+cw-x), min(h, cy+ch-y)
        if left >= right or top >= bottom:
            return
        art = art.crop((left, top, right, bottom))
        x, y = x+left, y+top
    canvas.alpha_composite(art, (x, y))


def render_commands(size, commands):
    canvas = Image.new("RGBA", tuple(map(round, size)))
    for item in commands:
        command(canvas, item)
    return canvas


def render(case):
    canvas = render_commands(case["size"], case["commands"])
    canvas.save(OUT / f"{case['id']}.png")
    canvas.resize((canvas.width*2, canvas.height*2), Image.Resampling.NEAREST).save(OUT / f"{case['id']}-2x.png")
    return canvas


def main():
    data = json.loads((OUT / "cards.json").read_text(encoding="utf-8"))
    cases = [(case, render(case)) for case in data["cases"]]
    width = data["management_width"]
    height = max(img.height for _, img in cases) + 100
    board = Image.new("RGB", (width*len(cases), height), "#211b2d")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype(data["font"], 16)
    for index, (case, card) in enumerate(cases):
        x = index*width
        draw.text((x+20, 12), case["label"], font=font, fill="#efc77c")
        board.paste(card, (x+20, 44), card)
        draw.text((x+20, 52+card.height), f"실제 카드 {card.width}×{card.height}px", font=font, fill="#b4a4bd")
    draw.text((20, height-28), "headless 실제 좌표·Pretendard 글리프 파일 합성 · 화면 캡처 아님", font=font, fill="#b4a4bd")
    board.save(OUT / "cards-board.png")
    print(f"EXPEDITION FILE RENDER PASS: {len(cases)} actual card states; Godot-rendered glyph masks/line positions; original textures; {OUT}")


if __name__ == "__main__":
    main()
