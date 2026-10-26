# 数据格式

本技能面向本项目 `TCGA-KIRC/` 下的三个文件。以下规模与取值已在本机核对（2026-10-26）。

## gene_counts.tsv

- 规模：60,660 个基因 × 20 个样本（文件共 60,661 行，含表头；21 列）。
- 第一列：`gene_id`，Ensembl ID 带版本号，例如 `ENSG00000000003.15`；全表唯一，无空值。
- 其余 20 列：TCGA aliquot barcode，例如 `TCGA-A3-3358-11A`（Normal）、`TCGA-A3-3358-01A`（Tumor）。
- 数值：非负整数 counts（GDC 的 STAR augmented gene counts），实测范围 0–2,842,932，无 NA、无负值、无非整数。
- **不是标准化矩阵**：不要预先做 TPM/FPKM/log 转换再交给 DESeq2。

## sample_info.csv

- 编码：UTF-8 **带 BOM**；逗号分隔；20 行数据。
- 必需列：`sample_id`、`group`。其余列：`patient_id`、`sample_type`、`project`、`case_uuid`、`sample_uuid`、`file_uuid`、`file_name`、`source_url`。
- `group` 取值：`Normal`（10 个）、`Tumor`（10 个），区分大小写。
- `sample_id` 与 `gene_counts.tsv` 的 20 个样本列**集合完全一致**；当前顺序也一致（前 10 个 Normal，后 10 个 Tumor）。脚本以 `sample_info` 顺序重排 counts，因此顺序不同不算错误；集合不同立即报错停止。
- `patient_id`：10 位患者，每人一个 Normal + 一个 Tumor（配对结构）。本技能默认按非配对两组比较，见 [method-selection.md](method-selection.md)。

## gene_annotation.tsv

- 规模：60,660 行 + 表头；制表符分隔。
- 列：`gene_id`、`gene_name`、`gene_type`。
- `gene_id` 与 counts 的行名一一对应（带版本号），覆盖率 100%；无重复。
- 本数据中 `gene_name` 无缺失；若其他数据缺失，结果中的 `gene_name` 写 `NA`。

## 通用约定

- 表头必须存在且列名精确匹配（区分大小写）。
- `gene_id` 必须唯一；重复会在校验阶段报错。
- 不要手动改动这些文件；需要清洗时另存新文件，并同步修改传入参数。
- 读取端已处理：TSV 不做引号解析；`sample_info.csv` 以 `UTF-8-BOM` 读取。
- 若文件被替换或上游流程改变，重新运行入口脚本即可触发全部校验，不要跳过。
