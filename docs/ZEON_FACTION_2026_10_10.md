# 吉翁阵营预留 · 2026-10-10

追加 BattleFormation.Side.ZEON，原有阵营编号保持不变。新增吉翁名称与用户提供的徽章原图 assets/ui/faction/zeon.png，图片原样保留。

selectable=false，当前菜单仍只有马夫蒂与联邦，没有吉翁选择或出击入口。机体池为空；ace/mp 返回 -1，lineup 返回空名单，防止跨阵营填充。后续开放需补齐机体、编队和敌对关系，再接入菜单和联机。

保留同时新增的 GP03D 联邦归属。

验证：隔离工程定向运行 ZeonFaction 13、Round15 188、LanPlan 125，共 326 PASS / 0 FAIL；合并 GP03D 归属后再测 ZeonFaction 13 PASS / 0 FAIL。未运行全项目回归。Round15 退出有资源清理警告。
