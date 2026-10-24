"""轮 57 一次性扫描：用「页脚契约」反查全仓还有没有页面**承诺了手柄却没实现**。

契约 = `InputSetup.hint(键盘文案, 手柄文案)` 的**第二参数**（非空即承诺）。

判据（★ 两条都是踩过坑之后才写对的）：
1. **认手柄** = 文件里出现 `InputEventJoypadButton`（事件路径）
   **或** `is_action_just_pressed` / `is_action_pressed`（轮询路径）。
   只看前者会把 `pause_menu.gd` 误判成没实现 —— 它走 `_process` 轮询，根本不需要认事件类型。
2. **必须先剔注释**。`campaign_map.gd` 的注释里**逐字引用了**施工前那句
   `if not (event is InputEventKey): return`，不剔注释就会扫出一个假阳性。
3. **"画这行提示的文件"不等于"要兑现它的文件"**。`hud.gd` 有 6 处手柄提示，
   可它零输入读取（`Input.is_action` / `InputEvent` 各 0 次），那一行字是**显示**，
   输入由 `player_controller.gd` 承担（已核实：轮询动作名）。
   ⇒ 纯显示层不算"承担者"，不计入嫌疑。
"""
import re
import glob


def strip_comments(src: str) -> str:
    """剔掉 GDScript 的 `#` 注释（跟踪引号，别把字符串里的 # 当注释）。"""
    out = []
    for line in src.split('\n'):
        res = []
        quote = ''
        esc = False
        for ch in line:
            if esc:
                res.append(ch)
                esc = False
                continue
            if ch == '\\' and quote:
                res.append(ch)
                esc = True
                continue
            if quote:
                res.append(ch)
                if ch == quote:
                    quote = ''
                continue
            if ch in ('"', "'"):
                quote = ch
                res.append(ch)
                continue
            if ch == '#':
                break
            res.append(ch)
        out.append(''.join(res))
    return '\n'.join(out)


HINT_RE = re.compile(r'InputSetup\.hint\(\s*("(?:[^"\\]|\\.)*")\s*,\s*("(?:[^"\\]|\\.)*")', re.S)

rows = []
for p in sorted(glob.glob('scripts/**/*.gd', recursive=True)):
    raw = open(p, encoding='utf-8', newline='').read()
    for m in HINT_RE.finditer(raw):
        ln = raw[:m.start()].count('\n') + 1
        pad = m.group(2).strip('"')
        if pad.strip():
            rows.append((p, ln, pad))

print('=== 承诺了「手柄键位」的位置（hint 第二参数非空）共 %d 处 ===' % len(rows))
files = {}
for p, ln, pad in rows:
    files.setdefault(p, []).append((ln, pad))
    print('  %-42s L%-5d  %s' % (p, ln, pad))

print()
print('=== 逐文件判定（注释已剔除）===')
bad = []
for p in sorted(files):
    code = strip_comments(open(p, encoding='utf-8', newline='').read())
    by_event = 'InputEventJoypadButton' in code
    by_poll = ('is_action_just_pressed' in code) or ('is_action_pressed' in code)
    # 纯显示层：没有任何输入读取 ⇒ 那行字是"显示"，兑现者在别处（如 hud.gd ↔ player_controller.gd）
    display_only = (not by_event) and (not by_poll) \
        and ('Input.is_action' not in code) and ('InputEvent' not in code)
    if by_event:
        how = '事件'
    elif by_poll:
        how = '轮询'
    elif display_only:
        how = '纯显示层（兑现者在别处）'
    else:
        how = '——'
    ok = by_event or by_poll or display_only
    print('  %-42s 认手柄=%-5s (%s)' % (p, str(ok), how))
    if not ok:
        bad.append(p)

print()
if bad:
    print('★★ 仍是「承诺了没实现」的：')
    for p in bad:
        print('   ', p)
else:
    print('★ 全仓没有第二处「承诺了没实现」的页面 —— 本轮两处就是全部。')
