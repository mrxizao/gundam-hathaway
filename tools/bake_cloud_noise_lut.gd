extends SceneTree
## Offline bake, never run by gameplay. Two linear RGBA8 192^3 lattices = 54 MiB.
## Cache the eight expressions separately: GPU contraction makes hash(i+1) differ
## slightly from an independently evaluated hash at the adjacent integer point.
const SIZE:=192
func _initialize() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd==null:
		push_error("Bake requires a Vulkan rendering device; run without --headless")
		quit(1);return
	var src:=RDShaderSource.new()
	src.source_compute='''#version 450
layout(local_size_x=4,local_size_y=4,local_size_z=4) in;
layout(rgba8,set=0,binding=0) uniform writeonly image3D output_a;
layout(rgba8,set=0,binding=1) uniform writeonly image3D output_b;
float hash_cloud(vec3 p){p=fract(p*vec3(0.1031,0.1030,0.0973));p+=dot(p,p.yxz+33.33);return fract((p.x+p.y)*p.z);}
void main(){ivec3 id=ivec3(gl_GlobalInvocationID);precise vec3 i=floor(vec3(id)-vec3(16.0));imageStore(output_a,id,vec4(hash_cloud(i),hash_cloud(i+vec3(1,0,0)),hash_cloud(i+vec3(0,1,0)),hash_cloud(i+vec3(1,1,0))));imageStore(output_b,id,vec4(hash_cloud(i+vec3(0,0,1)),hash_cloud(i+vec3(1,0,1)),hash_cloud(i+vec3(0,1,1)),hash_cloud(i+vec3(1,1,1))));}
'''
	var spirv:=rd.shader_compile_spirv_from_source(src)
	assert(spirv.compile_error_compute.is_empty(),spirv.compile_error_compute)
	var shader:=rd.shader_create_from_spirv(spirv)
	var format:=RDTextureFormat.new()
	format.texture_type=RenderingDevice.TEXTURE_TYPE_3D
	format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.width=SIZE;format.height=SIZE;format.depth=SIZE
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var textures:Array[RID]=[];var bindings:Array[RDUniform]=[]
	for slot in 2:
		var texture:=rd.texture_create(format,RDTextureView.new());assert(texture.is_valid());textures.append(texture)
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;uniform.binding=slot;uniform.add_id(texture);bindings.append(uniform)
	var uniforms:=rd.uniform_set_create(bindings,shader,0)
	var pipeline:=rd.compute_pipeline_create(shader)
	var commands:=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(commands,pipeline)
	rd.compute_list_bind_uniform_set(commands,uniforms,0)
	rd.compute_list_dispatch(commands,48,48,48)
	rd.compute_list_end();rd.submit();rd.sync()
	for slot in 2:
		var raw:=rd.texture_get_data(textures[slot],0);assert(raw.size()==SIZE*SIZE*SIZE*4)
		var slices:Array[Image]=[];var stride:=SIZE*SIZE*4
		for z in SIZE:slices.append(Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_RGBA8,raw.slice(z*stride,(z+1)*stride)))
		var lut:=ImageTexture3D.new();assert(lut.create(Image.FORMAT_RGBA8,SIZE,SIZE,SIZE,false,slices)==OK)
		DirAccess.make_dir_recursive_absolute("res://assets/textures")
		assert(ResourceSaver.save(lut,"res://assets/textures/cloud_noise_lut_"+str(slot)+".res",ResourceSaver.FLAG_COMPRESS)==OK)
		if "--dump-raw" in OS.get_cmdline_user_args():
			var f:=FileAccess.open("res://day6_cloud_noise_raw_"+str(slot)+".bin",FileAccess.WRITE);f.store_buffer(raw);f.close()
	rd.free_rid(uniforms);rd.free_rid(pipeline)
	for texture in textures:rd.free_rid(texture)
	rd.free_rid(shader);rd.free()
	print("DAY6_CLOUD_NOISE_BAKED bytes=",SIZE*SIZE*SIZE*8)
	quit()
