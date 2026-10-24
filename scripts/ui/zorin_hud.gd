extends RefCounted
static func rows(p, cockpit:=false)->Array:
	var s=p.nu_systems
	if not is_instance_valid(s):return []
	var result:Array=[
		{"name":p.weapon_name(),"key":InputSetup.hint("左键","R1"),"value":("装填 %d%%"%int(p.reload_progress()*100) if p.rifle_reloading else "%02d / 15"%p.rifle_mag) if p.current_slot()=="rifle" else ("%.1fs"%p.saber_cooldown if p.saber_cooldown>0 else "READY"),"bar":p.mag_ratio() if p.current_slot()=="rifle" else -1.0},
		{"name":"浮游导弹","key":InputSetup.hint("右键","L1"),"value":"%02d / %d"%[p.funnel_count,p.funnel_mag_size]},
		{"name":"六翼浮游炮 · "+s.mode_name(),"key":InputSetup.hint("F 展开 / 回收","L2 展开 / 回收"),"value":s.status_text(),"bar":s.energy/200.0},
		{"name":"米诺夫斯基屏障","key":InputSetup.hint("C","□"),"value":"%d/3 · %s"%[s.charges(),"%.1fs"%s.barrier_cd if s.barrier_cd>0 else "READY"]},
		{"name":"60mm火神炮","key":InputSetup.hint("空格","R2"),"value":"∞"},
		{"name":"盾牌","key":InputSetup.hint("T","△"),"value":"展开" if p.shield_up else "READY"}]


	if cockpit:
		result.insert(4,{"name":"屏障冷却","value":"%.1fs"%s.barrier_cd if s.barrier_cd>0 else "就绪","bar":s.cooldown_progress()})
		result.insert(5,{"name":"屏障充能","value":"等待冷却" if s.barrier_cd>0 and s.charge_remaining()>0 else ("%.1fs"%s.charge_remaining() if s.charge_remaining()>0 else "已满"),"bar":s.charge_progress()})
	return result
