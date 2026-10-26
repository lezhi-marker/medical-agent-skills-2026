# 差异表达分析摘要

- 生成时间：2026-10-26 10:23:16
- 分析方法：DESeq2 1.44.0
- 方法判定依据：矩阵全部为非负整数，判定为原始 counts，使用 DESeq2
- 比较方向：Tumor vs Normal（log2FoldChange > 0 表示 Tumor 表达高于 Normal）
- 筛选标准：|log2FC| >= 1 且 padj < 0.05
- 多重检验校正：Benjamini-Hochberg (BH)

## 输入
- 表达矩阵：60660 个基因 × 20 个样本
- 分组：Normal = 10，Tumor = 10
- 注释匹配率：100.0%

## 结果
- 可检验基因数（padj 非 NA）：34499
- 显著上调（Up）：5071
- 显著下调（Down）：4293
- 显著合计：9364

## 输出文件
- `results.tsv`：gene_id、gene_name、log2FoldChange、pvalue、padj（按 padj 升序）
- `volcano.png`：火山图（x = log2FC，y = -log10(padj)）
- `summary.md`：本摘要

## 备注
- log2FoldChange 为未经收缩的 MLE 估计。
- results() 默认启用独立过滤；padj 为 NA 的基因不纳入显著基因统计。
- 本分析按非配对两组比较执行；sample_info 中虽有 patient_id，但未建模患者配对效应。
- 统计显著不等同于生物学结论，阈值与样本量（Normal 10 / Tumor 10）需在解释时考虑。
