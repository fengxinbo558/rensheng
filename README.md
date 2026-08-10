# 声音导演

一款完全离线的 macOS 普通话朗读应用。主流程只需选音色、粘贴文字、点击“生成音频”；应用会自动拆分朗读段落、保存进度并导出成品。

## 当前功能

- 普通话长文朗读，单项目最多 3000 字
- 默认把文章整理成适合说话的自然短句；数字、日期、英文术语和原文用词会经过离线保真检查
- 原文与实际朗读稿分开保存，整理不安全时自动回到逐字朗读
- 自动安排声音片段与停顿，支持失败重试和断点继续
- 完成后自动生成 WAV、M4A 和 MP3，可发给没安装本应用的人播放
- 播放、暂停、停止和 0.1×–3.0× 调速，步进 0.1×
- 高级编辑默认折叠；需要时可切换自然讲解／逐字朗读、对照原文、修改单段朗读稿、恢复原文、调整节奏或只重做一段
- 录制或导入自定义音色，自动检查音量、爆音和环境底噪
- 干净录音优先保留原声细节；明显底噪时自动使用清理版
- 根据本机内存和本地资源自动选择生成引擎

自定义音色仅限本人声音，或已获得声音所有者明确授权的声音。

## 设备策略

口语整理使用确定性本地规则，不需要额外文字模型，内存开销远低于语音生成。应用会根据本机内存和包内资源自动选择自然人声或兼容路线，不会提示或执行系统升级。

真实 M1 8GB 和 16GB 的 3000 字长跑仍需完成后才能标注正式支持；在此之前以兼容路线作为低配安全后备，不用开发机限额测试冒充真实设备结论。

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

应用运行时不依赖网络，不会安装或修改系统组件。便携构建内含自然人声路线、兼容路线及其运行时，不再打包实验性的情绪表演模型。

口语导演层选择性参考了 MIT 许可的 [Open Notebook](https://github.com/lfnovo/open-notebook) 与 [Podcast Creator](https://github.com/lfnovo/podcast-creator) 工作流；来源、固定提交与修改边界见 `ThirdParty/OpenNotebook/NOTICE.md`。

当前应用使用临时签名，适合本机验证。要分发给其他 Mac 用户，还需开发者签名和 Apple 公证。

MP3 导出使用包内 LAME 3.100，其许可证与源码包一同保存在 `Runtime/MP3Encoder/`。
