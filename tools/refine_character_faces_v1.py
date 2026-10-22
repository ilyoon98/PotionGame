"""Apply generated full-head contours, retaining each original coherent body."""
from __future__ import annotations

import json
import numpy as np
from PIL import Image

from process_pixel_art import ROOT,rgb,validate
from prepare_character_outline_v5 import repair_outline
from prepare_character_v6 import dark_component

ART=ROOT / "art/characters/face-refinement-v1"
INK,SKIN=(*rgb("#241C32"),255),(*rgb("#F6D1AC"),255)
PALETTE={rgb(c) for c in (ROOT / "art/palette.hex").read_text().splitlines()}
PROFILES={
    "keeper":{"region":[8,16,23,27],"shift":[0,0],"eye_x":[15,18],"eye_y":21,
              "preserve_colors":["#86548E","#E9B95F"],"fringe_fill":[[17,19],[18,19],[19,19],[20,19],[19,18],[20,18]]},
    "elf":{"region":[3,11,27,27],"shift":[-1,0],"eye_x":[10,15],"eye_y":21},
    "mage":{"region":[3,18,25,27],"shift":[0,0],"eye_x":[10,14],"eye_y":22},
    "traveler":{"region":[3,11,23,27],"shift":[0,0],"eye_x":[10,14],"eye_y":22}}


def pupil_components(a,profile):
    dark=np.all(a==INK,axis=2);visited=set();groups=[]
    for yy,xx in zip(*np.where(dark)):
        if (xx,yy) in visited:continue
        group=[];queue=[(int(xx),int(yy))]
        while queue:
            x,y=queue.pop()
            if (x,y) in visited or not(0<=x<32 and 0<=y<48) or not dark[y,x]:continue
            visited.add((x,y));group.append((x,y))
            queue.extend((x+dx,y+dy) for dx in (-1,0,1) for dy in (-1,0,1) if dx or dy)
        if not 1<=len(group)<=4:continue
        if not all(min(profile["eye_x"])-2<=x<=max(profile["eye_x"])+3 and profile["eye_y"]-2<=y<=profile["eye_y"]+2 for x,y in group):continue
        skin_contacts=0
        for x,y in group:
            for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                if 0<=x+dx<32 and 0<=y+dy<48 and tuple(a[y+dy,x+dx])==SKIN:skin_contacts+=1
        if skin_contacts>=2:groups.append(group)
    return groups


def eye_checks(frame,name,closed=False):
    p=PROFILES[name];a=np.array(frame);result=[]
    for x in p["eye_x"]:
        y=p["eye_y"]
        points=[(x,y+1),(x+1,y+1)] if closed else [(x,y),(x,y+1)]
        if dark_component(frame,points[0],diagonals=True)!=sorted(points):raise ValueError(f"Eye merged: {name}/{points}")
        box=(x-1,y,x+3,y+3) if closed else (x-1,y-1,x+2,y+3)
        for yy in range(box[1],box[3]):
            for xx in range(box[0],box[2]):
                if (xx,yy) not in points and tuple(a[yy,xx])!=SKIN:raise ValueError(f"Eye skin margin: {name}/{xx,yy}")
        result.append({"pixels":points,"width":2 if closed else 1,"height":1 if closed else 2,"skin_gap":1})
    return result


def apply(frame,name):
    if not (ART / "pipeline" / f"{name}-native.png").is_file():return frame
    p=PROFILES[name];old=np.array(frame.convert("RGBA"));a=old.copy()
    donor=Image.open(ART / "pipeline" / f"{name}-native.png").convert("RGBA")
    shifted=Image.new("RGBA",(32,48));shifted.alpha_composite(donor,tuple(p["shift"]))
    source=np.array(shifted)
    if name=="elf":
        # The leaf is the only green head material. Source hue noise must not
        # turn the side fringe into a second green hair ornament.
        green=np.all(source==(*rgb("#718C59"),255),axis=2)|np.all(source==(*rgb("#B5C77D"),255),axis=2)
        head=np.zeros((48,32),bool);head[11:27]=True
        clip=np.zeros_like(head);clip[14:19,7:13]=True
        source[green & head & ~clip]=(*rgb("#916047"),255)
    x0,y0,x1,y1=p["region"];mask=np.zeros((48,32),bool);mask[y0:y1,x0:x1]=True
    for color in p.get("preserve_colors",[]):mask &= ~np.all(old==(*rgb(color),255),axis=2)
    a[mask]=source[mask]
    # Normalize existing small pupil components, then preserve all authored
    # cheek/chin contours. No large face rectangle is filled with skin.
    for group in pupil_components(a,p):
        for x,y in group:a[y,x]=SKIN
    for x in p["eye_x"]:
        y=p["eye_y"]
        for yy in range(y-1,y+3):
            for xx in range(x-1,x+2):a[yy,xx]=SKIN
        for yy in range(y,y+3):a[yy,x+2]=SKIN
        a[y:y+2,x]=INK
    if name=="keeper":
        # Retain the exact existing neck join, and use the generated continuous
        # fringe to close the rejected upper-right forehead recess above the
        # eye halo. The pupil halo starts on row20, so these hair pixels cannot
        # touch either eye diagonally.
        a[26]=old[26]
        for x,y in p["fringe_fill"]:
            a[y,x]=(*rgb("#916047"),255)
    image,_=repair_outline(Image.fromarray(a))
    a=np.array(image)
    if not np.array_equal(a[27:],old[27:]):raise ValueError(f"Face refinement changed body: {name}")
    check=validate(image,[32,48],PALETTE,5)
    if not check["passed"]:raise ValueError(f"Refined face palette: {name}/{check}")
    eye_checks(image,name)
    return image


def blink(frame,name):
    p=PROFILES[name];a=np.array(frame)
    for x in p["eye_x"]:
        y=p["eye_y"];a[y:y+2,x]=SKIN;a[y+1,x:x+2]=INK
    image=Image.fromarray(a);eye_checks(image,name,True);return image


def shifted_eye_points(name):
    p=PROFILES[name];return [[x,p["eye_y"]+dy] for x in p["eye_x"] for dy in (0,1)]
