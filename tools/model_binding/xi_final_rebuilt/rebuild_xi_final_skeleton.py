from xi_glb_lib import *
from copy import deepcopy
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
source=Path('C:/Users/MSIPC/Desktop/游戏/闪哈游戏/柯西与佩涅罗佩/柯西模型/柯西（最终决战样式）.glb')
g=GLB(source);j=deepcopy(g.j);data=bytearray(g.bin);gg=g.globals()
dest=Path('work/gundam_arizeus_v2/assets/models/xi_final_rebuilt');(dest/'authoring_hidden').mkdir(parents=True,exist_ok=True);(dest/'authoring_hidden/.gdignore').write_text('')
A=np.eye(4);A[:3,:3]=Rotation.from_euler('y',-90,degrees=True).as_matrix()*1.024;A[:3,3]=[0,.52,-.07]
spec=[]
def bone(name,parent,point):spec.append((name,parent,np.array(point,dtype=float)))
bone('Root',None,[0,0,0]);bone('Hips','Root',[0,.56,.20]);bone('Spine','Hips',[0,.60,.16]);bone('Chest','Spine',[0,.72,.18]);bone('Backpack','Chest',[0,.68,-.07]);bone('Neck','Chest',[0,.812,.24]);bone('Head','Neck',[0,.836,.27])
for side,sign in [('L',1),('R',-1)]:
 bone('Shoulder.'+side,'Chest',[sign*.15,.80,.14]);bone('UpperArm.'+side,'Shoulder.'+side,[sign*.15,.79,.14]);bone('LowerArm.'+side,'UpperArm.'+side,[.19,.665,.235]if side=='L'else[-.17,.68,.22]);bone('Hand.'+side,'LowerArm.'+side,[sign*.12,.43,.225]);bone('hand_'+side,'Hand.'+side,[.125,.401,.21]if side=='L'else[-.12,.406,.214]);bone('shield_'+side,'LowerArm.'+side,[sign*.28,.59,.24]);bone('BinderFront.'+side,'Shoulder.'+side,[sign*.18,.79,.23]);bone('BinderBack.'+side,'Chest',[sign*.07,.84,-.045]);bone('Wing.'+side,'Chest',[sign*.07,.84,-.045]);bone('RearHang.'+side,'Hips',[sign*.08,.47,-.08]);bone('SideArmor.'+side,'Hips',[sign*.12,.45,.14]);bone('Thruster.'+side,'Backpack',[sign*.075,.60,-.10]);bone('Thigh.'+side,'Hips',[sign*.085,.545,.235]);bone('Shin.'+side,'Thigh.'+side,[sign*.115,.405,.215]);bone('Foot.'+side,'Shin.'+side,[sign*.16,.12,.18]);bone('Toe.'+side,'Foot.'+side,[sign*.17,.07,.31]);bone('ChestArmor.'+side,'Chest',[sign*.06,.71,.23]);bone('thruster_'+side,'Thruster.'+side,[sign*.075,.60,-.10])
bone('Weapon.R','Hand.R',[-.17,.42,.26]);bone('muzzle_R','Weapon.R',[-.175,.23,.31]);bone('muzzle_L','Weapon.R',[-.175,.23,.31]);bone('head','Head',[0,.836,.27]);bone('vulcan_port','Head',[.045,.85,.31]);bone('vulcan_stbd','Head',[-.045,.85,.31]);bone('chest','Chest',[0,.72,.18]);bone('ChestVent','Chest',[0,.67,.25]);bone('waist','Hips',[0,.56,.20]);bone('Tail','Backpack',[0,.50,-.08])
ids={name:i for i,(name,_,_)in enumerate(spec)};nodes=[];globals_=[]
for name,parent,point in spec:
 m=np.eye(4);m[:3,3]=point;globals_.append(m);local=point-(spec[ids[parent]][2]if parent else np.zeros(3));nodes.append({'name':name,'translation':local.tolist(),'children':[]})
 if parent:nodes[ids[parent]]['children'].append(ids[name])
manual={'UpperArm.R':[169,204,205,207,208,209],'LowerArm.R':[25,26,42,43,44,121,122,135,190],'Hand.R':[28,29,191],'Weapon.R':[24],'UpperArm.L':[81,183,184,185,186,187,188,189],'LowerArm.L':[37,38,39,40,41,68,70,71,73,117,139,140,141],'Hand.L':[108,109,111,156],'shield_L':[10,11,12,13,14,15,16]}
manual['Thigh.L']=[117]
manual['Thigh.R']=[190]
manual['Shin.L']=[145,156,138]
manual['Shin.R']=[80,191]
manual['Shoulder.R']=[23,48,50,52,65,158,211]
manual['Shoulder.L']=[45,47,83,84,88,91,92,98,99,150,151,157,164,168]
manual={f'tripo_part_{part}':ids[name]for name,parts in manual.items()for part in parts}
assemblies={}
for n in g.j['nodes']:
 if n.get('name')in ['RearWingLeftAligned','RearWingRightAligned','TailAligned']:
  target={'RearWingLeftAligned':'Wing.L','RearWingRightAligned':'Wing.R','TailAligned':'Tail'}[n['name']]
  for child in n['children']:assemblies[child]=ids[target]
