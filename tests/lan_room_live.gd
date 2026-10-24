extends Node
class ProbeMenu extends MainMenu:
 var launched:=false
 func _launch()->void:launched=true
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func wait_for(condition:Callable,seconds:float)->bool:
 var until:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<until:
  if condition.call():return true
  await get_tree().process_frame
 return false
func _ready()->void:
 Settings.begin_isolated();Game.reset()
 var args:=OS.get_cmdline_user_args()
 var host:=args.has("host")
 var scenario:="code"
 for arg in args:
  if str(arg).begins_with("case="):scenario=str(arg).trim_prefix("case=")
 var menu:=ProbeMenu.new();add_child(menu);menu.set_process(false)
 menu.set_anchors_preset(Control.PRESET_TOP_LEFT);menu.size=Vector2(1600,900);menu.stage=MainMenu.Stage.LAN;menu.active=true;menu.input_lockout=0;menu._await_release=false
 for index in MainMenu.MODE_GROUPS.size():
  if MainMenu.MODE_GROUPS[index].modes.has(Game.MatchMode.LAN):menu.mode_index=index
 menu.lan_form_choice=MainMenu.LAN_FORMS.find(LanPlan.Form.ACE_DUEL)
 menu.side_index=0 if host else 1;menu.suit_index=0
 menu.lan_code="185739";menu.lan_pass="2468"
 if scenario=="cancel":
  menu.lan_code="999999";Net.address="127.0.0.1";menu._lan_start_join()
  check(menu._lan_resolving,"Code lookup remains cancellable")
  await get_tree().create_timer(.1).timeout
  menu._cancel_lan()
  await get_tree().create_timer(.2).timeout
  check(not menu._lan_resolving and Net.role==Net.Role.NONE,"Cancellation cannot join later")
  Net.role=Net.Role.CLIENT;Net.peer_ready=true
  menu.stage=MainMenu.Stage.LAN;menu._lan_wait=true;menu._lan_wait_elapsed=Net.LAN_WAIT_TIMEOUT+1
  menu._read_lan_room_input()
  check(Net.role==Net.Role.NONE and Game.lan_status.contains("同步超时"),"Incomplete handshake times out instead of blocking ready forever")
 elif host:
  if scenario=="custom":
   check(Net.host_game(27089,preload("res://scripts/data/lan_room.gd").auth_hash(menu.lan_pass))==OK,"Custom-port host")
   LanBrowser.host_beacon(menu.lan_code,Net.port,LanPlan.Form.ACE_DUEL,true);menu._begin_lan_wait()
  else:menu._lan_start_host()
  print("HOST_LISTENING ",scenario," port=",Net.port)
 else:
  Net.address="127.0.0.1"
  if scenario=="badpass":menu.lan_pass="1111"
  menu._lan_start_join()
 if scenario!="cancel":
  if scenario=="badpass":
   if host:
    check(await wait_for(func():return Game.lan_status.contains("密码不正确"),18),"Host rejects wrong password")
   else:
    check(await wait_for(func():return not menu._lan_resolving and Net.role==Net.Role.NONE,12),"Guest leaves rejected connection")
   check(not Net.start_committed and not Net.local_ready,"Rejected guest cannot ready or start")
  else:
   check(await wait_for(func():return Net.choices_ready(),18),"Both choices received over real ENet")
   if Net.choices_ready():
    check(not Net.start_committed,"Joining room does not auto-start")
    if not host:check(Net.address not in ["127.0.0.1","localhost"],"Room code resolved actual beacon sender address")
    if not host and scenario=="custom":check(Net.port==27089,"Uses advertised port instead of room-code hash")
    var geometry:Dictionary=menu._list_geometry()
    check(geometry.count==MainMenu.LOBBY_ROWS.size(),"Room mouse layout matches visible rows")
    var rect:Rect2=menu.row_rect(menu.size,geometry,4)
    var motion:=InputEventMouseMotion.new();motion.position=rect.get_center();menu._handle_mouse(motion)
    check(menu.lan_lobby_row==4,"Mouse focuses ready row")
    var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=rect.get_center()
    menu._handle_mouse(click);menu._read_input()
    check(Net.local_ready,"Mouse click readies actual session")
    check(await wait_for(func():return Net.start_committed,6),"Both ready commits match on both peers")
    await get_tree().create_timer(.1).timeout
    menu._read_input();check(menu.launched,"Room transitions into match after confirmations")
    check(Net.remote_ready,"Opponent readiness synchronized")
    await get_tree().create_timer(1.2 if host else .2).timeout
 LanBrowser.stop();Net.close();menu.queue_free()
 for frame in 3:await get_tree().process_frame
 Settings.end_isolated();print("LIVE_ROOM_RESULT ",scenario," ","HOST" if host else "GUEST"," failures=",failures)
 get_tree().quit(1 if failures else 0)
