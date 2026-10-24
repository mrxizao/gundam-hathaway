"""Project-authored technical PBR atlas. Offline only; requires NumPy and Pillow.
python tools/bake_adelaide_trim.py [output-directory]
"""
from pathlib import Path
import sys,numpy as np
from PIL import Image
out=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent.parent/'assets/materials/adelaide_pbr'
out.mkdir(parents=True,exist_ok=True)
cols=np.array([[.60,.62,.61],[.34,.39,.41],[.09,.105,.115],[.43,.46,.46],[.54,.52,.47],[.22,.27,.29],[.40,.43,.44],[.18,.20,.21]])
rng=np.random.default_rng(20261016);height=2048;width=2048;y,x=np.mgrid[:height,:width];row=y//256;v=(y%256)/255.0;u=x/2048.0
grain=rng.normal(0,.008,(height,width));groove=np.exp(-((v-.13)/.018)**2)+np.exp(-((v-.87)/.018)**2)
hfield=.003*grain-.045*groove
rgb=np.clip(cols[row]*(1+grain[:,:,None]*1.5-groove[:,:,None]*.10),0,1)
dy,dx=np.gradient(hfield);nx=-dx*18;ny=dy*18;nz=np.ones_like(nx);norm=np.sqrt(nx*nx+ny*ny+nz*nz)
normal=np.stack([nx/norm,ny/norm,nz/norm],-1)*.5+.5
orm=np.stack([np.clip(1-.13*groove,0,1),np.take(np.array([.87,.63,.96,.78,.88,.71,.75,.92]),row),np.take(np.array([0,.45,0,.12,0,.35,.22,0]),row)],-1)
for suffix,data in [('diff',rgb),('nor_gl',normal),('arm',orm)]:Image.fromarray(np.rint(data*255).astype('uint8')).save(out/f'adelaide_trim_atlas_{suffix}_2k.png',optimize=True)
print('ADELAIDE_TRIM_ATLAS_REBUILT',out)
