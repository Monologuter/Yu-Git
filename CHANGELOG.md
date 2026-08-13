# 更新日志

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。版本节奏与 `docs/02-产品需求文档.md` 对齐。

## [未发布]

### 新增

- **GitKit · ProcessRunner**：子进程执行器，并发排空 stdout/stderr 防管道死锁，支持超时与取消
- **GitKit · GitClient**：git CLI 调用层，隔离继承环境、禁止交互挂起、避免 index.lock 竞争
- **GitKit · StatusParser**：porcelain v2 解析器，覆盖重命名跨段、中文与含空格路径、冲突、submodule
- **GitKit · RepoActor**：仓库写操作的单一入口，显式串行化并记录操作日志
- **GitKit · GitOperation**：操作描述类型，自带中文摘要、注解与等价 git 命令
- **GitKit · FileOperationLog**：JSONL 操作日志，为 v0.5 的时间线 Undo 打底
- 工程规范（`docs/04-工程规范.md`）与本地质量门禁（swift-format 配置、git hooks）
