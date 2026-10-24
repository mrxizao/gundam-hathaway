import io, sys


def has_cjk(s):
    for ch in s:
        if ord(ch) > 0x2000:
            return True
    return False


def strip_comment(raw):
    l = ''
    in_str = False
    for ch in raw:
        if ch == '"':
            in_str = not in_str
            l += ch
            continue
        if ch == '#' and not in_str:
            break
        l += ch
    return l


def code_segments(code):
    segs, cur, ins = [], '', False
    for ch in code:
        if ch == '"':
            segs.append(('str' if ins else 'code', cur))
            ins = not ins
            cur = ''
        else:
            cur += ch
    segs.append(('str' if ins else 'code', cur))
    return segs


def bad_segments(code):
    return [s for k, s in code_segments(code) if k == 'code' and has_cjk(s)]


def fix_code(code):
    """把 "A"B"C" 里的 B（含中文的代码片段）变成 「B」 —— 删掉夹在中间的那对引号。"""
    pos = [i for i, ch in enumerate(code) if ch == '"']
    out = list(code)
    changed = False
    for j in range(1, len(pos) - 1, 2):
        a, b = pos[j], pos[j + 1]
        if has_cjk(code[a + 1:b]):
            out[a] = '「'
            out[b] = '」'
            changed = True
    return ''.join(out), changed


mode = sys.argv[1]
for p in sys.argv[2:]:
    # 只管 GDScript 一族：本扫描器**扫自己**会报一堆"需人工处理"（Python 的
    # 三引号 docstring 里必然带引号又带中文），那是噪音不是缺陷 —— 直接跳过。
    if not p.endswith(('.gd', '.tscn', '.tres')):
        print('=== %s ===' % p)
        print('跳过：不是 GDScript 族文件（本扫描器只判 .gd/.tscn/.tres）')
        continue
    raw_lines = io.open(p, encoding='utf-8').read().split('\n')
    hits, fixable, new = [], [], []
    for i, raw in enumerate(raw_lines, 1):
        code = strip_comment(raw)
        if bad_segments(code):
            fixed, changed = fix_code(code)
            left = bad_segments(fixed)
            if not changed or left:
                hits.append((i, raw, left or ['(无法自动修复)']))
                new.append(raw)
                continue
            fixable.append((i, raw))
            new.append(fixed + raw[len(code):])
        else:
            new.append(raw)
    print('=== %s ===' % p)
    if fixable:
        print('● 可自动修复 %d 行：' % len(fixable))
        for i, l in fixable:
            print('%4d  %s' % (i, l))
    if hits:
        print('★ 需人工处理 %d 行：' % len(hits))
        for i, l, s in hits:
            print('%4d  %s   << %s' % (i, l, s))
    if not fixable and not hits:
        print('OK：没有"代码片段里混着中文"的行')
    if mode == 'fix':
        io.open(p, 'w', encoding='utf-8', newline='').write('\n'.join(new))
