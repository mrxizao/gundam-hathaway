from xi_glb_lib import *
from scipy.spatial import cKDTree
from copy import deepcopy
import collections
repo=Path(__file__).resolve().parents[3]
output=repo/'assets/models/penelope_movie/authoring_hidden'
output.mkdir(exist_ok=True,parents=True)
old=GLB(repo/'archive/hidden_models/penelope_legacy_20261013/penelope_fly_legacy_hidden.glb')
source=Path(r'C:\Users\MSIPC\Desktop\游戏\闪哈游戏\柯西与佩涅罗佩\佩涅罗佩模型\佩涅罗佩重置\变形动画_20261013')
g=GLB(source/'佩涅罗佩_常态巡航变形.glb');j=deepcopy(g.j);data=bytearray(g.bin)
A=np.eye(4);A[:3,:3]=Rotation.from_euler('y',90,degrees=True).as_matrix()*1.0345;A[:3,3]=[0,0.499,0]
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
# Every mesh receives one rigid mechanical joint below its compatible anatomy.
# Source groups drive mechanics; canonical parents continue to drive combat.
parents={child:i for i,n in enumerate(g.j['nodes']) for child in n.get('children',[])}
for i,n in enumerate(g.j['nodes']):
 if 'mesh'not in n:continue
 v=points(g,n,ng[i]);c=(v.min(0)+v.max(0))/2; par=g.j['nodes'][parents[i]]['name']
 side='R' if c[2]>0 else 'L'
 if par.startswith('PENELOPE_'):
  tag=par.removeprefix('PENELOPE_')
  if tag in ['TAIL_OUTER','TAIL_INNER']:assignment[i]=oldnames.index('TailStab')
  elif tag in ['NOSE','NOSE_TRIM']:assignment[i]=oldnames.index('Head')
  elif tag in ['TOP_VANES','FLIGHT_ARMOR','ARMOR_LINK']:
   assignment[i]=oldnames.index('Backpack' if abs(c[2])<.06 else 'Shoulder.'+side)
  elif tag in ['ARMOR_LEFT','ARMOR_RIGHT']:
   assignment[i]=oldnames.index(('UpperArm.' if c[1]>.08 else ('LowerArm.' if c[1]>.015 else 'Hand.'))+side)
  elif tag.startswith('EQUIPMENT_STOW'):
   assignment[i]=oldnames.index('Hand.R')
  elif tag.startswith('LEG_') and tag!='LEG_TRIM':
   assignment[i]=oldnames.index(('Thigh.' if c[1]>-.18 else ('Foot.' if c[1]<-.36 else 'Shin.'))+side)
  elif tag.startswith('HIP_') or tag in ['CHEST_FLAPS','WAIST_LINK']:assignment[i]=oldnames.index('Hips')
  elif tag=='LEG_TRIM':assignment[i]=oldnames.index('Thigh.'+side)
# Exact original transform history is evaluated, but each part remains skinned once.
animated=set(assignment)
nodes=[]
for n in oldids:
 q=deepcopy(old.j['nodes'][n]);q.pop('mesh',None);q.pop('skin',None);q['children']=[remap[k] for k in q.get('children',[]) if k in remap];nodes.append(q)
movieids={i:len(nodes)+k for k,i in enumerate(sorted(animated))}
baseglob=[og[i] for i in oldids]+[A@ng[i] for i in sorted(animated)]
nodes.extend({} for _ in animated)
for i in sorted(animated):
 parent=assignment[i]
 local=np.linalg.inv(baseglob[parent])@A@ng[i]
 nodes[movieids[i]]={'name':'Movie_'+g.j['nodes'][i]['name'],'matrix':local.T.reshape(-1).tolist()}
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
  at['JOINTS_0']=add(js,'VEC4',5123);at['WEIGHTS_0']=add(weights,'VEC4')
 meshes.append(mesh);nodes.append({'name':n['name'],'mesh':len(meshes)-1,'skin':0})
root=len(nodes);joint_count=len(oldids)+len(movieids);roots=[remap[n] for n in oldids if not any(n in old.j['nodes'][p].get('children',[]) for p in oldids)];nodes.append({'name':'PEN_RIG','children':roots+list(range(joint_count,root))})
j['nodes']=nodes;j['meshes']=meshes;j['scenes']=[{'name':'PenelopeMovie20261013','nodes':[root]}];j['scene']=0
ib=np.array([np.linalg.inv(m).T.reshape(-1) for m in baseglob],dtype=np.float32);j['skins']=[{'name':'PenelopeMovieCompatibleRig','joints':list(range(joint_count)),'inverseBindMatrices':add(ib,'MAT4')}]
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
  original=sorted(animated)[bi-len(oldids)];parent=movieids.get(parents.get(original),assignment.get(original,oldnames.index('Chest')));par=baseglob[assignment[original]];out.append(np.linalg.inv(par)@A@gl[original])
 return out
anims=[]
for name,mode,length in [('fly',0,2.8),('cruise_idle',1,2.8),('form_on',2,0.65),('form_off',3,0.65),('cruise_on',2,0.65)]:
 times=np.linspace(0,length,145 if mode>1 else 2);frames=[bone_values((t/length if mode==2 else 1-t/length) if mode>1 else mode) for t in times];channels=[];samplers=[];timeacc=add(times.reshape(-1,1),'SCALAR')
 for bi in range(joint_count):
  mats=np.array([fr[bi] for fr in frames]);scales=np.linalg.norm(mats[:,:3,:3],axis=1);rot=mats[:,:3,:3]/scales[:,None,:];quats=Rotation.from_matrix(rot).as_quat()
  for k in range(1,len(quats)):
   if np.dot(quats[k-1],quats[k])<0:quats[k]*=-1
  for path,arr,typ in [('translation',mats[:,:3,3],'VEC3'),('rotation',quats,'VEC4'),('scale',scales,'VEC3')]:
   samplers.append({'input':timeacc,'output':add(arr,typ),'interpolation':'LINEAR'});channels.append({'sampler':len(samplers)-1,'target':{'node':bi,'path':path}})
 anims.append({'name':name,'channels':channels,'samplers':samplers})
j['animations']=anims;j['buffers']=[{'byteLength':len(data)}];raw=json.dumps(j,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);data.extend(b'\0'*((-len(data))%4));out=output/'penelope_movie_rigged.glb';out.write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(raw)+8+len(data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(data),0x004e4942)+data)
(output/'penelope_movie_mapping.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf-8');print('Generated',out.stat().st_size,'bytes',joint_count,'bones',len(meshes),'meshes');print(collections.Counter(v['joint']for v in mapping));print('WEAPON',[m for m in mapping if m['joint']in ['Weapon.R','Hand.R','Hand.L','Head']])
