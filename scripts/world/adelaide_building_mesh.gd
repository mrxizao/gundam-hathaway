extends RefCounted
## Metre-sized modules; facade floors are repeated, never scaled to arbitrary height.
const FLOOR_M:=6.4
const STYLE_NAMES:=["台阶式办公楼","板式商业楼","砖石沿街楼","玻璃幕墙塔楼","工业厂房","公共设施楼"]
var tools:Dictionary={}
var counts:Dictionary={}
var style:=0
var level:=0
var size:=Vector3.ONE
func build(dimensions:Vector3,kind:int,lod:int)->ArrayMesh:
	tools.clear();counts.clear();size=dimensions;style=kind;level=lod
	var w:=size.x;var h:=size.y;var d:=size.z
	# Flush perimeter and sub-metre recesses keep the original collision envelope readable.
	var body_role:=1 if style==2 else 2 if style in [3,4] else 0
	box(Vector3(0,h*0.5,0),Vector3(w-2.0,h,d-2.0),body_role)
	box(Vector3(0,0.6,0),Vector3(w,1.2,d),0)
	var podium:=minf(19.2,h*0.12)
	box(Vector3(0,podium*0.5,0),Vector3(w-2.0,podium,d-2.0),0)
	# Every variant retains a roof plane; structures remain inside its footprint.
	box(Vector3(0,h+0.35,0),Vector3(w,0.7,d),6 if style==4 else 5)
	if style==4:sheet_roof(h+.7,6.0)
	var parapet_h:=3.2 if style!=4 else 1.2
	for sign:float in [-1,1]:
		box(Vector3(sign*(w*0.5-0.75),h+parapet_h*0.5,0),Vector3(1.5,parapet_h,d),3,0)
		box(Vector3(0,h+parapet_h*0.5,sign*(d*0.5-0.75)),Vector3(w,parapet_h,1.5),3,0)
	if style==0:
		for tier in 3:box(Vector3(-w*0.22,h+1.8+float(tier)*1.7,-d*0.25),Vector3(w*(0.34-tier*0.07),3.4,d*(0.26-tier*0.04)),0)
	elif style==1:
		box(Vector3(0,h+2.2,-d*0.34),Vector3(w*0.66,4.4,d*0.20),2)
	elif style==2:
		for sign:float in [-1,1]:box(Vector3(sign*w*0.27,h+4.0,-d*0.28),Vector3(w*0.18,8.0,d*0.20),1)
	elif style==3:
		box(Vector3(-w*0.25,h+4.8,-d*0.25),Vector3(w*0.24,9.6,d*0.24),2)
	elif style==4:
		for n in 3:box(Vector3(-w*0.25+n*w*0.25,h+2.0,-d*0.28),Vector3(w*0.20,4.0,d*0.25),2)
	else:
		box(Vector3(-w*0.25,h+2.5,-d*0.28),Vector3(w*0.34,5.0,d*0.24),0)
	if level==2:
		# Coarse dark belts retain readable facade rhythm without hundreds of narrow strips.
		if style==3:glass_belt(h*.50,h*.94)
		else:
			var fraction:=.065 if style==4 else .135 if style==5 else .185
			for y:float in [h*0.25,h*0.55,h*0.85]:glass_belt(y,h*fraction)
	else:
		var stride:=1 if level==0 and style!=4 else 4 if level==0 else 4 if style!=4 else 8
		stride=maxi(stride,int(ceil(h/(FLOOR_M*120.0))))
		var floors:=int(floor(h/FLOOR_M))
		for floor_index in range(2,floors-1,stride):
			var y:=float(floor_index)*FLOOR_M
			var ratio:=.86 if style==3 else .20 if style==4 else .40 if style==5 else .56 if level==0 else .60
			glass_belt(y+FLOOR_M*float(stride)*0.48,FLOOR_M*float(stride)*ratio)
			for sign:float in [-1,1]:
				var band_role:=1 if style==2 else 3
				box(Vector3(0,y,sign*(d*0.5-0.55)),Vector3(w,0.85,1.1),band_role,3 if style==1 else 0)
				box(Vector3(sign*(w*0.5-0.55),y,0),Vector3(1.1,0.85,d),band_role,3 if style==1 else 0)
		var bay:=60.0 if style==4 else 48.0
		if level==1:bay*=2.0
		for face in 4:
			var horizontal:=face<2;var length:=w if horizontal else d
			var bays:=maxi(2,int(floor(length/bay)))
			for n in bays+1:
				var margin:=2.4 if style==5 else 1.2
				var along:float=lerpf(-length*.5+margin,length*.5-margin,float(n)/bays)
				var pos:=Vector3(along,h*.5,(-1 if face==0 else 1)*(d*.5-.7)) if horizontal else Vector3((-1 if face==2 else 1)*(w*.5-.7),h*.5,along)
				var thickness:=1.8 if style!=5 else 4.8
				box(pos,Vector3(thickness,h,1.4) if horizontal else Vector3(1.4,h,thickness),1 if style==2 else 0)
	# Distinct major facade modules survive all three LODs.
	if style==0:
		for band:float in [0.34,0.67]:
			for sign:float in [-1,1]:box(Vector3(0,h*band,sign*(d*.5-1.4)),Vector3(w,3.0,2.8),0)
	elif style==1:
		for band:float in [0.25,0.50,0.75]:
			for sign:float in [-1,1]:box(Vector3(0,h*band,sign*(d*.5-1.0)),Vector3(w,2.0,2.0),3,3)
	elif style==2:
		for sx:float in [-1,1]:
			for sz:float in [-1,1]:box(Vector3(sx*(w*.5-2.0),h*.5,sz*(d*.5-2.0)),Vector3(4.0,h,4.0),1)
	elif style==3:
		for sign:float in [-1,1]:box(Vector3(sign*(w*.5-1.7),h*.5,0),Vector3(3.4,h,d*.13),2)
	elif style==4:
		for sign:float in [-1,1]:box(Vector3(0,h*.72,sign*(d*.5-1.6)),Vector3(w,7.0,3.2),2)
	else:
		for n in 5:box(Vector3(-w*.36+n*w*.18,minf(h*.56,25.6)*.5,-d*.5+3.0),Vector3(6.0,minf(h*.56,25.6),6.0),0)
	if level<2 and style==3:
		# Slim mullions on the glass tower; opaque glazing avoids sorting.
		for sign:float in [-1,1]:
			box(Vector3(sign*(w*.5-3),h*.5,-d*.32),Vector3(6,h,3),2)
			box(Vector3(sign*w*.28,h*.5,-d*.5+1.4),Vector3(2.8,h,2.8),2)
		box(Vector3(0,h+2,-d*.32),Vector3(w*.42,3.2,d*.12),2)
	if level<2 and style==4:
		# Recessed loading bays and high clerestory; no projecting ground collision.
		for n in 3:
			var x:float=(-.28+n*.28)*w
			box(Vector3(x,10,-d*.5+.6),Vector3(24,20,1.2),2)
			box(Vector3(x,21,-d*.5+1),Vector3(27,1.6,2),3,1)
		for sign:float in [-1,1]:box(Vector3(sign*w*.23,h+4.3,0),Vector3(w*.09,.4,d*.5),4)
	if level<2 and style==5:
		box(Vector3(0,26,-d*.5+5),Vector3(minf(w*.65,180),2.4,10),0)
		box(Vector3(0,27.7,-d*.5+5),Vector3(minf(w*.65,180)+2,1,10),3,0)
	if level<2:
		# Entrance is recessed inside the existing parcel, no projecting ground obstacle.
		box(Vector3(0,7.0,-d*.5+.8),Vector3(minf(20,w*.12),14,1.0),4)
		box(Vector3(0,15.0,-d*.5+1.1),Vector3(minf(26,w*.15),1.0,2.0),3,1)
	return finish_mesh()
