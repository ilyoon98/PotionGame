"""Package the SVG-derived PNG as an ICO and preview its actual Windows sizes.

First run prepare_app_icon.gd with Godot --headless. Requires Pillow.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SIZES = (16, 24, 32, 48, 64, 128, 256)


def main():
    source = Image.open(ROOT / "icon.png").convert("RGBA")
    frames = []
    for size in SIZES:
        # Preserve the pixel grid at integer scales; antialias fractional scales.
        method = Image.Resampling.NEAREST if size in (32, 64, 128, 256) else Image.Resampling.LANCZOS
        frames.append(source.resize((size, size), method))
    frames[-1].save(ROOT / "icon.ico", format="ICO", sizes=[(n, n) for n in SIZES],
                    append_images=frames[:-1])

    # Read back every embedded frame instead of validating only the source PNG.
    with Image.open(ROOT / "icon.ico") as icon:
        assert icon.ico.sizes() == {(n, n) for n in SIZES}
        for size in SIZES:
            frame = icon.ico.getimage((size, size)).convert("RGBA")
            assert frame.getchannel("A").getextrema() == (0, 255)
            assert frame.getpixel((0, 0))[3] == 0

    output = ROOT / "assets" / "app_icon"
    output.mkdir(parents=True, exist_ok=True)
    preview = Image.new("RGB", (760, 420), "#211b2d")
    draw = ImageDraw.Draw(preview)
    font_path = Path("C:/Windows/Fonts/malgun.ttf")
    font = ImageFont.truetype(str(font_path), 15) if font_path.exists() else ImageFont.load_default()
    title_font = ImageFont.truetype(str(font_path), 24) if font_path.exists() else font
    draw.text((28, 22), "달그늘 물약상점 · 앱 아이콘", font=title_font, fill="#f3dfbb")
    draw.text((28, 63), "SVG 원본 / 투명 배경 / Windows ICO", font=font, fill="#bfaed0")
    preview.paste(source, (26, 117), source)
    for row, background in enumerate(("#f2eff5", "#30283e")):
        y = 113 + row * 138
        draw.rounded_rectangle((314, y, 732, y + 122), radius=12, fill=background)
        draw.text((330, y + 10), "실제 표시 크기", font=font,
                  fill="#604e70" if row == 0 else "#e1d3ef")
        for column, size in enumerate((16, 24, 32, 48, 64)):
            x = 330 + column * 78
            frame = frames[SIZES.index(size)]
            preview.paste(frame, (x + (64 - size) // 2, y + 34 + (64 - size) // 2), frame)
            draw.text((x + 20, y + 100), str(size), font=font,
                      fill="#604e70" if row == 0 else "#e1d3ef")
    draw.text((28, 388), "Windows 크기: 16 · 24 · 32 · 48 · 64 · 128 · 256 px", font=font, fill="#bfaed0")
    preview.save(output / "preview.png")
    print("APP ICON PASS: seven RGBA ICO sizes, transparent corners, light/dark preview")


if __name__ == "__main__":
    main()
