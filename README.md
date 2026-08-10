# 声音导演

一款完全离线的 macOS 普通话朗读应用。主流程只需选音色、粘贴文字、点击“生成音频”；应用会自动拆分朗读段落、保存进度并导出成品。

## 当前功能

- 普通话长文朗读，单项目最多 3000 字
- 自动拆分声音片段、安排停顿、失败重试和断点继续
- 完成后自动生成 WAV、M4A 和 MP3，可发给没安装本应用的人播放
- 播放、暂停、停止和 0.1×–3.0× 调速，步进 0.1×
- 高级编辑默认折叠；需要时可修改单段文字、调整节奏、切换候选版本或只重做一段
- 只录入一次自然声音，即可在高级编辑中为每段选择自然、开心、兴奋、悲伤或愤怒
- 非自然情绪提供轻微、自然清楚、较强三档；默认使用克制的“轻微”，不靠变调或增大音量伪造情绪
- 录制或导入自定义音色，自动检查音量、爆音和环境底噪
- 干净录音优先保留原声细节；明显底噪时自动使用清理版
- 根据本机内存和本地资源自动选择生成引擎

自定义音色仅限本人声音，或已获得声音所有者明确授权的声音。

## 设备策略

在当前 32GB 开发机的短句测试中，本地情绪人声进程的峰值内存约 1.8GB。macOS 15 或更高版本且包内资源完整时，应用会优先使用这条路线；不满足条件时会自动回到原有离线引擎，不会提示或执行系统升级。

1.8GB 是当前电脑上的实测结果，不能代替真实低配设备验证。真实 M1 8GB 和 16GB 长跑尚未完成，因此当前只能称为候选兼容，不作正式支持承诺。

## 构建与自检

```sh
zsh spike/packaging/cli-swiftui-probe/tests/run-self-tests.sh
BUILD_FLAVOR=portable zsh spike/packaging/cli-swiftui-probe/build.sh
```

构建结果：

```text
spike/packaging/cli-swiftui-probe/build/声音导演.app
```

## 本地数据

```text
~/Library/Application Support/LocalAudioProbe/Voices/
~/Library/Application Support/LocalAudioProbe/Projects/
~/Library/Application Support/LocalAudioProbe/voices.json
~/Music/本地音频概览/
```

应用运行时不依赖网络，不会安装或修改系统组件。便携构建内含本地情绪模型、原有后备路线及其运行时。情绪模型首次使用可能需要较长的一次性准备，之后短句生成会明显加快。

当前应用使用临时签名，适合本机验证。要分发给其他 Mac 用户，还需开发者签名和 Apple 公证。

MP3 导出使用包内 LAME 3.100，其许可证与源码包一同保存在 `Runtime/MP3Encoder/`。
