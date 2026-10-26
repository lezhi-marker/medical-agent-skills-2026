---
name: differential-expression
description: 对 TCGA-KIRC 等 RNA-seq 表达矩阵执行 Tumor vs Normal 差异表达分析：整数 counts 自动用 DESeq2，标准化/连续值自动用 limma，输出 results.tsv、volcano.png、summary.md。当用户要求做差异分析、比较肿瘤与正常样本、筛选差异基因时使用。
---

# 差异表达分析（Tumor vs Normal）

## 适用任务

- 对 `gene_counts.tsv`（基因 × 样本矩阵）与 `sample_info.csv`（含 `sample_id`、`group`）执行两组差异表达分析。
- 固定比较方向：**Tumor vs Normal**；`log2FoldChange > 0` 表示 Tumor 高于 Normal。
- 方法自动选择：非负整数 counts → DESeq2；已标准化/连续/已 log 值 → limma。
- 同时输出注释后的结果表、火山图和可追溯的摘要。

## 输入与输出

输入（全部通过命令行参数传入，不要拷贝或改写原文件）：

| 参数 | 文件 | 要求 |
|---|---|---|
| `--counts` | `gene_counts.tsv` | 第一列 `gene_id`，其余为样本列；整数 counts 或连续表达值 |
| `--samples` | `sample_info.csv` | 必需列 `sample_id`、`group`；group 只能是 `Normal` / `Tumor` |
| `--annotation` | `gene_annotation.tsv` | 必需列 `gene_id`、`gene_name` |
| `--outdir` | 输出目录 | 默认 `./results`；不存在时自动创建 |

输出（全部写入 `--outdir`）：

| 文件 | 内容 |
|---|---|
| `results.tsv` | `gene_id`、`gene_name`、`log2FoldChange`、`pvalue`、`padj`，按 padj 升序 |
| `volcano.png` | 火山图：x = log2FC，y = -log10(padj)，阈值线 ±1 与 0.05 |
| `summary.md` | 方法、方法判定依据、比较方向、筛选标准、显著基因数、备注 |

## 何时读取 references

- **运行前**读 [references/data-format.md](references/data-format.md)：确认列名、样本对应关系、编码（`sample_info.csv` 带 UTF-8 BOM）和数据属性。
- **方法不确定或数据不是明显整数时**读 [references/method-selection.md](references/method-selection.md)：自动判定规则、DESeq2/limma 参数、方向约定、配对设计说明。
- **报告结果、解释 padj 或做敏感性分析时**读 [references/filtering-criteria.md](references/filtering-criteria.md)：`|log2FC| >= 1 且 padj < 0.05` 的精确定义、NA 处理、上/下调定义。

## 如何调用 scripts

入口脚本：[scripts/run_deseq2.R](scripts/run_deseq2.R)。校验逻辑在 [scripts/checks.R](scripts/checks.R)，由入口 `source()`，**不要单独运行**。

在本项目根目录执行（R 4.4.3）：

```bash
"D:/R-4.4.3/bin/Rscript.exe" --vanilla \
  .claude/skills/differential-expression/scripts/run_deseq2.R \
  --counts TCGA-KIRC/gene_counts.tsv \
  --samples TCGA-KIRC/sample_info.csv \
  --annotation TCGA-KIRC/gene_annotation.tsv \
  --outdir results
```

说明：

- 必须加 `--vanilla`，避免用户/站点 profile 干扰（本机测试中曾出现 Rscript 段错误）。
- 路径含中文或空格时整体加引号；Windows 下建议用正斜杠。
- 执行顺序：读入 → 校验样本一一对应 → 判定数据类型 → DESeq2 或 limma → 合并注释 → 写结果 → 核验输出。任一步失败以非零状态退出。
- `checks.R` 负责全部辅助检查：文件存在性、表头、gene_id 唯一性、样本集合严格一致（不一致立即停止）、分组取值、注释匹配率、数据类型判定、输出文件核验。改校验逻辑只改 `checks.R`。
- 如需更换输出目录，传入新的 `--outdir`，不要覆盖已有结果目录中的文件。

## 如何核验结果

脚本结束时会自动执行 `verify_outputs()` 并打印 `[核验]` 行。仍建议人工检查：

1. 退出码为 0，终端无 `[错误]`。
2. `results.tsv` 恰好 5 列且列名一致；行数等于输入基因数（本项目为 60,660）；`gene_id` 无重复。
3. `summary.md` 中的方法、方向（Tumor vs Normal）、筛选标准（`|log2FC| >= 1 且 padj < 0.05`）与本次运行一致。
4. 火山图阈值线位于 x = ±1、y = -log10(0.05) ≈ 1.30；颜色分组与 summary 中的上/下调数一致。
5. 抽查若干基因：用原始 counts 计算两组均值，确认 log2FC 符号与“Tumor 高于 Normal 为正”一致。
6. 若 `padj` 全为 NA 或显著基因数为 0，先检查分组、样本量与输入是否为原始 counts，再排查模型；不要手工改结果。

独立复核（示例）：

```bash
head -3 results/results.tsv
```

```bash
"D:/R-4.4.3/bin/Rscript.exe" --vanilla -e 'r <- read.delim("results/results.tsv"); stopifnot(identical(names(r), c("gene_id","gene_name","log2FoldChange","pvalue","padj")), !anyDuplicated(r$gene_id)); cat(nrow(r), "genes\n")'
```

## 失败与边界

- **样本不一致**：脚本列出多余/缺失的 `sample_id` 后停止。修正输入文件；不要自行取交集或跳过校验。
- **分组不是 Normal / Tumor**：直接报错（当前技能不处理其他分组名或多组设计）。
- **每组少于 2 个样本**：报错。
- **NA/Inf**：报错；**负值**按已 log 数据处理，走 limma 分支。
- **依赖**：DESeq2 1.44.0、limma 3.60.6、ggplot2（本机已安装）。缺失时用 `BiocManager::install()`，不要静默跳过。
- **配对样本**：`sample_info.csv` 含 `patient_id`，本技能默认**非配对**两组比较；若用户要求配对设计，需修改 design 后重跑，不能复用本结果。
- 不要修改输入文件、不要手工编辑 `results.tsv`、不要更改比较方向或阈值（除非用户明确要求，并同步更新 `summary.md`）。
