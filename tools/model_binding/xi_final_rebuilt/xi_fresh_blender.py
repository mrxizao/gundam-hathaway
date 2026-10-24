import bpy, pathlib, json
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
source=pathlib.Path('C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/work/gundam_arizeus_v2/assets/models/xi_final_rebuilt/authoring_hidden/xi_final_fresh_rig.glb')
bpy.ops.import_scene.gltf(filepath=str(source))
rigs=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
assert len(rigs)==1
rig=rigs[0]
assert len(rig.data.bones)==62
rig.name='柯西最终决战_独立骨架'
rig.show_in_front=True
rig.data.display_type='OCTAHEDRAL'
for action in bpy.data.actions:
    if action.name.startswith(('dash_', 'shoot', 'slash', 'burst', 'turn_', 'fly_')):
        action.name='BASE_ONLY_'+action.name
# First review the complete mesh in its bind pose with bones visible.
rig.animation_data_clear()
for pose in rig.pose.bones:
    pose.matrix_basis.identity()
bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
bpy.context.view_layer.objects.active=rig
out=pathlib.Path('C:/Users/MSIPC/Documents/Codex/2026-10-08/yeu/outputs/xi_fresh_rig')
out.mkdir(exist_ok=True,parents=True)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(out/'柯西最终决战_独立骨架.blend'))
print('BLENDER FRESH ARMATURE SAVED',len(rig.data.bones),'bones')
