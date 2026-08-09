# 单次录音情绪基准

这里是正式应用之外的隔离实验。目标是先回答一个问题：同一段自然普通话参考录音，能否在尽量保持音色的前提下生成可识别的开心、兴奋、悲伤和愤怒。

## 隐私边界

- 用户录音放入 `private/`，生成样本放入 `results/`；两者均被 Git 忽略。
- 模型和 Python 运行环境分别放入项目根目录 `.emotion-models/` 与 `.emotion-runtime/`，不会安装到系统目录。
- 可提交的报告只保存匿名哈希、音频指标、模型版本、耗时和内存，不保存录音路径、录音内容或密钥。
- 本地基准不联网推理。下载依赖和模型仅用于准备项目内运行时。

## 首轮范围

首轮固定验证自然、开心、兴奋、悲伤和愤怒，每类三句，强度统一为“明显”。只有通过完整性检查和盲听门槛的表达才会进入正式应用。

运行契约自检：

```sh
python3 -m unittest discover experiments/emotion-control/tests -v
```

项目内运行时与模型准备：

```sh
experiments/emotion-control/setup_local_runtime.sh
experiments/emotion-control/download_local_models.sh
```

真实试听由 `run_benchmark.py` 顺序执行。可以先用
`--utterances-per-emotion 1` 为五种表达各生成一条，再决定是否运行完整十五条。
程序只在忽略目录中保存匿名音频、自动指标和答案文件，不会把参考录音、录音原文或绝对路径写入报告。
