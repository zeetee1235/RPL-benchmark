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

cat("Analysis complete.\n")
cat("Outputs:\n")
cat(" -", file.path(analysis_dir, "collapse_stage1.csv"), "\n")
cat(" -", file.path(analysis_dir, "collapse_stage2.csv"), "\n")
cat(" -", file.path(analysis_dir, "collapse_stage3.csv"), "\n")
cat(" -", file.path(analysis_dir, "mode_stage_comparison.csv"), "\n")
