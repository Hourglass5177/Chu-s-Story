# Fusion Pixel Font

仅用于传承小游戏 v2 的清晰像素 UI；字体原件未改名、未修改。

- 项目：https://github.com/TakWolf/fusion-pixel-font
- 固定发布：https://github.com/TakWolf/fusion-pixel-font/releases/tag/2026.09.01
- 12 px 发布包：https://github.com/TakWolf/fusion-pixel-font/releases/download/2026.09.01/fusion-pixel-font-12px-proportional-ttf-v2026.09.01.zip
- 10 px 发布包：https://github.com/TakWolf/fusion-pixel-font/releases/download/2026.09.01/fusion-pixel-font-10px-proportional-ttf-v2026.09.01.zip
- 许可原文：https://raw.githubusercontent.com/TakWolf/fusion-pixel-font/2026.09.01/LICENSE-OFL
- 下载日期：2026-09-13；许可：SIL Open Font License 1.1。字体及授权文本需一同随运行资源交付。

| 文件 | SHA-256 |
| --- | --- |
| fusion-pixel-12px-proportional-zh_hans.ttf | 1b423de0be589d159ef71af7d00530a7176e16af768a26adbc2e524e8817aad9 |
| fusion-pixel-10px-proportional-zh_hans.ttf | 04de2c9adf78db676bd910fd229e16c1d70230b776579049ce82f7c6a06703f2 |
| LICENSE-OFL.txt | bc518cf64b8032c07690f33cc270c35c179255a6ac8efa7c165ebae7e8f76a63 |

正文使用 12 px 字形，辅助文字使用 10 px 字形，以至少 24/20 个实际屏幕像素显示。禁用字体抗锯齿和子像素定位，避免灰色细边污染色板；中文正文不烘焙进背景画。

运行时为独立 FontFile 设置 `fixed_size=12/10` 与 `FIXED_SIZE_SCALE_ENABLED`，缓存原始字形网格后由最近邻显示缩放；不将像素轮廓先栅格化成 53/54 等任意逻辑字号。相关 API 已核对 Godot 4.7.2 的 TextServerAdvanced `_get_size` 与字形缩放实现。字体原件不因此改变。
