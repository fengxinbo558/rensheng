# 本地稍后听 v0.4 实施计划

- 设计来源：`docs/plans/2026-08-10-local-listen-later-design.md`
- 本轮交付：文字、网页、可提取文字的 PDF、来源记录、继续收听、首段可播
- 后续交付：本地音视频转写、扫描 PDF OCR、视频网站字幕、知识问答
- 系统边界：不升级 macOS，不安装 Homebrew／Docker／系统组件，保持 macOS 14 兼容路线

## 实施原则

1. 复用现有 `NarrationProject`、语义段、生成队列、音色库、播放器和导出系统，不推倒重做。
2. 每个任务先增加失败测试，再完成最小实现，最后运行全量自检。
3. 导入和播放进度必须原子保存，旧项目必须无损迁移。
4. 首页只显示来源、音色和主动作；技术参数继续隐藏。
5. 网页导入需要访问用户给出的网页，但正文提取、语音生成和项目存储仍在本机完成。
6. 任何导入失败都保留原项目或原文件，不静默截断、覆盖或上传内容。

## Task 1：扩展项目格式并保证旧项目无损迁移

修改：

- `NarrationProject.swift`
- `ProjectStore.swift`
- `tests/ProjectMigrationSelfTest.swift`
- `tests/ProjectStoreSelfTest.swift`

新增数据类型：

- `NarrationSourceKind`：`text`、`webPage`、`pdf`，并为后续 `audio`、`video` 预留解码值。
- `NarrationSource`：标题、类型、原始 URL、本地受管文件相对路径、导入时间。
- `NarrationImportState`：`captured`、`extracting`、`ready`、`needsAttention`。

为 `NarrationProject` 增加：

- `source`：来源信息，旧项目迁移为文字来源。
- `importState` 和 `importErrorSummary`。
- `playbackPositionSeconds`、`lastPlayedAt`、`listeningCompleted`。

步骤：

1. 将项目格式从 v4 升级到 v5。
2. 旧 JSON 缺少新字段时使用安全默认值，不使已有语义段、候选音频和导出失效。
3. 增加“已捕获但尚未提取文字”的项目创建入口；只有进入 `ready` 后才要求 `sourceText` 非空。
4. 把项目文字安全上限从 3000 字提高到 30000 字。继续按 180 字以内的语义段顺序生成，避免单次模型输入和峰值内存随全文长度增长。
5. 超过安全上限时明确提示用户拆分内容，不截断文字。
6. 项目排序改为优先 `lastPlayedAt`，没有播放记录时使用 `updatedAt`。

验收：

- v4 测试项目迁移后所有原字段保持一致，新字段使用默认值。
- 30000 字以内项目可以保存和重新载入，30001 字被明确拒绝。
- `captured` 项目允许暂时没有正文，`ready` 项目不允许空正文。
- 非法来源路径仍被限制在项目目录内。

## Task 2：建立统一的内容导入接口

新增：

- `ContentImporter.swift`
- `PlainTextImporter.swift`
- `PDFTextImporter.swift`
- `tests/ContentImporterSelfTest.swift`
- `tests/PDFTextImporterSelfTest.swift`

核心接口：

- `ContentImportRequest`：文字、URL 或本地文件。
- `ImportedContent`：标题、来源类型、提取文字、来源定位信息、可选受管文件。
- `ContentImporting`：异步导入并返回结构化结果。
- `ContentImportError`：不支持格式、空内容、密码保护、损坏文件、内容过长和网络错误。

步骤：

1. 纯文字导入复用当前安全检查，不改变用户原文。
2. PDF 使用系统 `PDFKit` 提取页面文字，不增加外部运行时。
3. PDF 按页合并并清理重复空白，保留自然段和页序；首版不自动删除页眉页脚，避免误删正文。
4. 识别没有可提取文字的扫描 PDF，提示“当前版本需要可选择文字的 PDF”，不生成空项目。
5. 将导入的 PDF 复制到项目目录的 `source/` 子目录；项目只保存安全相对路径。
6. 在构建和自检脚本中显式链接 `PDFKit`。

验收：

- 多页可搜索 PDF 按正确顺序得到正文。
- 空白、损坏、密码保护和扫描 PDF 返回可理解错误。
- 原 PDF 离开原位置后，项目中的受管副本仍可用于显示来源。
- 导入不会修改或删除用户原文件。

## Task 3：加入隐私边界清楚的网页正文提取

新增或引入：

- `WebArticleImporter.swift`
- `WebArticleExtractionHost.swift`
- `ThirdParty/Readability/Readability.js`
- `ThirdParty/Readability/LICENSE`
- `ThirdParty/Readability/NOTICE.md`
- `tests/WebArticleImporterSelfTest.swift`
- `tests/fixtures/article-basic.html`
- `tests/fixtures/article-noise.html`

修改：

- `build.sh`
- `tests/run-self-tests.sh`

