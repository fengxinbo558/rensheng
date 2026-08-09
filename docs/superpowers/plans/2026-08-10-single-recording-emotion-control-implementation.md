# 单次录音情绪控制实施计划

- 日期：2026-08-10
- 依据设计：`docs/superpowers/specs/2026-08-10-single-recording-emotion-control-design.md`
- 核心约束：用户只录一段自然普通话；不升级 macOS、不安装系统组件；依赖和模型只放在项目或应用包内；候选模型未通过试听前不进入正式界面。

## 1. 交付策略

本轮拆成“验证”和“产品化”两道门：

1. 先在隔离目录用同一段自然录音、同一组文字和同一组情绪测试本地候选；没有可识别情绪或电子感明显时立即停止集成。
2. 本地候选通过后，再实现项目数据、引擎协议和高级编辑界面。
3. 云端候选单独验证。没有用户授权、API 密钥和可验证删除的临时存储时，云端功能保持关闭，不阻塞完全离线版本。
4. 本地与云端分别由功能开关控制；同一项目生成期间锁定一种引擎。

## 2. 固定验收语料

基准使用一段 10–20 秒自然普通话参考录音，并准备五类表达，每类三句：

- 自然：中性说明文字，用于音色相似度基线。
- 开心：包含好消息和轻松分享，不依赖感叹号堆叠。
- 兴奋：高能量事件描述，区分于普通开心。
- 悲伤：克制的失落内容，避免通过哭腔特效取巧。
- 愤怒：明确不满和制止内容，区分于单纯大声。

首轮只验证以上五类。温柔、严肃、紧张、哀伤和强调重点在核心路线通过后追加，避免一次测试过宽。

每份生成结果保存：引擎与模型版本、指令版本、随机种子、参考录音摘要、生成耗时、峰值内存、输出时长、采样率、峰值、RMS、文件哈希和失败原因。参考录音本身不进入 Git。

## 3. 实施任务

### Task 1：建立隔离基准与安全边界

**文件**

- 修改：`.gitignore`
- 新建：`experiments/emotion-control/README.md`
- 新建：`experiments/emotion-control/benchmark-manifest.json`
- 新建：`experiments/emotion-control/emotion_prompts.py`
- 新建：`experiments/emotion-control/audio_metrics.py`
- 新建：`experiments/emotion-control/tests/test_benchmark_contract.py`

**行为**

1. 将模型、虚拟环境、用户录音、生成音频、API 密钥和临时对象存储目录全部排除在 Git 之外。
2. 固定五类首轮语料、三档强度中的“明显”档和提示词版本。
3. 只把音频指标和匿名文件哈希写入结果 JSON；不把用户录音绝对路径写入可提交文件。
4. 所有输出先写临时文件，验证 WAV 可读且时长大于零后再原子移动。

**验证**

- 清单字段缺失、未知情绪、输出越界或覆盖参考录音时必须失败。
- `git status` 不得出现录音、模型、音频或密钥。

### Task 2：准备项目内 Fun-CosyVoice3 候选运行时

**文件**

- 新建：`experiments/emotion-control/setup_local_runtime.sh`
- 新建：`experiments/emotion-control/run_cosyvoice.py`
- 新建：`experiments/emotion-control/tests/test_cosyvoice_runner.py`

**行为**

1. 运行时安装在项目忽略目录 `.emotion-runtime/`，模型安装在 `.emotion-models/`；不写 `/usr/local`、`/opt/homebrew`、系统 Python 或系统 Framework。
2. 锁定 Fun-CosyVoice3、Python 包和模型提交版本，记录许可证与来源。
3. Runner 接收参考录音、目标文字、情绪、强度、输出路径和随机种子；标准输出只发送逐行 JSON 事件。
4. 情绪指令必须进入 `inference_instruct2` 或候选版本等价的“参考音色 + 指令”接口，不能用后期变速或音量冒充。
5. 首轮允许一次性进程以快速验证；通过后才改成长驻 Worker。

