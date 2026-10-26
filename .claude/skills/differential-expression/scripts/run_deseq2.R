#!/usr/bin/env Rscript
# ============================================================================
# 差异表达分析入口脚本：Tumor vs Normal
#
# 用法：
#   Rscript run_deseq2.R --counts <gene_counts.tsv> \
#                        --samples <sample_info.csv> \
#                        --annotation <gene_annotation.tsv> \
#                        [--outdir <结果目录>]
#
# 方法：
#   - 非负整数 counts -> DESeq2
#   - 标准化 / 连续 / 已 log 值 -> limma
# 方向固定为 Tumor vs Normal（log2FC > 0 表示 Tumor 更高）。
# ============================================================================

args_all <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args_all, value = TRUE)
if (length(file_arg) != 1L) stop("请通过 Rscript 运行本脚本")
script_dir <- dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE))
source(file.path(script_dir, "checks.R"), encoding = "UTF-8")

required_cols <- c("gene_id", "gene_name", "log2FoldChange", "pvalue", "padj")
alpha <- 0.05
lfc_cutoff <- 1

print_usage <- function() {
  cat(
    "用法：Rscript run_deseq2.R --counts <file> --samples <file> --annotation <file> [--outdir <dir>]\n\n",
    "  --counts      gene_counts.tsv（行 = 基因，第一列 gene_id）\n",
    "  --samples     sample_info.csv（含 sample_id、group；group 必须为 Normal/Tumor）\n",
    "  --annotation  gene_annotation.tsv（含 gene_id、gene_name）\n",
    "  --outdir      输出目录，默认 ./results\n",
    sep = ""
  )
}

parse_args <- function(argv) {
  keys <- c("counts", "samples", "annotation", "outdir")
  opts <- setNames(vector("list", length(keys)), keys)

  i <- 1L
  while (i <= length(argv)) {
    a <- argv[i]
    if (a %in% c("-h", "--help")) {
      print_usage()
      quit(save = "no", status = 0)
    }
    key <- sub("^--", "", a)
    if (a != paste0("--", key) || !key %in% keys)
      fail("未知参数：%s", a)
    if (i == length(argv))
      fail("参数 %s 缺少取值", a)
    opts[[key]] <- argv[i + 1L]
    i <- i + 2L
  }

  required <- c("counts", "samples", "annotation")
  miss <- required[vapply(opts[required], is.null, logical(1))]
  if (length(miss) > 0) {
    print_usage()
    fail("缺少必需参数：%s", paste0("--", miss, collapse = ", "))
  }

  if (is.null(opts$outdir) || !nzchar(opts$outdir))
    opts$outdir <- file.path(getwd(), "results")
  opts
}

run_deseq2 <- function(counts, samples) {
  suppressPackageStartupMessages(library(DESeq2))

  dds <- DESeq2::DESeqDataSetFromMatrix(
    countData = round(counts),
    colData = samples,
    design = ~ group
  )
  dds <- DESeq2::DESeq(dds, quiet = TRUE)

  res <- DESeq2::results(
    dds,
    contrast = c("group", "Tumor", "Normal"),
    alpha = alpha,
    independentFiltering = TRUE
  )

  data.frame(
    gene_id = rownames(res),
    log2FoldChange = res$log2FoldChange,
    pvalue = res$pvalue,
    padj = res$padj,
    stringsAsFactors = FALSE
  )
}

run_limma <- function(counts, samples, value_type) {
  suppressPackageStartupMessages(library(limma))

  expr <- if (value_type$kind == "normalized_abundance") log2(counts + 1) else counts

  design <- stats::model.matrix(~ 0 + group, data = samples)
  colnames(design) <- levels(samples$group)  # Normal, Tumor

  fit <- limma::lmFit(expr, design)
  contrast <- limma::makeContrasts(contrasts = "Tumor - Normal", levels = design)
  fit2 <- limma::eBayes(limma::contrasts.fit(fit, contrast), trend = TRUE)

  tt <- limma::topTable(fit2, number = Inf, sort.by = "none")
  data.frame(
    gene_id = rownames(tt),
    log2FoldChange = tt$logFC,
    pvalue = tt$P.Value,
    padj = tt$adj.P.Val,
    stringsAsFactors = FALSE
  )
}

