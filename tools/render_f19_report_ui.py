"""Render existing management Controls only; unused period API stays in txt/JSON."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from render_expedition_cards import render_commands

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".verification/f19-supplement-20261019/ui"


def main():
    data = json.loads((OUT / "management.json").read_text(encoding="utf-8"))
    cases = data["cases"]
    width, height = 520, 840
    board = Image.new("RGB", (width * 3, height * 3 + 40), "#1d242b")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype(data["font"], 15)
    for i, case in enumerate(cases):
        canvas = render_commands(case["size"], case["commands"])
        canvas.save(OUT / f"{case['id']}.png")
        x, y = i % 3 * width, i // 3 * height
        draw.text((x + 12, y + 9), case["label"], font=font, fill="#aacbb0")
        board.paste(canvas, (x, y + 36), canvas)
    draw.text((12, board.height - 29), "실제 Control/TextServer 파일 합성 · 화면 캡처 아님 · 기간 API는 별도 txt/JSON", font=font, fill="#abb9be")
    board.save(OUT / "management-board.png")
    print(f"F19 REPORT UI RENDER PASS: {len(cases)} existing management layouts")


if __name__ == "__main__":
    main()
