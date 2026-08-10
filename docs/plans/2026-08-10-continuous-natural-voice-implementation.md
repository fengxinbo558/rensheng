# 连续自然人声核心实施计划

- 设计来源：`docs/plans/2026-08-10-continuous-natural-voice-design.md`
- 第一交付范围：常驻 Qwen Worker＋连续语义段
- 不在本轮交付：新模型发布、强情绪、视频/PDF 导入、系统升级或外部运行时安装

## Task 1：为 Qwen 运行器增加常驻协议

修改：

- `Runtime/qwen_runner.py`
- `Runtime/qwen_runner_smoke.py`

步骤：

1. 保留现有一次性命令行协议，确保旧的真实集成测试仍可运行。
2. 增加 `--worker`，以 JSON Lines 接收 `synthesize` 和 `shutdown` 命令。
3. Worker 启动时只加载一次模型，请求之间复用同一模型实例。
4. 当参考录音和参考文本未改变时，复用读取后的录音数组；依赖库内部的 ICL 缓存复用参考语音 token。
5. 每个事件带请求 ID，失败时返回 `failed` 而不让 Worker 因普通输入错误退出。
6. `--worker --validate-only` 不加载 MLX，用于快速协议自检。

验收：

- 快速自检在一个 Worker 中连续发送两个请求后再关闭。
- 空文字、超长文字和无效输出路径会返回可理解错误。
- 旧的一次性 `--validate-only` 自检继续通过。

## Task 2：在 Swift 中管理常驻 Worker

修改：

- `QwenSpeechEngine.swift`
- `SpeechEngine.swift`
- `tests/SpeechEngineConfigurationSelfTest.swift`

步骤：

1. `QwenSpeechEngine` 懒启动 Worker，启动后等待 `worker_ready`。
2. 每次 `synthesize` 只向现有进程写入一个请求，不再创建新进程。
3. 串行读取进度事件，直到当前请求 `completed` 或 `failed`。
4. `cancel()` 终止当前 Worker；已保存音频不受影响，后续继续时自动启动新 Worker。
5. 进程意外退出会被识别为引擎失败，由现有队列的一次自动重试触发 Worker 重启。
6. 引擎释放时向 Worker 发送 `shutdown`，超时或异常时才终止进程。

验收：

- 同一引擎实例连续生成多段时只有一次 `worker_ready`。
- 取消不继续后续段，再次新建队列可以继续。
- 正式界面不显示 Python、Worker 或模型路径。

## Task 3：将自然短句调整为连续语义段

修改：

- `SpokenScriptValidator.swift`
- `SpokenScriptDirector.swift`
- `NarrationWorkspaceModel.swift`
- `SegmentEditorRow.swift`
- `tests/SpokenScriptDirectorSelfTest.swift`
- `tests/NarrationDirectorSelfTest.swift`

首版取舍：

- 当前项目模型将可编辑段落与最小音频单元绑定。
- 为了先验证听感，本轮把新项目的可编辑段落直接扩展为连续语义段，而不引入字级强制对齐和子段音频切割。
- 这会让“重做一段”按 80～180 字左右的连续语义段执行，但不会重做全文。

步骤：

1. 自然讲解以约 140 字为目标、180 字为硬上限。
2. 同一原文自然段内优先合并完整句子；标题和明显换行仍保持边界。
3. 超长单句优先在逗号、顿号、冒号处断开。
4. 逐字朗读仍使用 120 字上限，减少对旧项目的影响。
5. 修改界面提示，明确“重做这一语义段”，不让用户误以为只替换单句。

验收：

- 一个含多个短句的自然段不再被拆成 40～55 字的多次 TTS。
- 任何语义段不超过 180 字，不丢字，不改变数字、日期和英文术语。
- 段落 ID 对同一输入保持稳定。

## Task 4：队列、恢复和导出回归

修改：

- `GenerationQueue.swift`
- `tests/GenerationQueueSelfTest.swift`
- 必要时修改 `AudioAssembler.swift`

步骤：

1. 确认同一 `GenerationQueue` 始终复用同一引擎实例。
2. 保留每个语义段的原子保存、两次尝试、取消和断点恢复。
3. 确认修改一个语义段的文字、表达或音色后只使相应输入指纹失效。
4. 确认速度和段后停顿仍只影响最终制作，不会不必要地重做模型音频。
5. 验证 WAV、M4A、MP3 完整性和独立播放能力。

## Task 5：真实链路和便携构建

步骤：

1. 运行全部 Swift 自检和 Python Worker 协议自检。
2. 用同一音色生成至少两个语义段，记录 `worker_ready` 次数、首段时间、第二段时间和峰值内存。
3. 确认第二段没有再次加载模型。
4. 构建 developer 版和 portable 版，检查签名、最低 macOS 14、运行时完整性和包体积。
5. 检查构建和运行过程没有调用系统升级、Homebrew、Docker 或系统配置修改。

本轮只在功能、恢复、速度指标和输出完整性通过后生成新的可试听应用。“更像真人”必须由后续同文本听感对比确认，不由自动测试代替。
