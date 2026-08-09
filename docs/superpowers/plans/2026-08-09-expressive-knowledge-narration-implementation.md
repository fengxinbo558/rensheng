# 本地普通话“声音导演”实施计划

- 日期：2026-08-09
- 依据设计：`docs/superpowers/specs/2026-08-09-expressive-knowledge-narration-design.md`
- 实施原则：先完成可试听的纵向闭环，再扩展项目界面；所有依赖项目内隔离，不修改 macOS。

## 1. 当前基线

### 已有能力

- SwiftUI 原生 macOS 应用，最低 macOS 14，Apple Silicon arm64。
- ZipVoice INT8 轻量引擎、GTCRN 参考音频降噪、WAV 后处理。
- 自定义音色录制/导入、质量检测、音色库和文件导出。
- 两组现有 Swift 自检：音色库与旧数据迁移。

### 已验证但尚未接入应用

- Qwen3-TTS 0.6B Base 8bit 模型：约 1.9GB。
- Python 3.12 + `mlx-audio==0.4.7` 运行环境：最小可用解释器与依赖约 550MB；`.uv-cache` 不进入应用。
- DeepFilterNet v3 模型：约 8.3MB。
- 用户认可的 G 路线：4.55 秒短参考、2 秒流式间隔、DeepFilterNet 轻度混合。

### 主要风险

1. 现有 Qwen 探针含用户绝对路径和固定测试文本，不能直接交付。
2. 当前 Python 虚拟环境解释器是绝对路径软链接，直接复制后无法在别人的 Mac 上运行。
3. `main.swift` 同时承担界面、进程和生成状态，继续堆功能会难以恢复和测试。
4. macOS 原生 MP3 编码能力需要实测；若不可用，必须把编码器放进应用，不能要求用户安装系统软件。
5. 8GB 和 16GB 尚无真实设备证据，实施期间不能宣称已经兼容。

## 2. 交付里程碑

### M0：安全基线

目标：现有应用可重复构建、测试，并能回退。

### M1：Qwen 单段纵向闭环

目标：桌面应用可以用现有音色调用 Qwen G 路线，生成一段 WAV、播放并保存；不依赖用户手动打开终端。

### M2：声音导演项目闭环

目标：3000 字以内文章可分析、逐段生成、暂停恢复、局部重做并拼接。

### M3：音色表达与成品导出

目标：可选多风格参考录音、WAV/M4A/MP3 导出和非技术化主界面。

### M4：设备与质量验收

目标：32GB 完整实测；8GB/16GB 在真实设备验证后再改变兼容标签。

## 3. 任务明细

## Task 0：建立可回退的源码基线

**文件**

- 新建：`.gitignore`
- 纳入本地版本记录：`*.swift`、`Info.plist`、`build.sh`、`README.md`、`tests/*.swift`、`tests/*.sh`

**步骤**

1. 忽略 `build/`、`.DS_Store`、临时音频、Python 缓存和本地模型，不把数 GB 模型提交到 Git。
2. 在改代码前把当前源文件作为本地基线提交；不上传远端。
3. 运行现有自检和构建，记录应用大小与签名检查结果。

**验证**

```sh
zsh tests/run-self-tests.sh
zsh build.sh
codesign --verify --deep --strict build/LocalAudioProbe.app
```

**完成条件**

- 两组现有自检均通过。
- 应用构建成功并通过临时签名校验。
- `build/` 和模型没有进入 Git。

## Task 1：把 Qwen 探针改造成稳定的本地生成助手

**文件**

- 新建：`Runtime/qwen_runner.py`
- 新建：`Runtime/qwen_runner_smoke.py`
- 参考但不直接复用：`../../qwen3-mlx-python-probe/run_qwen_fast_stream_probe.py`

**接口**

生成助手必须通过参数接收：模型目录、参考音频、参考原文、目标文字、输出路径、流式间隔、随机种子和后处理档位。禁止硬编码用户名、音色 UUID、测试文本和输出目录。

标准输出只发送逐行 JSON：

```json
{"event":"loading"}
{"event":"first_audio","seconds":1.4}
{"event":"progress","chunks":2}
{"event":"completed","output":"...","duration":12.3,"peakMemoryGB":4.0}
```

错误写入标准错误，并以非零状态退出。音频先写入临时文件，完成验证后原子移动到目标路径。

**测试顺序**

1. 先写参数校验测试：缺少模型、参考音频、参考原文或目标文字时必须失败。
2. 运行内置短句真实生成，验证 WAV 存在、时长大于 0、采样率正确、没有削波。
3. 用同一输入重复运行，确认固定随机种子能够得到可复现的流程状态。
4. 取消进程，确认不会留下冒充成品的文件。

