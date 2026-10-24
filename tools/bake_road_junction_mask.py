"""Offline: python tools/bake_road_junction_mask.py [ground_layout.json] [output.png]. Requires Pillow."""
from pathlib import Path
import json,sys
from PIL import Image,ImageDraw,ImageFilter
root=Path(__file__).resolve().parent.parent/'assets/materials/adelaide_pbr'
source=Path(sys.argv[1]) if len(sys.argv)>1 else root/'ground_layout.json'
target=Path(sys.argv[2]) if len(sys.argv)>2 else root/'road_junction_mask.png'
rects=json.loads(source.read_text(encoding='utf-8'))['hardscape']
im=Image.new('L',(2048,2048));draw=ImageDraw.Draw(im);count=0
for a in [r for r in rects if r[3]>r[2]*3]:
 for b in [r for r in rects if r[2]>r[3]*1.3]:
  x0=max(a[0],b[0]);z0=max(a[1],b[1]);x1=min(a[0]+a[2],b[0]+b[2]);z1=min(a[1]+a[3],b[1]+b[3])
  if x1<=x0 or z1<=z0:continue
  margin=110
  draw.rectangle(((x0-margin+65000)/145000*2048,(z0-margin+65000)/130000*2048,(x1+margin+65000)/145000*2048,(z1+margin+65000)/130000*2048),fill=255);count+=1
im.filter(ImageFilter.GaussianBlur(1.2)).save(target)
print('ROAD_JUNCTION_MASK_OK',count,target)