attach_gene_names <- function(res, annotation) {
  idx <- match(res$gene_id, annotation$gene_id)
  res$gene_name <- as.character(annotation$gene_name[idx])
  res
}

sort_results <- function(res) {
  res[order(res$padj, res$pvalue, res$gene_id, na.last = TRUE), , drop = FALSE]
}

count_significant <- function(res) {
  ok <- is.finite(res$log2FoldChange) & !is.na(res$padj)
  up <- sum(ok & res$padj < alpha & res$log2FoldChange >= lfc_cutoff)
  down <- sum(ok & res$padj < alpha & res$log2FoldChange <= -lfc_cutoff)
  list(up = up, down = down, total = up + down,
       testable = sum(!is.na(res$padj)))
}

write_results <- function(res, path) {
  write.table(
    res[, required_cols, drop = FALSE],
    file = path,
    sep = "\t", quote = FALSE, row.names = FALSE, na = "NA",
    fileEncoding = "UTF-8"
  )
  message("[输出] 已写入 ", path)
}

make_volcano <- function(res, path) {
  suppressPackageStartupMessages(library(ggplot2))

  d <- data.frame(log2FC = res$log2FoldChange, padj = res$padj)
  d <- d[is.finite(d$log2FC) & !is.na(d$padj), , drop = FALSE]

  if (nrow(d) == 0) {
    p <- ggplot() +
      annotate("text", x = 0, y = 0, label = "No genes with finite padj") +
      labs(title = "Tumor vs Normal",
           x = "log2 fold change (Tumor / Normal)",
           y = "-log10(padj)") +
      theme_bw()
    ggsave(path, p, width = 8, height = 6, dpi = 150)
    return(invisible(path))
  }

  d$neglog10 <- -log10(pmax(d$padj, .Machine$double.xmin))
  d$status <- ifelse(
    d$padj < alpha & d$log2FC >= lfc_cutoff, "Up",
    ifelse(d$padj < alpha & d$log2FC <= -lfc_cutoff, "Down", "Not significant")
  )
  d$status <- factor(d$status, levels = c("Up", "Down", "Not significant"))

  p <- ggplot(d, aes(x = log2FC, y = neglog10, color = status)) +
    geom_point(size = 0.7, alpha = 0.6) +
    geom_vline(xintercept = c(-lfc_cutoff, lfc_cutoff),
               linetype = "dashed", linewidth = 0.4, color = "grey40") +
    geom_hline(yintercept = -log10(alpha),
               linetype = "dashed", linewidth = 0.4, color = "grey40") +
    scale_color_manual(
      values = c("Up" = "#C0392B", "Down" = "#2471A3",
                 "Not significant" = "#B0B0B0"),
      drop = FALSE
    ) +
    labs(
      title = "Tumor vs Normal",
      x = "log2 fold change (Tumor / Normal)",
      y = "-log10(padj)",
      color = NULL,
      caption = "Dashed lines: |log2FC| = 1 and padj = 0.05"
    ) +
    theme_bw(base_size = 11) +
    theme(legend.position = "top")

  ggsave(path, p, width = 8, height = 6, dpi = 150)
  invisible(path)
}

