"""Re-import only explicit character speech from the supplied M09 adaptation."""
from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]
source=root/'data/script/m09_precision_defense_source.txt'
act=0;lines=[]
for text in source.read_text(encoding='utf-8-sig').splitlines():
    chapter=re.match(r'第([一二三四五])幕',text)
    if chapter:act='一二三四五'.index(chapter[1])+1
    row=re.match(r'^(雷恩|加乌曼|哈萨维)(?:（([^）]+)）)?：(.+)$',text)
    if row:lines.append(dict(id=f'm09_script_{len(lines)+1:03d}',act=act,speaker=row[1],kind=row[2] or '座舱',text=row[3]))
bank=root/'scripts/data/m09_dialogue.gd'
text=bank.read_text(encoding='utf-8')
text,count=re.subn(r'const LINES := .*?\nconst INTRO :=',lambda _: 'const LINES := '+json.dumps(lines,ensure_ascii=False,indent=2)+'\nconst INTRO :=',text,flags=re.S)
assert count==1
bank.write_bytes(text.replace('\n','\r\n').encode('utf-8'))
(root/'data/script/m09_precision_defense_dialogue.json').write_text(json.dumps(lines,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Imported {len(lines)} M09 character lines; stage directions excluded.')
