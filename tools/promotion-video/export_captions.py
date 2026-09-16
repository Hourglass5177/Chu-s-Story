from pathlib import Path
import json
R=Path(__file__).resolve().parents[2]; P=R/'artifacts/promotion-2026/字幕文案';P.mkdir(exist_ok=True)
plan=json.loads((Path(__file__).parent/'timeline.json').read_text(encoding='utf8'))
refs={}; lines=['# 宣传视频字幕文案','', '每个 TXT 只有一条正文，可直接修改。改好后告诉我，再统一接入。当前 MP4 仍使用原稿。','']
for s in plan['shots']:
 text=s['caption']
 if text not in refs:
  n=len(refs)+1; name=f'{n:02}_字幕.txt'; refs[text]=name
  path=P/name
  if not path.exists():path.write_text(text+'\n',encoding='utf-8-sig')
  lines.append(f'- {s["from_seconds"]:g} 秒起：[第 {n} 条]({name}) — {text}')
if not (P/'字幕索引.md').exists():
 (P/'字幕索引.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
(Path(__file__).parent/'caption-map.json').write_text(json.dumps(refs,ensure_ascii=False,indent=2),encoding='utf8')
print(P)
