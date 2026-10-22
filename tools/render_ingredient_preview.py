"""File-only actual IngredientIcons Control/TextServer glyph composition."""
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from render_expedition_cards import render_commands

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".verification/ingredients-rare-20261013/layout"


def main():
    data = json.loads((OUT / "ingredients.json").read_text(encoding="utf-8"))
    images = []
    for case in data["cases"]:
        canvas = render_commands(case["size"], case["commands"])
        canvas.save(OUT / f"{case['id']}.png")
        canvas.resize((canvas.width*2, canvas.height*2), Image.Resampling.NEAREST).save(OUT / f"{case['id']}-2x.png")
        images.append((case, canvas))
    width = max(canvas.width for _, canvas in images) + 12
    height = max(canvas.height for _, canvas in images) + 36
    board = Image.new("RGBA", (width*2, height*math.ceil(len(images)/2)+32), "#1d242b")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype(data["font"], 16)
    for index, (case, canvas) in enumerate(images):
        x, y = index % 2*width, index // 2*height
        draw.text((x+12, y+6), case["id"], font=font, fill="#aacbb0")
        board.alpha_composite(canvas, (x+6, y+30))
    draw.text((12, board.height-27), "실제 공통 컴포넌트·글리프 파일 합성 / 화면 캡처 아님", font=font, fill="#abb9be")
    board.save(OUT / "ingredients-board.png")
    print(f"INGREDIENT FILE RENDER PASS: {len(images)} actual component previews; {OUT}")


if __name__ == "__main__":
    main()
