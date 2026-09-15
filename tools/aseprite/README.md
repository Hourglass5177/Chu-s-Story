# Aseprite 本机制作工具链

> 历史归档（2026-09-15）：用户已改用直接图像生成，本目录只保留旧源文件、工具版本与复现方法。不要将 `build_p1.py`、`build_r2_review.py` 的输出覆盖当前生成素材和审查页面；当前制作要求以 AGENTS.md 最新段落为准。

本目录维护《楚物志》的像素素材制作工具链。绘画源文件与绘画 Lua 由对应美术任务维护；这里的 `verify_toolchain.lua` 只是两个方块组成的工具验证夹具，不是游戏素材。

## 固定版本与位置

- Aseprite：`v1.3.18.5`，官方源代码包。
- 本次自行编译的版本字符串为 `Aseprite 1.3.18.5-dev`、Lua API 41；`-dev` 来自源码构建标记，不表示使用了未固定的主分支。
- Skia：该 Aseprite 版本 `INSTALL.md` 指定的 `aseprite-m124`，使用官方 `m124-08a5439a6b` Windows Release x64 开发库。
- 本机根目录：`F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/`。
- 编译结果：`F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/build/bin/aseprite.exe`。
- Python：使用 Codex 捆绑运行时；验证脚本需要 Pillow，不需要外部 Lua。
- 编译器：Visual Studio 2022 / MSVC x64；SDK 10.0.26100.0；CMake 与 Ninja 的具体版本及哈希见 `toolchain-lock.json`。

所有依赖和编译产物在游戏工程外。本脚本只给子进程设置编译环境，不更改全局 PATH、注册表或用户偏好。

## 重新编译

从工程根目录运行：

```powershell
& 'C:/Users/ROG/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/aseprite/build_toolchain.py
```

脚本先校验固定包哈希，再配置和编译。已有包和完整解压目录会复用，不删除目录。源码包的哈希已与 GitHub release asset 的官方 digest 比对；旧 Skia release 没有提供官方 digest，记录的是本次从官方 release 下载后计算的 SHA256。不能把后者称为第三方签名验证。

`--root`、`--vsdevcmd`、`--cmake`、`--ninja`、`--jobs` 可覆盖本机路径与并行数；默认并行数为 8。CMake 4 使用 `CMAKE_POLICY_VERSION_MINIMUM=3.5` 兼容第三方库历史配置。

## 绘画与导出

```powershell
& 'F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/build/bin/aseprite.exe' --batch --script-param output='F:/Documents/楚物志/artifacts/preview' --script '你的绘画脚本.lua'
& 'F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/build/bin/aseprite.exe' --batch '你的源文件.aseprite' --sheet-type horizontal --sheet '图集.png' --data '图集.json' --format json-array --list-layers --list-tags --list-slices
```

脚本参数放在 `--script` 前。需要精确帧尺寸与锚点的游戏资源默认不使用逐帧自动裁切。美术源文件保留图层、时间轴、标签与锚点；PNG/JSON 是导出物。

API 以固定版本的实际引擎和 [官方 Lua 文档](https://www.aseprite.org/api/)为准。使用 `app.open()` 打开文件、`sprite:setPalette()` 设置色板，不能照抄未经核对的第三方速查表。绘画可由 Lua 逐像素、成组色块与图层操作完成；工具可确定性重放，不代表无需看图修正。

## 工具链验证

```powershell
& 'C:/Users/ROG/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/aseprite/verify_toolchain.py
```

结果写入 `artifacts/aseprite-toolchain/`。验证会真的调用 Aseprite，创建并重新打开可编辑源文件，导出 PNG/JSON，再检查：两层、两帧、100/150 ms、动画标签、脚底 pivot、固定三种可见颜色、二值透明，以及两帧恰好一个预期像素发生变化。验证不录音，不调用图片生成服务，不修改游戏素材。

2026-09-13 本机编译已成功，上述八项检查已通过。可执行文件 SHA256 为 `9603198bf22020f97650fa6f3dc091cd7b2872ddd0093be28adf158febe96105`。这只证明工具链能生成、保留并导出结构化像素资产，不证明具体游戏素材已通过审美验收。

## P1 素材导出与检查

```powershell
& 'C:/Users/ROG/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/aseprite/export_p1_assets.py
```

遍历 `InheritanceTasks/Art/Pixel/v2/source/`，由真实 Aseprite CLI 将所有源文件导出到 `runtime/` 下的同一相对路径，PNG 图集横向排列并保留完整帧尺寸；JSON 包含图层、标签、切片及帧时长。角色为14帧，风箱8帧，炉火6帧，其余当前P1文件为静态。宽高从每个源文件的真实文件头读取，不假定所有资产相同。

报告 `artifacts/pixel-v2/asset-validation.json` 包含色板外颜色、二值透明、尺寸、源文件哈希、颜色预算警告和动作逐帧差异。`color-counts.json`、`action-deltas.json` 便于单独查看。六角色对照图和神农八帧跑步图仅把已导出的像素整数放大并拼合，Pillow 不参与运行素材绘画。

色数超预算或动作相邻帧完全相同会报告为待美术检查，不擅自修改源文件。即使报告没有错误，也必须完成真实背景、正常速度、六角色及黑白底的视觉审查；详见 `PIXEL_STANDARD.md`。

## 已安装的知识技能

`pixel-art-studio` 来自 [Gamezxz/pixel-art-studio](https://github.com/Gamezxz/pixel-art-studio)，固定 commit `f8c246635c4621a6c2b427833149afdc3dc3c719`，通过 Codex 的 `skill-installer` 安装至 `F:/Tools/OpenAI/CodexHome/skills/pixel-art-studio/`，MIT 许可原文随技能保留。

本项目只采用其中的有限色板、剪影、色块、动画循环与逐轮看图检查知识。用户指定 Aseprite 为制作主工具，优先于该技能建议的 Pillow 工作流。不能把其默认材质公式、每种色块最少像素数等建议当成不可变美术定律，也不执行未经审阅的外部代码。

## 许可与交付边界

Aseprite 是源码可读的商业软件。其[官方 FAQ](https://www.aseprite.org/faq/)允许用自行编译版本创作和销售自己的美术；[EULA](https://github.com/aseprite/aseprite/blob/v1.3.18.5/EULA.txt)不允许向第三方分发程序副本。

可以交付本项目自有 `.aseprite`、Lua、PNG、JSON、色板及相关说明。**不要把 `aseprite.exe`、本机编译目录或编辑器安装包放进游戏/美术交付 ZIP。** 工具链源码与第三方素材许可分别记录；不得把看过的网络参考图当作可发布素材。

官方依据：[该 tag 的编译说明](https://github.com/aseprite/aseprite/blob/v1.3.18.5/INSTALL.md)、[命令行说明](https://www.aseprite.org/docs/cli/)、[Sprite API](https://github.com/aseprite/api/blob/main/api/sprite.md)。
