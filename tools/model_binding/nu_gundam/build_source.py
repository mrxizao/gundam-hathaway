"""Preserve the supplied RX-93 assembly and build a rigid combat skeleton."""
from pathlib import Path
import sys, json, struct, hashlib
from copy import deepcopy
from io import BytesIO
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/model_binding/penelope_movie'))
from xi_glb_lib import GLB, points, Rotation
OUT=Path(r'C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/work/nu_asset_build')
OUT.mkdir(parents=True,exist_ok=True)
source=GLB(Path(r'D:/牛高达/完成版本体.glb'))
floating=GLB(Path(r'D:/牛高达/浮游炮2.glb'))
donor=GLB(ROOT/'assets/models/odysseus/authoring_hidden/odysseus_rigged.glb')
oldids=donor.j['skins'][0]['joints'][:39];oldglob=donor.globals()
names=[donor.j['nodes'][i]['name'] for i in oldids]
parents={c:i for i,n in enumerate(donor.j['nodes']) for c in n.get('children',[])}
A=np.eye(4);A[:3,:3]=Rotation.from_euler('y',90,degrees=True).as_matrix();A[:3,3]=[0,.489,0]
def cv(p):return A[:3,:3]@np.array(p)+A[:3,3]
raw_positions={'Hips':[0,0,-.07],'Spine':[.01,.12,-.07],'Chest':[.02,.23,-.07],
 'Backpack':[-.08,.25,-.07],'Neck':[.05,.31,-.06],'Head':[.07,.38,-.06],
 'Shoulder.R':[.04,.31,.10],'UpperArm.R':[.055,.275,.10],
 'LowerArm.R':[.065,.18,.12],'Hand.R':[.075,.045,.12],
 'Shoulder.L':[.04,.31,-.21],'UpperArm.L':[.055,.275,-.21],
 'LowerArm.L':[.065,.18,-.24],'Hand.L':[.075,.045,-.24],
 'Thigh.R':[0,-.07,.08],'Shin.R':[0,-.25,.08],'Foot.R':[.04,-.43,.08],'Toe.R':[.12,-.455,.08],
 'Thigh.L':[0,-.07,-.22],'Shin.L':[0,-.25,-.22],'Foot.L':[.04,-.43,-.22],'Toe.L':[.12,-.455,-.22]}
globals_new=[];nodes=[]
for k,i in enumerate(oldids):
 n=donor.j['nodes'][i];pa=parents.get(i);parent=oldids.index(pa) if pa in oldids else -1
 p=cv(raw_positions[n['name']]) if n['name'] in raw_positions else (globals_new[parent][:3,3]+oldglob[i][:3,3]-oldglob[pa][:3,3] if parent>=0 else oldglob[i][:3,3])
 m=np.eye(4);m[:3,3]=p;globals_new.append(m)
 local=m if parent<0 else np.linalg.inv(globals_new[parent])@m
 nodes.append({'name':n['name'],'translation':local[:3,3].tolist(),'children':[]})
 if parent>=0:nodes[parent]['children'].append(k)
docks=[list(range(53,59)),list(range(75,81)),list(range(60,66)),[86,87,88,94,96,97,98,100],list(range(67,73)),[89,90,91,92,95,99]]
gg=source.globals();bounds={}
for i,n in enumerate(source.j['nodes']):
 if 'mesh'in n:
  v=points(source,n,gg[i]);v=v@A[:3,:3].T+A[:3,3];bounds[i]=(v.min(0),v.max(0))
def add_bone(name,parent,position):
 index=len(nodes);parent=names.index(parent);m=np.eye(4);m[:3,3]=position
 nodes.append({'name':name,'translation':(position-globals_new[parent][:3,3]).tolist()})
 nodes[parent]['children'].append(index);names.append(name);globals_new.append(m);return index
add_bone('NuRifle','Hand.R',globals_new[names.index('Hand.R')][:3,3])
add_bone('NuShield','LowerArm.L',globals_new[names.index('LowerArm.L')][:3,3])
add_bone('NuBazooka','Backpack',cv([-.14,.10,-.066]))
for k,group in enumerate(docks):
 lo=np.min([bounds[i][0] for i in group],0);hi=np.max([bounds[i][1] for i in group],0)
 add_bone('NuDock'+str(k),'Backpack',(lo+hi)/2)
