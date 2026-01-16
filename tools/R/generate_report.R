#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root_dir <- if (length(args) >= 1) args[[1]] else "."
out_dir <- if (length(args) >= 2) args[[2]] else file.path(root_dir, "docs", "report")

summary_path <- file.path(root_dir, "results", "summary.csv")
thresholds_path <- file.path(root_dir, "results", "thresholds.csv")

if (!file.exists(summary_path)) stop("summary.csv 파일을 찾을 수 없습니다: ", summary_path)
if (!file.exists(thresholds_path)) stop("thresholds.csv 파일을 찾을 수 없습니다: ", thresholds_path)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
fig_dir <- file.path(out_dir, "figures")
tab_dir <- file.path(out_dir, "tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

# 한글 폰트 설정
if (capabilities("cairo")) {
  pdf_options <- function() {
    pdf.options(encoding = "CP1252")
  }
} else {
  pdf_options <- function() {}
}

summary <- read.csv(summary_path, stringsAsFactors = FALSE)
thresholds <- read.csv(thresholds_path, stringsAsFactors = FALSE)

to_num <- function(x) suppressWarnings(as.numeric(x))
summary$n_senders <- to_num(summary$n_senders)
summary$seed <- to_num(summary$seed)
summary$success_ratio <- to_num(summary$success_ratio)
summary$interference_ratio <- to_num(summary$interference_ratio)
summary$send_interval_s <- to_num(summary$send_interval_s)
summary$pdr <- to_num(summary$pdr)
summary$avg_rtt_ms <- to_num(summary$avg_rtt_ms)
summary$p95_rtt_ms <- to_num(summary$p95_rtt_ms)
summary$invalid_run <- to_num(summary$invalid_run)
summary$dio_count <- to_num(summary$dio_count)
summary$dao_count <- to_num(summary$dao_count)
summary$overhead <- summary$dio_count + summary$dao_count

thresholds$pdr_med <- to_num(thresholds$pdr_med)
thresholds$rtt_med_ms <- to_num(thresholds$rtt_med_ms)
if ("threshold_found" %in% names(thresholds)) {
  thresholds$threshold_found <- tolower(as.character(thresholds$threshold_found)) %in% c("true", "1")
}

summary <- summary[summary$invalid_run == 0, , drop = FALSE]

mode_colors <- c("rpl-lite" = "#1b9e77", "brpl" = "#7570b3", "rpl-classic" = "#d95f02")

plot_stage1_pdr <- function() {
  stage1 <- summary[summary$stage == "stage1", , drop = FALSE]
  if (nrow(stage1) == 0) return()
  agg <- aggregate(
    pdr ~ mode + n_senders,
    data = stage1,
    FUN = function(x) c(mean = mean(x), sd = sd(x))
  )
  agg <- do.call(data.frame, agg)
  names(agg) <- c("mode", "n_senders", "pdr_mean", "pdr_sd")

  cairo_pdf(file.path(fig_dir, "stage1_pdr.pdf"), width = 7, height = 5)
  par(cex.lab = 1.2, cex.axis = 1.1, cex.main = 1.2)
  plot(NULL, xlim = range(agg$n_senders, na.rm = TRUE), ylim = c(0, 1),
       xlab = "송신 노드 수 (N)", ylab = "PDR",
       main = "1단계: 송신 노드 수에 따른 PDR 변화")
  for (mode in unique(agg$mode)) {
    rows <- agg[agg$mode == mode, , drop = FALSE]
    rows <- rows[order(rows$n_senders), ]
    lines(rows$n_senders, rows$pdr_mean, type = "b", pch = 19,
          col = mode_colors[mode])
    segments(rows$n_senders, rows$pdr_mean - rows$pdr_sd,
             rows$n_senders, rows$pdr_mean + rows$pdr_sd,
             col = mode_colors[mode])
  }
  legend("bottomleft", legend = unique(agg$mode), col = mode_colors[unique(agg$mode)],
         lty = 1, pch = 19, bty = "n")
  dev.off()
}

parse_condition <- function(cond) {
  if (is.na(cond) || cond == "") return(NULL)
  parts <- strsplit(cond, ",")[[1]]
  vals <- list()
  for (p in parts) {
    kv <- strsplit(trimws(p), "=")[[1]]
    if (length(kv) == 2) vals[[kv[1]]] <- as.numeric(kv[2])
  }
  vals
}

plot_stage_rtt_at_threshold <- function(stage, out_name) {
  row <- thresholds[thresholds$stage == stage & thresholds$mode == "rpl-lite", , drop = FALSE]
  if (nrow(row) == 0 || !isTRUE(row$threshold_found[1])) return()
  cond <- parse_condition(row$threshold_condition[1])
  if (is.null(cond)) return()
  subset <- summary[
    summary$stage == stage &
      summary$n_senders == cond$N &
      summary$success_ratio == cond$sr &
      summary$interference_ratio == cond$ir &
      summary$send_interval_s == cond$si, , drop = FALSE
  ]
  if (nrow(subset) == 0) return()
  agg <- aggregate(
    cbind(pdr, avg_rtt_ms) ~ mode,
    data = subset,
    FUN = median
  )
  cairo_pdf(file.path(fig_dir, out_name), width = 7, height = 5)
  par(cex.lab = 1.3, cex.axis = 1.2, cex.main = 1.3)
  bar <- barplot(agg$avg_rtt_ms, names.arg = agg$mode,
                 col = mode_colors[agg$mode], ylim = c(0, max(agg$avg_rtt_ms) * 1.2),
                 ylab = "중앙값 RTT (ms)",
                 main = paste(gsub("stage", "", stage), "단계: 임계 조건에서의 RTT"))
  text(bar, agg$avg_rtt_ms, labels = sprintf("PDR %.2f", agg$pdr), pos = 3, cex = 1.1)
  dev.off()
}

plot_overhead_vs_performance <- function() {
  if (nrow(summary) == 0) return()
  cairo_pdf(file.path(fig_dir, "overhead_vs_performance.pdf"), width = 10, height = 5)
  par(mfrow = c(1, 2), cex.lab = 1.1, cex.axis = 1.0, cex.main = 1.1)
  plot(summary$overhead, summary$pdr, col = mode_colors[summary$mode],
       pch = 19, xlab = "제어 오버헤드 (DIO+DAO)", ylab = "PDR",
       main = "오버헤드 대 PDR")
  plot(summary$overhead, summary$avg_rtt_ms, col = mode_colors[summary$mode],
       pch = 19, xlab = "제어 오버헤드 (DIO+DAO)", ylab = "RTT (ms)",
       main = "오버헤드 대 RTT")
  legend("topright", legend = unique(summary$mode), col = mode_colors[unique(summary$mode)],
         pch = 19, bty = "n")
  dev.off()
}

plot_stage2_heatmap <- function() {
  stage2 <- summary[summary$stage == "stage2", , drop = FALSE]
  if (nrow(stage2) == 0) return()
  modes <- unique(stage2$mode)
  cairo_pdf(file.path(fig_dir, "stage2_coverage_heatmap.pdf"), width = 10, height = 5)
  par(mfrow = c(1, length(modes)), cex.lab = 1.1, cex.axis = 1.0, cex.main = 1.1)
  for (mode in modes) {
    sub <- stage2[stage2$mode == mode, , drop = FALSE]
    grid <- aggregate(pdr ~ success_ratio + interference_ratio, data = sub, FUN = mean)
    sr_vals <- sort(unique(grid$success_ratio))
    ir_vals <- sort(unique(grid$interference_ratio))
    mat <- matrix(NA, nrow = length(ir_vals), ncol = length(sr_vals))
    for (i in seq_len(nrow(grid))) {
      sr_idx <- which(sr_vals == grid$success_ratio[i])
      ir_idx <- which(ir_vals == grid$interference_ratio[i])
      mat[ir_idx, sr_idx] <- grid$pdr[i]
    }
    image(sr_vals, ir_vals, t(mat),
          xlab = "성공률", ylab = "간섭률",
          main = paste("2단계 커버리지:", mode),
          col = colorRampPalette(c("#f7fbff", "#08306b"))(20))
  }
  dev.off()
}

write_thresholds_table <- function() {
  out_path <- file.path(tab_dir, "thresholds_table.tex")
  lines <- c(
    "\\begin{table}[H]",
    "\\centering",
    "\\caption{임계점 요약}",
    "\\label{tab:thresholds}",
    "\\begin{tabular}{lllp{6cm}rr}",
    "\\toprule",
    "모드 & 단계 & 발견 & 조건 & PDR (중앙값) & RTT (중앙값 ms) \\\\",
    "\\midrule"
  )
  for (i in seq_len(nrow(thresholds))) {
    row <- thresholds[i, , drop = FALSE]
    found <- if (isTRUE(row$threshold_found)) "Y" else "N"
    cond <- if (!is.na(row$threshold_condition)) row$threshold_condition else "-"
    pdr <- if (!is.na(row$pdr_med)) sprintf("%.3f", row$pdr_med) else "-"
    rtt <- if (!is.na(row$rtt_med_ms)) sprintf("%.1f", row$rtt_med_ms) else "-"
    lines <- c(lines, sprintf(
      "%s & %s & %s & %s & %s & %s \\\\",
      row$mode, row$stage, found, cond, pdr, rtt
    ))
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}", "\\end{table}")
  writeLines(lines, out_path)
}

write_stage_mean_table <- function() {
  out_path <- file.path(tab_dir, "stage_mean_table.tex")
  agg <- aggregate(cbind(pdr, avg_rtt_ms) ~ mode + stage, data = summary, FUN = mean)
  lines <- c(
    "\\begin{table}[H]",
    "\\centering",
    "\\caption{단계별 평균 성능}",
    "\\label{tab:stage_means}",
    "\\begin{tabular}{llrr}",
    "\\toprule",
    "모드 & 단계 & 평균 PDR & 평균 RTT (ms) \\\\",
    "\\midrule"
  )
  for (i in seq_len(nrow(agg))) {
    row <- agg[i, , drop = FALSE]
    lines <- c(lines, sprintf(
      "%s & %s & %.3f & %.1f \\\\",
      row$mode, row$stage, row$pdr, row$avg_rtt_ms
    ))
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}", "\\end{table}")
  writeLines(lines, out_path)
}

plot_stage1_pdr()
plot_stage_rtt_at_threshold("stage2", "stage2_rtt_at_collapse.pdf")
plot_stage_rtt_at_threshold("stage3", "stage3_rtt_at_collapse.pdf")
plot_overhead_vs_performance()
plot_stage2_heatmap()
write_thresholds_table()
write_stage_mean_table()

cat("보고서 파일이 생성되었습니다:", out_dir, "\n")
