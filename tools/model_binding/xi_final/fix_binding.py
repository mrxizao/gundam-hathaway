from xi_glb_lib import *
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
repo=Path(__file__).resolve().parents[3]
path=repo/'assets/models/xi_final/authoring_hidden/xi_final_rigged.glb'
g=GLB(path);j=g.j;data=bytearray(g.bin);old=g.globals();names={n['name']:i for i,n in enumerate(j['nodes'][:78])}
manual={
 'UpperArm.R':[169,204,205,207,208,209],
 'LowerArm.R':[25,26,42,43,44,121,122,135,190],
 'Hand.R':[28,29,191], 'Weapon.R':[24],
 'UpperArm.L':[81,183,184,185,186,187,188,189],
 'LowerArm.L':[37,38,39,40,41,68,70,71,73,117,139,140,141,10,11,12,13,14,15,16],
 'Hand.L':[108,109,111,156],
}
manual={f'tripo_part_{part}':names[bone] for bone,parts in manual.items()for part in parts}
parents={c:i for i,n in enumerate(j['nodes'])for c in n.get('children',[])}
def write(acc,arr):
 a=j['accessors'][acc];v=j['bufferViews'][a['bufferView']];offset=v.get('byteOffset',0)+a.get('byteOffset',0)
 raw=np.ascontiguousarray(arr,dtype={5126:'<f4',5123:'<u2',5125:'<u4'}[a['componentType']]).tobytes()
 data[offset:offset+len(raw)]=raw
for n in j['nodes']:
 if 'mesh'not in n:continue
 for prim in j['meshes'][n['mesh']]['primitives']:
  at=prim['attributes'];v=g.acc(at['POSITION']);ix=g.acc(prim['indices']).reshape(-1,3)
  _,weld=np.unique(np.round(v,6),axis=0,return_inverse=True);f=weld[ix];rows=f.reshape(-1);cols=np.roll(f,1,axis=1).reshape(-1)
  count,groups=connected_components(coo_matrix((np.ones(len(rows)),(rows,cols)),shape=(weld.max()+1,weld.max()+1)),directed=False);groups=groups[weld]
  sizes=np.bincount(groups);core=groups==sizes.argmax();js=g.acc(at['JOINTS_0']).copy()
  # Remove tiny detached export islands far from the part's real surface.
  lo=v[core].min(0);hi=v[core].max(0);keep=np.ones(len(v),dtype=bool)
  for group in np.unique(groups):
   if sizes[group]>=sizes.max()*0.05:continue
   mask=groups==group;island_lo=v[mask].min(0);island_hi=v[mask].max(0)
   gap=np.maximum(np.maximum(lo-island_hi,island_lo-hi),0)
   if np.linalg.norm(gap)>0.03:keep[mask]=False
  faces_kept=ix[keep[ix].all(axis=1)].reshape(-1,1)
  write(prim['indices'],faces_kept);j['accessors'][prim['indices']]['count']=len(faces_kept)

  # New shoulder shells are complete assemblies, not the donor's individually hinged panels.
  for bi in np.unique(js[:,0]):
   if j['nodes'][int(bi)]['name'].startswith('Movie_') and parents.get(int(bi)) in [names['Shoulder.L'],names['Shoulder.R']]:
    target=names['Movie_tripo_part_32'] if parents[int(bi)]==names['Shoulder.L'] else names['Movie_tripo_part_47']
    js[js[:,0]==bi,0]=target
  if n['name'] in manual:js[core,0]=manual[n['name']]
  write(at['JOINTS_0'],js)
  if n['name']=='tripo_part_24':
   palm=np.array([-.12,.406,.214]);points_core=v[core];closest=points_core[np.linalg.norm(points_core-palm,axis=1).argmin()]
   offset=palm-closest;v=v.copy();v[core]+=offset;write(at['POSITION'],v)
   print('Rifle grip translation',offset)
new=[m.copy()for m in old[:78]]
targets={
 'Movie_tripo_part_32':[.18,.79,.23], 'Movie_tripo_part_47':[-.18,.79,.23],
 'Movie_BackWingLeftRigidPivot':[.067,.84,-.045], 'Movie_BackWingRightRigidPivot':[-.07,.84,-.045],
 'UpperArm.R':[-.18,.79,.23], 'LowerArm.R':[-.17,.68,.22], 'Hand.R':[-.12,.43,.225],
 'UpperArm.L':[.18,.79,.23], 'LowerArm.L':[.19,.665,.235], 'Hand.L':[.11,.43,.225],
 'hand_R':[-.12,.406,.214], 'hand_L':[.125,.401,.21],
}
for bone,point in targets.items():new[names[bone]][:3,3]=point
deltas={}
for i in range(78):
 parent=parents.get(i)
 oldlocal=np.linalg.inv(old[parent])@old[i] if parent is not None else old[i]
 local=np.linalg.inv(new[parent])@new[i] if parent is not None and parent<78 else new[i]
 deltas[i]=local[:3,3]-oldlocal[:3,3]
 for field in ['translation','rotation','scale']:j['nodes'][i].pop(field,None)
 j['nodes'][i]['matrix']=local.T.reshape(-1).tolist()
write(j['skins'][0]['inverseBindMatrices'],np.stack([np.linalg.inv(m).T.reshape(-1)for m in new]))
for animation in j['animations']:
 for channel in animation['channels']:
  if channel['target']['path']!='translation':continue
  bone=channel['target']['node'];sampler=animation['samplers'][channel['sampler']]
  write(sampler['output'],g.acc(sampler['output'])+deltas[bone])
raw=json.dumps(j,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);data.extend(b'\0'*((-len(data))%4))
path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(raw)+len(data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(data),0x004e4942)+data)
(path.parent.parent/'manual_binding.json').write_text(json.dumps({'parts':manual,'pivots':targets},indent=2))
print('Corrected arm pivots, palms, rifle and complete shoulder assemblies')