anatomy={
 'Hips':[0,8,9,10,14,15,17,19,20,32], 'Chest':[1,42,43,45,47,48,49,50,51],
 'Backpack':[11,16,23,28,34], 'Head':[85,93], 'Shoulder.R':[7], 'Shoulder.L':[4],
 'UpperArm.R':[40,41], 'UpperArm.L':[39,30], 'LowerArm.R':[18,29,44],
 'LowerArm.L':[12,22,46], 'Hand.R':[21], 'Hand.L':[38],
 'Thigh.R':[25,27,31], 'Thigh.L':[26,33,37], 'Foot.R':[5,13,36], 'Foot.L':[6,24,35],
 'NuRifle':[83], 'NuShield':[82], 'NuBazooka':[84]}
binding={i:names.index(name) for name,ids in anatomy.items() for i in ids}
for k,group in enumerate(docks):
 for i in group:binding[i]=names.index('NuDock'+str(k))
class Writer:
 def __init__(self,g):
  self.g=g;self.data=bytearray();self.j={'asset':{'version':'2.0','generator':'RX93 rigid assembly'},'bufferViews':[],'accessors':[],'meshes':[],'nodes':[], 'scene':0}
  for field in ['materials','textures','samplers','extensionsUsed','extensionsRequired']: 
   if field in g.j:self.j[field]=deepcopy(g.j[field])
  self.j['images']=[];cache={}
  for image in g.j.get('images',[]):
   view=g.j['bufferViews'][image['bufferView']];start=view.get('byteOffset',0);raw=g.bin[start:start+view['byteLength']]
   im=Image.open(BytesIO(raw));im.thumbnail((1024,1024));buf=BytesIO();im.save(buf,format='PNG',optimize=True);raw=buf.getvalue();key=hashlib.sha256(raw).hexdigest()
   if key not in cache:cache[key]=self.view(raw)
   self.j['images'].append({'bufferView':cache[key],'mimeType':'image/png'})
 def view(self,raw):
  self.data.extend(b'\0'*((-len(self.data))%4));off=len(self.data);self.data.extend(raw);idx=len(self.j['bufferViews']);self.j['bufferViews'].append({'buffer':0,'byteOffset':off,'byteLength':len(raw)});return idx
 def acc(self,arr,kind,comp=5126):
  arr=np.ascontiguousarray(arr,dtype={5126:'<f4',5123:'<u2',5125:'<u4',5121:'u1'}[comp]);idx=len(self.j['accessors']);v={'bufferView':self.view(arr.tobytes()),'componentType':comp,'count':len(arr),'type':kind}
  if kind=='VEC3':v['min']=arr.min(0).tolist();v['max']=arr.max(0).tolist()
  self.j['accessors'].append(v);return idx
 def mesh(self,index,xf,bone=None,name=None):
  n=self.g.j['nodes'][index];mesh=deepcopy(self.g.j['meshes'][n['mesh']]);mesh['name']=name or n['name']
  for pr in mesh['primitives']:
   attrs=pr['attributes'];count=self.g.j['accessors'][attrs['POSITION']]['count']
   for key,accessor in list(attrs.items()):
    a=self.g.j['accessors'][accessor];arr=self.g.acc(accessor)
    if key=='POSITION':arr=arr@xf[:3,:3].T+xf[:3,3]
    elif key=='NORMAL':arr=arr@np.linalg.inv(xf[:3,:3]);arr/=np.maximum(np.linalg.norm(arr,axis=1)[:,None],1e-8)
    elif key=='TANGENT':arr[:,:3]=arr[:,:3]@xf[:3,:3].T;arr[:,:3]/=np.maximum(np.linalg.norm(arr[:,:3],axis=1)[:,None],1e-8)
    attrs[key]=self.acc(arr,a['type'],a['componentType'])
   if 'indices'in pr:pr['indices']=self.acc(self.g.acc(pr['indices']),'SCALAR',5125)
   if bone is not None:
    js=np.zeros((count,4),dtype=np.uint16);js[:,0]=bone;weights=np.zeros((count,4),dtype=np.float32);weights[:,0]=1
    # Two supplied leg casings span the knee; preserve their continuous surfaces.
    if index in [2,3]:
     v=self.g.acc(prior_position[index]);rawy=(v@gg[index][:3,:3].T+gg[index][:3,3])[:,1]
     side='L' if index==2 else 'R';thigh=np.clip((rawy+.23)/.08,0,1);foot=np.clip((-.37-rawy)/.08,0,1)
     js[:,0]=names.index('Thigh.'+side);js[:,1]=names.index('Shin.'+side);js[:,2]=names.index('Foot.'+side)
     weights[:,:3]=np.column_stack([thigh,(1-thigh)*(1-foot),(1-thigh)*foot])
    attrs['JOINTS_0']=self.acc(js,'VEC4',5123);attrs['WEIGHTS_0']=self.acc(weights,'VEC4')
  idx=len(self.j['meshes']);self.j['meshes'].append(mesh);return idx
 def save(self,path):
  self.j['buffers']=[{'byteLength':len(self.data)}];raw=json.dumps(self.j,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);self.data.extend(b'\0'*((-len(self.data))%4))
  path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(raw)+len(self.data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(self.data),0x004e4942)+self.data)