步骤：

1. 只接受 `http` 和 `https` URL，拒绝本地文件、脚本 URL 和无法解析的地址。
2. 使用临时、无持久 Cookie 的 `URLSession` 下载用户指定页面，设置超时和最大响应体积。
3. 在不执行页面第三方脚本的隔离 `WKWebView` 中载入 HTML，再注入固定版本的 Mozilla Readability 提取标题和正文。
4. 把 Readability 固定到明确提交，保存 Apache 2.0 许可证、来源和本地修改说明。
5. 提取失败时显示原因并允许用户改为手工粘贴，不保存空白正文。
6. 构建脚本复制 Readability 资源并显式链接 `WebKit`。

验收：

- 测试文章能去除导航、广告、评论和页脚，保留标题、正文顺序、标点和段落。
- 网页正文提取不会执行测试页中的脚本。
- 无正文、超时、超大响应、非 HTML 和非法 URL 都有明确错误。
- 生成项目保存原始 URL，但不保存 Cookie、账号或浏览器历史。

## Task 4：实现可恢复的导入协调器

新增：

- `ContentImportCoordinator.swift`
- `tests/ContentImportCoordinatorSelfTest.swift`

修改：

- `ProjectStore.swift`
- `NarrationWorkspaceModel.swift`
- `tests/ProjectStoreSelfTest.swift`

步骤：

1. 收到来源后先创建 `captured` 项目并原子保存。
2. 开始处理时更新为 `extracting`，成功后写入标题、正文、受管来源和 `ready`。
3. 失败时更新为 `needsAttention` 和面向用户的错误摘要，不删除项目或原文件。
4. 应用重开时列出未完成项目；网页和 PDF 可以由用户一键重试。
5. 导入成功后调用现有朗读稿和语义段分析，不复制另一套分段逻辑。
6. 用户取消时停止当前导入并保留来源记录，避免半写入正文。

验收：

- 在提取成功、失败和取消的每个阶段，磁盘上的项目 JSON 都能重新载入。
- 重试只覆盖导入产物，不破坏已有音色选择和项目名称。
- 同一项目不会并发启动两个导入任务。

## Task 5：把首页改成“放进一个想听的内容”

新增：

- `SourceImportView.swift`
- `SourceBadgeView.swift`

修改：

- `NarrationWorkspaceView.swift`
- `ProjectEditorView.swift`
- `ProjectListView.swift`
- `NarrationWorkspaceModel.swift`

界面结构：

1. 顶部主标题改为“把没时间看的内容，留到稍后听”。
2. 主卡片提供“粘贴文字”“粘贴网页”“选择文件”三个入口，并支持把 PDF 拖入卡片。
3. 选择来源后显示可编辑正文和音色；生成仍只有一个主要按钮。
4. “我的朗读”改为“我的听读”，项目行显示来源图标、生成进度和收听进度。
5. `needsAttention` 项目只显示一个“处理问题”入口，不在列表堆叠技术错误。
6. 高级编辑继续默认折叠。

可访问性：

- 所有仅图标按钮增加可读标签。
- 拖放不是唯一入口，键盘和文件选择器能完成相同操作。
- 导入错误同时使用文字和图标，不只依赖颜色。
- 导入期间焦点和 VoiceOver 状态提示保持稳定。

验收：

- 新用户不打开高级设置即可完成文字、网页或 PDF 到生成的流程。
- 从打开应用到开始生成最多三个主要动作。
- 旧项目打开和编辑路径保持可用。

## Task 6：保存播放位置并支持一键继续

修改：

- `PlaybackController.swift`
- `NarrationWorkspaceModel.swift`
- `ProjectPlayerBar.swift`
- `PlaybackControlsView.swift`
- `tests/PlaybackControllerSelfTest.swift`
- `tests/ProjectStoreSelfTest.swift`

步骤：

1. `PlaybackController.play` 增加可选起始时间，并把越界位置安全限制在音频时长内。
2. 播放时每隔约 5 秒、暂停时、停止前和切换项目前保存当前位置；不按 0.1 秒计时器频率写磁盘。
3. 保存 `lastPlayedAt`，播放到成品末尾时标记 `listeningCompleted`。
4. 重新打开项目时显示“从 mm:ss 继续”，用户主动点击后才播放。
5. 用户选择“从头播放”时清空当前位置，但不删除音频。

验收：

- 播放、暂停、关闭应用和重新打开后，从保存位置继续。
- 播放进度写入经过节流，不产生持续磁盘写入。
- 换音色或局部重做不会无故清除仍然有效的播放位置。
- 新成品比旧成品短时，保存位置被安全限制到新时长。

## Task 7：第一语义段完成即可播放

新增：

- `AvailableAudioBuilder.swift`
- `tests/AvailableAudioBuilderSelfTest.swift`

修改：

