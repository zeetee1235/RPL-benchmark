#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root_dir <- if (length(args) >= 1) args[[1]] else "."

summary_path <- file.path(root_dir, "results", "summary.csv")
analysis_dir <- file.path(root_dir, "results", "analysis")
if (!file.exists(summary_path)) stop("summary.csv not found: ", summary_path)
if (!dir.exists(analysis_dir)) dir.create(analysis_dir, recursive = TRUE)

summary <- read.csv(summary_path, stringsAsFactors = FALSE)

numeric_cols <- c(
  "n_senders","seed","success_ratio","interference_ratio","send_interval_s",
  "rx_count","tx_expected","pdr","avg_rtt_ms","p95_rtt_ms",
  "duration_s","warmup_s","measure_s","invalid_run"
)
for (col in numeric_cols) {
  if (col %in% names(summary)) summary[[col]] <- suppressWarnings(as.numeric(summary[[col]]))
}

if (!("invalid_run" %in% names(summary))) {
  summary$invalid_run <- 0
}
summary <- summary[summary$invalid_run == 0, , drop = FALSE]

cond_cols <- c("mode","stage","n_senders","success_ratio","interference_ratio","send_interval_s")
agg <- aggregate(
  cbind(pdr, avg_rtt_ms, p95_rtt_ms, rx_count, tx_expected) ~ .,
  data = summary[, c(cond_cols, "pdr","avg_rtt_ms","p95_rtt_ms","rx_count","tx_expected")],
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

write.csv(agg, file.path(analysis_dir, "rtt_summary_by_condition.csv"), row.names = FALSE)

mode_stage <- aggregate(
  cbind(pdr, avg_rtt_ms, p95_rtt_ms) ~ mode + stage,
  data = summary,
  FUN = mean,
  na.rm = TRUE
)
write.csv(mode_stage, file.path(analysis_dir, "rtt_mode_stage_mean.csv"), row.names = FALSE)

docs_dir <- file.path(root_dir, "docs")
figures_dir <- file.path(docs_dir, "figures")
if (!dir.exists(figures_dir)) dir.create(figures_dir, recursive = TRUE)

stage1 <- summary[summary$stage == "stage1", , drop = FALSE]
if (nrow(stage1) > 0) {
  agg_stage1 <- aggregate(
    cbind(avg_rtt_ms, p95_rtt_ms) ~ mode + n_senders,
    data = stage1,
    FUN = function(x) c(mean = mean(x, na.rm = TRUE), sd = sd(x, na.rm = TRUE))
  )
  agg_stage1 <- do.call(data.frame, agg_stage1)
  names(agg_stage1) <- c(
    "mode", "n_senders",
    "mean_rtt", "sd_rtt",
    "mean_p95", "sd_p95"
  )

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
    agg_stage1, "mean_rtt", "sd_rtt",
    "RTT (ms)", "Average RTT by Number of Senders (Stage 1)",
    file.path(figures_dir, "stage1_rtt.pdf")
  )
  plot_with_error(
    agg_stage1, "mean_p95", "sd_p95",
    "RTT P95 (ms)", "RTT P95 by Number of Senders (Stage 1)",
    file.path(figures_dir, "stage1_rtt_p95.pdf")
  )
}

cat("RTT analysis complete.\n")
cat("Outputs:\n")
cat(" -", file.path(analysis_dir, "rtt_summary_by_condition.csv"), "\n")
cat(" -", file.path(analysis_dir, "rtt_mode_stage_mean.csv"), "\n")
cat(" -", file.path(figures_dir, "stage1_rtt.pdf"), "\n")
cat(" -", file.path(figures_dir, "stage1_rtt_p95.pdf"), "\n")
