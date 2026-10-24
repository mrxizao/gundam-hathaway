from xi_glb_lib import *
from scipy.spatial import cKDTree
from copy import deepcopy
import collections
repo=Path(__file__).resolve().parents[3]
output=Path(__file__).resolve().parent/'output'
output.mkdir(exist_ok=True)
old=GLB(repo/'archive/hidden_models/xi_legacy_20261013/xi_fly_legacy_hidden.glb')
source=Path('C:/Users/MSIPC/Desktop/游戏/闪哈游戏/柯西与佩涅罗佩/柯西模型/柯西剧场版_最新模型与动画')
g=GLB(source/'03_巡航变形动画.glb');base=GLB(source/'01_基础模型.glb');j=deepcopy(g.j);data=bytearray(g.bin)
A=np.eye(4);A[:3,:3]=Rotation.from_euler('y',-90,degrees=True).as_matrix()*1.024;A[:3,3]=[0,0.520,-0.07]
oldids=old.j['skins'][0]['joints'];remap={n:i for i,n in enumerate(oldids)};og=old.globals();ng=g.globals();oldnames=[old.j['nodes'][n]['name'] for n in oldids]
verts=[];bones=[]
for i,n in enumerate(old.j['nodes']):
 if 'mesh' not in n:continue
 for prim in old.j['meshes'][n['mesh']]['primitives']:
  pos=old.acc(prim['attributes']['POSITION']);pos=pos@og[i][:3,:3].T+og[i][:3,3]
  js=old.acc(prim['attributes']['JOINTS_0']);ws=old.acc(prim['attributes']['WEIGHTS_0']);bi=js[np.arange(len(js)),ws.argmax(1)]
  verts.append(pos);bones.append(bi)
