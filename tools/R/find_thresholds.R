#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  if (!(flag %in% args)) return(default)
  idx <- match(flag, args)
  if (is.na(idx) || idx >= length(args)) return(default)
  args[[idx + 1]]
}

summary_path <- get_arg("--summary")
out_path <- get_arg("--out")
root_dir <- get_arg("--root", ".")

if (is.null(summary_path)) {
  summary_path <- file.path(root_dir, "results", "summary.csv")
}
if (is.null(out_path)) {
  out_path <- file.path(root_dir, "results", "thresholds.csv")
}

if (!file.exists(summary_path)) {
  stop("summary.csv not found: ", summary_path)
}

summary <- read.csv(summary_path, stringsAsFactors = FALSE)

to_num <- function(x) suppressWarnings(as.numeric(x))

summary$n_senders <- to_num(summary$n_senders)
summary$success_ratio <- to_num(summary$success_ratio)
summary$interference_ratio <- to_num(summary$interference_ratio)
summary$send_interval_s <- to_num(summary$send_interval_s)
summary$pdr <- to_num(summary$pdr)
summary$avg_delay_ms <- to_num(summary$avg_delay_ms)
summary$dio_count <- to_num(summary$dio_count)
summary$dao_count <- to_num(summary$dao_count)

summary$overhead <- summary$dio_count + summary$dao_count

cond_cols <- c(
  "mode", "stage", "n_senders", "success_ratio", "interference_ratio", "send_interval_s"
)

agg <- aggregate(
  cbind(pdr, avg_delay_ms, overhead) ~ .,
  data = summary[, c(cond_cols, "pdr", "avg_delay_ms", "overhead")],
  FUN = mean,
  na.rm = TRUE
)

condition_label <- function(stage, row) {
  if (stage == "stage1") {
    return(sprintf("N=%d", row$n_senders))
  }
  if (stage == "stage2") {
    return(sprintf(
      "N=%d, success_ratio=%.2f, interference_ratio=%.2f",
      row$n_senders, row$success_ratio, row$interference_ratio
    ))
  }
  sprintf(
    "N=%d, success_ratio=%.2f, interference_ratio=%.2f, send_interval_s=%d",
    row$n_senders, row$success_ratio, row$interference_ratio, row$send_interval_s
  )
}

order_stage <- function(df, stage) {
  if (stage == "stage1") {
    df[order(df$n_senders), , drop = FALSE]
  } else if (stage == "stage2") {
    df[order(-df$success_ratio, -df$interference_ratio, df$n_senders), , drop = FALSE]
  } else {
    df[order(-df$send_interval_s, df$n_senders, -df$success_ratio, -df$interference_ratio), , drop = FALSE]
  }
}

thresholds <- list()
stages <- c("stage1", "stage2", "stage3")
modes <- sort(unique(agg$mode))

for (mode in modes) {
  for (stage in stages) {
    stage_rows <- agg[agg$mode == mode & agg$stage == stage, , drop = FALSE]
    if (nrow(stage_rows) == 0) next

    stage_rows <- order_stage(stage_rows, stage)
    prev_overhead <- NA_real_
    threshold_row <- NULL

    for (i in seq_len(nrow(stage_rows))) {
      row <- stage_rows[i, , drop = FALSE]
      overhead_spike <- FALSE
      if (!is.na(prev_overhead) && prev_overhead > 0 && row$overhead > 0) {
        overhead_spike <- row$overhead >= (2 * prev_overhead)
      }

      notes <- c()
      if (row$pdr < 0.90) notes <- c(notes, "pdr<0.90")
      if (row$avg_delay_ms > 5000) notes <- c(notes, "delay>5000ms")
      if (overhead_spike) notes <- c(notes, "control_overhead_spike")

      if (row$pdr < 0.90 || row$avg_delay_ms > 5000 || overhead_spike) {
        threshold_row <- data.frame(
          mode = mode,
          stage = stage,
          threshold_condition_string = condition_label(stage, row),
          pdr = sprintf("%.6f", row$pdr),
          avg_delay_ms = sprintf("%.2f", row$avg_delay_ms),
          overhead = sprintf("%.2f", row$overhead),
          notes = if (length(notes) > 0) paste(notes, collapse = ";") else "collapse",
          stringsAsFactors = FALSE
        )
        break
      }
      prev_overhead <- row$overhead
    }

    if (is.null(threshold_row)) {
      row <- stage_rows[nrow(stage_rows), , drop = FALSE]
      threshold_row <- data.frame(
        mode = mode,
        stage = stage,
        threshold_condition_string = "none",
        pdr = sprintf("%.6f", row$pdr),
        avg_delay_ms = sprintf("%.2f", row$avg_delay_ms),
        overhead = sprintf("%.2f", row$overhead),
        notes = "no collapse found",
        stringsAsFactors = FALSE
      )
    }

    thresholds[[length(thresholds) + 1]] <- threshold_row
  }
}

thresholds_df <- do.call(rbind, thresholds)
write.csv(thresholds_df, out_path, row.names = FALSE, quote = FALSE)

cat("Thresholds written to:", out_path, "\n")
