"""Show alpha components and actual sheet gutters before native registration."""
import numpy as np
from PIL import Image
import build_keeper_keyframes_v2 as b
im=Image.open(b.OUT/'source/generated-01.png').convert('RGBA')
print('sheet',im.size)
for i in range(6):
    x,y=i%3,i//3
    cell=im.crop((round(x*im.width/3),round(y*im.height/2),round((x+1)*im.width/3),round((y+1)*im.height/2)))
    a=np.array(cell);mask=a[:,:,3]>=224;seen=np.zeros(mask.shape,bool);groups=[]
    for yy,xx in zip(*np.where(mask)):
        if seen[yy,xx]:continue
        points=[];stack=[(int(xx),int(yy))];seen[yy,xx]=True
        while stack:
            ax,ay=stack.pop();points.append((ax,ay))
            for dx in (-1,0,1):
                for dy in (-1,0,1):
                    nx,ny=ax+dx,ay+dy
                    if 0<=nx<mask.shape[1] and 0<=ny<mask.shape[0] and mask[ny,nx] and not seen[ny,nx]:seen[ny,nx]=True;stack.append((nx,ny))
        xs,ys=zip(*points);groups.append((len(points),[min(xs),min(ys),max(xs)+1,max(ys)+1]))
    print(b.POSES[i],sorted(groups,reverse=True)[:7])
    cell.save(b.OUT/'source'/f'cell-{i}.png')
