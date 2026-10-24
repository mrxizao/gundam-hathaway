from pathlib import Path
from copy import deepcopy
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from xi_glb_lib import *

repo=Path(__file__).resolve().parents[3]
dest=repo/'assets/models/xi_final/authoring_hidden'
dest.mkdir(parents=True,exist_ok=True)
(dest/'.gdignore').write_text('')
source=Path('C:/Users/MSIPC/Desktop/游戏/闪哈游戏/柯西与佩涅罗佩/柯西模型/柯西（最终决战样式）.glb')
g=GLB(source); donor=GLB(repo/'assets/models/xi_movie/authoring_hidden/xi_movie_rigged.glb')
j=deepcopy(g.j);data=bytearray(g.bin);dg=donor.globals();gg=g.globals()
A=np.eye(4);A[:3,:3]=Rotation.from_euler('y',-90,degrees=True).as_matrix()*1.024;A[:3,3]=[0,.520,-.07]
verts=[];labels=[]
for i,n in enumerate(donor.j['nodes']):
 if 'mesh' not in n:continue
 for prim in donor.j['meshes'][n['mesh']]['primitives']:
  valid=np.unique(donor.acc(prim['indices']).reshape(-1)) if 'indices'in prim else np.arange(len(donor.acc(prim['attributes']['POSITION'])))
  v=donor.acc(prim['attributes']['POSITION'])[valid];v=v@dg[i][:3,:3].T+dg[i][:3,3]
  js=donor.acc(prim['attributes']['JOINTS_0'])[valid];ws=donor.acc(prim['attributes']['WEIGHTS_0'])[valid]
  verts.append(v);labels.append(js[np.arange(len(v)),ws.argmax(1)])
tree=cKDTree(np.concatenate(verts));labels=np.concatenate(labels)
# Append donor animation/bind buffers without changing source textures/materials.
data.extend(b'\0'*((-len(data))%4));offset=len(data);data.extend(donor.bin)
viewbase=len(j['bufferViews']);accbase=len(j['accessors'])
for view in donor.j['bufferViews']:
 v=deepcopy(view);v['buffer']=0;v['byteOffset']=v.get('byteOffset',0)+offset;j['bufferViews'].append(v)
for accessor in donor.j['accessors']:
 a=deepcopy(accessor)
 if 'bufferView'in a:a['bufferView']+=viewbase
 j['accessors'].append(a)
nodes=deepcopy(donor.j['nodes'][:78])
for n in nodes:n['children']=[c for c in n.get('children',[])if c<78]
def add(arr,kind,component=5126):
 arr=np.ascontiguousarray(arr,dtype={5126:'<f4',5123:'<u2',5125:'<u4',5121:'u1'}[component]);data.extend(b'\0'*((-len(data))%4));off=len(data);data.extend(arr.tobytes())
 view=len(j['bufferViews']);j['bufferViews'].append({'buffer':0,'byteOffset':off,'byteLength':arr.nbytes})
 idx=len(j['accessors']);a={'bufferView':view,'componentType':component,'count':len(arr),'type':kind}
 if kind=='VEC3':a.update(min=arr.min(0).tolist(),max=arr.max(0).tolist())
 j['accessors'].append(a);return idx
mapping=[];meshes=[]
semantic_groups={}
for n in g.j['nodes']:
 if n.get('name')in ['RearWingLeftAligned','RearWingRightAligned','TailAligned']:
  chosen={'RearWingLeftAligned':76,'RearWingRightAligned':77,'TailAligned':7}[n['name']]
  for child in n['children']:semantic_groups[child]=chosen
