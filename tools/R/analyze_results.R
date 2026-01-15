#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root_dir <- if (length(args) >= 1) args[[1]] else "."
pdr_threshold <- if (length(args) >= 2) as.numeric(args[[2]]) else 0.9

summary_path <- file.path(root_dir, "results", "summary.csv")
analysis_dir <- file.path(root_dir, "results", "analysis")

if (!file.exists(summary_path)) stop("summary.csv not found: ", summary_path)
if (!dir.exists(analysis_dir)) dir.create(analysis_dir, recursive = TRUE)

summary <- read.csv(summary_path, stringsAsFactors = FALSE)

numeric_cols <- c(
  "n_senders","seed","success_ratio","interference_ratio","send_interval_s",
  "rx_count","tx_expected","pdr","avg_delay_ms","p95_delay_ms",
  "dio_count","dao_count","duration_s","warmup_s","measure_s"
)
for (col in numeric_cols) {
  if (col %in% names(summary)) summary[[col]] <- suppressWarnings(as.numeric(summary[[col]]))
}

summary$overhead_per_s <- (summary$dio_count + summary$dao_count) / summary$duration_s

cond_cols <- c("mode","stage","n_senders","success_ratio","interference_ratio","send_interval_s")
agg <- aggregate(
  cbind(pdr, avg_delay_ms, p95_delay_ms, rx_count, tx_expected, dio_count, dao_count) ~ .,
  data = summary[, c(cond_cols, "pdr","avg_delay_ms","p95_delay_ms","rx_count","tx_expected","dio_count","dao_count")],
  FUN = mean,
  na.rm = TRUE
)
runs <- aggregate(
  seed ~ .,
  data = summary[, c(cond_cols, "seed")],
  FUN = length
)
names(runs)[names(runs) == "seed"] <- "runs"
agg <- merge(agg, runs, all.x = TRUE)

agg$collapse_flag <- (agg$pdr < pdr_threshold) | (agg$rx_count <= 0)

stage1 <- agg[agg$stage == "stage1", , drop = FALSE]
stage1_rows <- list()
for (mode in sort(unique(stage1$mode))) {
  subset_mode <- stage1[stage1$mode == mode, , drop = FALSE]
  subset_mode <- subset_mode[order(subset_mode$n_senders), ]
  idx <- which(subset_mode$collapse_flag)
  if (length(idx) > 0) {
    row <- subset_mode[idx[1], c("mode","stage","n_senders","pdr","avg_delay_ms","p95_delay_ms","runs")]
  } else {
    row <- data.frame(
      mode = mode, stage = "stage1", n_senders = NA,
      pdr = NA, avg_delay_ms = NA, p95_delay_ms = NA, runs = NA
    )
  }
  stage1_rows[[length(stage1_rows) + 1]] <- row
}
stage1_out <- do.call(rbind, stage1_rows)
write.csv(stage1_out, file.path(analysis_dir, "collapse_stage1.csv"), row.names = FALSE)

stage2 <- agg[agg$stage == "stage2", , drop = FALSE]
stage2_rows <- list()
if (nrow(stage2) > 0) {
  key <- interaction(stage2$mode, stage2$n_senders, stage2$interference_ratio, drop = TRUE)
  groups <- split(stage2, key)
  for (group in groups) {
    group <- group[order(-group$success_ratio), ]
    idx <- which(group$collapse_flag)
    if (length(idx) > 0) {
      row <- group[idx[1], c("mode","stage","n_senders","success_ratio","interference_ratio","pdr","avg_delay_ms","p95_delay_ms","runs")]
      stage2_rows[[length(stage2_rows) + 1]] <- row
    }
  }
}
stage2_out <- if (length(stage2_rows) > 0) do.call(rbind, stage2_rows) else data.frame()
write.csv(stage2_out, file.path(analysis_dir, "collapse_stage2.csv"), row.names = FALSE)

stage3 <- agg[agg$stage == "stage3", , drop = FALSE]
stage3_rows <- list()
if (nrow(stage3) > 0) {
  key <- interaction(stage3$mode, stage3$n_senders, stage3$success_ratio, stage3$interference_ratio, drop = TRUE)
  groups <- split(stage3, key)
  for (group in groups) {
    group <- group[order(group$send_interval_s), ]
    idx <- which(group$collapse_flag)
    if (length(idx) > 0) {
      row <- group[idx[1], c("mode","stage","n_senders","success_ratio","interference_ratio","send_interval_s","pdr","avg_delay_ms","p95_delay_ms","runs")]
      stage3_rows[[length(stage3_rows) + 1]] <- row
    }
  }
}
stage3_out <- if (length(stage3_rows) > 0) do.call(rbind, stage3_rows) else data.frame()
write.csv(stage3_out, file.path(analysis_dir, "collapse_stage3.csv"), row.names = FALSE)

