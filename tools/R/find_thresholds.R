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

PDR_TH <- 0.90
AVG_RTT_TH_MS <- 5000
P95_RTT_TH_MS <- 8000
COLLAPSE_FRACTION_TH <- 2 / 3

summary <- read.csv(summary_path, stringsAsFactors = FALSE)

needed <- c(
  "mode","stage","n_senders","seed",
  "success_ratio","interference_ratio","send_interval_s","pdr"
)
missing <- setdiff(needed, names(summary))
if (length(missing) > 0) {
  stop("Missing required columns: ", paste(missing, collapse = ", "))
}

if (!("avg_rtt_ms" %in% names(summary))) summary$avg_rtt_ms <- NA_real_
if (!("p95_rtt_ms" %in% names(summary))) summary$p95_rtt_ms <- NA_real_
if (!("invalid_run" %in% names(summary))) summary$invalid_run <- 0

if (!("overhead" %in% names(summary))) {
  if (all(c("dio_count", "dao_count") %in% names(summary))) {
    summary$overhead <- summary$dio_count + summary$dao_count
  } else {
    summary$overhead <- NA_real_
  }
}

to_num <- function(x) suppressWarnings(as.numeric(x))
summary$n_senders <- to_num(summary$n_senders)
summary$seed <- to_num(summary$seed)
summary$success_ratio <- to_num(summary$success_ratio)
summary$interference_ratio <- to_num(summary$interference_ratio)
summary$send_interval_s <- to_num(summary$send_interval_s)
summary$pdr <- to_num(summary$pdr)
summary$avg_rtt_ms <- to_num(summary$avg_rtt_ms)
summary$p95_rtt_ms <- to_num(summary$p95_rtt_ms)
summary$invalid_run <- as.integer(summary$invalid_run)
summary$overhead <- to_num(summary$overhead)

order_key <- function(df, st) {
  if (st == "stage1") {
    order(df$n_senders, na.last = TRUE)
  } else if (st == "stage2") {
    order(-df$success_ratio, -df$interference_ratio, df$n_senders, df$send_interval_s, na.last = TRUE)
  } else if (st == "stage3") {
    order(df$n_senders, df$success_ratio, df$interference_ratio, -df$send_interval_s, na.last = TRUE)
  } else {
    order(df$n_senders, df$success_ratio, df$interference_ratio, df$send_interval_s, na.last = TRUE)
  }
}

key_cols <- c("mode","stage","n_senders","seed","success_ratio","interference_ratio","send_interval_s")
key_str <- apply(summary[, key_cols], 1, function(x) paste(x, collapse = "|"))
summary$key_str <- key_str

has_ts <- "timestamp" %in% names(summary)
has_run_id <- "run_id" %in% names(summary)
ts_col <- if (has_ts) "timestamp" else if (has_run_id) "run_id" else NULL
if (!is.null(ts_col)) {
  summary[[ts_col]] <- as.character(summary[[ts_col]])
}

summary$has_pdr <- !is.na(summary$pdr)
summary$has_rtt <- !is.na(summary$avg_rtt_ms) | !is.na(summary$p95_rtt_ms)

ts_rank <- if (!is.null(ts_col)) {
  -rank(summary[[ts_col]], ties.method = "first")
} else {
  rep(0, nrow(summary))
}

dedup_order <- order(
  summary$key_str,
  summary$invalid_run,
  -as.integer(summary$has_pdr),
  -as.integer(summary$has_rtt),
  ts_rank
)
summary_dedup <- summary[dedup_order, , drop = FALSE]
summary_dedup <- summary_dedup[!duplicated(summary_dedup$key_str), , drop = FALSE]

rtt_metric <- ifelse(!is.na(summary_dedup$p95_rtt_ms), summary_dedup$p95_rtt_ms, summary_dedup$avg_rtt_ms)
rtt_th <- ifelse(!is.na(summary_dedup$p95_rtt_ms), P95_RTT_TH_MS, AVG_RTT_TH_MS)
collapse_pdr <- !is.na(summary_dedup$pdr) & (summary_dedup$pdr < PDR_TH)
collapse_rtt <- !is.na(rtt_metric) & (rtt_metric > rtt_th)
collapse_invalid <- summary_dedup$invalid_run == 1
summary_dedup$collapse <- collapse_invalid | collapse_pdr | collapse_rtt