func finish_mesh()->ArrayMesh:
	var mesh:=ArrayMesh.new()
	var roles:=tools.keys();roles.sort()
	for role:int in roles:
		var st:SurfaceTool=tools[role];st.generate_tangents();st.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count()-1,str(role))
	mesh.set_meta("style",style);mesh.set_meta("lod",level);mesh.set_meta("dimensions",size)
	mesh.set_meta("floor_m",FLOOR_M);mesh.set_meta("triangles",triangle_count(mesh))
	return mesh
func sheet_roof(y:float,rise:float)->void:
	var w:=size.x;var d:=size.z
	quad(Vector3(-w*.5,y,-d*.5),Vector3(0,y+rise,-d*.5),Vector3(0,y+rise,d*.5),Vector3(-w*.5,y,d*.5),Vector3(-rise,w*.5,0).normalized(),6)
	quad(Vector3(0,y+rise,-d*.5),Vector3(w*.5,y,-d*.5),Vector3(w*.5,y,d*.5),Vector3(0,y+rise,d*.5),Vector3(rise,w*.5,0).normalized(),6)
	for sign:float in [-1,1]:quad(Vector3(-w*.5,y,sign*d*.5),Vector3(-.1,y+rise,sign*d*.5),Vector3(.1,y+rise,sign*d*.5),Vector3(w*.5,y,sign*d*.5),Vector3(0,0,sign),2)
