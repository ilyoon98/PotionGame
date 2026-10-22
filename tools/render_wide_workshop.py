"""File-only proof of actual runtime draw commands. This does not emulate GPU shaders."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".verification/wide-runtime"
DATA = json.loads((OUT / "runtime.json").read_text(encoding="utf-8"))
FONT = ImageFont.truetype(DATA["font"], 10)


def draw_command(canvas, command):
    x, y, width, height = map(round, command["rect"])
    if width <= 0 or height <= 0:
        return
    color = command.get("color", "#ffffffff")
    texture = command.get("texture")
    if texture:
        art = Image.open(texture["image"]).convert("RGBA")
        if "region" in command:
            rx, ry, rw, rh = map(round, command["region"])
            art = art.crop((rx, ry, rx + rw, ry + rh))
        art = art.resize((width, height), Image.Resampling.NEAREST)
        if command.get("flip_h"):
            art = art.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if color != "#ffffffff":
            art = ImageChops.multiply(art, Image.new("RGBA", art.size, color))
        canvas.alpha_composite(art, (x, y))
    else:
        layer = Image.new("RGBA", (width, height), color)
        canvas.alpha_composite(layer, (x, y))


def draw_gauges(canvas, commands):
    draw = ImageDraw.Draw(canvas)
    for command in commands:
        x, y, w, h = map(round, command["rect"])
        if command["kind"] == "texture":
            draw_command(canvas, command)
        elif command["kind"] == "backing":
            draw.rectangle((x, y, x+w-1, y+h-1), fill="#281f33", outline="#766180")
        elif command["kind"] == "caption":
            # The live draw_string uses this exact baseline and Pretendard size.
            caption_font = ImageFont.truetype(DATA["font"], command["font_size"])
            draw.text((x, y+command["baseline"]), command["text"], font=caption_font, fill="#efc77c", anchor="ls")
        elif command["kind"] == "bar":
            draw.rectangle((x, y, x+w-1, y+h-1), fill="#49364f")
            amount = int(max(0, min(1, command["progress"])) * w)
            if amount:
                draw.rectangle((x, y, x+amount-1, y+h-1), fill=command["color"] if command["running"] else "#81718a")
            if not command["running"]:
                for px in (x+w-3, x+w-1):
                    draw.rectangle((px, y-2, px, y-1), fill="#efd7a2")


def draw_button(canvas, bounds, icon=None, text="", size=11, disabled=False, primary=False):
    x, y, w, h = map(round, bounds)
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x, y, x+w-1, y+h-1), radius=5,
                           fill="#efc77c" if primary else "#30273c", outline="#796449" if primary else "#594764")
    color = "#66596e" if disabled else "#211b2d" if primary else "#b4a4bd"
    font = ImageFont.truetype(DATA["font"], size)
    if isinstance(icon, dict):
        image = Image.open(icon["image"]).convert("RGBA")
        target = 20 if text else 18
        image.thumbnail((target, target), Image.Resampling.NEAREST)
        ix = x+5 if text else x+(w-image.width)//2
        canvas.alpha_composite(image, (ix, y+(h-image.height)//2))
    if text:
        text_x = x+w-6 if isinstance(icon, dict) else x+w/2
        draw.text((text_x, y+h/2), text, font=font, fill=color, anchor="rm" if isinstance(icon, dict) else "mm")


def render(case):
    canvas = Image.new("RGBA", tuple(DATA["size"]))
    for command in case["sky_frame"]:
        draw_command(canvas, command)
    for kind in ("time", "weather"):
        x, y, w, h = map(round, case["snapshot"]["sky"][kind+"_clip"])
        pane = Image.new("RGBA", (w, h))
        for command in case["sky_"+kind]:
            draw_command(pane, command)
        canvas.alpha_composite(pane, (x, y))
    for command in case["halos"] + case["art"] + case["pot"]:
        draw_command(canvas, command)
    draw_gauges(canvas, case["gauges"])
    for rect in case["buttons"].values():
        x, y, w, h = map(round, rect)
        draw = ImageDraw.Draw(canvas)
        draw.rectangle((x, y, x+w-1, y+h-1), fill="#281f33", outline="#766180")
        draw.ellipse((x+4, y+4, x+10, y+10), outline="#efc77c")
        draw.line((x+10, y+10, x+14, y+14), fill="#efc77c")
    for item in case["toolbar"]:
        item = dict(item)
        x, y, w, h = item["rect"]
        item["rect"] = [x, y+DATA["art_height"], w, h]
        if "disabled" in item:
            draw_button(canvas, item["rect"], item.get("icon"), item.get("text", ""), item["font_size"], item["disabled"], item["name"] == "ManageButton")
        elif "texture" in item:
            draw_command(canvas, item)
        elif "text" in item:
            draw = ImageDraw.Draw(canvas)
            draw.text((x, y+DATA["art_height"]+h/2), item["text"], font=ImageFont.truetype(DATA["font"], item["font_size"]), fill="#efc77c", anchor="lm")
    return canvas


width, height = DATA["size"]
row_height = height + 52
board = Image.new("RGB", (width*2, row_height*((len(DATA["cases"])+1)//2)+40), "#252329")
title_font = ImageFont.truetype(DATA["font"], 18)
for index, case in enumerate(DATA["cases"]):
    image = render(case)
    image.save(OUT / (case["id"]+".png"))
    zoom = image.resize((width*2, height*2), Image.Resampling.NEAREST)
    zoom.save(OUT / (case["id"]+"-2x.png"))
    # Seven 540px-wide games, two per row; labels are outside the game bounds.
    bx = (index % 2) * width
    by = (index // 2) * row_height
    board.paste(image, (bx, by+30), image)
    ImageDraw.Draw(board).text((bx+8, by+4), case["id"], font=title_font, fill="#efc77c")
ImageDraw.Draw(board).text((8, board.height-30), "실제 런타임 상태·좌표의 파일 렌더 / GPU 조명·화면 캡처 아님", font=title_font, fill="#efc77c")
board.save(OUT / "states-board.png")
first = Image.open(OUT / (DATA["cases"][0]["id"]+".png"))
first.crop((0, DATA["art_height"], width, height)).resize((width*2, (height-DATA["art_height"])*2), Image.Resampling.NEAREST).save(OUT / "toolbar-2x.png")
print(f"WIDE FILE RENDER PASS: {len(DATA['cases'])} actual runtime cases at {width}x{height} and {width*2}x{height*2}; original textures, pane clipping and unlit captions; GPU shader not emulated: {OUT}")