for i,n in enumerate(g.j['nodes']):
 if 'mesh'not in n:continue
 mesh=deepcopy(g.j['meshes'][n['mesh']]);xf=A@gg[i]
 parts=[]
 for prim in mesh['primitives']:
  raw=g.acc(prim['attributes']['POSITION']);valid=np.unique(g.acc(prim['indices']).reshape(-1)) if 'indices'in prim else np.arange(len(raw));parts.append(raw[valid]@xf[:3,:3].T+xf[:3,3])
 v=np.concatenate(parts);_,near=tree.query(v[::max(1,len(v)//2000)]);counts=np.bincount(labels[near].astype(int),minlength=78);joint=int(counts.argmax())
 mapping.append({'part':n['name'],'joint':nodes[joint]['name'],'joint_index':joint,'center':v.mean(0).tolist()})
 for prim in mesh['primitives']:
  at=prim['attributes'];raw=g.acc(at['POSITION']);indices=g.acc(prim['indices']).reshape(-1) if 'indices'in prim else np.arange(len(raw));valid,inverse=np.unique(indices,return_inverse=True)
  prim['indices']=add(inverse.reshape(-1,1),'SCALAR',5125)
  for name,accessor in list(at.items()):
   if name not in ['POSITION','NORMAL','TANGENT']:
    info=g.j['accessors'][accessor];at[name]=add(g.acc(accessor)[valid],info['type'],info['componentType'])
  v=raw[valid];v=v@xf[:3,:3].T+xf[:3,3];at['POSITION']=add(v,'VEC3')
  if 'NORMAL'in at:
   norm=g.acc(at['NORMAL'])[valid]@np.linalg.inv(xf[:3,:3]);norm/=np.maximum(np.linalg.norm(norm,axis=1)[:,None],1e-8);at['NORMAL']=add(norm,'VEC3')
  if 'TANGENT'in at:
   tangent=g.acc(at['TANGENT'])[valid];tangent[:,:3]=tangent[:,:3]@xf[:3,:3].T;tangent[:,:3]/=np.maximum(np.linalg.norm(tangent[:,:3],axis=1)[:,None],1e-8);at['TANGENT']=add(tangent,'VEC4')
  # Bind disconnected export fragments independently; a part can contain distant islands.
  _,weld=np.unique(np.round(v,6),axis=0,return_inverse=True);faces=weld[inverse.reshape(-1,3)]
  rows=faces.reshape(-1);cols=np.roll(faces,1,axis=1).reshape(-1)
  count,groups=connected_components(coo_matrix((np.ones(len(rows)),(rows,cols)),shape=(weld.max()+1,weld.max()+1)),directed=False)
  groups=groups[weld]
  order=np.argsort(groups,kind="stable");sizes=np.bincount(groups,minlength=count);ends=np.cumsum(sizes);starts=ends-sizes
  selection=np.concatenate([order[np.arange(start,end,max(1,int(np.ceil((end-start)/256))))]for start,end in zip(starts,ends)if end>start])
  _,near=tree.query(v[selection],workers=-1);nearest=labels[near].astype(int)
  js=np.zeros((len(v),4),dtype=np.uint16)
  votes=np.bincount(groups[selection]*78+nearest,minlength=count*78).reshape(count,78)
  js[:,0]=votes.argmax(axis=1)[groups]
  if i in semantic_groups:js[:,0]=semantic_groups[i]
  w=np.zeros((len(v),4),dtype=np.float32);w[:,0]=1
  at['JOINTS_0']=add(js,'VEC4',5123);at['WEIGHTS_0']=add(w,'VEC4')
 nodes.append({'name':n['name'],'mesh':len(meshes),'skin':0});meshes.append(mesh)
j['meshes']=meshes;j['nodes']=nodes+[{'name':'Xi_Rig','children':[0]+list(range(78,len(nodes)))}];j['scenes']=[{'name':'XiFinal','nodes':[len(nodes)]}];j['scene']=0
j['skins']=deepcopy(donor.j['skins']);j['skins'][0]['inverseBindMatrices']+=accbase
j['animations']=deepcopy(donor.j['animations'])
for anim in j['animations']:
 for sampler in anim['samplers']:sampler['input']+=accbase;sampler['output']+=accbase
j['buffers']=[{'byteLength':len(data)}];raw=json.dumps(j,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);data.extend(b'\0'*((-len(data))%4))
(dest/'xi_final_rigged.glb').write_bytes(struct.pack('<III',0x46546c67,2,28+len(raw)+len(data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(data),0x004e4942)+data)
(dest.parent/'part_bindings.json').write_text(json.dumps(mapping,ensure_ascii=False,indent=2),encoding='utf-8')
print('Built',len(meshes),'parts / 78 bones')