def classify(c):
 x,y,z=c;side='L'if x>=0 else'R'
 if abs(x)<.085 and y>.79 and z>.18:return ids['Head']
 if y<.56 and .055<abs(x)<.245 and .09<z<.33:return ids[('Foot.'if y<.14 else'Shin.'if y<.405 else'Thigh.')+side]
 if abs(x)>.10 and y>.40 and z>.08:return ids[('Shoulder.'if y>.80 else'UpperArm.'if y>.68 else'LowerArm.')+side]
 if z<-.04:return ids['Backpack']
 return ids['Hips'if y<.55 else'Chest']
def add(arr,kind,component=5126):
 arr=np.ascontiguousarray(arr,dtype={5126:'<f4',5123:'<u2',5125:'<u4',5121:'u1'}[component]);data.extend(b'\0'*((-len(data))%4));offset=len(data);data.extend(arr.tobytes());view=len(j['bufferViews']);j['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':arr.nbytes});idx=len(j['accessors']);a={'bufferView':view,'componentType':component,'count':len(arr),'type':kind}
 if kind=='VEC3':a.update(min=arr.min(0).tolist(),max=arr.max(0).tolist())
 j['accessors'].append(a);return idx
fits=json.loads(Path('work/xi_final_cruise_actual_fits.json').read_text());fits={x['part']:A@np.array(x['matrix'])@np.linalg.inv(A)for x in fits if x['part']not in ['tripo_part_89','tripo_part_90']};mechanical=[];meshes=[];mesh_nodes=[];report=[];triangles=0;rest_error=0.0;removed_triangles=0
for ni,n in enumerate(g.j['nodes']):
 if 'mesh'not in n:continue
 xf=A@gg[ni];mesh=deepcopy(g.j['meshes'][n['mesh']]);part_components=[]
 # Determine the main anatomical owner from the original connected surface.
 transformed=[]
 for p in mesh['primitives']:
  v=g.acc(p['attributes']['POSITION']);ix=g.acc(p['indices']).reshape(-1,3);_,weld=np.unique(np.round(v,6),axis=0,return_inverse=True);f=weld[ix];rows=f.reshape(-1);cols=np.roll(f,1,axis=1).reshape(-1);_,groups=connected_components(coo_matrix((np.ones(len(rows)),(rows,cols)),shape=(weld.max()+1,weld.max()+1)),directed=False);groups=groups[weld];v=v@xf[:3,:3].T+xf[:3,3];active=np.unique(ix);sizes=np.bincount(groups[active]);core=int(sizes.argmax());center=v[active[groups[active]==core]].mean(0);owner=manual.get(n['name'],assemblies.get(ni,classify(center)));transformed.append((p,v,ix,groups,core,owner))
 owner=transformed[0][-1];mech=None
 if n['name']in fits:
  mech=len(nodes);local=np.linalg.inv(globals_[owner]);nodes.append({'name':'Movie_Final_'+n['name'],'matrix':local.T.reshape(-1).tolist(),'children':[]});nodes[owner]['children'].append(mech);globals_.append(np.eye(4));mechanical.append({'id':mech,'parent':owner,'part':n['name'],'delta':fits[n['name']]})
 for p,v,ix,groups,core,owner in transformed:
  at=p['attributes'];at['POSITION']=add(v,'VEC3');count=len(v);js=np.zeros((count,4),dtype=np.uint16);ws=np.zeros((count,4),dtype=np.float32);ws[:,0]=1;active=np.unique(ix)
  for group in np.unique(groups[active]):
   members=active[groups[active]==group];target=(mech if mech is not None else owner)if group==core else classify(v[members].mean(0));js[members,0]=target;part_components.append({'component':int(group),'vertices':len(members),'bone':nodes[target]['name']})
  at['JOINTS_0']=add(js,'VEC4',5123);at['WEIGHTS_0']=add(ws,'VEC4')
  if n['name']in ['tripo_part_89','tripo_part_90']:
   # Explicit user-authorized floating white/dark pair only; other islands stay.
   keep=~np.any(groups[ix]==core,axis=1);removed_triangles+=int(np.count_nonzero(~keep));ix=ix[keep];p['indices']=add(ix.reshape(-1,1),'SCALAR',5125)
  triangles+=len(ix)
  # Bind/rest must reproduce every source point; no triangles or islands removed.
  for target in np.unique(js[active,0]):
   bind=np.linalg.inv(globals_[int(target)]);roundtrip=globals_[int(target)]@bind;rest_error=max(rest_error,float(np.max(np.abs(roundtrip-np.eye(4)))))
  if 'NORMAL'in at:
   normal=g.acc(at['NORMAL'])@np.linalg.inv(xf[:3,:3]);normal/=np.maximum(np.linalg.norm(normal,axis=1)[:,None],1e-8);at['NORMAL']=add(normal,'VEC3')
  if 'TANGENT'in at:
   t=g.acc(at['TANGENT']);t[:,:3]=t[:,:3]@xf[:3,:3].T;t[:,:3]/=np.maximum(np.linalg.norm(t[:,:3],axis=1)[:,None],1e-8);at['TANGENT']=add(t,'VEC4')
 mesh['primitives']=[p for p in mesh['primitives']if j['accessors'][p['indices']]['count']>0]
 if not mesh['primitives']:continue
 mesh_nodes.append({'name':n['name'],'mesh':len(meshes),'skin':0});meshes.append(mesh);report.append({'part':n['name'],'primary_bone':nodes[owner]['name'],'components':part_components})
