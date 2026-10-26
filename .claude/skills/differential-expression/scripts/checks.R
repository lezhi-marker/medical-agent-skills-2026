# checks.R -------------------------------------------------------------------
# 输入校验、方法判定与输出核验。
# 由 scripts/run_deseq2.R source() 调用，不单独运行。
# 修改校验逻辑时只改本文件，入口脚本不重复实现。

fail <- function(...) stop(sprintf(...), call. = FALSE)

show_ids <- function(x, n = 5) {
  if (length(x) <= n) return(paste(x, collapse = ", "))
  paste0(paste(head(x, n), collapse = ", "), sprintf(" 等共 %d 个", length(x)))
}

check_required_files <- function(paths) {
  for (nm in names(paths)) {
    p <- paths[[nm]]
    if (is.null(p) || !nzchar(p)) fail("%s 路径为空", nm)
    if (!file.exists(p)) fail("找不到 %s 文件：%s", nm, p)
    if (dir.exists(p)) fail("%s 路径是目录而不是文件：%s", nm, p)
    size <- file.info(p)$size
    if (is.na(size) || size == 0) fail("%s 文件为空：%s", nm, p)
  }
  invisible(TRUE)
}

read_inputs <- function(counts_path, samples_path, annotation_path) {
  check_required_files(c(
    counts = counts_path,
    sample_info = samples_path,
    annotation = annotation_path
  ))

  # ---- counts -------------------------------------------------------------
  counts_df <- read.delim(counts_path, check.names = FALSE, quote = "",
                          stringsAsFactors = FALSE)
  if (!"gene_id" %in% names(counts_df))
    fail("gene_counts 第一列应为 gene_id，实际列名为：%s", show_ids(names(counts_df)))
  if (ncol(counts_df) < 3)
    fail("gene_counts 至少需要 gene_id 加 2 个样本列，实际 %d 列", ncol(counts_df))

  counts_df$gene_id <- trimws(as.character(counts_df$gene_id))
  if (anyNA(counts_df$gene_id) || any(!nzchar(counts_df$gene_id)))
    fail("gene_counts 中存在空 gene_id")
  if (anyDuplicated(counts_df$gene_id))
    fail("gene_counts 中 gene_id 重复：%s",
         show_ids(unique(counts_df$gene_id[duplicated(counts_df$gene_id)])))

  sample_cols <- setdiff(names(counts_df), "gene_id")
  if (!all(vapply(counts_df[sample_cols], is.numeric, logical(1))))
    fail("gene_counts 的样本列必须全部为数值")

  counts <- matrix(
    as.numeric(as.matrix(counts_df[, sample_cols, drop = FALSE])),
    nrow = nrow(counts_df),
    dimnames = list(counts_df$gene_id, sample_cols)
  )

  # ---- sample_info --------------------------------------------------------
  samples <- read.csv(samples_path, check.names = FALSE,
                      stringsAsFactors = FALSE, fileEncoding = "UTF-8-BOM")
  if (!all(c("sample_id", "group") %in% names(samples)))
    fail("sample_info 缺少必需列：%s",
         paste(setdiff(c("sample_id", "group"), names(samples)), collapse = ", "))

  samples$sample_id <- trimws(as.character(samples$sample_id))
  samples$group <- trimws(as.character(samples$group))
  if (anyNA(samples$sample_id) || any(!nzchar(samples$sample_id)))
    fail("sample_info 中存在空 sample_id")
  if (anyDuplicated(samples$sample_id))
    fail("sample_info 中 sample_id 重复：%s",
         show_ids(unique(samples$sample_id[duplicated(samples$sample_id)])))

  # 严格一一对应：多一个、少一个、数量不符都停止
  extra <- setdiff(sample_cols, samples$sample_id)
  missing <- setdiff(samples$sample_id, sample_cols)
  if (length(extra) > 0 || length(missing) > 0 || ncol(counts) != nrow(samples)) {
    parts <- character()
    if (length(extra) > 0)
      parts <- c(parts, sprintf("counts 中 %d 个样本列不在 sample_info 中：%s",
                                length(extra), show_ids(extra)))
    if (length(missing) > 0)
      parts <- c(parts, sprintf("sample_info 中 %d 个 sample_id 不在 counts 中：%s",
                                length(missing), show_ids(missing)))
    if (length(extra) == 0 && length(missing) == 0)
      parts <- c(parts, sprintf("counts 有 %d 个样本列，sample_info 有 %d 行",
                                ncol(counts), nrow(samples)))
    fail("counts 列名与 sample_info 的 sample_id 不是一一对应，已停止。%s",
         paste(parts, collapse = "；"))
  }

  # 以 sample_info 的顺序重排样本列
  counts <- counts[, samples$sample_id, drop = FALSE]

  # ---- group --------------------------------------------------------------
  observed <- sort(unique(samples$group))
  if (!identical(observed, c("Normal", "Tumor")))
    fail("分组必须且只能包含 Normal 与 Tumor（区分大小写），实际为：%s",
         paste(observed, collapse = ", "))
  samples$group <- factor(samples$group, levels = c("Normal", "Tumor"))
  rownames(samples) <- samples$sample_id

  group_tab <- table(samples$group)
  if (any(group_tab < 2))
    fail("每组至少需要 2 个样本，当前：%s",
         paste(sprintf("%s=%d", names(group_tab), as.integer(group_tab)),
               collapse = ", "))

  # ---- annotation ---------------------------------------------------------
  annotation <- read.delim(annotation_path, check.names = FALSE, quote = "",
                           stringsAsFactors = FALSE)
  if (!all(c("gene_id", "gene_name") %in% names(annotation)))
    fail("gene_annotation 缺少必需列：%s",
         paste(setdiff(c("gene_id", "gene_name"), names(annotation)),
               collapse = ", "))

  annotation$gene_id <- trimws(as.character(annotation$gene_id))
  annotation$gene_name <- as.character(annotation$gene_name)
  if (anyDuplicated(annotation$gene_id)) {
    warning("gene_annotation 中 gene_id 有重复，已保留首次出现的记录",
            call. = FALSE)
    annotation <- annotation[!duplicated(annotation$gene_id), , drop = FALSE]
  }

  coverage <- mean(rownames(counts) %in% annotation$gene_id)
  if (coverage == 0)
    fail("gene_annotation 与 counts 的 gene_id 完全无法匹配，请检查是否都带版本号")
  if (coverage < 0.9)
    warning(sprintf("仅 %.1f%% 的基因能在注释中找到，请检查 gene_id 版本号是否一致",
                    coverage * 100), call. = FALSE)

  message(sprintf("[输入] 表达矩阵：%d 个基因 × %d 个样本",
                  nrow(counts), ncol(counts)))
  message(sprintf("[输入] 分组：Normal=%d，Tumor=%d",
                  as.integer(group_tab[["Normal"]]),
                  as.integer(group_tab[["Tumor"]])))
  message(sprintf("[输入] 注释匹配率：%.1f%%", coverage * 100))
  message("[输入] counts 列名与 sample_info 的 sample_id 一一对应，检查通过")

  list(
    counts = counts,
    samples = samples,
    annotation = annotation,
    coverage = coverage,
    group_tab = group_tab
  )
}

