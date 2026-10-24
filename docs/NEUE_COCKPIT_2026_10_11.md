# 露维杰露独立驾驶舱 · 2026-10-11

按用户动画截图与设定线稿重做露维杰露专用样式，并纳入追加的半天窗要求：
- 前方与侧方分隔显示窗、实体侧后舱壁。
- 顶部为分段半天窗，保留设备横梁、通风面板与窗框，抬头可透过窗口看见实际游戏世界。
- 独立低位横向三屏布局、实体按钮；仪表仍以相机空间 3D 模型显示。
- 暗绿渐变屏幕、琥珀刻度和扫描线；中屏使用露维杰露机体图与简洁标注，不沿用全周天机型装饰。
- 保留 M 切换雷达、轮廓与线稿，不改变其他机体的样式分支。

验证：tests/neue_cabin_probe.tscn 12 PASS / 0 FAIL；独立 GPU 预览检查正前与抬头半天窗视角，未运行全项目回归。测试环境受限导致系统证书存储读取警告，与驾驶舱脚本无关。预览使用测试背景，正式游戏窗口透出实际场景。

## 四屏与棱锥形修订

根据用户后续补充，将露维杰露舱体改为向前收拢的截棱锥：前端截面窄、后端截面宽，所有显示面和框架均为平面/直线，不使用球面舱壁。

四块大型显示区域分别为正前、左侧、右侧和顶部，开口占各面约 94% 的线性尺寸；顶部保留窄设备横梁。底部三块小仪表属于操纵台，与四块主显示区域分开。

定向结构与布局检查 12 PASS / 0 FAIL；GPU 检查正前和抬头视角。未进行全项目回归。

## 原设结构细化

加入平直窗框的分段套接与紧固件；顶部设备桥增加梯形面板、圆形控件与两侧指示槽。后部实体舱壁补入检修缝、圆形通风口与格栅。

左右操纵台增加带倾角的实体基座、双排键列、下沿键盘、连接器槽、拨杆和带触发按钮的握把。原有三个小仪表嵌在控制台中，四块大型显示区域保持不变。

本轮结构与布局检查 12 PASS / 0 FAIL，完成独立 GPU 正前与抬头预览；未运行全项目回归。

## 前收三角与仪表位置修正

左右显示区域下部增加实体前收三角结构，宽端在后、尖端连接前方大屏下角，加入放射状加强筋。下方三块小仪表及左右控制台整体降低并压低高度，正前视角中控制台顶边低于大屏下沿，不再覆盖大屏。

独立检查 16 PASS / 0 FAIL；GPU 正前预览核对两侧三角轮廓和仪表位置。保留工程中其他会话新增的 GP03 专用接线与依赖。未运行全项目回归。

## 第一人称示意图构图修订（取代上一轮实心三角板）

以用户新给的第一人称示意图为准：前屏改为上宽下窄梯形，左右大屏展开并由下沿框架向前屏下角汇聚，顶部维持大显示区与设备横梁。撤掉上一轮遮住侧屏的实心三角板；三角收束关系由大屏边界和窗框体现。

小仪表缩小并集中在前屏正下方，左右控制台同步收窄，修改小屏标题与刻度密度以避免小尺寸溢出。仅修改露维杰露分支，保留其他机体的接线。

定向检查 14 PASS / 0 FAIL，GPU 检查正前及抬头预览。未运行全项目回归。

## 黄色示意轮廓：异形仪表盘

按用户黄色部分指定外形：中央仪表盘为上宽下窄梯形，左右为镜像斜四边形；玻璃、斜面边框与挤出的外壁共享同一轮廓。仪表内容通过 UV 映射贴合形状，仍保持相机空间 3D 显示。撤掉原来的矩形外壳与矩形控制台底板，不将仪表改成黄色。

结构与轮廓定向检查 17 PASS / 0 FAIL，GPU 正前预览核对三块形状与文字。未运行全项目回归。

## 下方空白填充

根据控制台设定图与动画局部，添加沿下方舱壁展开的左右多边形控制台：错列按键、红色开关、青绿色辅助小屏、圆柱旋钮与槽口、双操纵杆及中央键盘。部件为相机空间实体 3D 几何，主显示屏及三块异形仪表轮廓保持不变。辅助屏和新增按键为外观组件，尚未添加交互功能。

扩充重建检查：左右控制台生成、细节节点和异形玻璃保留，共 20 PASS / 0 FAIL；GPU 正前预览已核对。未运行全项目回归。


## Unified camera-space shell
- Replaced Neue planar panorama overlay with a solid bevelled 3D shell in the instrument viewport. Four transparent display apertures retain the forward-tapering layout.
- Shared rail junctions, rounded corner caps, continuous roof bridge and lower fascia connect the controls to the cabin.
- Neue shell follows screen camera like the instrument assembly; other cockpit families retain their existing panorama rendering.
- Existing three shaped instruments, CRT state display, lower consoles and controls preserved.
- Validation: 23 targeted assertions passed, including shell geometry creation and 1920x1080 rebuild; GPU preview inspected. Full gameplay regression not run.


## Ceiling equipment band refinement
- Expanded the thin overhead bridge into a roughly 74-pixel deep ceiling band at 1280x720, with its lower edge following the sloping side rails.
- Added bevelled upper/lower lips, recessed center service panel, circular control, paired vent grilles and fastened outer access covers. Top display opening remains visible.
- Targeted cabin probe: 23 assertions passed; GPU front preview inspected.


## Opaque side triangles
- Added the two opaque triangular cheek walls beside the forward display following the latest red-marked reference. Outer edges are near vertical; inner edges follow the tapered forward frame.
- Added thickness walls, perimeter rails and inset ribs; kept the roof band and instrument assembly intact.
- Validation: 23 targeted assertions passed and GPU preview inspected.


## Cabin detail refinement
- Added inset cheek-wall lining, panel seams, fasteners and access grips. Added forward-window inner gasket and captive screws.
- Added recessed lower switch banks and round auxiliary dials; moved switch banks above console lip after GPU overlap inspection.
- Validation: 23 cabin assertions passed before final placement adjustment, final GPU preview inspected. No full gameplay regression.


## Yellow dashed sight and lock UI
- Neue first-person weapon sight now uses yellow dashed cross arms with a clear center. Retains actual aim projection and behind-camera/offscreen handling.
- Compact cockpit target display now uses yellow dashed target frame; confirmed lock increases opacity and adds corner dots. Existing distance, acquisition state, reasons and lead indicators retained. Other suits unchanged.
- Validation: cabin probe 23 assertions passed; GPU drawing preview inspected with a synthetic sight and confirmed-lock frame. Live moving-target combat not tested.


## Side display yellow calibration marks
- Added mirrored yellow dashed crosses and short oblique calibration ticks on the two side display areas. These are decorative calibration marks, not additional target locks.
- Overlay follows the fixed cockpit camera layout, scales with the cabin, ignores mouse input and is cleared on cockpit rebuild/suit changes.
- Validation: 23 cabin assertions passed and GPU preview inspected for triangle/instrument overlap.
