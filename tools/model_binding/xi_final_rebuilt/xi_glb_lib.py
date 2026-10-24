from pathlib import Path
import json,struct,numpy as np,re
from scipy.spatial.transform import Rotation
class GLB:
 def __init__(self,p):
  self.raw=Path(p).read_bytes();ln=struct.unpack_from('<I',self.raw,12)[0];self.j=json.loads(self.raw[20:20+ln]);pos=20+ln;self.bin=self.raw[pos+8:pos+8+struct.unpack_from('<I',self.raw,pos)[0]]
 def acc(self,n):
  a=self.j['accessors'][n];v=self.j['bufferViews'][a['bufferView']];dtype={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']];dim={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']];return np.ndarray((a['count'],dim),dtype=dtype,buffer=self.bin,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',np.dtype(dtype).itemsize*dim),np.dtype(dtype).itemsize)).copy()
 def globals(self):
  ns=self.j['nodes'];parents={c:i for i,n in enumerate(ns) for c in n.get('children',[])};cache={}
  def one(i):
   if i in cache:return cache[i]
   n=ns[i];m=np.eye(4)
   if 'matrix'in n:m=np.array(n['matrix']).reshape(4,4).T
   else:m[:3,:3]=Rotation.from_quat(n.get('rotation',[0,0,0,1])).as_matrix()@np.diag(n.get('scale',[1,1,1]));m[:3,3]=n.get('translation',[0,0,0])
   cache[i]=(one(parents[i]) if i in parents else np.eye(4))@m;return cache[i]
  return [one(i) for i in range(len(ns))]
def points(g,n,gl):
 v=np.concatenate([g.acc(p['attributes']['POSITION']) for p in g.j['meshes'][n['mesh']]['primitives']]);return v@gl[:3,:3].T+gl[:3,3]
