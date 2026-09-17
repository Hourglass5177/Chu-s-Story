# 宣传片制作工程

最终提交版为118秒，1920×1080。最终文件存放项目 deliverables/，最终切点为 final-timeline.json；用户定稿原文为 final-captions/，approved-subtitles/保存实际剪辑使用的逐条文字。

board_edit.py保留主体玩法版编排，short_edit.py保留118秒缩剪与混音；remotion保留工程及依赖锁文件，可用npm ci恢复依赖。

2026-09-16按用户决定回收全部原始录制、独立采集音频、试录、逐镜头渲染和旧长片。当前工程不能直接重渲染原视频；重新剪镜头需要先用record.py/capture.tscn重新录制。不要用最终片替代原始素材后宣称无损可编辑。

FFmpeg仍使用项目artifacts/media-20260909/toolchain中的现有工具链。采集只针对指定游戏窗口和游戏总线，不录麦克风；同机其他项目运行时须校验窗口所属进程。
