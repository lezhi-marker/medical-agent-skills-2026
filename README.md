# medical-agent-skills-2026

本仓库整理“实验一”的两个自建 Claude Code Skill、TCGA-KIRC 示例数据与一次差异表达分析的运行结果。仓库只包含演示所需的文件，不包含本地设置、密钥或缓存。

## 目录结构

```text
.
├── .claude/skills/
│   ├── differential-expression/     # 差异表达分析 Skill
│   │   ├── SKILL.md
│   │   ├── references/              # 数据格式、方法选择、筛选标准
│   │   └── scripts/                 # run_deseq2.R + checks.R
│   └── medical-dialog/              # 医疗对话整理 Skill
│       ├── SKILL.md
│       ├── references/              # 整理规则
│       ├── scripts/                 # convert.py
│       └── examples/                # 示例对话与输出
├── TCGA-KIRC/                       # 输入数据
│   ├── gene_counts.tsv
│   ├── sample_info.csv
│   └── gene_annotation.tsv
├── results/                         # 本次运行结果
│   ├── results.tsv
│   ├── volcano.png
│   └── summary.md
├── README.md
└── .gitignore
```

## Skill 1：differential-expression

### 用途

对基因 × 样本表达矩阵执行 **Tumor vs Normal** 两组差异表达分析。技能会根据输入自动选择方法：非负整数 counts 使用 DESeq2；已标准化、连续或已取对数的表达值使用 limma。输出带基因注释的结果表、火山图和可追溯的摘要。

### 输入与输出

| 参数 | 文件 | 要求 |
|---|---|---|
| `--counts` | `TCGA-KIRC/gene_counts.tsv` | 第一列 `gene_id`，其余为样本列 |
| `--samples` | `TCGA-KIRC/sample_info.csv` | 必需列 `sample_id`、`group`；group 为 `Normal` / `Tumor` |
| `--annotation` | `TCGA-KIRC/gene_annotation.tsv` | 必需列 `gene_id`、`gene_name` |
| `--outdir` | 输出目录 | 默认 `./results` |

输出文件：

- `results.tsv`：`gene_id`、`gene_name`、`log2FoldChange`、`pvalue`、`padj`，按 padj 升序。
- `volcano.png`：火山图，x = log2FC，y = -log10(padj)，阈值线为 x = ±1、y = -log10(0.05)。
- `summary.md`：方法、方法判定依据、比较方向、筛选标准、显著基因数与备注。

### 运行

在仓库根目录执行：

```bash
"D:/R-4.4.3/bin/Rscript.exe" --vanilla \
  .claude/skills/differential-expression/scripts/run_deseq2.R \
  --counts TCGA-KIRC/gene_counts.tsv \
  --samples TCGA-KIRC/sample_info.csv \
  --annotation TCGA-KIRC/gene_annotation.tsv \
  --outdir results
```

必须使用 `--vanilla`，避免本机 R profile 干扰。脚本会先检查 counts 的样本列与 `sample_info.csv` 的 `sample_id` 是否一一对应；不一致会列出多余/缺失 ID 并以非零状态停止。`checks.R` 由入口脚本 `source()`，不要单独运行。

### 筛选标准

显著差异基因定义为 **`|log2FC| >= 1` 且 `padj < 0.05`**。`padj` 使用 Benjamini-Hochberg 校正；`padj` 为 NA 的基因不纳入显著基因统计。`log2FoldChange > 0` 表示 Tumor 表达高于 Normal。

### 结果核验

1. 命令退出码为 0，终端无 `[错误]`。
2. `results.tsv` 恰好 5 列，行数为 60,660，`gene_id` 无重复。
3. `summary.md` 写明方法、方向 Tumor vs Normal、筛选标准。
4. 火山图阈值线与上/下调数量一致。
5. 抽查基因：用原始 counts 计算两组均值，确认 log2FC 符号方向正确。

## Skill 2：medical-dialog

### 用途

把医生–患者对话（`dialogue.txt`）整理为结构化问答记录（`qa_record.md`）：问答配对、去除口语填充、保留原意、按清单标注缺失项“未提及”。**只整理，不诊断、不建议、不补充对话之外的医学信息。**

### 运行

```bash
python .claude/skills/medical-dialog/scripts/convert.py \
  --input .claude/skills/medical-dialog/examples/dialogue.txt \
  --output .claude/skills/medical-dialog/examples/qa_record.md
```

脚本使用 Python 3.12 标准库，输出 UTF-8 Markdown。示例对话为虚构内容，仅用于演示整理流程。

### 输出与核验

输出包含概览表、逐轮 Q/A（主题、提问、回答、缺失项、原文行号）和全对话缺失项汇总。核验时按“原文行”逐条对照，确认只删除了规则列出的填充词，且 Q/A 中没有任何原文之外的医学事实。

## 数据来源

`TCGA-KIRC/` 为 TCGA-KIRC 公共数据的一个演示子集：60,660 个基因 × 20 个样本（10 Normal、10 Tumor）。`sample_info.csv` 提供 `sample_id`、`group` 等样本信息，`gene_annotation.tsv` 提供 `gene_id`、`gene_name` 注释。数据仅用于方法演示，不用于临床决策；使用时应遵守 TCGA/GDC 的数据使用与引用要求。

## 非配对两组比较说明

本仓库的差异分析是**非配对**的 Tumor vs Normal 两组比较：

- 模型为 `design = ~ group`，不包含患者配对效应。
- 比较方向为 `Tumor - Normal`；`log2FoldChange > 0` 表示 Tumor 表达高于 Normal。
- 数据中 10 位患者各有 Normal/Tumor 样本，但当前结果没有利用 `patient_id` 做配对或区组分析。
- 如需配对设计，应修改模型（例如加入 `patient_id`）后重新运行；不能把本结果当作配对分析。

## 结果复现

### 环境

- R 4.4.3（`D:/R-4.4.3/bin/Rscript.exe`）
- DESeq2 1.44.0、limma 3.60.6、ggplot2 4.0.3
- Python 3.12（仅 `medical-dialog` 使用，标准库）

### 复现步骤

1. 按上面的“运行”命令执行差异分析。
2. 检查 `results/summary.md` 中的方法、方向、筛选标准和显著基因数。
3. 检查 `results/results.tsv` 的 5 列与 60,660 行。
4. 打开 `results/volcano.png`，确认阈值线与颜色分组。

当前环境下的结果：可检验基因 34,499；显著上调 5,071、下调 4,293、合计 9,364。R 包版本或输入数据变化可能导致数值不同。

医疗对话示例可直接用上面的 `convert.py` 命令重跑，输出除生成时间外应与 `examples/qa_record.md` 一致。

## 安全与隐私

- `.gitignore` 排除 `settings.json`、`settings.local.json`、`.env`、`*.key`、`*.pem`、`__pycache__/`、`.Rhistory`、`~$*`。
- 仓库不包含 API 密钥、访问令牌或本地 Claude 配置。
- 医疗对话示例为虚构内容；不要提交真实患者信息。

## 许可与引用

本仓库的自建 Skill 与说明用于教学和演示。TCGA-KIRC 数据来自公共数据库，使用时请遵循原始数据提供方的使用条款并引用相应文献。
