extends Node
## Low-quality GPU budget only. UI stays native; physics stays at 60 Hz.
const MIN_SCALE := 0.5
const MAX_SCALE := 0.75
var sample_time := 0.0
var sample_frames := 0
var gpu_time := 0.0
var slow_windows := 0
var fast_windows := 0
var previous_mode := false
var original_scale := 1.0
var original_msaa := Viewport.MSAA_DISABLED
var original_max_fps := 0
var original_lod := 1.0
var last_config:Array=[]
func _ready() -> void:
 process_mode=Node.PROCESS_MODE_ALWAYS
 original_scale=get_viewport().scaling_3d_scale
 original_msaa=get_viewport().msaa_3d
 original_max_fps=Engine.max_fps
 original_lod=get_viewport().mesh_lod_threshold

static func scale_limits(size:Vector2i,selected:float,low:bool) -> Vector2:
 if not low:return Vector2(MIN_SCALE,selected)
 var ceiling:=clampf(minf(selected,minf(1280.0/maxi(size.x,1),720.0/maxi(size.y,1))),0.1,1.0)
 var floor_scale:=clampf(minf(ceiling,minf(640.0/maxi(size.x,1),360.0/maxi(size.y,1))),0.1,ceiling)
 return Vector2(floor_scale,ceiling)

func _process(delta: float) -> void:
 var vp:=get_viewport()
 var low:=Settings.low_spec_mode()
 var window_size:=get_window().size
 var limits:=scale_limits(window_size,Settings.render_scale(),low)
 var config:Array=[Settings.low_end_60,Settings.render_scale_index,Settings.dynamic_resolution,low,window_size]
 if config!=last_config:
  last_config=config
  previous_mode=Settings.dynamic_resolution
  sample_time=0.0;sample_frames=0;gpu_time=0.0;slow_windows=0;fast_windows=0
  vp.scaling_3d_scale=limits.y
  vp.msaa_3d=Viewport.MSAA_DISABLED if Settings.low_end_60 else original_msaa
  vp.mesh_lod_threshold=16.0 if low else (4.0 if Settings.low_end_60 else original_lod)
  Engine.max_fps=60 if Settings.low_end_60 else original_max_fps
  RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),previous_mode)
 if not previous_mode or get_tree().paused or delta>0.1:return
 sample_time+=delta;sample_frames+=1
 gpu_time+=RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())*0.001
 if sample_time<1.0:return
 var average:=sample_time/maxi(sample_frames,1)
 var gpu_average:=gpu_time/maxi(sample_frames,1)
 sample_time=0.0;sample_frames=0;gpu_time=0.0
 # Valid GPU timings avoid reducing image resolution for a CPU-only bottleneck.
 var pressure:=gpu_average if gpu_average>0.0001 else average
 slow_windows=slow_windows+1 if pressure>0.0185 else 0
 fast_windows=fast_windows+1 if pressure<0.0155 else 0
 if slow_windows>=2:
  vp.scaling_3d_scale=maxf(limits.x,vp.scaling_3d_scale-0.05)
  slow_windows=0;fast_windows=0
 elif fast_windows>=8:
  vp.scaling_3d_scale=minf(limits.y,vp.scaling_3d_scale+0.025)
  fast_windows=0
