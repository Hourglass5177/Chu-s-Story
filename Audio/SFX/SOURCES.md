# 主体音效来源与处理

## 第五版（当前）：成就华彩与结算单音

按用户最新要求，仅重做achievement/result：成就1.90秒五音上行古筝与轻和弦落点，有限邻近采样变调（≤4半音），少量早期反射；结算0.65秒原速低弦单音。两者均来自现有CC0 `guzheng-847157-hq.mp3`，不新增第三方音源、不叠锣。其他17个音效逐字节保留，当前清单中两项标记 `achievement-result-v5`。第四版备份在 `artifacts/board-audio/pre-fanfare-v4/`，试听页两项置顶、新旧对照。

## 第四版（历史）：高频操作改为木鱼轻点

用户要求确认、返回等频繁播放的提示采用轻声中国打击乐音色。确认/选择、返回/取消/关闭、响应改为 140–160ms 木鱼单点；确认稍清晰，返回用更低的滤波截止频率和更小增益收暗，保持原速，不用低音变调。无效操作、倒计时与技术提示同时换用布头槌木鱼录音，统一材质；倒计时两点、第二点更轻。

本版共修改 6 个 WAV，其他 13 个（含古筝状态提示和实物拟音）逐字节保留。新源为 jonopodmore 的 CC0 `Mokugyo.wav`，作者描述为日本木鱼，不声称湖北器物录音；详见 `Audio/Source/chinese-instruments/SOURCES.md`。固定低增益、7ms 起音和60ms 尾部渐收，无额外混响。旧版归档 `artifacts/board-audio/pre-percussion-v3/`。

试听页默认游戏响度，增加确认/返回交替8次的连续试听，可叠加 BGM 检查高频操作。当前清单标记 `soft-percussion-v4` 的6项为本次修改，其余保留第三版标记；播放检查与用户听感认可分别记录。

## 第三版（历史）：轻声与原速采样

用户否定第二版音色不自然、过重和突兀。本版继续重做同样 13 个提示音，使用原速古筝录音的一至两音，撤掉变调、密集音阶和叠锣；锣的源文件保留归档，当前不参与导出。返回改为轻收单音，不使用降调滑音。

弦声采用 120ms 柔起音、220ms 渐收与温和高低通；木鱼式材质敲击保持原速并削弱冲击。使用固定增益保留相对动态，不再把每个柔化后的提示重新归一到同一个峰值。13 个提示的文件峰值较第二版降低约 4.9–8.9dB。6 个物件拟音逐字节保留，BGM 不变。

构建入口 `tools/build_board_sfx.py`，当前清单标记 `soft-natural-v3`。第二版归档 `artifacts/board-audio/pre-soft-v2/`。试听页默认读取游戏代码中的单音效/总线增益，可切换素材原始响度；新旧采用相同试听增益，支持同时播放 BGM、避免多条提示叠响。浏览器/系统设备仍可能改变实际输出。此处描述制作和检查结果，不代表用户听感验收。

## 第二版（历史，用户已否定听感）

用户要求“大多数音效”整体改成中国乐器音色，并否定旧返回音。本轮重做 13/19：confirm、back、invalid、turn、action、warning、recover、event、response、achievement、result、eliminate、technical。采用古筝实录、轻叠中国锣及木鱼式干敲击，详见 `Audio/Source/chinese-instruments/SOURCES.md`。均为 CC0 采样加工，当前这 13 个不再采用第一版正弦合成或 Kenney 返回/确认/错误音。

另外 6 个 dice_roll、dice_land、card、page、trade、move 保留原物件拟音。旧版音频归档在 `artifacts/board-audio/pre-chinese-v1/`，试听页左新右旧。以下为第一版来源历史，不能作为当前 manifest 的替代。

2026-09-15。共 19 个短音效，事件到源文件、SHA-256 和时长记录在 `manifest.json`。

## CC0 拟音与界面音

- [Kenney Casino Audio 1.1](https://kenney.nl/assets/casino-audio)：骰子滚动/落定、纸牌滑动/翻动、筹码碰撞。项目用于桌游骰子、卡牌、交易和棋子。
- [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds)：click_003、back_001、error_003，用于确认、返回和无效操作。
- 原包授权分别保存在 `casino-LICENSE.txt`、`interface-LICENSE.txt`，允许个人及商业项目使用，CC0。
- 原包缓存：`artifacts/board-audio/sources/`。`tools/build_board_sfx.py` 用 FFmpeg 将选中的片段转为 44.1 kHz、16 位、单声道 WAV，短淡入淡出，峰值整理至约 -6.4 dBFS；运行时再按类别混音。素材没有循环标记。

## 本项目合成

turn、action、warning、recover、event、response、achievement、result、eliminate、technical 由 `tools/build_board_sfx.py` 预先合成：正弦基音、弱非整数泛音、软起音与指数衰减。配方与音符频率在代码及 manifest 中。不是实际湖北非遗乐器录音，不使用语音、模型或网络生成服务。

程序合成在构建阶段完成；运行时只加载缓存、播放短音频。所有随机变调用 BoardSfx 独立随机源，不消耗游戏规则 RNG。

试听入口：`artifacts/board-audio/sfx-review.html`。旧页面曾直接播放素材原始电平，第三版已改为默认应用游戏增益。资源通过与实际输出检查不代表已通过用户听感验收。
