#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root_dir <- if (length(args) >= 1) args[[1]] else "."

summary_path <- file.path(root_dir, "results", "summary.csv")
thresholds_path <- file.path(root_dir, "results", "thresholds.csv")

if (!file.exists(summary_path)) stop("summary.csv not found: ", summary_path)

summary <- read.csv(summary_path, stringsAsFactors = FALSE)

cat("== Summary Check ==\n")
cat("rows:", nrow(summary), "\n")
cat("modes:", paste(sort(unique(summary$mode)), collapse = ", "), "\n")
cat("stages:", paste(sort(unique(summary$stage)), collapse = ", "), "\n\n")

expected_cols <- c(
  "mode","stage","n_senders","seed","success_ratio","interference_ratio",
  "send_interval_s","rx_count","tx_expected","pdr","avg_delay_ms","p95_delay_ms",
  "dio_count","dao_count","duration_s","warmup_s","measure_s","log_path","csc_path"
)
missing_cols <- setdiff(expected_cols, names(summary))
if (length(missing_cols) > 0) {
  cat("missing columns:", paste(missing_cols, collapse = ", "), "\n\n")
}

cat("== Per-stage/mode counts ==\n")
counts <- as.data.frame(table(summary$mode, summary$stage), stringsAsFactors = FALSE)
names(counts) <- c("mode", "stage", "runs")
counts <- counts[counts$runs > 0, , drop = FALSE]
counts <- counts[order(counts$mode, counts$stage), ]
print(counts, row.names = FALSE)
cat("\n")

cat("== Zero RX rows (rx_count <= 0) ==\n")
zero_rx <- summary[summary$rx_count <= 0, , drop = FALSE]
if (nrow(zero_rx) == 0) {
  cat("none\n\n")
} else {
  zero_counts <- as.data.frame(table(zero_rx$mode, zero_rx$stage), stringsAsFactors = FALSE)
  names(zero_counts) <- c("mode", "stage", "rows")
  zero_counts <- zero_counts[zero_counts$rows > 0, , drop = FALSE]
  zero_counts <- zero_counts[order(zero_counts$mode, zero_counts$stage), ]
  print(zero_counts, row.names = FALSE)
  cat("\n")
}

cat("== Duplicates (same condition) ==\n")
dup_cols <- c("mode","stage","n_senders","seed","success_ratio","interference_ratio","send_interval_s")
dup_base <- summary[, dup_cols]
dup_counts <- aggregate(list(rows = rep(1, nrow(dup_base))), by = dup_base, FUN = sum)
dup_counts <- dup_counts[dup_counts$rows > 1, , drop = FALSE]
dup_counts <- dup_counts[order(-dup_counts$rows), ]
if (nrow(dup_counts) == 0) {
  cat("none\n\n")
} else {
  print(dup_counts, row.names = FALSE)
  cat("\n")
}

cat("== Log/CSC/CSV file existence ==\n")
log_exists <- file.exists(summary$log_path)
csc_exists <- file.exists(summary$csc_path)
csv_path <- sub("\\.log$", ".csv", summary$log_path)
csv_exists <- file.exists(csv_path)
csv_bytes <- ifelse(csv_exists, file.info(csv_path)$size, NA_real_)
log_missing <- sum(!log_exists, na.rm = TRUE)
csc_missing <- sum(!csc_exists, na.rm = TRUE)
csv_missing <- sum(!csv_exists, na.rm = TRUE)
csv_empty <- sum(csv_exists & csv_bytes == 0, na.rm = TRUE)
exist_summary <- data.frame(
  log_missing = log_missing,
  csc_missing = csc_missing,
  csv_missing = csv_missing,
  csv_empty = csv_empty
)
print(exist_summary, row.names = FALSE)
cat("\n")

if (file.exists(thresholds_path)) {
  cat("== Thresholds Preview ==\n")
  thresholds <- tryCatch(
    read.csv(thresholds_path, stringsAsFactors = FALSE, fill = TRUE),
    error = function(e) e
  )
  if (inherits(thresholds, "error")) {
    cat("failed to read thresholds.csv:", thresholds$message, "\n")
  } else {
    print(thresholds, row.names = FALSE)
  }
} else {
  cat("thresholds.csv not found: ", thresholds_path, "\n")
}
