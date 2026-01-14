#!/usr/bin/env Rscript
#
# analyze_results.R
# RPL 실험 결과를 분석하고 LaTeX 보고서를 생성합니다.
#

# 필요한 패키지 로드
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(knitr)
  library(kableExtra)
})

# 작업 디렉토리 설정
setwd("/home/dev/WSN-IoT-lab/rpl-benchmark")

# CSV 파일 읽기 함수
read_result_csv <- function(file_path) {
  df <- read.csv(file_path, stringsAsFactors = FALSE)
  
  # 파일명에서 메타데이터 추출
  filename <- basename(file_path)
  parts <- strsplit(filename, "_")[[1]]
  
  df$n_senders <- as.integer(sub("N", "", parts[1]))
  df$seed <- as.integer(sub("seed", "", parts[2]))
  df$success_ratio <- as.numeric(sub("sr(.+)p(.+)", "\\1.\\2", parts[3]))
  df$interference_ratio <- as.numeric(sub("ir(.+)p(.+)", "\\1.\\2", parts[4]))
  df$send_interval <- as.integer(sub("si(.+)\\.csv", "\\1", parts[5]))
  
  return(df)
}

# 모든 결과 파일 읽기
read_all_results <- function(stage, mode) {
  results_dir <- file.path("results", "raw", stage, mode)
  csv_files <- list.files(results_dir, pattern = "\\.csv$", full.names = TRUE)
  
  if (length(csv_files) == 0) {
    cat("No CSV files found in", results_dir, "\n")
    return(NULL)
  }
  
  all_data <- lapply(csv_files, read_result_csv)
  combined <- bind_rows(all_data)
  combined$mode <- mode
  combined$stage <- stage
  
  return(combined)
}

# 통계 요약 생성
generate_summary <- function(data) {
  summary <- data %>%
    group_by(mode, n_senders, seed) %>%
    summarise(
      total_sent = max(seq, na.rm = TRUE),
      total_received = n(),
      pdr = (total_received / total_sent) * 100,
      avg_delay_ms = mean(delay_ms, na.rm = TRUE),
      median_delay_ms = median(delay_ms, na.rm = TRUE),
      max_delay_ms = max(delay_ms, na.rm = TRUE),
      .groups = 'drop'
    )
  
  return(summary)
}

# 모드별 평균 통계
aggregate_by_mode <- function(summary) {
  aggregated <- summary %>%
    group_by(mode, n_senders) %>%
    summarise(
      mean_pdr = mean(pdr, na.rm = TRUE),
      sd_pdr = sd(pdr, na.rm = TRUE),
      mean_delay = mean(avg_delay_ms, na.rm = TRUE),
      sd_delay = sd(avg_delay_ms, na.rm = TRUE),
      n_runs = n(),
      .groups = 'drop'
    )
  
  return(aggregated)
}

# LaTeX 테이블 생성
generate_latex_table <- function(aggregated, caption, label) {
  table_data <- aggregated %>%
    mutate(
      PDR = sprintf("%.2f ± %.2f", mean_pdr, sd_pdr),
      Delay = sprintf("%.2f ± %.2f", mean_delay, sd_delay)
    ) %>%
    select(Mode = mode, `N Senders` = n_senders, PDR, `Delay (ms)` = Delay, `Runs` = n_runs)
  
  latex_code <- kable(table_data, 
                      format = "latex", 
                      booktabs = TRUE,
                      caption = caption,
                      label = label) %>%
    kable_styling(latex_options = c("hold_position"))
  
  return(latex_code)
}

# 그래프 생성
plot_pdr_comparison <- function(aggregated, output_file) {
  p <- ggplot(aggregated, aes(x = n_senders, y = mean_pdr, color = mode, group = mode)) +
    geom_line(size = 1) +
    geom_point(size = 3) +
    geom_errorbar(aes(ymin = mean_pdr - sd_pdr, ymax = mean_pdr + sd_pdr), width = 0.5) +
    labs(
      title = "Packet Delivery Ratio by Number of Senders",
      x = "Number of Senders",
      y = "PDR (%)",
      color = "Mode"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold"),
      legend.position = "bottom"
    ) +
    scale_y_continuous(limits = c(0, 100))
  
  ggsave(output_file, plot = p, width = 8, height = 5, dpi = 300)
  cat("Plot saved to", output_file, "\n")
}

plot_delay_comparison <- function(aggregated, output_file) {
  p <- ggplot(aggregated, aes(x = n_senders, y = mean_delay, color = mode, group = mode)) +
    geom_line(size = 1) +
    geom_point(size = 3) +
    geom_errorbar(aes(ymin = mean_delay - sd_delay, ymax = mean_delay + sd_delay), width = 0.5) +
    labs(
      title = "Average Delay by Number of Senders",
      x = "Number of Senders",
      y = "Delay (ms)",
      color = "Mode"
    ) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold"),
      legend.position = "bottom"
    )
  
  ggsave(output_file, plot = p, width = 8, height = 5, dpi = 300)
  cat("Plot saved to", output_file, "\n")
}

# 메인 실행
main <- function() {
  cat("========================================\n")
  cat("RPL Benchmark Results Analysis\n")
  cat("========================================\n\n")
  
  # Stage1 데이터 읽기
  stage <- "stage1"
  modes <- c("rpl-classic", "rpl-lite", "brpl")
  
  all_results <- list()
  for (mode in modes) {
    cat("Reading", mode, "results...\n")
    data <- read_all_results(stage, mode)
    if (!is.null(data)) {
      all_results[[mode]] <- data
    }
  }
  
  if (length(all_results) == 0) {
    cat("No data found!\n")
    return()
  }
  
  # 모든 데이터 결합
  combined_data <- bind_rows(all_results)
  
  # 통계 요약
  cat("\nGenerating summary statistics...\n")
  summary <- generate_summary(combined_data)
  aggregated <- aggregate_by_mode(summary)
  
  # 결과 출력
  print(aggregated)
  
  # LaTeX 테이블 생성
  cat("\nGenerating LaTeX table...\n")
  latex_table <- generate_latex_table(
    aggregated,
    caption = "Performance Comparison of RPL Variants (Stage 1)",
    label = "tab:stage1_results"
  )
  
  # 테이블 저장
  table_file <- "docs/tables/stage1_summary.tex"
  dir.create(dirname(table_file), recursive = TRUE, showWarnings = FALSE)
  writeLines(latex_table, table_file)
  cat("LaTeX table saved to", table_file, "\n")
  
  # 그래프 생성
  cat("\nGenerating plots...\n")
  dir.create("docs/figures", recursive = TRUE, showWarnings = FALSE)
  plot_pdr_comparison(aggregated, "docs/figures/stage1_pdr.pdf")
  plot_delay_comparison(aggregated, "docs/figures/stage1_delay.pdf")
  
  cat("\n========================================\n")
  cat("Analysis complete!\n")
  cat("========================================\n")
}

# 스크립트 실행
if (!interactive()) {
  main()
}
