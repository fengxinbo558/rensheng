# 声音导演

一款以本地离线处理为主的 macOS 普通话朗读应用。主流程只需加入文字、PDF 或网页，选好音色并点击生成；应用会自动整理朗读段落、保存进度并导出成品。

## 当前功能

- 普通话长文朗读，单项目最多 30000 字
- 支持粘贴文字、可搜索 PDF 和网页正文；网页只在获取原文时联网，提取后的整理、生成和保存仍在本机完成
- “我的听读”保存来源、生成状态和上次播放位置，可从中断处继续听
- 默认把同一自然段整理为连续语义段，减少短句反复起调；数字、日期、英文术语和原文用词会经过离线保真检查
- 原文与实际朗读稿分开保存，整理不安全时自动回到逐字朗读
- 自然人声模型在同一次任务中保持常驻，自动安排语义段与停顿，支持失败重试和断点继续
- 个人音色默认使用说话人特征嵌入，避免每个片段开头复读参考录音最后几个字
- 完成后自动生成 WAV、M4A 和 MP3，可发给没安装本应用的人播放
- 播放、暂停、停止和 0.1×–3.0× 调速，步进 0.1×
- 高级编辑默认折叠；需要时可切换自然讲解／逐字朗读、对照原文、修改单段朗读稿、恢复原文、调整节奏或只重做一段
- 录制或导入自定义音色，自动检查音量、爆音和环境底噪
- 干净录音优先保留原声细节；明显底噪时自动使用清理版
- 根据本机内存和本地资源自动选择生成引擎

自定义音色仅限本人声音，或已获得声音所有者明确授权的声音。

## 设备策略

口语整理和 PDF 正文提取使用确定性本地规则，不需要额外文字模型，内存开销远低于语音生成。应用会根据本机内存和包内资源自动选择自然人声或兼容路线，不会提示或执行系统升级。

真实 M1 8GB 和 16GB 的 30000 字长跑仍需完成后才能标注正式支持；在此之前以兼容路线作为低配安全后备，不用开发机限额测试冒充真实设备结论。

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

除用户主动导入网页时的原文获取外，应用运行不依赖网络，也不会安装或修改系统组件。便携构建内含自然人声路线、兼容路线及其运行时，不再打包实验性的情绪表演模型。

口语导演层选择性参考了 MIT 许可的 [Open Notebook](https://github.com/lfnovo/open-notebook) 与 [Podcast Creator](https://github.com/lfnovo/podcast-creator) 工作流；来源、固定提交与修改边界见 `ThirdParty/OpenNotebook/NOTICE.md`。

网页正文提取使用 Apache-2.0 许可的 Mozilla Readability；固定版本、校验值与集成边界见 `ThirdParty/Readability/NOTICE.md`。

当前应用使用临时签名，适合本机验证。要分发给其他 Mac 用户，还需开发者签名和 Apple 公证。

MP3 导出使用包内 LAME 3.100，其许可证与源码包一同保存在 `Runtime/MP3Encoder/`。