**完成条件**

- 不含 `/Users/<user>` 等绝对路径。
- 从任意工作目录调用都能生成。
- 生成结果达到 G 试听路线的参数与后处理基线。

## Task 2：引入可替换的语音引擎层

**文件**

- 新建：`SpeechEngine.swift`
- 新建：`ZipVoiceSpeechEngine.swift`
- 新建：`QwenSpeechEngine.swift`
- 新建：`RuntimeLocator.swift`
- 修改：`main.swift`
- 修改：`AppConfiguration.swift`
- 新建：`tests/SpeechEngineConfigurationSelfTest.swift`

**设计**

`SpeechEngine` 只暴露生成、取消和能力描述，不让界面知道 Python、Sherpa 或模型路径。`ZipVoiceSpeechEngine` 包装当前代码；`QwenSpeechEngine` 启动 `qwen_runner.py` 并解析 JSON 进度。

`RuntimeLocator` 优先使用应用包内资源；开发模式才允许使用项目内回退目录。发布构建禁止退回用户电脑上的开发路径。

**测试顺序**

1. 为资源查找和引擎选择写失败测试。
2. 实现 ZipVoice 包装，确认现有生成行为不变。
3. 实现 Qwen 进程和进度解析。
4. 模拟错误 JSON、进程崩溃和用户取消。
5. 在现有桌面界面增加临时“Qwen 试听”入口，完成 M1 纵向闭环。

**验证**

- 当前 ZipVoice 仍能生成和播放。
- Qwen 能从桌面应用生成、播放、保存并在访达中显示。
- 取消后界面恢复可操作状态。
- 错误信息不显示整段终端日志或技术堆栈。

## Task 3：制作不依赖开发环境的便携运行包

**文件**

- 新建：`package-runtime.sh`
- 修改：`build.sh`
- 修改：`RuntimeLocator.swift`
- 修改：`Info.plist`（只在需要新增版本号或文件类型时）

**步骤**

1. 建立独立的运行时暂存目录，只复制：
   - Python 3.12 arm64 解释器与标准库。
   - `.venv` 中实际需要的 `site-packages`。
   - Qwen 0.6B 8bit 模型。
   - DeepFilterNet v3 模型。
   - `qwen_runner.py`。
2. 不复制 `.uv-cache`、测试包、下载缓存、`__pycache__` 和开发工具。
3. 不复制虚拟环境中的绝对路径解释器软链接；直接调用应用包内 Python。运行时环境只允许指向应用包内路径，例如使用 `PYTHONPATH` 定位依赖；是否需要 `PYTHONHOME` 由离开开发目录后的便携测试决定，不能靠假设。
4. 提供两种构建：
   - `developer`：快速构建，使用项目内运行时，仅供本机开发。
   - `portable`：把全部运行时和模型装进 `.app`，供其他 Mac 测试。
5. 给所有原生动态库补充签名并再次深度校验应用。

**验证**

```sh
BUILD_FLAVOR=portable zsh build.sh
codesign --verify --deep --strict build/LocalAudioProbe.app
```

另外检查应用内容中不存在 `/Users/<user>`，并从临时目录启动便携应用生成一段音频。预计便携应用约 2.5～3.0GB；以实际构建结果为准。

**完成条件**

- 便携应用不读取项目外的 Python、模型或音频资源。
- 不需要管理员密码和联网。
- 不复制约 461MB 的 uv 下载缓存。

## Task 4：建立朗读项目数据模型和存储

**文件**

- 新建：`NarrationProject.swift`
- 新建：`NarrationSegment.swift`
- 新建：`ProjectStore.swift`
- 修改：`AppConfiguration.swift`
- 新建：`tests/ProjectStoreSelfTest.swift`
- 新建：`tests/ProjectMigrationSelfTest.swift`

**数据要点**

- 项目版本号、UUID、名称、原文、音色 ID、创建和修改时间。
- 段落稳定 ID、顺序、文字、类型、表达方式、速度、停顿。
- 输入指纹、生成状态、候选音频、当前选中版本和错误摘要。
- 最终成品路径只作为派生数据，不替代段落源文件。

**测试顺序**

1. 新项目保存和重新加载。
2. 3000 字限制与空文本校验。
3. 原子保存：写入失败时旧项目仍可读取。
4. 修改一个段落只让该段输入指纹失效。
5. 删除只能发生在对应项目目录内，路径越界测试必须失败。
6. 未知新字段可忽略，旧版本可以迁移。

**完成条件**

- 项目关闭后重新打开，所有文字、设置和已完成段落保持一致。
- 临时文件不会被当作完成结果。

## Task 5：实现轻量的 NarrationDirector

**文件**