comp_mean <- aggregate(
  cbind(pdr, avg_delay_ms, p95_delay_ms, overhead_per_s) ~ mode + stage,
  data = summary,
  FUN = mean,
  na.rm = TRUE
)
comp_median <- aggregate(
  cbind(pdr, avg_delay_ms, p95_delay_ms, overhead_per_s) ~ mode + stage,
  data = summary,
  FUN = median,
  na.rm = TRUE
)
names(comp_mean)[3:ncol(comp_mean)] <- paste0(names(comp_mean)[3:ncol(comp_mean)], "_mean")
names(comp_median)[3:ncol(comp_median)] <- paste0(names(comp_median)[3:ncol(comp_median)], "_median")
comp <- merge(comp_mean, comp_median, by = c("mode","stage"))
runs_by_mode <- aggregate(seed ~ mode + stage, data = summary, FUN = length)
names(runs_by_mode)[names(runs_by_mode) == "seed"] <- "runs"
comp <- merge(comp, runs_by_mode, by = c("mode","stage"))
write.csv(comp, file.path(analysis_dir, "mode_stage_comparison.csv"), row.names = FALSE)

docs_dir <- file.path(root_dir, "docs")
tables_dir <- file.path(docs_dir, "tables")
figures_dir <- file.path(docs_dir, "figures")
if (!dir.exists(tables_dir)) dir.create(tables_dir, recursive = TRUE)
if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)

stage1_summary <- summary[summary$stage == "stage1", , drop = FALSE]
if (nrow(stage1_summary) > 0) {
  stage1_summary$pdr_pct <- stage1_summary$pdr * 100
  agg_stage1 <- aggregate(
    cbind(pdr_pct, avg_delay_ms) ~ mode + n_senders,
    data = stage1_summary,
    FUN = function(x) c(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE))
  )
  agg_stage1 <- do.call(data.frame, agg_stage1)
  names(agg_stage1) <- c(
    "mode", "n_senders",
    "mean_pdr", "sd_pdr",
    "mean_delay", "sd_delay"
  )
  runs_stage1 <- aggregate(seed ~ mode + n_senders, data = stage1_summary, FUN = length)
  names(runs_stage1)[names(runs_stage1) == "seed"] <- "n_runs"
  agg_stage1 <- merge(agg_stage1, runs_stage1, by = c("mode", "n_senders"))

  tex_path <- file.path(tables_dir, "stage1_summary.tex")
  lines <- c(
    "\\begin{table}[H]",
    "\\centering",
    "\\caption{Performance Comparison of RPL Variants (Stage 1)}",
    "\\label{tab:stage1_results}",
    "\\begin{tabular}{llrrr}",
    "\\toprule",
    "Mode & N Senders & PDR (\\%) & Delay (ms) & Runs \\\\",
    "\\midrule"
  )
  mode_order <- c("rpl-classic", "rpl-lite", "brpl")
  for (mode in mode_order) {
    mode_rows <- agg_stage1[agg_stage1$mode == mode, , drop = FALSE]
    if (nrow(mode_rows) == 0) next
    mode_rows <- mode_rows[order(mode_rows$n_senders), ]
    for (i in seq_len(nrow(mode_rows))) {
      row <- mode_rows[i, ]
      pdr_str <- sprintf("%.2f $\\\\pm$ %.2f", row$mean_pdr, row$sd_pdr)
      delay_str <- sprintf("%.2f $\\\\pm$ %.2f", row$mean_delay, row$sd_delay)
      lines <- c(lines, sprintf(
        "%s & %d & %s & %s & %d \\\\",
        row$mode, row$n_senders, pdr_str, delay_str, row$n_runs
      ))
    }
  }
  lines <- c(lines, "\\bottomrule", "\\end{tabular}", "\\end{table}")
  writeLines(lines, tex_path)

  plot_with_error <- function(df, y_mean, y_sd, ylab, title, out_path) {
    pdf(out_path)
    mode_order <- c("rpl-classic", "rpl-lite", "brpl")
    colors <- c("rpl-classic" = "#1b9e77", "rpl-lite" = "#d95f02", "brpl" = "#7570b3")
    plot(NULL,
      xlim = range(df$n_senders, na.rm = TRUE),
      ylim = c(0, max(df[[y_mean]] + df[[y_sd]], na.rm = TRUE) * 1.1),
      xlab = "Number of Senders",
      ylab = ylab,
      main = title
    )
    for (mode in mode_order) {
      mode_rows <- df[df$mode == mode, , drop = FALSE]
      if (nrow(mode_rows) == 0) next
      mode_rows <- mode_rows[order(mode_rows$n_senders), ]
      x <- mode_rows$n_senders
      y <- mode_rows[[y_mean]]
      ysd <- mode_rows[[y_sd]]
      lines(x, y, type = "b", pch = 19, col = colors[mode])
      segments(x, y - ysd, x, y + ysd, col = colors[mode])
    }
    legend("topleft", legend = mode_order, col = colors[mode_order], lty = 1, pch = 19, bty = "n")
    dev.off()
  }

  plot_with_error(
    agg_stage1, "mean_pdr", "sd_pdr",
    "PDR (%)", "Packet Delivery Ratio by Number of Senders",
    file.path(figures_dir, "stage1_pdr.pdf")
  )
  plot_with_error(
    agg_stage1, "mean_delay", "sd_delay",
    "Delay (ms)", "Average Delay by Number of Senders",
    file.path(figures_dir, "stage1_delay.pdf")
  )
}

cat("Analysis complete.\n")
cat("Outputs:\n")
cat(" -", file.path(analysis_dir, "collapse_stage1.csv"), "\n")
cat(" -", file.path(analysis_dir, "collapse_stage2.csv"), "\n")
cat(" -", file.path(analysis_dir, "collapse_stage3.csv"), "\n")
cat(" -", file.path(analysis_dir, "mode_stage_comparison.csv"), "\n")
