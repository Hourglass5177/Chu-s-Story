# 中国乐器方向音效 · 采样来源

## 第五版增量：成就与结算

沿用下方CC0古筝源 `guzheng-847157-hq.mp3`。结算为原速低弦单音；成就将邻近录音有限变调（≤4半音）组成五音上行，末尾轻叠低根音/五度，加入低电平早期反射。不改其他音效来源，不恢复锣层。具体起点、音高和增益记录在 `Audio/SFX/manifest.json` 的 `achievement-result-v5` 两项。

## 第四版增量：布头槌木鱼

- 文件：`mokugyo-607215-hq.mp3`；jonopodmore，原名 **Mokugyo.wav**。
- 发布页：https://freesound.org/people/jonopodmore/sounds/607215/ ，授权 **CC0 1.0**。
- 公开 HQ MP3：https://cdn.freesound.org/previews/607/607215_541139-hq.mp3 。这份下载为有损预览，不是原始无损 WAV。
- 作者描述：来自日本高野山的小木鱼，使用原配布头槌敲击。用于木鱼打击乐音色，不声称为中国产器物或湖北非遗录音。
- 当前用于确认（含选择/页签按钮）、返回（含取消/关闭）、响应、无效操作、倒计时和技术提示。原速取单次轻敲，180Hz 高通、1650–2400Hz 低通、7ms 软起音、60ms 尾部渐收；固定低增益，无变调、叠弦和额外混响。
- 发布页快照：`artifacts/board-audio/mokugyo-source.html`；源与输出 SHA-256 见 `Audio/SFX/manifest.json`。

以下是第二版来源历史。第三版已撤掉锣与变调；第四版将上述六项统一换成木鱼，古筝只保留回合、行动、事件、恢复、成就、淘汰和结算。

## 第二版历史来源

2026-09-15。用户要求大多数主体提示音改用中国乐器音色，特别否定旧返回声。以下均从 Freesound 发布页核对 CC0；所下载的是发布者公开的 HQ MP3 预览，不冒充原始无损 WAV。供本项目裁切、调音、止音、排列短乐句，原文件保留。

| 文件 | 发布者 / 原始标题 | 来源与授权 | 用法 |
|---|---|---|---|
| guzheng-847157-hq.mp3 | nanliu_music / GUZHENG - instrument- Single Note - Sound | https://freesound.org/people/nanliu_music/sounds/847157/ · CC0 | 古筝实录中两次独立拨弦（约 0.029 秒、7.400 秒）取样；确认、返回、回合、行动、事件、响应、恢复、成就、淘汰、结算 |
| gong-76886-hq.mp3 | airtaxi / Gong.wav，作者描述 Chinese gong | https://freesound.org/people/airtaxi/sounds/76886/ · CC0 | 约 0.90 秒起的锣声，滤除低频与高频噪声后轻叠成就/结算，不作为大响锣 |
| temple-block-544881-hq.mp3 | ashboy34 / smallestgranitedry.wav | https://freesound.org/people/ashboy34/sounds/544881/ · CC0 | 止音、短敲击；错误、倒计时与技术提示 |

第三项由 Temple block 衍生条目（https://freesound.org/people/Sadiquecat/sounds/742277/）溯源取得原始干声。原作者说明是具有中空木声的硬塑材质物件，因此这里只称“木鱼式”敲击音色，不称传统木鱼实录。古筝与锣按原发布者对乐器的描述标注；未声称是编钟、古琴或湖北非遗特定器物。

CC0 1.0：https://creativecommons.org/publicdomain/zero/1.0/ 。无需署名，但此处保留作者信息。源文件与输出 SHA-256 记录在 `Audio/SFX/manifest.json`；发布页快照保存在 `artifacts/board-audio/*-source.html`。

处理工具：`tools/build_board_sfx.py`。短乐句采用 D 宫五声材料，按语义使用清拨、双音、低弦、上行拂弦和阻尼收音；采样采用带抗混叠重采样的有限变调，实际起音和琴体共鸣来自录音。不是此前正弦泛音公式更改名称。
