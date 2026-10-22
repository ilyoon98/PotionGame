"""Publish existing approved pixel assets for the Godot runtime; no new artwork."""
from pathlib import Path
import hashlib,json,shutil
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/pixel_v1';ART=ROOT/'art/mockups/full-ingame-v9'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def main():
    OUT.mkdir(parents=True,exist_ok=True);data=read(ART/'animation-data.json');catalog={'version':1,'scale':3,'native_character':[32,48],'scene':[180,83],'characters':{},'potions':{},'sources':{},'props':{},'weather':{},'fire':[]}
    def publish(source,target):
        dest=OUT/target;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,dest);catalog['sources'][target]={'source':source.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()};return 'res://assets/pixel_v1/'+target
    floor=Image.new('RGBA',(180,83));d=ImageDraw.Draw(floor)
    for y,color in [(79,'#E9B95F'),(80,'#916047'),(81,'#50333B'),(82,'#241C32')]:d.line((0,y,179,y),fill=color)
    floor.save(OUT/'floor.png');catalog['props']['floor']='res://assets/pixel_v1/floor.png'
    # Update the approved mockup's floor without changing its other pixels.
    back=Image.open(ART/'background-native.png').convert('RGBA');back.paste(floor.crop((0,79,180,83)),(0,79));back.save(ART/'background-native.png')
    for key,name in [('window','window'),('poster','poster'),('counter','counter')]:catalog['props'][key]=publish(ROOT/f'art/mockups/full-ingame-v1/{name}-native.png',f'props/{key}.png')
    catalog['props']['herb']=publish(ROOT/'art/mockups/full-ingame-v1/herb_station-native.png','props/herb.png');catalog['props']['shelf']=publish(ART/'shelf-frame-native.png','props/shelf.png')
    for weather,paths in data['environment']['weather'].items():catalog['weather'][weather]=[publish((ART/p).resolve(),f'weather/{weather}-{i}.png') for i,p in enumerate(paths)]
    catalog['fire']=[publish((ART/p).resolve(),f'fire/{i}.png') for i,p in enumerate(data['environment']['fire'])]
    for recipe in data['recipes']:
        row=dict(recipe);base=ROOT/'art/mockups/full-ingame-v7/potions';row['bottle']=publish(base/recipe['bottle_path'],f'potions/{recipe["id"]}.png');row['pots']=[publish(base/p,f'pots/{recipe["id"]}-{i}.png') for i,p in enumerate(recipe['pot_frames'])];catalog['potions'][recipe['id']]=row
    for cid in ['keeper',*data['customer_order']]:
        row=data['keeper'] if cid=='keeper' else data['customers'][cid];base=(ART/row['root']).resolve();entry={'poses':{},'grips':row.get('grips',row.get('brew_grips',{})),'bindings':row.get('bindings',{})}
        for pose in row['poses']:
            fine=publish(base/f'motion/fine/{pose}-atlas.png',f'characters/{cid}/{pose}-fine.png');grid=Image.open(base/f'motion/grid/{pose}-atlas.png').convert('RGBA');native=Image.fromarray(np.array(grid)[::3,::3]);p=OUT/f'characters/{cid}/{pose}-native.png';native.save(p);entry['poses'][pose]={'fine':fine,'native':'res://assets/pixel_v1/'+p.relative_to(OUT).as_posix()}
            if cid!='keeper' and pose in entry['grips']:entry.setdefault('palms',{})[pose]=publish(ART/f'palms/{cid}/{pose}.png',f'characters/{cid}/{pose}-palm.png')
        catalog['characters'][cid]=entry
    catalog['spoon']=publish((ART/data['keeper']['root']).resolve()/'props/spoon-native.png','props/spoon.png')
    mask=Image.open(ROOT/'art/mockups/full-ingame-v7/potions/pot-liquid-mask.png').convert('L')
    catalog['liquid_pixels']=[[x,y] for y in range(mask.height) for x in range(mask.width) if mask.getpixel((x,y))]
    # Explicit lossless/no-border-fill settings also work on a fresh checkout.
    for png in OUT.rglob('*.png'):
        settings=Path(str(png)+'.import')
        if settings.exists():
            text=settings.read_text(encoding='utf-8').replace('process/fix_alpha_border=true','process/fix_alpha_border=false')
        else:
            resource='res://'+png.relative_to(ROOT).as_posix();dest='res://.godot/imported/'+png.name+'-'+hashlib.md5(resource.encode()).hexdigest()+'.ctex'
            text='[remap]\nimporter="texture"\ntype="CompressedTexture2D"\npath="'+dest+'"\n\n[deps]\nsource_file="'+resource+'"\ndest_files=["'+dest+'"]\n\n[params]\ncompress/mode=0\nmipmaps/generate=false\nprocess/fix_alpha_border=false\nprocess/premult_alpha=false\n'
        settings.write_text(text,encoding='utf-8')
    (OUT/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('Published pixel runtime:5characters/36potions/full-width floor')
if __name__=='__main__':main()
