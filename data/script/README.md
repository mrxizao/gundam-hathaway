# 剧本源（**真源**，不是产物）

`h1_dialogue.csv` / `h2_dialogue.csv` 是老板交付的两份《闪光的哈萨维》台词剧本：

| 文件 | 来源 | 行数 |
|---|---|---|
| `h1_dialogue.csv` | 闪哈1 · 说话人标注版（`[POPGO]…chs.ass` 为底本） | 1318 |
| `h2_dialogue.csv` | 闪哈2 · 结构化表 | 1731 |

**这两个文件是真源，别手改**（改了就与工作区里那份交付物分家）。
工程里用的台词库 `scripts/data/comms_bank.gd` 是它的**投影**，重建方式：

```
python tools/import_script.py
```

## 为什么这个目录里有 `.gdignore`

Godot 内建 **CSV 导入器**（把 CSV 当翻译表导成 `CSVTranslation`）。它看见这两个文件会
按「第一行是 `keys,en,ja…`」去解析，解析失败就在编辑器里刷一串警告 —— 而这两个 CSV
跟翻译表毫无关系，只是**数据**。`.gdignore` 让资源扫描器整个跳过本目录。

⚠️ 存档：`data/script/` 不参与导出（没有代码在运行时读它）—— 这是**故意的**，
生成物才是进构建的那一份。