write_summary <- function(path, method_label, value_type, res, samples, coverage) {
  sig <- count_significant(res)
  tab <- table(samples$group)

  method_note <- if (grepl("^DESeq2", method_label)) {
    c("- log2FoldChange 为未经收缩的 MLE 估计。",
      "- results() 默认启用独立过滤；padj 为 NA 的基因不纳入显著基因统计。")
  } else {
    c("- 输入为连续值：标准化丰度按 log2(x+1) 转换，已 log 转换的数据直接使用（假设底数为 2）。",
      "- limma-trend（eBayes trend = TRUE）用于稳定方差。")
  }

  lines <- c(
    "# 差异表达分析摘要", "",
    sprintf("- 生成时间：%s", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    sprintf("- 分析方法：%s", method_label),
    sprintf("- 方法判定依据：%s", value_type$reason),
    "- 比较方向：Tumor vs Normal（log2FoldChange > 0 表示 Tumor 表达高于 Normal）",
    "- 筛选标准：|log2FC| >= 1 且 padj < 0.05",
    "- 多重检验校正：Benjamini-Hochberg (BH)",
    "",
    "## 输入",
    sprintf("- 表达矩阵：%d 个基因 × %d 个样本", nrow(res), nrow(samples)),
    sprintf("- 分组：Normal = %d，Tumor = %d",
            as.integer(tab[["Normal"]]), as.integer(tab[["Tumor"]])),
    sprintf("- 注释匹配率：%.1f%%", coverage * 100),
    "",
    "## 结果",
    sprintf("- 可检验基因数（padj 非 NA）：%d", sig$testable),
    sprintf("- 显著上调（Up）：%d", sig$up),
    sprintf("- 显著下调（Down）：%d", sig$down),
    sprintf("- 显著合计：%d", sig$total),
    "",
    "## 输出文件",
    "- `results.tsv`：gene_id、gene_name、log2FoldChange、pvalue、padj（按 padj 升序）",
    "- `volcano.png`：火山图（x = log2FC，y = -log10(padj)）",
    "- `summary.md`：本摘要",
    "",
    "## 备注",
    method_note,
    "- 本分析按非配对两组比较执行；sample_info 中虽有 patient_id，但未建模患者配对效应。",
    "- 统计显著不等同于生物学结论，阈值与样本量（Normal 10 / Tumor 10）需在解释时考虑。"
  )

  con <- file(path, open = "wb")
  writeLines(enc2utf8(lines), con, useBytes = TRUE)
  close(con)
  message("[输出] 已写入 ", path)
}

main <- function() {
  opts <- parse_args(commandArgs(trailingOnly = TRUE))

  outdir <- normalizePath(opts$outdir, winslash = "/", mustWork = FALSE)
  if (!dir.exists(outdir)) {
    if (!dir.create(outdir, recursive = TRUE, showWarnings = FALSE))
      fail("无法创建输出目录：%s", outdir)
  }

  inputs <- read_inputs(opts$counts, opts$samples, opts$annotation)
  value_type <- classify_input(inputs$counts)

  if (value_type$kind == "integer_counts") {
    message("[方法] DESeq2（", value_type$reason, "）")
    res <- run_deseq2(inputs$counts, inputs$samples)
    method_label <- paste0("DESeq2 ", as.character(packageVersion("DESeq2")))
  } else {
    message("[方法] limma（", value_type$reason, "）")
    res <- run_limma(inputs$counts, inputs$samples, value_type)
    method_label <- paste0("limma ", as.character(packageVersion("limma")))
  }

  res <- attach_gene_names(res, inputs$annotation)
  res <- sort_results(res)

  write_results(res, file.path(outdir, "results.tsv"))
  make_volcano(res, file.path(outdir, "volcano.png"))
  message("[输出] 已写入 ", file.path(outdir, "volcano.png"))
  write_summary(file.path(outdir, "summary.md"), method_label, value_type,
                res, inputs$samples, inputs$coverage)

  verify_outputs(outdir, required_cols, expected_rows = nrow(res))

  sig <- count_significant(res)
  message(sprintf("[完成] 显著上调 %d 个，显著下调 %d 个。结果目录：%s",
                  sig$up, sig$down, outdir))
}

tryCatch(
  main(),
  error = function(e) {
    message("\n[错误] ", conditionMessage(e))
    quit(save = "no", status = 1)
  }
)
