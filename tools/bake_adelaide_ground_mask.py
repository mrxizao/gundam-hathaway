"""Offline mask compiler. The game has no Python dependency.

Run export_adelaide_ground_layout.tscn first after changing Adelaide geometry.
Requires numpy and Pillow. Run this script on the exported geometry, then let
Godot reimport the mask and run suite_adelaide_ground before shipping.
"""
from pathlib import Path
import json,argparse
import numpy as np
from PIL import Image
parser=argparse.ArgumentParser(description=__doc__)
root=Path(__file__).resolve().parents[1]
parser.add_argument('--layout',type=Path,default=root/'assets/materials/adelaide_pbr/ground_layout.json')
parser.add_argument('--output',type=Path,default=root/'assets/materials/adelaide_pbr')
args=parser.parse_args();A=args.output
layout=json.loads(args.layout.read_text(encoding='utf8'))
origin=np.array([-65000,-65000]);size=np.array([145000,130000]);N=4096
xx=origin[0]+(np.arange(N,dtype=np.float32)+.5)*size[0]/N
zz=origin[1]+(np.arange(N,dtype=np.float32)+.5)*size[1]/N
def distance_field(rectangles):
 field=np.full((N,N),512,dtype=np.float32)
 for x,z,w,h in rectangles:
  a=max(0,int((x-512-origin[0])/size[0]*N));b=min(N,int((x+w+512-origin[0])/size[0]*N)+2)
  c=max(0,int((z-512-origin[1])/size[1]*N));d=min(N,int((z+h+512-origin[1])/size[1]*N)+2)
  if a>=b or c>=d:continue
  dx=np.maximum(np.abs(xx[a:b]-(x+w*.5))-w*.5,0)
  dz=np.maximum(np.abs(zz[c:d]-(z+h*.5))-h*.5,0)
  local=np.sqrt(dx[None,:]**2+dz[:,None]**2)
  np.minimum(field[c:d,a:b],local,out=field[c:d,a:b])
 return np.round(field/512*255).astype(np.uint8)
def smooth(a,b,x):
 y=np.clip((x-a)/(b-a),0,1);return y*y*(3-2*y)
mask=np.empty((N,N,4),dtype=np.uint8)
mask[:,:,0]=distance_field(layout['hardscape']);print('HARDSCAPE_MASK',len(layout['hardscape']),flush=True)
mask[:,:,1]=distance_field(layout['parcels']);print('PARCEL_MASK',len(layout['parcels']),flush=True)
river=(-1450+np.sin(xx/18/520)*115+np.sin(xx/18/1300)*65)*18
shore=np.abs(zz[:,None]-river[None,:])
damp=(1-smooth(1442,3842,shore))*smooth(-60750,-60250,xx)[None,:]*(1-smooth(73750,74250,xx))[None,:]
mask[:,:,2]=np.round(damp*255).astype(np.uint8)
del shore,damp
x,z,w,h=layout['airport'];edge=np.maximum(np.abs(xx[None,:]-(x+w/2))-w/2,np.abs(zz[:,None]-(z+h/2))-h/2)
mask[:,:,3]=np.round((1-smooth(-300,300,edge))*255).astype(np.uint8)
A.mkdir(exist_ok=True,parents=True);Image.fromarray(mask,'RGBA').save(A/'adelaide_ground_mask.png',optimize=True)
metadata={'bounds_m':[int(v) for v in [*origin,*size]],'size':[N,N],'distance_range_m':512,'channels':{'R':'nearest existing hardscape rectangle distance / 512; 0 inside','G':'nearest existing building parcel distance / 512; 0 inside','B':'riverbank dampness from actual river_z and bounds','A':'airport turf from actual airport reservation; 600m smooth transition'},'roads_hash':layout['roads_hash'],'buildings_hash':layout['buildings_hash'],'collision_hash':layout['collision_hash'],'parcels_hash':layout['parcels_hash'],'hardscape_count':len(layout['hardscape']),'parcel_count':len(layout['parcels'])}
(A/'ground_mask_metadata.json').write_text(json.dumps(metadata,indent=2))
(A/'ground_layout.json').write_text(json.dumps(layout,separators=(',',':')))
print("ADELAIDE_GROUND_MASK_READY",A)
