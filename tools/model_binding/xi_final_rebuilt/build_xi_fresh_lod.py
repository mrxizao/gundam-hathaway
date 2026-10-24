from xi_glb_lib import *
from scipy.spatial import ConvexHull
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from PIL import Image
from io import BytesIO
import hashlib
c=Path('work/gundam_arizeus_v2');g=GLB('work/gundam_arizeus_v2/assets/models/xi_final_rebuilt/authoring_hidden/xi_final_fresh_rig.glb');triangles=[];colors={}
for mesh in g.j['meshes']:
 for prim in mesh['primitives']:
  v=g.acc(prim['attributes']['POSITION']);ix=g.acc(prim['indices']).reshape(-1,3);_,weld=np.unique(np.round(v,6),axis=0,return_inverse=True);faces=weld[ix];rows=faces.reshape(-1);cols=np.roll(faces,1,axis=1).reshape(-1);count,groups=connected_components(coo_matrix((np.ones(len(rows)),(rows,cols)),shape=(weld.max()+1,weld.max()+1)),directed=False);groups=groups[weld];active=np.unique(ix);dominant=np.bincount(groups[active]).argmax();v=v[active[groups[active]==dominant]];keep=np.unique(np.r_[np.arange(0,len(v),max(1,len(v)//1200)),v.argmin(0),v.argmax(0)]);v=v[keep];faces=np.array([[0,1,2]]) if len(v)<4 else ConvexHull(v,qhull_options="QJ").simplices
  matidx=prim.get('material',0)
  if matidx not in colors:
   mat=g.j['materials'][matidx].get('pbrMetallicRoughness',{});color=np.array(mat.get('baseColorFactor',[1,1,1,1]),dtype=float)[:3]
   if 'baseColorTexture'in mat:
    image=g.j['images'][g.j['textures'][mat['baseColorTexture']['index']]['source']];view=g.j['bufferViews'][image['bufferView']];im=Image.open(BytesIO(g.bin[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']])).convert('RGB').resize((12,12));color*=np.array(im).reshape(-1,3).mean(0)/255
   colors[matidx]=color.tolist()
  for face in faces:
   coords=v[face].copy();coords*=28.0/.9684375;triangles.append(coords.reshape(-1).tolist()+colors[matidx])
(c/'tools/xi_fresh_lod.json').write_text(json.dumps(triangles,separators=(',',':')))
root=Path('C:/Users/MSIPC/Documents/gundam/assets/models/distant_lod');dst=c/'assets/models/distant_lod';import shutil;assert not dst.is_junction();dst.mkdir(exist_ok=True);
for f in root.iterdir():
 if f.is_file():shutil.copy2(f,dst/f.name)
key=hashlib.md5(b'res://assets/models/xi_final_rebuilt/xi_final_fresh_rig.scn').hexdigest()
(c/'tools/import_xi_fresh_lod.gd').write_text('''extends SceneTree
func _initialize() -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://tools/xi_fresh_lod.json"))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in source:
		tool.set_color(Color(row[9],row[10],row[11]))
		for vertex in 3: tool.add_vertex(Vector3(row[vertex*3],row[vertex*3+1],row[vertex*3+2]))
	tool.generate_normals()
	var mesh := tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo=true
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0,material)
	assert(ResourceSaver.save(mesh,"res://assets/models/distant_lod/'''+key+'''.res",ResourceSaver.FLAG_COMPRESS)==OK)
	print("XI FINAL LOD ",mesh.get_surface_count()," surface / ",source.size()," triangles")
	quit()
''')
print('Prepared LOD',len(triangles),'triangles',key)