prior_position={i:source.j['meshes'][n['mesh']]['primitives'][0]['attributes']['POSITION'] for i,n in enumerate(source.j['nodes']) if 'mesh'in n}
w=Writer(source);w.j['nodes']=deepcopy(nodes);count=len(nodes);mapping=[]
for i,n in enumerate(source.j['nodes']):
 if 'mesh'not in n:continue
 bone=binding.get(i,names.index('Chest'));name=names[bone]+'_'+n['name']
 mesh=w.mesh(i,A@gg[i],bone,name);w.j['nodes'].append({'name':name,'mesh':mesh,'skin':0});mapping.append({'source':i,'name':name,'bone':names[bone]})
w.j['skins']=[{'joints':list(range(count)),'inverseBindMatrices':w.acc(np.array([np.linalg.inv(m).T.reshape(-1) for m in globals_new]),'MAT4')}]
root=len(w.j['nodes']);w.j['nodes'].append({'name':'RX93_NU_GUNDAM','children':[0]+list(range(count,root))});w.j['scenes']=[{'nodes':[root]}];w.save(OUT/'nu_rigged.glb')
for k,group in enumerate(docks):
 f=Writer(floating);fg=floating.globals();chosen=[]
 for i in group:
  name=source.j['nodes'][i]['name'];chosen.extend(j for j,n in enumerate(floating.j['nodes']) if n.get('name')==name and 'mesh'in n)
 cloud=np.concatenate([points(floating,floating.j['nodes'][i],fg[i]) for i in chosen]);lo=cloud.min(0);hi=cloud.max(0);center=(lo+hi)/2
 xf=np.eye(4);xf[:3,:3]=np.eye(3)*(.40/max(hi-lo));xf[:3,3]=-center*(.40/max(hi-lo))
 for i in chosen:f.j['nodes'].append({'name':floating.j['nodes'][i]['name'],'mesh':f.mesh(i,xf@fg[i])})
 f.j['scenes']=[{'nodes':list(range(len(f.j['nodes'])))}];f.save(OUT/f'fin_{k}.glb')
metadata={'bones':names,'parts':mapping,'dock_groups':docks,'body_native_height':.935,'head':cv([.07,.38,-.06]).tolist(),
 'rifle_muzzle':cv([.215,-.339,.112]).tolist(),'bazooka_muzzle':cv([-.14,-.44,-.066]).tolist()}
(OUT/'metadata.json').write_text(json.dumps(metadata,indent=2),encoding='utf8')
print('Built rigid RX-93:',len(mapping),'parts,',count,'bones and six supplied fin models.',flush=True)