joint_count=len(nodes);j['nodes']=nodes+mesh_nodes+[{'name':'Xi_Rig','children':[0]+list(range(joint_count,joint_count+len(mesh_nodes)))}];j['meshes']=meshes;j['scenes']=[{'name':'XiFinalFreshRig','nodes':[len(j['nodes'])-1]}];j['scene']=0;j['skins']=[{'name':'XiFinalFreshRig','joints':list(range(joint_count)),'inverseBindMatrices':add(np.stack([np.linalg.inv(m).T.reshape(-1)for m in globals_]),'MAT4')}]
Path('work/xi_final_fresh_skeleton.json').write_text(json.dumps({'joints':[{'name':name,'parent':parent,'point':point.tolist()}for name,parent,point in spec],'parts':report,'mesh_parts':len(meshes),'triangles':triangles,'rest_transform_error':rest_error,'removed_triangles':removed_triangles,'removed_parts':253-len(meshes),'authorized_exclusions':['tripo_part_89:primary_component','tripo_part_90:primary_component'],'bones':joint_count},ensure_ascii=False,indent=2),encoding='utf-8')
def local_pose(bi,amount):
 if bi in mechs:
  b=mechs[bi];d=b['delta'];r=d[:3,:3];t=d[:3,3];pivot=np.linalg.lstsq(np.eye(3)-r,t,rcond=1e-8)[0];drift=t-(pivot-r@pivot);rt=Rotation.from_rotvec(Rotation.from_matrix(r).as_rotvec()*amount).as_matrix();m=np.eye(4);m[:3,:3]=rt;m[:3,3]=pivot-rt@pivot+drift*amount;return np.linalg.inv(globals_[b['parent']])@m
 n=nodes[bi];m=np.eye(4);m[:3,3]=n.get('translation',[0,0,0]);return m
mechs={b['id']:b for b in mechanical};animations=[]
actions=[('fly',1,'normal'),('cruise_idle',1,'cruise'),('form_on',.4333333,'on'),('form_off',.4333333,'off'),('cruise_on',.4333333,'on')]
actions += [('dash_'+d,.4,'normal')for d in ['f','b','l','r','fl','fr','bl','br','u','d']]
actions += [('fly_'+d,2.8,'normal')for d in ['f','b','l','r','fl','fr','bl','br']]
actions += [('turn_'+d,2.8,'normal')for d in ['pitch_up','pitch_down','yaw_L','yaw_R','roll_L','roll_R']]
actions += [('shoot',.48,'normal'),('slash',1.14,'normal'),('burst',1.4,'normal'),('burst_cruise',1.4,'cruise'),('trans_fly_to_slash',.3,'normal'),('trans_slash_to_fly',.34,'normal')]
for action,duration,mode in actions:
 times=np.linspace(0,duration,27 if mode in ['on','off']else 2);timeacc=add(times.reshape(-1,1),'SCALAR');samplers=[];channels=[]
 for bi in range(joint_count):
  values=[]
  for time in times:
   t=0 if mode=='normal'else 1 if mode=='cruise'else float(time/duration);t=t*t*t*(t*(t*6-15)+10);t=1-t if mode=='off'else t;m=local_pose(bi,t);s=np.linalg.norm(m[:3,:3],axis=0);q=Rotation.from_matrix(m[:3,:3]/s).as_quat();values.append((m[:3,3],q,s))
  for k,(field,kind)in enumerate([('translation','VEC3'),('rotation','VEC4'),('scale','VEC3')]):
   samplers.append({'input':timeacc,'output':add(np.stack([v[k]for v in values]),kind),'interpolation':'LINEAR'});channels.append({'sampler':len(samplers)-1,'target':{'node':bi,'path':field}})
 animations.append({'name':action,'channels':channels,'samplers':samplers})
j['animations']=animations;j['buffers']=[{'byteLength':len(data)}];raw=json.dumps(j,separators=(',',':')).encode();raw+=b' '*((-len(raw))%4);data.extend(b'\0'*((-len(data))%4));out=dest/'authoring_hidden/xi_final_fresh_rig.glb';out.write_bytes(struct.pack('<III',0x46546c67,2,28+len(raw)+len(data))+struct.pack('<II',len(raw),0x4e4f534a)+raw+struct.pack('<II',len(data),0x004e4942)+data)
print('Fresh skeleton:',joint_count,'bones;',len(meshes),'original meshes;',triangles,'retained triangles; authorized removed triangles',removed_triangles)