tree=cKDTree(np.concatenate(verts));labels=np.concatenate(bones)
# Keep the new parts rigid. Sampling nearby old surface labels establishes
# anatomy without relying on the unrelated tripo part numbering.
def anatomy(i):
 n=g.j['nodes'][i]
 if 'mesh'not in n:return oldnames.index('Chest')
 points_world=points(g,n,ng[i]);v=points_world@A[:3,:3].T+A[:3,3]
 _,near=tree.query(v[::max(1,len(v)//3000)])
 counts=np.bincount(labels[near],minlength=len(oldids));return int(counts.argmax())
assignment={i:anatomy(i) for i,n in enumerate(g.j['nodes']) if 'mesh'in n}
# Verified equipment assemblies: keep rifle, fingers and shield off leg/armor joints.
manual={'tripo_part_34':'Weapon.R','tripo_part_60':'Weapon.R','tripo_part_68':'Weapon.R','tripo_part_59':'Hand.R','tripo_part_63':'Hand.L','tripo_part_24':'LowerArm.R','tripo_part_65':'LowerArm.R','tripo_part_9':'LowerArm.L','tripo_part_37':'LowerArm.L','tripo_part_10':'LowerArm.L','tripo_part_2':'Thigh.L','tripo_part_4':'Thigh.R','tripo_part_7':'Thigh.R','tripo_part_14':'Thigh.L','tripo_part_30':'Thigh.L','tripo_part_46':'Thigh.R','tripo_part_51':'Thigh.R','tripo_part_58':'Thigh.L','tripo_part_104':'Thigh.L','tripo_part_108':'Thigh.L','tripo_part_109':'Thigh.R','tripo_part_36':'Foot.L'}
# Calf hardware must follow the shin, not the legacy rear launcher.
manual.update({name:'Shin.L' for name in ['tripo_part_28', 'tripo_part_66', 'tripo_part_73', 'tripo_part_84', 'tripo_part_86']})
# Runtime action audit: torso shells, inner arm, knee and shoulder connector.
manual.update({'tripo_part_17': 'Chest', 'tripo_part_38': 'Chest', 'tripo_part_43': 'UpperArm.L', 'tripo_part_72': 'Shin.R', 'tripo_part_107': 'Shoulder.L'})
for i,n in enumerate(g.j['nodes']):
 if n.get('name') in manual:assignment[i]=oldnames.index(manual[n['name']])

animated={ch['target']['node'] for ch in g.j['animations'][0]['channels']}
# Shoulder hardware follows shoulder/chest, never a nearby head or neck joint.
for i in animated:
 if i in assignment:
  assignment[i]=oldnames.index('Shoulder.L' if (A@ng[i])[0,3]>0 else 'Shoulder.R')
parents={child:i for i,n in enumerate(g.j['nodes']) for child in n.get('children',[])}
# Rigid wing children must follow their authored pivots even without own tracks.
for i in range(len(g.j['nodes'])):
 ancestor=parents.get(i)
 while ancestor is not None:
  if ancestor in animated: animated.add(i);break
  ancestor=parents.get(ancestor)
# All source animation nodes become extra joints, retaining their parent chains.
nodes=[]
for n in oldids:
 q=deepcopy(old.j['nodes'][n]);q.pop('mesh',None);q.pop('skin',None);q['children']=[remap[k] for k in q.get('children',[]) if k in remap];nodes.append(q)
movieids={i:len(nodes)+k for k,i in enumerate(sorted(animated))}
baseglob=[og[i] for i in oldids]+[A@ng[i] for i in sorted(animated)]
nodes.extend({} for _ in animated)
for i in sorted(animated):
 parent=movieids.get(parents.get(i),assignment.get(i,oldnames.index('Chest')))
 global_rest=A@ng[i]
 parent_rest=A@ng[parents[i]] if parents.get(i)in movieids else baseglob[parent]
 local=np.linalg.inv(parent_rest)@global_rest
 nodes[movieids[i]]={'name':'Movie_'+g.j['nodes'][i]['name'],'matrix':local.T.reshape(-1).tolist()}
for i in sorted(animated):
 parent=movieids.get(parents.get(i),assignment.get(i,oldnames.index('Chest')))
 nodes[parent].setdefault('children',[]).append(movieids[i])

def add(arr,kind,component=5126):
 arr=np.ascontiguousarray(arr,dtype={5126:'<f4',5123:'<u2'}[component]);data.extend(b'\0'*((-len(data))%4));off=len(data);data.extend(arr.tobytes());view=len(j['bufferViews']);j['bufferViews'].append({'buffer':0,'byteOffset':off,'byteLength':arr.nbytes});idx=len(j['accessors']);a={'bufferView':view,'componentType':component,'count':len(arr),'type':kind}
 if kind=='VEC3':a['min']=arr.min(0).tolist();a['max']=arr.max(0).tolist()
 if kind=='SCALAR':a['min']=[float(arr.min())];a['max']=[float(arr.max())]
 j['accessors'].append(a);return idx
meshes=[];mapping=[]
for i,n in enumerate(g.j['nodes']):
 if 'mesh'not in n:continue
 mesh=deepcopy(g.j['meshes'][n['mesh']]);xf=A@ng[i];joint=movieids.get(i,assignment[i]);mapping.append({'part':n['name'],'joint':nodes[joint]['name'],'vertices':sum(g.j['accessors'][p['attributes']['POSITION']]['count'] for p in mesh['primitives'])})
 for prim in mesh['primitives']:
  at=prim['attributes'];v=g.acc(at['POSITION']);v=v@xf[:3,:3].T+xf[:3,3];at['POSITION']=add(v,'VEC3')
  if 'NORMAL'in at:
   normals=g.acc(at['NORMAL'])@np.linalg.inv(xf[:3,:3]);normals/=np.maximum(np.linalg.norm(normals,axis=1)[:,None],1e-8);at['NORMAL']=add(normals,'VEC3')
  if 'TANGENT'in at:
   tangent=g.acc(at['TANGENT']);tangent[:,:3]=tangent[:,:3]@xf[:3,:3].T;tangent[:,:3]/=np.maximum(np.linalg.norm(tangent[:,:3],axis=1)[:,None],1e-8);at['TANGENT']=add(tangent,'VEC4')
  count=len(v);js=np.zeros((count,4),dtype=np.uint16);js[:,0]=joint;weights=np.zeros((count,4),dtype=np.float32);weights[:,0]=1
  if n['name'] in ['tripo_part_33_arm_preserved','tripo_part_5']:
   side='R' if n['name'].endswith('preserved') else 'L'
   upper=np.clip((v[:,1]-.535)/.08,0,1);hand=np.clip((.455-v[:,1])/.055,0,1);lower=(1-upper)*(1-hand)
   weights[:,:3]=np.column_stack([upper,lower,(1-upper)*hand]);js[:,0]=oldnames.index('UpperArm.'+side);js[:,1]=oldnames.index('LowerArm.'+side);js[:,2]=oldnames.index('Hand.'+side)
  if n['name'] in ['tripo_part_2','tripo_part_4','tripo_part_7','tripo_part_14','tripo_part_30','tripo_part_46']:
   side='L' if n['name'] in ['tripo_part_2','tripo_part_14','tripo_part_30'] else 'R'
   thigh=np.clip((v[:,1]-.28)/.065,0,1);foot=np.clip((.145-v[:,1])/.04,0,1)
   weights[:,:3]=np.column_stack([thigh,(1-thigh)*(1-foot),(1-thigh)*foot]);js[:,0]=oldnames.index('Thigh.'+side);js[:,1]=oldnames.index('Shin.'+side);js[:,2]=oldnames.index('Foot.'+side)
  at['JOINTS_0']=add(js,'VEC4',5123);at['WEIGHTS_0']=add(weights,'VEC4')
 meshes.append(mesh);nodes.append({'name':n['name'],'mesh':len(meshes)-1,'skin':0})
root=len(nodes);joint_count=len(oldids)+len(movieids);roots=[remap[n] for n in oldids if not any(n in old.j['nodes'][p].get('children',[]) for p in oldids)];nodes.append({'name':'Xi_Rig','children':roots+list(range(joint_count,root))})
j['nodes']=nodes;j['meshes']=meshes;j['scenes']=[{'name':'XiMovie20261013','nodes':[root]}];j['scene']=0
ib=np.array([np.linalg.inv(m).T.reshape(-1) for m in baseglob],dtype=np.float32);j['skins']=[{'name':'XiMovieCompatibleRig','joints':list(range(joint_count)),'inverseBindMatrices':add(ib,'MAT4')}]
# Bake supplied mechanical curves into the added joints; preserve rest stance.
def node_local(n):
 if 'matrix'in n:return np.array(n['matrix']).reshape(4,4).T
 m=np.eye(4);m[:3,:3]=Rotation.from_quat(n.get('rotation',[0,0,0,1])).as_matrix()@np.diag(n.get('scale',[1,1,1]));m[:3,3]=n.get('translation',[0,0,0]);return m
locals0=[node_local(n) for n in g.j['nodes']]
def globals_at(progress):
 local=[m.copy() for m in locals0]
 for ch in g.j['animations'][0]['channels']:
  sampler=g.j['animations'][0]['samplers'][ch['sampler']];times=g.acc(sampler['input']).ravel();values=g.acc(sampler['output']);tm=float(times[-1])*progress;k=min(np.searchsorted(times,tm,side='right')-1,len(times)-2);k=max(0,k);t=np.clip((tm-times[k])/max(times[k+1]-times[k],1e-8),0,1);node=ch['target']['node'];path=ch['target']['path']
  if path=='translation':local[node][:3,3]=values[k]*(1-t)+values[k+1]*t
  elif path=='rotation':
   from scipy.spatial.transform import Slerp
   local[node][:3,:3]=Slerp([0,1],Rotation.from_quat(values[k:k+2]))([t]).as_matrix()[0]
 cache={}
 def one(i):
  if i not in cache:cache[i]=(one(parents[i])if i in parents else np.eye(4))@local[i]
  return cache[i]
 return [one(i) for i in range(len(local))]
def bone_values(progress):
 gl=globals_at(progress);out=[]
 for bi in range(joint_count):
  if bi<len(oldids):out.append(node_local(nodes[bi]));continue
  original=sorted(animated)[bi-len(oldids)];parent=movieids.get(parents.get(original),assignment.get(original,oldnames.index('Chest')));par=A@gl[parents[original]] if parents.get(original)in movieids else baseglob[parent];out.append(np.linalg.inv(par)@A@gl[original])
 return out
anims=[]
for name,mode,length in [('fly',0,2.8),('cruise_idle',1,2.8),('form_on',2,0.4333333),('form_off',3,0.4333333),('cruise_on',2,0.4333333)]:
 times=np.linspace(0,length,29 if mode>1 else 2);frames=[bone_values((t/length if mode==2 else 1-t/length) if mode>1 else mode) for t in times];channels=[];samplers=[];timeacc=add(times.reshape(-1,1),'SCALAR')
 for bi in range(joint_count):
  mats=np.array([fr[bi] for fr in frames]);scales=np.linalg.norm(mats[:,:3,:3],axis=1);rot=mats[:,:3,:3]/scales[:,None,:];quats=Rotation.from_matrix(rot).as_quat()
  for k in range(1,len(quats)):
   if np.dot(quats[k-1],quats[k])<0:quats[k]*=-1
  for path,arr,typ in [('translation',mats[:,:3,3],'VEC3'),('rotation',quats,'VEC4'),('scale',scales,'VEC3')]:
   samplers.append({'input':timeacc,'output':add(arr,typ),'interpolation':'LINEAR'});channels.append({'sampler':len(samplers)-1,'target':{'node':bi,'path':path}})
 anims.append({'name':name,'channels':channels,'samplers':samplers})
j['animations']=anims;j['buffers']=[{'byteLength':len(data)}];raw=json.dumps(j,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);data.extend(b'\0'*((-len(data))%4));out=output/'xi_movie_rigged.glb';out.write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(raw)+8+len(data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(data),0x004e4942)+data)
(output/'xi_movie_mapping.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf-8');print('Generated',out.stat().st_size,'bytes',joint_count,'bones',len(meshes),'meshes');print(collections.Counter(v['joint']for v in mapping));print('WEAPON',[m for m in mapping if m['joint']in ['Weapon.R','Hand.R','Hand.L','Head']])