# 判定数据类型：整数 counts -> DESeq2；标准化/连续/已 log -> limma
classify_input <- function(counts) {
  vals <- as.numeric(counts)
  if (length(vals) == 0) fail("表达矩阵为空")
  if (any(!is.finite(vals))) fail("表达矩阵含 NA/NaN/Inf，无法分析")

  if (any(vals < 0))
    return(list(kind = "log_scale",
                reason = "矩阵含负值，判定为已 log 转换的连续表达值，使用 limma"))

  if (all(vals == floor(vals)))
    return(list(kind = "integer_counts",
                reason = "矩阵全部为非负整数，判定为原始 counts，使用 DESeq2"))

  if (max(vals) <= 1)
    return(list(kind = "normalized_abundance",
                reason = "矩阵为非整数且最大值不超过 1，判定为标准化比例，log2(x+1) 后使用 limma"))

  q99 <- as.numeric(stats::quantile(vals, 0.99, names = FALSE))
  if (q99 > 100)
    return(list(kind = "normalized_abundance",
                reason = sprintf("矩阵为非整数连续值（99%% 分位数 = %.1f），判定为标准化丰度，log2(x+1) 后使用 limma", q99)))

  list(kind = "log_scale",
       reason = sprintf("矩阵为非整数且尺度较小（99%% 分位数 = %.1f），判定为已 log 转换值，直接使用 limma", q99))
}

verify_outputs <- function(outdir, expected_cols, expected_rows = NULL) {
  paths <- file.path(outdir, c("results.tsv", "volcano.png", "summary.md"))
  names(paths) <- c("results.tsv", "volcano.png", "summary.md")

  missing <- names(paths)[!file.exists(paths)]
  if (length(missing) > 0)
    fail("以下输出文件未生成：%s", paste(missing, collapse = ", "))

  sizes <- file.info(paths)$size
  empty <- names(paths)[is.na(sizes) | sizes == 0]
  if (length(empty) > 0)
    fail("以下输出文件为空：%s", paste(empty, collapse = ", "))

  res <- read.delim(paths[["results.tsv"]], check.names = FALSE, quote = "",
                    stringsAsFactors = FALSE)
  if (!identical(names(res), expected_cols))
    fail("results.tsv 列名不符合要求。实际：%s；应为：%s",
         paste(names(res), collapse = ", "),
         paste(expected_cols, collapse = ", "))
  if (nrow(res) == 0) fail("results.tsv 没有数据行")
  if (!is.null(expected_rows) && nrow(res) != expected_rows)
    fail("results.tsv 行数为 %d，预期 %d", nrow(res), expected_rows)
  if (anyDuplicated(res$gene_id)) fail("results.tsv 中 gene_id 重复")
  if (all(is.na(res$padj)))
    warning("results.tsv 中所有 padj 均为 NA，请检查数据与模型", call. = FALSE)

  message("[核验] results.tsv 列名正确，共 ", nrow(res), " 行")
  message("[核验] volcano.png、summary.md 均已生成且非空")
  invisible(TRUE)
}
