extends SceneTree
func _initialize() -> void:
 for pair in [["灵格斯改.glb","normal"],["灵格斯改巡航模式.glb","cruise"]]:
  var doc := GLTFDocument.new()
  var state := GLTFState.new()
  assert(doc.append_from_file("C:/Users/MSIPC/Desktop/游戏/闪哈游戏/灵格斯特装型/"+pair[0],state)==OK)
  var model := doc.generate_scene(state)
  assert(model != null)
  var scene := PackedScene.new()
  assert(scene.pack(model)==OK)
  assert(ResourceSaver.save(scene,"res://data/regz_models/"+pair[1]+".scn",ResourceSaver.FLAG_COMPRESS)==OK)
  print("REGZ IMPORT ",pair[1]," meshes ",model.find_children("*","MeshInstance3D",true,false).size())
  model.free()
 quit()
