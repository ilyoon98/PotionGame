"""Render adopted-cost proof from actual existing Controls/TextServer glyphs."""
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from render_expedition_cards import render_commands

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".verification/f19-adopted180-20261019/ui"


def main():
    data = json.loads((OUT / "management.json").read_text(encoding="utf-8"))
    cases = data["cases"]
    board = Image.new("RGB", (1560, 840 * math.ceil(len(cases) / 3) + 40), "#1d242b")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype(data["font"], 16)
    for i, case in enumerate(cases):
        canvas = render_commands(case["size"], case["commands"])
        canvas.save(OUT / f"{case['id']}.png")
        x, y = i % 3 * 520, i // 3 * 840
        draw.text((x + 12, y + 9), case["label"], font=font, fill="#aacbb0")
        board.paste(canvas, (x, y + 36), canvas)
    draw.text((12, board.height - 29), "실제 Control/TextServer 파일 합성 · 화면 캡처 아님 · 채택15/30/45만", font=font, fill="#abb9be")
    board.save(OUT / "management-board.png")
    print(f"ADOPTED180 MANAGEMENT RENDER PASS: {len(cases)} real layout cases")


if __name__ == "__main__":
    main()
