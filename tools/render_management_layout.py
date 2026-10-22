"""File-only management proof using the shared actual Control/glyph compositor."""
import json
import argparse
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from render_expedition_cards import render_commands

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".verification/management-layout-20261013"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--sage", action="store_true", help="Read separate production sage proof without replacing the purple artifacts")
    mode.add_argument("--stats", action="store_true", help="Read separate header/statistics proof without replacing the previous artifacts")
    mode.add_argument("--special", action="store_true", help="Read the separate special recipe integration proof")
    args = parser.parse_args()
    out = ROOT / ".verification/special-management-20261013" if args.special else ROOT / ".verification/management-statistics-20261013" if args.stats else ROOT / ".verification/management-sage-20261013" if args.sage else OUT
    data = json.loads((out / "management.json").read_text(encoding="utf-8"))
    images = []
    for case in data["cases"]:
        canvas = render_commands(case["size"], case["commands"])
        canvas.save(out / f"{case['id']}.png")
        canvas.resize((canvas.width*2, canvas.height*2), Image.Resampling.NEAREST).save(out / f"{case['id']}-2x.png")
        images.append((case, canvas))
    width = max(canvas.width for _, canvas in images)
    height = max(canvas.height for _, canvas in images)
    sage = data.get("palette") == "sage"
    background = "#" + data["cases"][0]["background"][:6]
    board = Image.new("RGB", (width*2, (height+40)*math.ceil(len(images)/2)+32), background)
    font = ImageFont.truetype(data["font"], 16)
    draw = ImageDraw.Draw(board)
    for index, (case, canvas) in enumerate(images):
        x, y = index % 2*width, index // 2*(height+40)
        draw.text((x+20, y+10), case["label"], font=font, fill="#aacbb0" if sage else "#efc77c")
        board.paste(canvas, (x, y+36), canvas)
    draw.text((20, board.height-28), "실제 Control·글리프·스크롤 클립 파일 합성 / 화면 캡처 아님", font=font, fill="#abb9be" if sage else "#b4a4bd")
    board.save(out / "management-board.png")
    print(f"MANAGEMENT FILE RENDER PASS: {len(images)} actual runtime layouts at {width}×{height}; shared TextServer glyph/Control compositor, production palette; {out}")


if __name__ == "__main__":
    main()