- 新建：`NarrationDirector.swift`
- 新建：`NarrationRules.swift`
- 新建：`tests/NarrationDirectorSelfTest.swift`
- 新建：`tests/fixtures/narration-cases.json`

**规则范围**

- 识别标题、编号列表、定义、举例、疑问、结论和普通讲解。
- 按中文标点和段落边界切分，避免把数字、小数、英文缩写错误拆开。
- 单段目标 30～100 字，硬上限 120 字；过短相邻句在语义标签相同时合并。
- 无法判断时使用普通讲解，不猜测强烈情绪。

**默认映射**

- 标题、重点结论：强调、稍慢、长停顿。
- 定义：沉稳、稍慢、正常停顿。
- 举例：亲切、正常速度、正常停顿。
- 疑问：亲切、正常速度、短停顿。
- 普通讲解：自然、正常速度、正常停顿。

**测试顺序**

先为每种结构写失败用例，再实现最小规则。加入包含日期、百分比、英文、引号和多级列表的回归用例。

**完成条件**

- 固定语料输出稳定，不依赖网络或随机模型。
- 分析只添加元数据，不改变用户原文字符。

## Task 6：实现逐段生成队列与恢复

**文件**

- 新建：`GenerationQueue.swift`
- 新建：`GenerationJob.swift`
- 新建：`GenerationJournal.swift`
- 新建：`tests/GenerationQueueSelfTest.swift`

**行为**

- 同时最多一个生成进程。
- 状态为等待、生成中、完成、失败、已取消。
- 每段完成后先验证音频，再原子更新项目。
- 同一输入指纹的完成段落直接复用。
- 首次失败使用同一引擎重试一次；再次失败后记录可理解错误。只有设备策略明确允许时才回退 ZipVoice，不能静默改变音色质量。
- 取消只终止当前进程，保留此前段落。
- 应用重启后把遗留的“生成中”恢复为“等待”，从第一个未完成段继续。

**测试方法**

使用假的快速引擎测试排序、缓存、重试、取消和恢复；真实 Qwen 只用于少量集成测试，避免普通单元测试每次加载模型。

**完成条件**

- 模拟第 7 段失败时，前 6 段不丢失，重开应用后从第 7 段继续。

## Task 7：实现段落音频整理和最终导出

**文件**

- 新建：`AudioAssembler.swift`
- 新建：`AudioExporter.swift`
- 修改：`AudioProcessing.swift`
- 扩展：`tests/AudioPostProcessCLI.swift`
- 新建：`tests/AudioAssemblerSelfTest.swift`

**行为**

- 对每段做削波、时长和底噪检查。
- 只有检测到明显底噪时才调用 DeepFilterNet；先维持用户认可的轻度混合上限，禁止无条件强降噪。
- 速度变化使用保持音高的时间伸缩，档位限制在轻微范围，避免明显机械感。
- 段后停顿使用固定可测试区间；拼接前统一目标响度并在边界使用短淡入淡出。
- WAV 为内部母版；M4A 使用系统编码器。
- 先做 MP3 编码能力探针。如果系统编码器不可用，在应用内打包 arm64 的本地 MP3 编码助手与许可证，不要求用户安装 Homebrew 或其他组件。

**测试顺序**

1. 生成不同采样率、音量和长度的夹具。
2. 验证拼接顺序、停顿时长、输出总时长和无削波。
3. 验证局部重做只替换目标段落。
4. 验证 WAV/M4A/MP3 在独立播放器中可打开。

**完成条件**

- 最终成品不依赖本应用环境即可播放。
- 拼接失败不会删除段落母版。

## Task 8：扩展音色为可选多风格参考

**文件**

- 修改：`VoiceLibrary.swift`
- 修改：`VoiceEditorView.swift`
- 修改：`AudioCaptureController.swift`
- 新建：`tests/VoiceStyleMigrationSelfTest.swift`

**数据迁移**

旧音色的现有参考录音自动映射为“自然讲解”，不要求用户重新录制。新音色可以依次补录自然讲解、亲切表达和重点强调，每种参考保存原音与清理版本。

**质量门槛**

- 音量过低、严重削波或没有有效人声时阻止保存并要求重录。
- 底噪警告允许用户试听后决定，但默认建议重录。
- 每种参考的原文与录音必须成对保存。

**完成条件**

- 旧音色无损迁移。
- 缺少某种风格时明确回退到自然讲解，不显示为已经具备该风格。

## Task 9：重组为非技术化项目界面

**文件**

- 新建：`ProjectListView.swift`
- 新建：`ProjectEditorView.swift`
- 新建：`SegmentEditorRow.swift`
- 新建：`GenerationProgressView.swift`
- 新建：`ProjectPlayerBar.swift`
- 修改：`main.swift`

