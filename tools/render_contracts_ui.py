"""File-only F18 proof using actual Control/TextServer exports, never a screenshot."""
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from render_expedition_cards import render_commands

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".verification/contracts-ui-20261015/files"


def main():
    data = json.loads((OUT / "management.json").read_text(encoding="utf-8"))
    images = []
    for case in data["cases"]:
        canvas = render_commands(case["size"], case["commands"])
        canvas.save(OUT / f"{case['id']}.png")
        canvas.resize((canvas.width * 2, canvas.height * 2), Image.Resampling.NEAREST).save(OUT / f"{case['id']}-2x.png")
        images.append((case, canvas))
    width = max(canvas.width for _, canvas in images)
    height = max(canvas.height for _, canvas in images)
    board = Image.new("RGB", (width * 3, (height + 40) * math.ceil(len(images) / 3) + 32), "#1d242b")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype(data["font"], 16)
    for index, (case, canvas) in enumerate(images):
        x, y = index % 3 * width, index // 3 * (height + 40)
        draw.text((x + 16, y + 10), case["label"], font=font, fill="#aacbb0")
        board.paste(canvas, (x, y + 36), canvas)
    draw.text((16, board.height - 28), "실제 Control·Pretendard 글리프 파일 합성 / 화면 캡처 아님", font=font, fill="#abb9be")
    board.save(OUT / "contracts-board.png")
    print(f"CONTRACTS UI FILE RENDER PASS: {len(images)} actual layouts; {OUT}")


if __name__ == "__main__":
    main()
