# 方法选择规则

## 自动判定

`run_deseq2.R` 调用 `checks.R::classify_input()`，按顺序判断：

| 条件 | 判定 | 方法 | 处理 |
|---|---|---|---|
| 含 NA / NaN / Inf | 非法 | 停止 | 报错退出 |
| 存在负值 | 连续 / 已 log | limma | 直接使用（假设底数为 2） |
| 全部为非负整数 | 原始 counts | DESeq2 | 负二项模型 |
| 非整数且最大值 ≤ 1 | 标准化比例 | limma | `log2(x+1)` 后拟合 |
| 非整数且 99% 分位数 > 100 | 标准化丰度 | limma | `log2(x+1)` 后拟合 |
| 其余非整数（尺度较小） | 已 log 连续值 | limma | 直接使用（假设底数为 2） |

判定依据会写入 `summary.md` 的“方法判定依据”，便于复核。阈值（100、≤1）是启发式规则；若明显误判，先检查数据分布，再决定是否预处理后重跑，并在摘要中说明。

## DESeq2 分支

- 设计：`~ group`，`group` 因子水平为 `Normal`、`Tumor`（Normal 为参考）。
- `DESeq()` 使用默认参数；`results(contrast = c("group", "Tumor", "Normal"), alpha = 0.05)`。
- 输出未收缩的 `log2FoldChange`（未调用 `lfcShrink`），保留原值以便与阈值直接比较。
- `results()` 默认启用独立过滤；被过滤基因的 `padj` 为 `NA`，不参与显著基因统计。
- 仅适用于原始 counts；不要对 TPM/FPKM/log 数据使用本分支。

## limma 分支

- 设计矩阵：`model.matrix(~ 0 + group)`，列名改为 `Normal`、`Tumor`。
- 对比：`makeContrasts("Tumor - Normal")`，即 `log2FC = Tumor - Normal`。
- 拟合：`lmFit()` → `contrasts.fit()` → `eBayes(trend = TRUE)`。
- 标准化丰度先做 `log2(x + 1)`；已是 log 值则直接使用（假设底数为 2）。
- 输出列同样为 `gene_id, gene_name, log2FoldChange, pvalue, padj`（padj 为 BH 校正）。

## 方向约定（两个分支一致）

- 因子水平固定：`Normal` → `Tumor`。
- 对比固定：`Tumor - Normal`；`log2FoldChange > 0` 表示 **Tumor 表达更高**，`< 0` 表示 Normal 更高。
- 火山图、`summary.md`、`results.tsv` 均使用这一方向；不要交换对比顺序，否则全部符号反转。

## 边界情况

- 单组样本数 < 2：报错。
- 患者配对：`sample_info.csv` 有 10 位患者，每人 Normal + Tumor。本技能默认**非配对**比较（符合“Tumor vs Normal”任务定义）；若需要配对设计，应把 `patient_id` 加入 design（如 `~ patient_id + group`），这属于扩展分析，必须另行实现并在摘要中声明，不能与默认结果混用。
- 批次/协变量：当前未建模。
- 数据既不像 counts 也不像 log 值（例如 0–100 的非整数）：会被判为 `log_scale`；应核对上游处理流程，必要时自行转换后重跑并记录。
