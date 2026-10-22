"""Compose the v4 candidate: shared floor, potion shelf, recipe liquid, motion.

Reuses corrected male identity and normal DOM typography. No game save/runtime
assets are replaced. Moving fabric uses explicitly selected native-grid or
one-display-pixel transforms; both retain palette colors and hard alpha.
"""
from __future__ import annotations

import base64
import copy
import io
import json
from collections import Counter

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import build_animated_ingame_mockup as shared
from process_pixel_art import validate

ROOT = shared.ROOT
OUT = ROOT / "art/mockups/full-ingame-v4"
PREVIOUS = ROOT / "art/mockups/full-ingame-v3"
POTIONS = OUT / "potions"
MOTION = OUT / "motion"
COLORS = shared.COLORS
PALETTE = shared.PALETTE
POSITIONS = {"window": [4, 5], "witch": [72, 32], "elf": [148, 32],
             "pot": [41, 47], "fire": [51, 70], "heldBottle": [154, 56]}
SIZE = [540, 300]
ART_SIZE = [540, 249]
POSES, FPS, ELF_PHASE = 16, 8, .625
PRIMARY_MODE = "fine"
TEMPLATE = "secondary_motion_workshop.template.html"


def read(path):
    return Image.open(path).convert("RGBA")


def from_uri(value):
    return read(io.BytesIO(base64.b64decode(value.split(",", 1)[1])))


def floor_art():
    image = Image.new("RGBA", (180, 83))
    draw = ImageDraw.Draw(image)
    draw.rectangle((4, 79, 175, 82), fill=COLORS["wood"], outline=COLORS["outline"])
    draw.line((5, 79, 174, 79), fill=COLORS["honey"])
    draw.line((5, 81, 174, 81), fill="#50333B")
    return image


def static_art(potions):
    image = floor_art()
    old = ROOT / "art/mockups/full-ingame-v1"
    placements = {"window": [4, 5], "herb_station": [4, 48], "poster": [153, 1], "counter": [105, 64]}
    for name, position in placements.items():
        image.alpha_composite(read(old / f"{name}-native.png"), tuple(position))
    image.alpha_composite(read(POTIONS / potions["shelf_composite_path"]), (105, 1))
    return image.resize(tuple(ART_SIZE), Image.Resampling.NEAREST)


def motion_index(seconds, phase=0):
    time = seconds + phase
    return int(time*FPS) % POSES + (POSES if 3.6 <= time % 4.5 < 3.85 else 0)


def compose_art(static, common, modes, recipes, seconds, mode="fine", recipe="moon", weather="night_rain"):
    image = Image.new("RGBA", tuple(ART_SIZE))
    def place(sprite, name, native=True):
        if native:
            sprite = sprite.resize((sprite.width*3, sprite.height*3), Image.Resampling.NEAREST)
        point = tuple(value*3 for value in POSITIONS[name])
        image.alpha_composite(sprite, point)
    place(common["weather"][weather][int(seconds*8) % 12], "window")
    image.alpha_composite(static)
    place(common["fire"][int(seconds*8) % 4], "fire")
    place(recipes[recipe][int(seconds*6) % 3], "pot")
    place(modes[mode]["witch"][motion_index(seconds)], "witch", False)
    place(modes[mode]["elf"][motion_index(seconds, ELF_PHASE)], "elf", False)
    place(common["heldBottle"][0], "heldBottle")
    return image


