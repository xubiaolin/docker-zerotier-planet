# 本地 Markdown 任务跟踪

每个功能使用一个目录 `.scratch/<feature>/`。发布规格时写入该目录的 `spec.md`。发布实施任务时，在 `issues/` 下为每项任务创建一个 `NN-<slug>.md` 文件，编号从 `01` 开始。

在实施任务文件顶部用 `Status:` 记录当前分诊标签，标签取值见[分诊标签表](triage-labels.md)。将评论按时间顺序追加到文件末尾的 `## Comments` 下。

读取任务时，打开给定路径的文件。如果只提供了编号，在对应功能的 `issues/` 目录中按编号查找。

## Wayfinding operations

`wayfinder` 将待澄清的问题和已作出的决定保存在同一功能目录中。

- 在 `map.md` 的 `Notes`、`Decisions-so-far` 和 `Fog` 三节中分别记录笔记、已有决定和尚待澄清的问题。
- 每个决策问题占用一个 `issues/NN-<slug>.md` 文件。正文写明要回答的问题，`Type:` 取 `research`、`prototype`、`grilling` 或 `task`。
- 在文件顶部用 `Blocked by: 01, 02` 这样的行列出依赖。所有依赖都标为 `resolved` 后，该问题即可领取。
- 从尚未解决、尚未领取且依赖已解除的问题中，选取编号最小的一项。开始工作前先写入并保存 `Status: claimed`。
- 解决问题后，在 `## Answer` 下追加答案，将状态改为 `Status: resolved`，再将结论摘要和任务链接补入 `map.md` 的 `Decisions-so-far`。
