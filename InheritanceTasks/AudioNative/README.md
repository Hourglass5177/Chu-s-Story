# 黄梅戏本地音高分析扩展

该扩展仅负责在 Windows x86_64 上使用 ONNX Runtime CPU 执行轻量 CREPE 音高模型，向 GDScript 返回时间、音高和置信度序列。歌词完整度、移调对齐、节奏比较、两句门槛和任务事务仍由 Godot 规则层处理。

- 模型只在评分器首次使用时从 `res://` 读取并初始化一次。
- 推理接口是同步的；调用方必须在工作线程执行，并在主线程接收结果。
- 录音数据由调用方传入，不在扩展中写盘、上传或持久化。
- 模型、运行库版本、哈希与许可证见项目媒体授权/第三方组件记录。

本地构建示例：

```powershell
cmake -S InheritanceTasks/AudioNative -B .build/chuwuzhi-audio `
  -G "Visual Studio 17 2022" -A x64 `
  -DGODOT_CPP_DIR=F:/Temp/godot-cpp-4.5 `
  -DONNXRUNTIME_ROOT=F:/Temp/chuwuzhi_onnx/package
cmake --build .build/chuwuzhi-audio --config Release
```

构建使用的 `godot-cpp` 必须与目标 Godot 版本保持前向兼容；当前二进制使用 4.5 分支构建并以 4.5 为最低兼容版本，在项目固定的 Godot 4.6.2 上验证。