cond_cols <- c("mode","stage","n_senders","success_ratio","interference_ratio","send_interval_s")
cond_key <- apply(summary_dedup[, cond_cols], 1, function(x) paste(x, collapse = "|"))
summary_dedup$cond_key <- cond_key

cond_levels <- unique(cond_key)
agg_rows <- lapply(cond_levels, function(key) {
  group <- summary_dedup[summary_dedup$cond_key == key, , drop = FALSE]
  seeds <- nrow(group)
  collapse_count <- sum(group$collapse, na.rm = TRUE)
  collapse_frac <- if (seeds > 0) collapse_count / seeds else NA_real_
  pdr_med <- median(group$pdr, na.rm = TRUE)
  avg_rtt_med <- median(group$avg_rtt_ms, na.rm = TRUE)
  p95_rtt_med <- median(group$p95_rtt_ms, na.rm = TRUE)
  overhead_med <- median(group$overhead, na.rm = TRUE)
  any_invalid <- any(group$invalid_run == 1, na.rm = TRUE)
  collapsed <- !is.na(collapse_frac) && collapse_frac >= COLLAPSE_FRACTION_TH
  data.frame(
    mode = group$mode[1],
    stage = group$stage[1],
    n_senders = group$n_senders[1],
    success_ratio = group$success_ratio[1],
    interference_ratio = group$interference_ratio[1],
    send_interval_s = group$send_interval_s[1],
    seeds = seeds,
    collapse_count = collapse_count,
    collapse_frac = collapse_frac,
    pdr_med = pdr_med,
    avg_rtt_med = avg_rtt_med,
    p95_rtt_med = p95_rtt_med,
    overhead_med = overhead_med,
    any_invalid = any_invalid,
    collapsed = collapsed,
    stringsAsFactors = FALSE
  )
})

agg <- do.call(rbind, agg_rows)

find_first_collapse <- function(df) {
  if (nrow(df) == 0) {
    return(data.frame(
      threshold_found = FALSE,
      threshold_index = NA_integer_,
      threshold_condition = NA_character_,
      pdr_med = NA_real_,
      rtt_med_ms = NA_real_,
      overhead_med = NA_real_,
      collapse_frac = NA_real_,
      stringsAsFactors = FALSE
    ))
  }
  stage <- unique(df$stage)
  stage <- if (length(stage) == 1) stage else stage[1]
  df_ord <- df[order_key(df, stage), , drop = FALSE]
  idx <- which(df_ord$collapsed)
  if (length(idx) == 0) {
    return(data.frame(
      threshold_found = FALSE,
      threshold_index = NA_integer_,
      threshold_condition = NA_character_,
      pdr_med = NA_real_,
      rtt_med_ms = NA_real_,
      overhead_med = NA_real_,
      collapse_frac = NA_real_,
      stringsAsFactors = FALSE
    ))
  }
  i <- idx[1]
  row <- df_ord[i, , drop = FALSE]
  cond_str <- paste0(
    "N=", row$n_senders,
    ", sr=", row$success_ratio,
    ", ir=", row$interference_ratio,
    ", si=", row$send_interval_s
  )
  rtt_med <- if (!is.na(row$p95_rtt_med)) row$p95_rtt_med else row$avg_rtt_med
  data.frame(
    threshold_found = TRUE,
    threshold_index = i,
    threshold_condition = cond_str,
    pdr_med = row$pdr_med,
    rtt_med_ms = rtt_med,
    overhead_med = row$overhead_med,
    collapse_frac = row$collapse_frac,
    stringsAsFactors = FALSE
  )
}

mode_stage_key <- paste(agg$mode, agg$stage, sep = "|")
groups <- split(agg, mode_stage_key)
thresholds <- lapply(groups, function(df) {
  ms <- strsplit(unique(paste(df$mode, df$stage, sep = "|")), "\\|")[[1]]
  result <- find_first_collapse(df)
  cbind(mode = ms[1], stage = ms[2], result, stringsAsFactors = FALSE)
})

thresholds_df <- do.call(rbind, thresholds)
write.csv(thresholds_df, out_path, row.names = FALSE, quote = TRUE)

cat("Thresholds written to:", out_path, "\n")
