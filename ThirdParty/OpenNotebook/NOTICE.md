# Open Notebook 来源说明

“声音导演”的离线口语导演层参考了以下开源项目的分阶段工作流、领域数据边界与提示词组织思路：

- Open Notebook：<https://github.com/lfnovo/open-notebook>
  - 评审提交：`a7de90d38aaf18ee85fd661854d35c11e44613e2`
  - Copyright (c) 2024 Luis Novo
- Podcast Creator：<https://github.com/lfnovo/podcast-creator>
  - 评审提交：`904da36cca12846e8c610fff5cab2972735b007d`
  - Copyright (c) 2025 Luis Novo

两个上游项目均以 MIT License 发布，许可正文见同目录 `LICENSE`。

本地修改与边界：

- 将“内容 → 提纲／口语稿 → 逐段 TTS → 成品”的思路改写为原生 Swift 数据结构与完全离线流程。
- 使用本项目自己的项目存储、保真校验、短句分段、语音引擎、生成队列、音量处理、停顿和导出实现。
- 未嵌入上游的 Docker、FastAPI、Next.js、SurrealDB、MoviePy、账号系统或云端 TTS 服务。
- 本应用不是 Open Notebook 或 Podcast Creator 的官方发行版。
