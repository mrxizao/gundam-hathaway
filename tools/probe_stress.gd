extends Node
## 压力探针：连续重开 6 局，每局结束打印节点数 / 对象数 / 帧耗时。
## 用来抓"重开会卡住"这类**资源只增不减**的问题。
## 跑法：godot --headless --path <工程> res://tools/probe_stress.tscn


func _ready() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _f(30)

	print("轮次 | 节点数 | 对象数 | 孤儿 | 音频播放器 | 物理ms | 进程ms")
	for cycle in 6:
		main.call("_on_start_match", SuitProfile.Id.XI, Difficulty.Level.HARD)
		await _f(20)
		main.call("_start_fight")
		await _f(30)

		var p = main.get("player")
		# 打一阵子：机炮 + 光束 + 浮游导弹都放一遍，把音频与特效都压出来
		for i in 40:
			if p == null or not is_instance_valid(p):
				break
			p.gun_cooldown = 0.0
			p.call("fire_gun", true)
			if i % 6 == 0:
				p.rifle_cooldown = 0.0
				p.call("fire_beam", true, null, false)
			if i % 10 == 0:
				p.funnel_cooldown = 0.0
				var foe = main.get("enemy")
				if foe != null and is_instance_valid(foe):
					p.call("fire_funnel", foe)
			await _f(2)

		var e = main.get("enemy")
		if e != null and is_instance_valid(e):
			e.ifield_hp = 0.0
			e.take_damage(999999.0, p, Damage.Type.SABER)
		await _f(50)
		await _f(60)   # 等输入锁

		print("%d | %d | %d | %d | %d | %.2f | %.2f" % [
			cycle + 1,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			_count_audio(main),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		])

		# 走"再战一局"：模拟按 Enter
		main.call("spawn_round")
		main.set("phase", 1)
		Game.set_phase(Game.Phase.INTRO)
		await _f(20)

	print("STRESS_DONE")
	get_tree().quit(0)


func _count_audio(root: Node) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is AudioStreamPlayer or cur is AudioStreamPlayer3D:
			n += 1
		for c in cur.get_children():
			stack.append(c)
	return n


func _f(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
