# 黄梅戏本地音高分析扩展

该扩展在 Windows x86_64 上提供两个独立适配器：`WindowsVocalCapture` 采集麦克风；`CrepePitchExtractor` 使用 ONNX Runtime CPU 执行轻量 CREPE 音高模型。发声完整度、移调对齐、节奏比较、两句门槛和任务事务仍由 Godot 规则层处理。

- 模型只在评分器首次使用时从 `res://` 读取并初始化一次。
- 推理接口是同步的；调用方必须在工作线程执行，并在主线程接收结果。
- 录音只在内存中处理，不写盘、上传或持久化。
- 模型、运行库版本、哈希与许可证见项目媒体授权/第三方组件记录。

本地构建示例：

```powershell
cmake -S InheritanceTasks/AudioNative -B .build/chuwuzhi-audio `
  -G "Visual Studio 17 2022" -A x64 `
  -DGODOT_CPP_DIR=F:/Temp/godot-cpp-4.5 `
  -DONNXRUNTIME_ROOT=F:/Temp/chuwuzhi_onnx/package
cmake --build .build/chuwuzhi-audio --config Release
```

构建使用的 `godot-cpp` 必须与目标 Godot 版本保持前向兼容；当前二进制使用 4.5 分支构建并以 4.5 为最低兼容版本。工程使用 Godot 4.7，验证固定 4.7.2；不要把扩展的最低兼容版本当成工程引擎版本。

Windows 导出必须区分 godot-cpp 的引擎目标。`cmake --build --config Release` 只选择 MSVC 优化配置，**不会**把默认的 `GODOTCPP_TARGET=template_debug` 改成 `template_release`。两种目标在内存预留空间的处理上不同，混用可能导致 Release 程序退出时发生堆损坏。

- 编辑器与 Debug 导出使用 `GODOTCPP_TARGET=template_debug`，输出 `chuwuzhi_audio.windows.x86_64.dll`。
- Release 导出必须在独立构建目录配置 `-DGODOTCPP_TARGET=template_release`，输出 `chuwuzhi_audio.windows.release.x86_64.dll`。`.gdextension` 按引擎目标选择对应文件，保留两者。
- 本机当前编译器为 Visual Studio 18 2026。CMake/MSBuild 在中文构建路径下出现过生成文件路径乱码；编译时将本目录的 `CMakeLists.txt` 和 `src/` 复制到 ASCII 路径的临时目录，并使用独立 ASCII 构建目录，完成后把 DLL 复制回 `bin/`。
- Windows 导出预设须包含 `*.json,*.onnx`，保证指南、参考分析与模型进入 PCK。运行库和模型均需随游戏分发；不得靠开发机上的文件补足导出包。
- 打包时还需从 Visual Studio 的 `VC/Redist/MSVC/.../x64/Microsoft.VC145.CRT` 复制 `msvcp140.dll`、`msvcp140_1.dll`、`vcruntime140.dll`、`vcruntime140_1.dll` 到游戏 EXE 同目录，并附组件说明。当前 ONNX Runtime 和扩展都依赖这些运行库；不要复制开发机的系统 DLL。

音频链路诊断（不打开麦克风、不保存录音）：

```powershell
& "F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --log-file artifacts/huangmei-probe.log -s tools/probe_huangmei_scoring.gd -- --reference
```

使用授权参考唱段经过真实录音效果器与本地模型，输出录音收尾、PCM 解码、模型加载、推理和比较耗时，以及主线程最大帧间隔。省略 `--reference` 使用静音样本。自动回归入口为 `test_huangmei_audio_pipeline.gd`。这些是无麦克风自动验证，不能代替实机权限、设备和真人录唱检查。

## Windows 麦克风采集修复

Godot 4.7.2 的 WASAPI 输入仅处理单/双声道。遇到四声道麦克风，它会逐帧报错并填入静音。因此正式录唱不再创建 `AudioStreamMicrophone`，项目关闭引擎内置输入；也不会改玩家的 Windows 默认设备或录音格式。

`WindowsVocalCapture` 在独立线程打开 Windows 默认多媒体输入，使用 WASAPI 共享模式的 `AUTOCONVERTPCM` 将设备格式转换为 16 kHz 单声道 float。打开设备、读取、释放 COM 对象均在同一线程。暂停时持续排空但丢弃样本；录制时长只计算有效录制区间的样本数。断流、拔出设备、无法转换和权限错误返回技术错误；取消会停止采集并清空内存。上层对数字静音、恒定直流和非有限样本也拒绝评分。

仅协商格式、不录音：

```powershell
& "F:/godot 4.7.2/Godot_v4.7.2-stable_win64_console.exe" --headless --path . -s tools/probe_huangmei_microphone.gd
```

经测试者明确同意，可追加 `-- --capture` 做一次 3 秒真实采集检查。只输出声道、采样率、时长、音量与错误状态，不输出或保存声音。`tools/audit_huangmei_reference.gd` 则只离线分析授权参考音频，辅助核对参考曲线，不访问麦克风。

Windows API 依据：[采集流](https://learn.microsoft.com/en-us/windows/win32/coreaudio/capturing-a-stream)、[GetBuffer 与断流标记](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudiocaptureclient-getbuffer)。