**验证**

- `--validate-only` 不加载模型即可检查参数和路径。
- 没有参考录音、未知情绪或输出不是 WAV 时明确失败。
- 真实短句生成后检查 WAV、耗时、峰值内存和退出状态。

### Task 3：运行本地五类情绪基准并作去留判断

**文件**

- 新建：`experiments/emotion-control/run_benchmark.py`
- 生成但忽略：`experiments/emotion-control/results/`
- 新建：`experiments/emotion-control/report-template.md`

**步骤**

1. 对同一自然录音生成自然、开心、兴奋、悲伤、愤怒各三段。
2. 随机化文件名并把情绪标签放入单独答案文件，便于盲听。
3. 先完成自动完整性、削波、静音、异常高频能量和文件哈希检查。
4. 输出可直接在访达打开的试听目录及一份基准报告。
5. 用户试听前不修改正式应用；若五类中只有部分达到 4/5 识别门槛，只把通过的类别纳入首版。

**停止条件**

- 自然档仍有明显电流音或金属感。
- “明显”情绪主要靠音量差异，盲听不可识别。
- 强情绪听成另一个人，或说话人验证分数相对自然档下降超过设计阈值。
- 峰值内存在 32GB 开发机上已明显超过未来 16GB 设备可承受范围。

### Task 4：验证云端候选与隐私闭环

**文件**

- 新建：`experiments/emotion-control/run_qwen_cloud.py`
- 新建：`experiments/emotion-control/temporary_audio_store.py`
- 新建：`experiments/emotion-control/tests/test_cloud_contract.py`

**前置条件**

- 用户主动启用云端实验并提供自己的服务凭证。
- 临时对象存储支持短时签名链接、立即删除和删除后不可访问验证。

**行为**

1. 先上传参考录音到不可枚举的临时对象，创建云端克隆音色后立即删除并验证。
2. 注册成功、失败、取消和超时都执行删除；删除验证失败则停止。
3. 使用同一五类语料和评分标准生成云端样本。
4. 日志只记录请求 ID、模型版本、耗时和错误摘要；密钥、录音 URL、原文和完整服务响应不得落盘。

**验证**

- 用假的本地 HTTP 服务测试授权、超时、取消、删除和重试，不消耗云端额度。
- 真实服务只在前置条件满足后运行。

### Task 5：扩展项目表达数据并保持旧项目兼容

只有 Task 3 至少有一个本地非自然情绪通过，或 Task 4 云端候选通过后才执行。

**文件**

- 修改：`NarrationSegment.swift`
- 修改：`NarrationProject.swift`
- 修改：`NarrationRules.swift`
- 新建：`ExpressionProfile.swift`
- 新建：`EmotionInstructionBuilder.swift`
- 新建：`tests/ExpressionProfileSelfTest.swift`
- 修改：`tests/ProjectMigrationSelfTest.swift`

**行为**

1. `ExpressionProfile` 保存情绪、强度、来源和提示词版本。
2. 项目格式版本递增；旧值按设计文档映射，不丢文字、候选音频和导出记录。
3. 输入指纹加入表达、强度、引擎版本和云端音色版本。
4. 修改一段表达只使该段失效。
5. “自动”根据段落类型生成内部指令，但不得承诺未通过基准的情绪。

**验证**

- 覆盖所有旧表达迁移、未知新字段、往返编码和单段失效。
- 旧项目首次打开后仍可播放已有成品。

### Task 6：实现可替换情绪引擎与项目级路由

**文件**

- 修改：`SpeechEngine.swift`
- 新建：`LocalExpressiveSpeechEngine.swift`
- 新建：`CloudExpressiveSpeechEngine.swift`
- 新建：`ExpressionEngineRouter.swift`
- 修改：`RuntimeLocator.swift`
- 修改：`GenerationQueue.swift`
- 新建：`tests/ExpressionEngineRouterSelfTest.swift`
- 修改：`tests/GenerationQueueSelfTest.swift`