- `AudioAssembler.swift`
- `GenerationQueue.swift`
- `NarrationWorkspaceModel.swift`
- `ProjectPlayerBar.swift`
- `tests/GenerationQueueSelfTest.swift`

首版取舍：

- 不在每生成一段后反复重写不断增长的成品文件。
- 用户点击“试听已完成部分”时，才把从第一段开始连续完成的语义段组装成临时 WAV。
- 生成队列继续写新的独立段文件，播放器只读取已经原子完成的文件，避免读写冲突。

步骤：

1. 找到从第一段开始连续完成且具有选中候选的语义段。
2. 至少完成一段时启用“试听已完成部分”。
3. 点击后组装临时预览并立即播放；后续生成继续进行。
4. 新语义段完成后，下次点击试听时刷新预览。
5. 全文完成后自动切换到正式 M4A 成品，不改变用户已保存的时间位置。
6. 修改前面语义段时使临时预览失效，后面的独立母版继续保留。

验收：

- 第一段完成后无需等待全文即可播放。
- 播放预览时生成队列继续工作，音频文件没有竞争或损坏。
- 中间某段未完成时，预览不会跳过它并错误拼接后续内容。
- 全部完成后的正式 WAV、M4A 和 MP3 与现有导出行为一致。

## Task 8：完善错误恢复和空状态

修改：

- `NarrationWorkspaceModel.swift`
- `ProjectListView.swift`
- `ProjectEditorView.swift`
- `GenerationProgressView.swift`

步骤：

1. 区分导入失败、朗读稿失败、语音生成失败和成品制作失败。
2. 每种错误只给一个当前最有用的动作：重试导入、改为粘贴、继续生成或重做一段。
3. 网页离线时说明“网页获取需要联网，导入后生成仍在本机完成”。
4. PDF 没有可提取文字时说明扫描版 OCR 尚未支持。
5. 项目未完成时关闭应用不弹出阻塞式警告，依靠已保存状态恢复。

验收：

- 用户不需要理解模型、Worker、PDFKit 或 Readability 名称就能处理常见错误。
- 错误状态不会覆盖已经成功生成的音频。

## Task 9：版本、说明和许可证

修改：

- `Info.plist`
- `README.md`
- `ThirdParty/Readability/NOTICE.md`

步骤：

1. 版本升级为 v0.4.0。
2. README 主流程改为“放入内容、选择声音、开始听”。
3. 写明网页获取阶段需要网络，导入后的处理和语音生成离线完成。
4. 写明 PDF 首版仅支持可选择文字的文件，音视频转写将在 v0.5 提供。
5. 更新本地数据目录、来源受管副本和隐私说明。
6. 记录新增开源代码的来源、固定提交、许可证和修改边界。

## Task 10：全量验证和交付

自动验证：

1. 运行 `tests/run-self-tests.sh`，包括新增迁移、导入、PDF、网页、进度和可用音频测试。
2. 运行网页提取离线 fixture 测试，确保测试不依赖外网结果。
3. 构建 developer 版，检查 macOS 14 编译目标、PDFKit／WebKit 链接和资源完整性。
4. 构建 portable 版，检查临时签名、包内运行时、Readability 许可证和模型资源。
5. 使用文字、测试网页和多页 PDF 各完成一次导入、生成、首段播放、暂停、重开和继续。
6. 断网后验证已经导入的项目仍可分析、生成、播放和导出；同时确认新网页导入给出准确提示。
7. 检查构建与运行过程没有调用系统升级、系统设置修改、Homebrew、Docker 或其他系统包管理器。

人工听感验证：

- 用同一普通话音色连续收听至少十分钟。
- 检查首段预览与最终成品的内容、停顿和音量是否一致。
- 确认没有因为网页或 PDF 分段引入重复标题、页码或异常断句。

设备验证：

- 当前开发机完成开发回归。
- 在真实 M1 8GB 和 16GB 机器上记录 30000 字项目的导入时间、首段时间、峰值内存、完整生成稳定性和恢复结果。
- 真机数据未完成前，README 继续明确“兼容路线可用，但长跑正式支持待验证”，不使用开发机限额测试替代结论。

交付物：

- 新的 `build/声音导演.app`。
- 三类来源的可重复测试样例。
- 自动测试与构建结果记录。
- 真实设备验证清单；无法在当前机器完成的项目明确标记为待验证。

## 推荐实施顺序

1. Task 1：项目格式和迁移。
2. Task 2：纯文字与 PDF 导入。
3. Task 4：导入协调器。
4. Task 6：播放位置。
5. Task 7：首段可播。
6. Task 5：首页和项目列表。
7. Task 3：网页导入与第三方许可证。
8. Task 8：错误恢复。
9. Task 9～10：版本、说明、全量验证和交付。

这个顺序先建立可测试的数据和恢复能力，再接入界面与网页，避免界面完成后才发现旧项目迁移、长文限制或播放进度无法可靠保存。