def compose_text(art):
    screen = Image.new("RGBA", tuple(SIZE), COLORS["mat"])
    screen.alpha_composite(art)
    draw = ImageDraw.Draw(screen)
    def label(position, value, size=14, color="cream", anchor=None):
        shared.normal_text(screen, position, value, size, color, anchor)
    def stamp(kind, position, scale=1):
        shared.stamp(screen, kind, position, scale)
    draw.rectangle((6,114,111,140),fill=COLORS["outline"],outline=COLORS["stone"])
    label((12,117),"9종 재배 중")
    draw.rectangle((12,136,92,138),fill=COLORS["paper"])
    draw.rectangle((12,136,66,138),fill=COLORS["leaf"])
    stamp("search",(94,123))
    draw.rectangle((120,85,215,114),fill=COLORS["outline"],outline=COLORS["stone"])
    stamp("moon",(124,89),2)
    label((145,88),"제작 중")
    stamp("search",(202,91))
    draw.rectangle((126,109,197,111),fill=COLORS["paper"])
    draw.rectangle((126,109,168,111),fill=COLORS["lilac"])
    label((495,43),"2곳",anchor="mt")
    label((495,65),"탐사 중",anchor="mt")
    stamp("search",(517,84))
    label((323,158),"재고 8 / 12")
    stamp("coin",(324,176))
    label((337,174),"+24 G · 선호",color="gold")
    draw.rectangle((0,249,539,299),fill=COLORS["outline"])
    draw.line((0,249,539,249),fill=COLORS["wood"])
    stamp("move",(9,266),2)
    stamp("coin",(43,265),2)
    label((68,264),"1,284 G",17,"gold")
    stamp("moon",(187,262),2)
    stamp("rain",(225,262),2)
    label((254,266),"밤 · 비")
    for x,w,text in ((398,42,"관리"),(444,28,"minimize"),(476,28,"expand"),(508,28,"close")):
        draw.rectangle((x,258,x+w-1,289),fill=COLORS["paper"],outline=COLORS["stone"])
        if text == "관리": label((x+5,264),text,16)
        else: stamp(text,(x+(w-18)//2,265),2)
    return screen


def save_gif(screens, path):
    colors = sorted(PALETTE)
    counts = Counter(tuple(pixel) for pixel in np.array(screens[0]).reshape(-1,3))
    colors += [color for color, count in counts.most_common() if color not in PALETTE][:256-len(colors)]
    colors += [(0,0,0)]*(256-len(colors))
    palette = Image.new("P", (1,1))
    palette.putpalette([int(channel) for color in colors for channel in color])
    frames = [screen.quantize(palette=palette, dither=Image.Dither.NONE) for screen in screens]
    frames[0].save(path,save_all=True,append_images=frames[1:],
                   duration=[120 if i%2==0 else 130 for i in range(len(frames))],loop=0,optimize=False,disposal=2)


def color_review(rows, recipes):
    selected = ["health","mana","moon","purify","agility","vigor","nightwalk","rare_forest_breath"]
    names = {row["id"]: row["name"] for row in rows}
    board = Image.new("RGB", (896,176), COLORS["mat"])
    font = ImageFont.truetype(str(ROOT / "assets/fonts/pretendard/Pretendard-Regular.otf"),13)
    draw = ImageDraw.Draw(board)
    for index, recipe in enumerate(selected):
        x = index*112+8
        pot = recipes[recipe][0].resize((96,96), Image.Resampling.NEAREST)
        board.paste(pot, (x,40),pot)
        draw.text((x+48,14),names[recipe],font=font,fill=COLORS["cream"],anchor="mt")
        draw.text((x+48,144),recipe.replace("rare_forest_breath","숲의 숨결"),font=font,fill=COLORS["cream"],anchor="mt")
    board.save(OUT / "recipe-liquid-review.png")


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    base = json.loads((PREVIOUS / "animation-data.json").read_text(encoding="utf-8"))
    motion = json.loads((MOTION / "frames.json").read_text(encoding="utf-8"))
    potions = json.loads((POTIONS / "recipes.json").read_text(encoding="utf-8"))
    if not motion["passed"] or motion["pose_count"] != POSES:
        raise ValueError("Secondary motion validation failed or pose contract changed")
    if potions["validation"]["status"] != "passed":
        raise ValueError("Potion shelf validation failed")
    modes = {mode:{name:[read(MOTION/path) for path in paths] for name,paths in groups.items()}
             for mode,groups in motion["modes"].items()}
    rows = potions["recipes"]
    if len(rows) != 36 or len({row["id"] for row in rows}) != 36:
        raise ValueError("Potion recipe set must contain the 36 actual IDs")
    recipes = {row["id"]:[read(POTIONS/path) for path in row["pot_frames"]] for row in rows}
    common = {"fire":[from_uri(value) for value in base["sprites"]["fire"]],
              "weather":{key:[from_uri(value) for value in frames] for key,frames in base["sprites"]["weather"].items()},
              "heldBottle":[read(POTIONS/next(row["bottle_path"] for row in rows if row["id"]=="purify"))]}
    static = static_art(potions)
    static.save(OUT / "static-art.png")
    floor_art().save(OUT / "common-floor-native.png")
    checks = {}
    for mode in ("fine","grid"):
        screens = []
        for i in range(144):
            art = compose_art(static,common,modes,recipes,i/8,mode)
            check = validate(art,ART_SIZE,PALETTE,24)
            if not check["passed"]:
                raise ValueError(f"Art composition failed: {mode}/{i}")
            screens.append(compose_text(art).convert("RGB"))
        checks[mode] = {"checked_art_frames":144,"off_palette":0,"partial_alpha":0}
        filename = "animated-preview.gif" if mode == PRIMARY_MODE else f"animated-{mode}.gif"
        save_gif(screens,OUT / filename)
        if mode == PRIMARY_MODE:
            screens[0].save(OUT / "still.png")
            screens[0].resize((1080,600),Image.Resampling.NEAREST).save(OUT / "still-2x.png")
    color_review(rows,recipes)
    data = copy.deepcopy(base)
    data.update(revision="v4-secondary-motion-potion-shelf",size=SIZE,artSize=ART_SIZE,
                staticArt=shared.uri(static),positions=POSITIONS,currentBrew="moon",
                motionModes={mode:{"nativeScale":3,**{name:[shared.uri(frame) for frame in frames]
                               for name,frames in groups.items()}} for mode,groups in modes.items()},
                potionRecipes=[{"id":row["id"],"name":row["name"],"liquidColor":row["liquid_color"],
                                "frames":[shared.uri(frame) for frame in recipes[row["id"]]]} for row in rows])
    data["sprites"]["pot"] = [shared.uri(frame) for frame in recipes["moon"]]
    data["sprites"]["heldBottle"] = [shared.uri(common["heldBottle"][0])]
    data["timing"].update(motion_fps=FPS,motion_poses=POSES,elf_phase_seconds=ELF_PHASE)
    data["layout_revision"] = {"individual_rug_removed":True,"shared_floor_top_row":79,"herb_station_y":48,
                               "shelf_rows":potions["shelf_positions"],"growth_label_y":114}
    payload = json.dumps(data,ensure_ascii=False,separators=(",",":"))
    (OUT / "animation-data.json").write_text(payload,encoding="utf-8")
    template = (ROOT / "tools" / TEMPLATE).read_text(encoding="utf-8")
    if template.count("__ANIMATION_DATA__") != 1:
        raise ValueError("Preview data placeholder missing or duplicated")
    template = template.replace("달그늘 물약상점 · 움직임 목업", "달그늘 물약상점 · 작업실 목업 v4")
    template = template.replace("달그늘 물약상점 · 작은 움직임 목업", "달그늘 물약상점 · 작업실 목업 v4")
    (OUT / "animated-preview.html").write_text(template.replace("__ANIMATION_DATA__",payload),encoding="utf-8")
    report = {"status":"passed","art_status":"candidate","approved_by_user":False,
              "canvas_size":ART_SIZE,"scene_size":SIZE,"common_floor_added":True,"individual_rug_removed":True,
              "male_identity_and_anatomy_source":"../full-ingame-v3/characters/",
              "fine_mode_changes_only_free_fabric_edges_on_display_grid":True,
              "native_pixel_scale":3,"fine_displacement_native_pixels":1/3,
              "normal_text_palette_check_excluded":True,"recipe_count":36,
              "art_frames":checks,"gif_frame_count":144,"gif_duration_ms":18000,
              "secondary_motion_validation":"motion/frames.json","potion_validation":"potions/recipes.json",
              "contacts":{"herb_station":78,"counter":78,"characters":78,"hearth":78,"floor_top":79}}
    (OUT / "validation.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":"passed","modes":2,"recipes":36,"frames_each":144,
                      "shared_floor":True,"normal_text":True},indent=2))


if __name__ == "__main__":
    main()