**行为**

1. 语音请求携带结构化表达，不让界面拼接模型提示词。
2. 本地引擎使用长驻 Worker，同一项目模型只加载一次、用户音色特征只计算一次。
3. 路由在项目生成开始前锁定，生成中不在本地与云端之间跳转。
4. 不支持的表达明确返回能力错误，不静默降级成自然。
5. 取消、失败重试和断点恢复沿用现有逐段队列；已有完成段不丢失。

**验证**

- 用假引擎测试能力匹配、项目锁定、取消、恢复、单段重做和错误文案。
- 真实模型集成测试只生成固定短句，避免普通自检反复加载数 GB 模型。

### Task 7：把情绪控制放入渐进式高级编辑

**文件**

- 修改：`SegmentEditorRow.swift`
- 修改：`ProjectEditorView.swift`
- 修改：`NarrationWorkspaceView.swift`
- 视需要新建：`ExpressionPicker.swift`
- 新建：`tests/ExpressionAvailabilitySelfTest.swift`

**行为**

1. 主界面仍只显示选择音色、输入文字和生成。
2. 高级编辑展开后，每段显示一个“表达”菜单；选固定非自然情绪后才显示轻微、明显、强烈。
3. 菜单只列当前项目锁定引擎真正支持且已通过验收的情绪。
4. 自动模式只显示“已自动安排表达”，模型、提示词和云服务商放在设置或诊断信息中。
5. 改表达后提供单段重做，不强迫重做整篇；如果需要换引擎，则明确要求从头生成整个项目。

**验证**

- 键盘可以完成菜单选择，状态变化有可读标签，折叠时不丢设置。
- 未启用云端时界面不会诱导上传，也不会显示云端专属情绪。

### Task 8：云端设置、授权与删除

只有 Task 4 通过后执行。

**文件**

- 新建：`CloudSpeechSettings.swift`
- 新建：`CloudCredentialStore.swift`
- 新建：`CloudVoiceRegistry.swift`
- 修改：应用设置界面相关文件
- 新建：`tests/CloudSpeechSettingsSelfTest.swift`

**行为**

1. 默认关闭云端；首次开启展示录音和文字上传范围并要求一次明确确认。
2. 密钥只存 macOS Keychain，项目 JSON 只保存不敏感的音色 ID 和版本。
3. 用户可删除云端音色、清除密钥和关闭增强；删除失败必须显示状态。
4. API 调试信息不得包含密钥、完整文字、录音 URL 或可复用签名参数。

### Task 9：构建、真机资源验证与交付

**文件**

- 修改：`package-runtime.sh`
- 修改：`build.sh`
- 修改：`README.md`
- 修改：相关自检脚本

**步骤**

1. 本地情绪引擎通过后才纳入便携应用；裁剪测试、缓存和无关模型文件。
2. 运行全部 Swift 自检、Python runner 测试、开发构建和便携构建。
3. 检查应用包内不存在开发机绝对路径、用户录音、密钥或基准结果。
4. 用便携应用真实生成自然和至少一种通过的情绪，检查播放、暂停、停止、局部重做和三种导出格式。
5. 记录冷启动、热启动、峰值内存、实时率、应用体积和音频哈希。
6. 32GB 开发机只给开发结果；M1 8GB/16GB 必须在真实设备长文测试后才标记正式支持。

## 4. 完成定义

本功能只有同时满足以下条件才算完成：

- 用户只需一段自然录音，不需补录或表演情绪。
- 至少一项非自然情绪通过既定盲听与音色相似度门槛。
- 情绪真实进入模型，正式界面不存在仅调速度、音量或音高的假选项。
- 完全离线模式可独立使用；未授权时没有任何录音或文字上传。
- 同一项目不混用引擎，不出现明显音色跳变。
- 旧项目、已有候选和已有导出可以继续读取与播放。
- 便携应用不要求用户安装 Python、Homebrew 或系统组件，也不升级 macOS。
