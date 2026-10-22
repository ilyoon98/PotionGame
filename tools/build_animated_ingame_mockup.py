"""Build the v2 motion mockup from native sprites, with separate normal text.

Animation is deterministic pixel-frame composition. No runtime/save is changed.
"""
from __future__ import annotations

import base64
import io
import json
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from build_full_ingame_mockup import ROOT, OLD, COLORS, PALETTE, icon
from process_pixel_art import validate, rgb

OUT = ROOT / "art/mockups/full-ingame-v2"
PREVIOUS = ROOT / "art/mockups/full-ingame-v1"
POSITIONS = {"window": [4,5], "witch": [72,32], "elf": [148,33],
             "pot": [41,47], "fire": [51,70], "heldBottle": [154,57]}


def read(path):
    return Image.open(path).convert("RGBA")


def uri(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


def sprite(name):
    return read(PREVIOUS / (name + "-native.png"))


def character_frames(source, eyes, cut):
    """Lift only the head/neck 1 native pixel; hands and feet stay identical."""
    original = np.array(source)
    closed = original.copy()
    for x,y in eyes:
        if tuple(original[y,x,:3]) != rgb(COLORS["outline"]):
            raise ValueError(f"Eye mask no longer matches source at {(x,y)}")
        closed[y,x] = (*rgb("#F6D1AC"),255)
    for x,y in eyes[1::2]:
        closed[y,x] = (*rgb(COLORS["outline"]),255)
        if tuple(original[y,x+1,:3]) != rgb("#F6D1AC"):
            raise ValueError("Closed eyelid would paint outside skin")
        closed[y,x+1] = (*rgb(COLORS["outline"]),255)
    frames = []
    for data in (original, closed):
        lifted = data.copy()
        lifted[:cut] = data[1:cut+1]
        frames.extend([Image.fromarray(data), Image.fromarray(lifted)])
    for frame in frames:
        if not np.array_equal(np.array(frame)[cut:], original[cut:]):
            raise ValueError("Idle animation moved the hands or feet")
    return frames


def pot_frames():
    base = np.array(sprite("cauldron_moon"))
    # Open only the center of the stone hearth. Its side supports and base
    # remain fixed, so flame can be drawn behind rather than onto the pot.
    base[26:30,12:21] = 0
    liquid = np.all(base[:,:,:3] == rgb(COLORS["lilac"]),axis=2) & (base[:,:,3] == 255)
    frames = []
    patterns = [((10,10),(11,10),(18,11)),
                ((14,11),(15,11),(21,9)),
                ((9,11),(17,9),(18,9))]
    for dots in patterns:
        frame = base.copy()
        for x,y in dots:
            if not liquid[y,x]: raise ValueError("Boiling effect leaves exposed liquid")
            frame[y,x] = (*rgb(COLORS["purple"]),255)
        frames.append(Image.fromarray(frame))
    return frames


def idle_index(seconds, phase=0):
    clock = seconds + phase
    breathe = 1 if clock % 3 >= 1.5 else 0
    blink = 2 if 3.6 <= clock % 4.5 < 3.85 else 0
    return breathe + blink


def normal_text(canvas, position, value, size=14, color="cream", anchor=None):
    font = ImageFont.truetype(str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"),size)
    ImageDraw.Draw(canvas).text(position,value,font=font,fill=COLORS.get(color,color),anchor=anchor)


def stamp(canvas,kind,position,scale=2):
    im = icon(kind)
    canvas.alpha_composite(im.resize((im.width*scale,im.height*scale),Image.Resampling.NEAREST),position)


def static_art(scene):
    art = Image.new("RGBA",(180,83))
    for name in ("window","herb_station","shelf_frame","poster","counter"):
        art.alpha_composite(sprite(name),tuple(scene["placements"][name]))
    for row in scene["visible_owned_stock"]:
        art.alpha_composite(sprite("potion_"+row["id"]),tuple(row["position"]))
    # No rug/platform, no raster text, no weather, no moving object.
    return art.resize((540,249),Image.Resampling.NEAREST).crop((0,0,540,248))


def compose_art(static, frames, seconds, weather):
    canvas = Image.new("RGBA",(540,248))
    def draw(image,key):
        x,y = POSITIONS[key]
        canvas.alpha_composite(image.resize((image.width*3,image.height*3),Image.Resampling.NEAREST),(x*3,y*3))
    draw(frames["weather"][weather][int(seconds*8)%12],"window")
    canvas.alpha_composite(static)
    draw(frames["fire"][int(seconds*8)%4],"fire")
    draw(frames["pot"][int(seconds*6)%3],"pot")
    draw(frames["witch"][idle_index(seconds)],"witch")
    draw(frames["elf"][idle_index(seconds,1.5)],"elf")
    draw(frames["heldBottle"][0],"heldBottle")
    return canvas


def compose_text(art, weather="night_rain"):
    screen = Image.new("RGBA",(540,300),COLORS["mat"])
    screen.alpha_composite(art)
    draw = ImageDraw.Draw(screen)
    draw.rectangle((6,222,111,247),fill=COLORS["outline"],outline=COLORS["stone"])
    normal_text(screen,(12,225),"9종 재배 중")
    draw.rectangle((12,243,92,245),fill=COLORS["paper"])
    draw.rectangle((12,243,66,245),fill=COLORS["leaf"])
    stamp(screen,"search",(94,230),1)
    draw.rectangle((120,85,215,114),fill=COLORS["outline"],outline=COLORS["stone"])
    stamp(screen,"moon",(124,89),2)
    normal_text(screen,(145,88),"제작 중")
    stamp(screen,"search",(202,91),1)
    draw.rectangle((126,109,197,111),fill=COLORS["paper"])
    draw.rectangle((126,109,168,111),fill=COLORS["lilac"])
    normal_text(screen,(495,43),"2곳",14,anchor="mt")
    normal_text(screen,(495,65),"탐사 중",14,anchor="mt")
    stamp(screen,"search",(517,84),1)
    normal_text(screen,(323,158),"재고 8 / 12")
    stamp(screen,"coin",(324,176),1)
    normal_text(screen,(337,174),"+24 G · 선호",14,"gold")
    draw.rectangle((0,248,539,299),fill=COLORS["outline"])
    draw.line((0,248,539,248),fill=COLORS["wood"])
    stamp(screen,"move",(9,266),2)
    stamp(screen,"coin",(43,265),2)
    normal_text(screen,(68,264),"1,284 G",17,"gold")
    stamp(screen,"moon",(187,262),2)
    stamp(screen,"rain",(225,262),2)
    normal_text(screen,(254,266),"밤 · 비" if weather.startswith("night") else "낮 · 맑음")
    for x,w,label in ((398,42,"관리"),(444,28,"minimize"),(476,28,"expand"),(508,28,"close")):
        draw.rectangle((x,258,x+w-1,289),fill=COLORS["paper"],outline=COLORS["stone"])
        if label == "관리": normal_text(screen,(x+5,264),label,16)
        else: stamp(screen,label,(x+(w-18)//2,265),2)
    return screen


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    effect_data = json.loads((OUT / "effects/frames.json").read_text(encoding="utf-8"))
    scene = json.loads((PREVIOUS / "scene.json").read_text(encoding="utf-8"))
    frames = {"witch": character_frames(read(ROOT / OLD / "witch-native.png"),[(15,23),(15,24)],30),
              "elf": character_frames(sprite("elf"),[(9,18),(9,19),(15,18),(15,19)],27),
              "pot":pot_frames(),"heldBottle":[sprite("potion_purify")],
              "fire":[read(OUT/"effects"/p) for p in effect_data["fire"]],
              "weather":{key:[read(OUT/"effects"/p) for p in paths] for key,paths in effect_data["weather"].items()}}
    report={"status":"passed", "art_status":"candidate", "approved_by_user":False,
            "platform_removed":True,"glyphs_are_separate_normal_text":True,"art_scale":3,"frames":{}}
    for key in ("witch","elf","pot","heldBottle"):
        for index,frame in enumerate(frames[key]):
            check=validate(frame,list(frame.size),PALETTE,5)
            if not check["passed"]: raise ValueError(f"Frame failed: {key}/{index}")
            folder=OUT/"frames"/key
            folder.mkdir(parents=True,exist_ok=True)
            frame.save(folder/f"frame-{index:02}.png")
            report["frames"][f"{key}/{index}"]=check
    static=static_art(scene)
    static.save(OUT/"static-art.png")
    # Every art-only composed frame is palette-pure and uses integer locations.
    screens=[]
    for i in range(72):
        seconds=i/8
        art=compose_art(static,frames,seconds,"night_rain")
        check=validate(art,[540,248],PALETTE,24)
        if not check["passed"]: raise ValueError("Composed animated art leaves palette")
        screens.append(compose_text(art).convert("RGB"))
    screens[0].save(OUT/"still.png")
    screens[0].resize((1080,600),Image.Resampling.NEAREST).save(OUT/"still-2x.png")
    # Preserve every approved art color in the GIF. Other palette entries are
    # solely soft font-edge colors; sprite colors are not nearest-RGB remapped.
    base_colors=sorted(PALETTE)
    frequencies=Counter(tuple(pixel) for pixel in np.array(screens[0]).reshape(-1,3))
    edge_colors=[color for color,count in frequencies.most_common() if color not in PALETTE][:256-len(base_colors)]
    gif_colors=base_colors+edge_colors
    gif_colors += [(0,0,0)]*(256-len(gif_colors))
    gif_palette=Image.new("P",(1,1))
    gif_palette.putpalette([int(channel) for color in gif_colors for channel in color])
    gif_frames=[frame.quantize(palette=gif_palette,dither=Image.Dither.NONE) for frame in screens]
    gif_frames[0].save(OUT/"animated-preview.gif",save_all=True,append_images=gif_frames[1:],
                       duration=[120 if i%2==0 else 130 for i in range(72)],loop=0,optimize=False,disposal=2)
    data={"palette":COLORS,"staticArt":uri(static),"size":[540,300],"scale":3,"positions":POSITIONS,
          "font":"../../../assets/fonts/pretendard/Pretendard-Regular.otf",
          "sprites":{key:([uri(image) for image in value] if key!="weather" else
                          {weather:[uri(image) for image in images] for weather,images in value.items()})
                     for key,value in frames.items()},
          "snapshot":{"gold":1284,"inventory":"8 / 12","grow":"9종 재배 중","expeditions":"2곳"},
          "timing":{"idle_seconds":3,"blink_seconds":4.5,"blink_span":[3.6,3.85],"pot_fps":6,"fire_fps":8,"weather_fps":8}}
    (OUT/"animation-data.json").write_text(json.dumps(data,ensure_ascii=False,separators=(",",":")),encoding="utf-8")
    template=(ROOT/"tools/animated_workshop.template.html").read_text(encoding="utf-8")
    if template.count("__ANIMATION_DATA__")!=1: raise ValueError("Preview data placeholder is missing or duplicated")
    (OUT/"animated-preview.html").write_text(template.replace("__ANIMATION_DATA__",json.dumps(data,ensure_ascii=False,separators=(",",":"))),encoding="utf-8")
    report.update({"effects_validation":effect_data["validation"],"art_frames_checked":72,
                   "gif_duration_ms":9000,"gif_frame_count":72,"canvas_size":[540,248],"scene_size":[540,300],
                   "normal_text_palette_check_excluded":True,"hands_and_feet_fixed":True,
                   "motion_note":"Only head/neck lifts one pixel. Pot body and stone supports stay fixed; exposed liquid bubbles. Fire is behind hearth center."})
    (OUT/"validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":"passed","idle_frames":8,"pot_frames":3,"effect_frames":52,
                      "gif_frames":72,"duration_ms":9000,"normal_text":True,"platform_removed":True},indent=2))


if __name__=="__main__":
    main()
