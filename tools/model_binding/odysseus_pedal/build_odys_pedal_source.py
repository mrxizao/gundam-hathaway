from pathlib import Path
from copy import deepcopy
import sys,json,struct,numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from xi_glb_lib import GLB
src=Path(r'C:\Users\MSIPC\Desktop\游戏\闪哈游戏\柯西与佩涅罗佩\佩涅罗佩模型\佩涅罗佩重置')
a=GLB(src/'奥德修斯搭载飞行踏板.glb');b=GLB(src/'佩涅罗佩模型2.0.glb');j=deepcopy(a.j);data=bytearray(a.bin)
while len(data)%4:data.append(0)
offset=len(data);data.extend(b.bin)
offs={k:len(j.get(k,[])) for k in ['bufferViews','accessors','images','samplers','textures','materials','meshes']}
for v in b.j['bufferViews']:
 v=deepcopy(v);v['byteOffset']=v.get('byteOffset',0)+offset;j.setdefault('bufferViews',[]).append(v)
for v in b.j['accessors']:
 v=deepcopy(v)
 if 'bufferView'in v:v['bufferView']+=offs['bufferViews']
 j.setdefault('accessors',[]).append(v)
for v in b.j.get('images',[]):
 v=deepcopy(v)
 if 'bufferView'in v:v['bufferView']+=offs['bufferViews']
 j.setdefault('images',[]).append(v)
j.setdefault('samplers',[]).extend(deepcopy(b.j.get('samplers',[])))
for v in b.j.get('textures',[]):
 v=deepcopy(v)
 if 'source'in v:v['source']+=offs['images']
 if 'sampler'in v:v['sampler']+=offs['samplers']
 j.setdefault('textures',[]).append(v)
def textures(v):
 if isinstance(v,dict):
  for k,x in v.items():
   if k.endswith('Texture') and isinstance(x,dict) and 'index'in x:x['index']+=offs['textures']
   else:textures(x)
 elif isinstance(v,list):
  for x in v:textures(x)
for v in b.j.get('materials',[]):
 v=deepcopy(v);textures(v);j.setdefault('materials',[]).append(v)
rifle=next(i for i,n in enumerate(b.j['nodes']) if n.get('name')=='tripo_part_11')
mesh=deepcopy(b.j['meshes'][b.j['nodes'][rifle]['mesh']])
for p in mesh['primitives']:
 p['attributes']={k:v+offs['accessors'] for k,v in p['attributes'].items()}
 if 'indices'in p:p['indices']+=offs['accessors']
 if 'material'in p:p['material']+=offs['materials']
mi=len(j['meshes']);j['meshes'].append(mesh)
# Match the donor hand already gripping this rifle to the recipient palm.
# The recipient mesh includes a long wrist cuff; only the lower fist is the grip.
from xi_glb_lib import points
old_hand=next(i for i,n in enumerate(b.j['nodes']) if n.get('name')=='tripo_part_162')
new_hand=next(i for i,n in enumerate(a.j['nodes']) if n.get('name')=='tripo_part_42.002')
donor=points(b,b.j['nodes'][old_hand],b.globals()[old_hand]).mean(0)
fingers=points(a,a.j['nodes'][new_hand],a.globals()[new_hand])
palm_id=next(i for i,n in enumerate(a.j['nodes']) if n.get('name')=='tripo_part_18.002')
fist=points(a,a.j['nodes'][palm_id],a.globals()[palm_id]);palm=(fist[(fist[:,1]>fist[:,1].min())&(fist[:,1]<fist[:,1].min()+.045)].mean(0)+fingers.mean(0))/2
xf=b.globals()[rifle];xf[:3,:3]*=.9;xf[:3,3]=xf[:3,3]*.9+palm-donor*.9
print('GRIP',donor,'to',palm,'offset',palm-donor)
xf=np.linalg.inv(a.globals()[289])@xf
ni=len(j['nodes']);j['nodes'].append({'name':'Penelope_Rifle','mesh':mi,'matrix':xf.T.flatten().tolist()})
j['nodes'][289]['children'].append(ni)
j['buffers']=[{'byteLength':len(data)}]
raw=json.dumps(j,separators=(',',':')).encode();raw+=b' '*(-len(raw)%4);data.extend(b'\0'*(-len(data)%4))
out=Path('work/gundam_odysseus_pedal/assets/models/odysseus_pedal/authoring_hidden/odysseus_pedal.glb');out.write_bytes(struct.pack('<III',0x46546c67,2,28+len(raw)+len(data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(data),0x004e4942)+data)
print(out)
