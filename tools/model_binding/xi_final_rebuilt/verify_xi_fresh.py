from xi_glb_lib import *
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
s=GLB('C:/Users/MSIPC/Desktop/游戏/闪哈游戏/柯西与佩涅罗佩/柯西模型/柯西（最终决战样式）.glb');d=GLB('work/gundam_arizeus_v2/assets/models/xi_final_rebuilt/authoring_hidden/xi_final_fresh_rig.glb');sg=s.globals();dn={n['name']:n for n in d.j['nodes'] if 'mesh'in n};A=np.eye(4);A[:3,:3]=Rotation.from_euler('y',-90,degrees=True).as_matrix()*1.024;A[:3,3]=[0,.52,-.07];removed=0;error=0;triangles=0
for ni,n in enumerate(s.j['nodes']):
 if 'mesh'not in n:continue
 assert n['name']in dn
 for a,b in zip(s.j['meshes'][n['mesh']]['primitives'],d.j['meshes'][dn[n['name']]['mesh']]['primitives']):
  v=s.acc(a['attributes']['POSITION']);target=points(s,{'mesh':n['mesh']},sg[ni]) if len(s.j['meshes'][n['mesh']]['primitives'])==1 else v@sg[ni][:3,:3].T+sg[ni][:3,3];target=target@A[:3,:3].T+A[:3,3];actual=d.acc(b['attributes']['POSITION']);error=max(error,float(np.max(np.abs(target-actual))));ix=s.acc(a['indices']).reshape(-1,3)
  if n['name']in ['tripo_part_89','tripo_part_90']:
   _,w=np.unique(np.round(target,6),axis=0,return_inverse=True);faces=w[ix];r=faces.reshape(-1);c=np.roll(faces,1,axis=1).reshape(-1);_,groups=connected_components(coo_matrix((np.ones(len(r)),(r,c)),shape=(w.max()+1,w.max()+1)),directed=False);groups=groups[w];core=np.bincount(groups[np.unique(ix)]).argmax();keep=~np.any(groups[ix]==core,axis=1);removed+=int(np.count_nonzero(~keep));ix=ix[keep]
  assert np.array_equal(ix,d.acc(b['indices']).reshape(-1,3)),n['name']
  triangles+=len(ix)
assert removed==3889
report=dict(meshes=len(dn),triangles=triangles,max_vertex_error=error,deleted_meshes=0,deleted_triangles=removed,only_authorized_primary_components_removed=True)
Path('work/xi_fresh_integrity.json').write_text(json.dumps(report,indent=2));print(report)
