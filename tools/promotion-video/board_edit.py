"""Board-game-first revision. Reads user prose; never writes authoring TXT/MD."""
from pathlib import Path
import re,json,sys
import edit
P=edit.P/'字幕文案_主体玩法版'
caps=[(P/f'{i:02}_字幕.txt').read_text(encoding='utf-8-sig').strip() for i in range(1,14)]
baseline=['在武汉，开启一场非遗旅行。','楚物志，一场走遍荆楚的桌上旅行。','走到非遗点，把当地的故事收入手中。','收集不同类别与地区，凑出你的收藏组合。','过早，再出发。各地美食，各有妙用。','旅途中，总有意想不到的事。','在非遗研究所交易，换回想要的那一张。','完成成就，让这趟旅程多一份收获。','六种博主，六种旅行方式。','和朋友同游，也能与电脑对手切磋。','亲手体验非遗，完成传承。','从一次短练习开始，踏上自己的旅程。','楚物志 · 楚行九州']
if '--apply-user-copy' in sys.argv:
 for line in (P/'字幕索引.md').read_text(encoding='utf-8-sig').splitlines():
  match=re.search(r'\[第(\d+)条\].*? — (.*)$',line)
  if match:
   i=int(match[1])-1; text=match[2].strip()
   if text!=baseline[i]: caps[i]=text
else: caps=baseline
caps=[c.replace('传承人物小游戏','传承任务小游戏') for c in caps]
approved=edit.W/'approved-subtitles';approved.mkdir(exist_ok=True)
for i,c in enumerate(caps,1): (approved/f'{i:02}.txt').write_text(c+'\n',encoding='utf8')
def s(take,start,duration,n,city='',**kw):
 return dict(take=take,start=start,duration=duration,caption=caps[n-1],city=city,**kw)
edit.SH=edit.P/'shots-board-v3';edit.SH.mkdir(exist_ok=True)
edit.shots=[
 s('board2',4.2,7,1,'武汉'),
 s('home',3,8,2,'湖北非遗文化主题桌游'),
 s('collection',5,15,3,'移动 · 收集非遗'),
 s('collection',17,8,4,'多种非遗 · 不同效果'),
 s('collection',28,5,4,'收藏组合 · 计分'),
 s('foodvariety',6,5,5,'荆楚美食'),
 s('food',18.8,7,5,'武汉 · 热干面'),
 s('event',5.5,5,6,'事件 · 旅途变化'),
 s('eventcards',6,9,6,'保留事件 · 择机使用'),
 s('market',14,14,7,'非遗研究所 · 买卖'),
 s('achievements',10,11,8,'成就 · 超越人类'),
 s('professions',9,12,9,'职业 · 不同能力'),
 s('ai',3,10,10,'电脑对手 · 真实行动'),
 s('ai',50,4,10,'电脑对手 · 补给选择'),
 s('board2',48,10,11,'武汉 · 汉剧',tv=True,music=True),
 s('tutorial',8,7,12,'入门教学'),
 s('collection',36,4,12,'详细规则'),
 s('outro',0,9,13),
]
assert sum(x['duration'] for x in edit.shots)==150
edit.BGM_WINDOW=(120,130)
edit.main()