func glass_belt(y:float,height:float)->void:
	var w:=size.x;var d:=size.z
	var lo:=maxf(6.2,y-height*.5);var hi:=minf(size.y-1.0,y+height*.5)
	if hi<=lo:return
	for sign:float in [-1,1]:
		var z:=sign*(d*.5-.45)
		quad(Vector3(-w*.5+1.8,lo,z),Vector3(w*.5-1.8,lo,z),Vector3(w*.5-1.8,hi,z),Vector3(-w*.5+1.8,hi,z),Vector3(0,0,sign),4)
		var x:=sign*(w*.5-.45)
		quad(Vector3(x,lo,-d*.5+1.8),Vector3(x,lo,d*.5-1.8),Vector3(x,hi,d*.5-1.8),Vector3(x,hi,-d*.5+1.8),Vector3(sign,0,0),4)
func box(center:Vector3,extent:Vector3,role:int,row:int=0)->void:
	var q:=extent*.5
	var v:Array[Vector3]=[]
	for p:Vector3 in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]:v.append(center+p*q)
	var faces:=[[0,3,2,1],[4,5,6,7],[0,4,7,3],[1,2,6,5],[3,7,6,2],[0,1,5,4]]
	var normals:=[Vector3(0,0,-1),Vector3(0,0,1),Vector3(-1,0,0),Vector3(1,0,0),Vector3.UP,Vector3.DOWN]
	for i in 6:
		var f:Array=faces[i];quad(v[f[0]],v[f[1]],v[f[2]],v[f[3]],normals[i],role,row)
func quad(a:Vector3,b:Vector3,c:Vector3,d:Vector3,n:Vector3,role:int,row:int=0)->void:
	if not tools.has(role):var fresh:=SurfaceTool.new();fresh.begin(Mesh.PRIMITIVE_TRIANGLES);tools[role]=fresh
	var st:SurfaceTool=tools[role]
	var verts:Array=[a,c,b,a,d,c] if (b-a).cross(c-a).dot(n)>0 else [a,b,c,a,c,d]
	var lo:=INF;var hi:=-INF
	for point:Vector3 in [a,b,c,d]:
		var value:=point.y if absf(n.y)<.5 else point.z
		lo=minf(lo,value);hi=maxf(hi,value)
	for i in 6:
		var p:Vector3=verts[i];var uv:=Vector2(p.x,p.y) if absf(n.z)>.5 else Vector2(p.z,p.y) if absf(n.x)>.5 else Vector2(p.x,p.z)
		st.set_normal(n);st.set_uv(uv);st.set_uv2(Vector2(0,((p.y if absf(n.y)<.5 else p.z)-lo)/maxf(.001,hi-lo)));st.set_color(Color(float(row)/7.0,0,0,1));st.add_vertex(p)
static func triangle_count(mesh:ArrayMesh)->int:
	var count:=0
	for s in mesh.get_surface_count():count+=mesh.surface_get_array_len(s)/3
	return count
