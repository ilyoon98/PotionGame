"""F19 file proof from actual Control/TextServer commands, not a screenshot."""
import json
import math
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from render_expedition_cards import render_commands

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".verification/f19-20261019/ui-files"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--final", action="store_true")
    args = parser.parse_args()
    out = OUT.with_name(OUT.name + "-final") if args.final else OUT
    data = json.loads((out / "management.json").read_text(encoding="utf-8"))
    images = []
    for case in data["cases"]:
        canvas = render_commands(case["size"], case["commands"])
        canvas.save(out / f"{case['id']}.png")
        images.append((case, canvas))
    width = max(canvas.width for _, canvas in images)
    height = max(canvas.height for _, canvas in images)
    board = Image.new("RGB", (width * 3, (height + 40) * math.ceil(len(images) / 3) + 32), "#1d242b")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype(data["font"], 16)
    for index, (case, canvas) in enumerate(images):
        x, y = index % 3 * width, index // 3 * (height + 40)
        draw.text((x + 14, y + 10), case["label"], font=font, fill="#aacbb0")
        board.paste(canvas, (x, y + 36), canvas)
    draw.text((14, board.height - 28), "실제 Control·Pretendard 글리프 파일 합성 / 화면 캡처 아님", font=font, fill="#abb9be")
    board.save(out / "late-management-board.png")
    print(f"F19 MANAGEMENT FILE RENDER PASS: {len(images)} actual layouts; {out}")


if __name__ == "__main__":
    main()
