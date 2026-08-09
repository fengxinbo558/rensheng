# LocalAudioProbe

这是用 Command Line Tools 直接编译的 macOS SwiftUI 技术探针，不需要完整 Xcode，也不会修改 macOS。

## 当前功能

- 本地普通话文本转 WAV
- 内置参考音色试听
- 麦克风录制自定义音色
- 导入 WAV、M4A、MP3 等 macOS 可读取的音频
- 自动检测录音音量、削波和环境底噪
- 使用 GTCRN 对参考音频进行完全离线降噪
- 保留原始录音，并支持原音与降噪音色对比试听
- 快速（4 步）和标准（8 步）两档生成质量
- 生成结果自动去孤立爆音、抑制停顿底噪并安全限幅
- 多个自定义音色的本地保存、选择和删除
- 生成结果永久保存并在访达中显示

自定义音色要求用户填写与参考录音完全一致的原文，并确认声音属于本人或已经得到声音所有者的明确授权。

## 构建

```sh
zsh spike/packaging/cli-swiftui-probe/build.sh
```

构建结果：

```text
spike/packaging/cli-swiftui-probe/build/LocalAudioProbe.app
```

## 自检

```sh
zsh spike/packaging/cli-swiftui-probe/tests/run-self-tests.sh
```

## 本地数据

```text
~/Library/Application Support/LocalAudioProbe/Voices/
~/Library/Application Support/LocalAudioProbe/voices.json
~/Music/本地音频概览/
```

构建后的应用包含 TTS 运行时、语音模型、声码器和约 0.5 MB 的离线降噪模型，大小约 284 MB。运行时不依赖网络，也不会安装或修改系统组件。

当前应用使用临时签名，适合本机验证。要直接分发给其他 Mac 用户，仍需要后续完成开发者签名和公证。

离线降噪模型来自 sherpa-onnx 官方 `speech-enhancement-models` 发布，当前文件 SHA-256：

```text
e77603ac0c23dac3227dd2d7135b3a585cbee2679048aecfa886657d3ae1b534
```