**界面顺序**

1. 新建或继续朗读项目。
2. 粘贴文字并选择音色。
3. 分析朗读方式。
4. 浏览段落，必要时修改三个简单选项。
5. 生成试听样本。
6. 生成全文，边生成边播放。
7. 对单段重做或追加第二版本。
8. 拼接并导出。

所有核心操作直接出现在窗口内，不依赖菜单发现。技术名称、模型路径、Python 和日志默认隐藏。交互控件加入中文辅助功能标签和完整键盘焦点顺序。

**完成条件**

- 新用户不看说明即可找到音色、试听、全文生成、局部重做和导出。
- 生成过程中界面保持响应，可以暂停和取消。

## Task 10：自动设备档位与安全回退

**文件**

- 新建：`DeviceProfile.swift`
- 新建：`RuntimeBenchmark.swift`
- 新建：`tests/DeviceProfileSelfTest.swift`
- 修改：`QwenSpeechEngine.swift`
- 修改：`GenerationQueue.swift`

**决策**

- 读取实际物理内存与 Apple Silicon 信息。
- 第一次运行 Qwen 前生成内置短句，记录加载时间、首段时间、总时间和进程是否异常退出。
- 自动档位使用硬件与短测试中的保守结果。
- 8GB/16GB 在没有真实验证前显示“兼容性待验证”，而不是正式支持。
- 内存不足或进程被系统终止时，当前段落回到等待状态，并建议使用兼容档；不占用内存去模拟其他硬件。

**完成条件**

- 同一台电脑的稳定测试结果可以缓存，模型版本变化后自动重新测试。
- 手动选择高档位失败时可以恢复到自动档，不损坏项目。

## Task 11：验证、试听与发布候选

在进入发布候选前，对 1.7B Base 建立独立候选实验：在项目隔离目录准备模型，用与 0.6B 完全相同的参考音频、语料、随机种子和后处理生成盲听样本，同时记录模型大小、加载时间、首段时间、总时间和峰值内存。只有盲听自然度明确胜出且 32GB 稳定性通过，才制作独立的可选模型包；否则第一版只发布 0.6B，不因为模型参数更大而启用。

**自动验证**

```sh
zsh tests/run-self-tests.sh
BUILD_FLAVOR=developer zsh build.sh
BUILD_FLAVOR=portable zsh build.sh
codesign --verify --deep --strict build/LocalAudioProbe.app
```

扩展 `run-self-tests.sh`，确保新增的纯 Swift 自检全部运行。真实 Qwen 集成测试单独执行并保存 JSON 清单、模型版本、音频散列、生成时间和内存数据。

**32GB 实测**

- 12 段固定知识语料的当前 G 与声音导演 A/B 音频。
- 3000 字项目暂停、退出、恢复、局部重做和导出。
- 连续 30 段无削波、截断、参考尾部重复和项目丢失。

**真实设备门槛**

- 16GB：短句、1000 字项目、恢复与导出。
- M1 8GB：短句、1000 字项目、取消与恢复；不能崩溃或被系统强制结束。

**盲听门槛**

- 至少 5 名普通话听众。
- 新方案在停顿和表达自然度上至少 70% 被偏好。
- 电子感与音色相似度不低于当前 G。
- 胜率低于 60% 时停止继续微调 0.6B，转入 1.7B/云端候选评估，不继续堆界面功能。

## 4. 每个里程碑的提交策略

每个 Task 完成后只提交该 Task 涉及的源文件和测试，不提交构建产物、模型、用户音色或生成音频。提交前必须运行该 Task 的定向测试；每个里程碑结束时再运行完整自检与构建。

推荐提交顺序：

1. `chore: capture local audio probe source baseline`
2. `feat: add portable qwen speech runner`
3. `refactor: isolate speech engines`
4. `build: package local qwen runtime`
5. `feat: add narration project storage`
6. `feat: add local narration director`
7. `feat: add resumable generation queue`
8. `feat: assemble and export narration audio`
9. `feat: add expressive voice references`
10. `feat: add narration project interface`
11. `feat: adapt generation to device capacity`
12. `test: verify expressive narration release candidate`

## 5. 不可跳过的停止点

1. M1 未能在桌面应用内稳定生成 Qwen 音频时，不开始项目界面。
2. 便携构建仍依赖开发机绝对路径时，不交给其他用户。
3. 项目恢复测试未通过时，不开始 3000 字长文测试。
4. 32GB 完整流程未通过时，不进入 8GB/16GB 宣传或分发。
5. 没有真实 8GB/16GB 设备结果时，只报告候选状态。
6. 任何实现都不得通过升级 macOS、安装系统级运行时或要求管理员权限来绕过问题。
