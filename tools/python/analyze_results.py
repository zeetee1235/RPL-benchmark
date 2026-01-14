#!/usr/bin/env python3
"""
analyze_results.py
RPL 실험 결과를 분석하고 LaTeX 테이블을 생성합니다.
"""

import os
import glob
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path

# 한글 폰트 설정
plt.rcParams['font.family'] = 'NanumGothic'
plt.rcParams['axes.unicode_minus'] = False

def parse_filename(filename):
    """파일명에서 메타데이터 추출"""
    parts = Path(filename).stem.split('_')
    return {
        'n_senders': int(parts[0].replace('N', '')),
        'seed': int(parts[1].replace('seed', '')),
        'success_ratio': float(parts[2].replace('sr', '').replace('p', '.')),
        'interference_ratio': float(parts[3].replace('ir', '').replace('p', '.')),
        'send_interval': int(parts[4].replace('si', ''))
    }

def read_result_csv(filepath, mode):
    """CSV 파일 읽기"""
    try:
        df = pd.read_csv(filepath)
        metadata = parse_filename(filepath)
        for key, value in metadata.items():
            df[key] = value
        df['mode'] = mode
        return df
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return None

def read_all_results(stage='stage1'):
    """모든 결과 파일 읽기"""
    results_dir = Path('/home/dev/WSN-IoT-lab/rpl-benchmark/results/raw') / stage
    all_data = []
    
    for mode in ['rpl-classic', 'rpl-lite', 'brpl']:
        mode_dir = results_dir / mode
        if not mode_dir.exists():
            print(f"Directory not found: {mode_dir}")
            continue
            
        csv_files = glob.glob(str(mode_dir / '*.csv'))
        print(f"Found {len(csv_files)} files for {mode}")
        
        for csv_file in csv_files:
            df = read_result_csv(csv_file, mode)
            if df is not None:
                all_data.append(df)
    
    if not all_data:
        print("No data found!")
        return None
    
    return pd.concat(all_data, ignore_index=True)

def generate_summary(data):
    """통계 요약 생성"""
    summary = data.groupby(['mode', 'n_senders', 'seed']).agg({
        'seq': 'max',
        'delay_ms': ['mean', 'median', 'max', 'count']
    }).reset_index()
    
    summary.columns = ['mode', 'n_senders', 'seed', 'total_sent', 
                       'avg_delay_ms', 'median_delay_ms', 'max_delay_ms', 'total_received']
    
    summary['pdr'] = (summary['total_received'] / summary['total_sent']) * 100
    
    return summary

def aggregate_by_mode(summary):
    """모드별 평균 통계"""
    aggregated = summary.groupby(['mode', 'n_senders']).agg({
        'pdr': ['mean', 'std', 'count'],
        'avg_delay_ms': ['mean', 'std']
    }).reset_index()
    
    aggregated.columns = ['mode', 'n_senders', 'mean_pdr', 'sd_pdr', 'n_runs', 
                          'mean_delay', 'sd_delay']
    
    return aggregated

def generate_latex_table(aggregated, output_file):
    """LaTeX 테이블 생성"""
    lines = []
    lines.append("\\begin{table}[H]")
    lines.append("\\centering")
    lines.append("\\caption{Performance Comparison of RPL Variants (Stage 1)}")
    lines.append("\\label{tab:stage1_results}")
    lines.append("\\begin{tabular}{llrrr}")
    lines.append("\\toprule")
    lines.append("Mode & N Senders & PDR (\\%) & Delay (ms) & Runs \\\\")
    lines.append("\\midrule")
    
    for mode in ['rpl-classic', 'rpl-lite', 'brpl']:
        mode_data = aggregated[aggregated['mode'] == mode].sort_values('n_senders')
        for _, row in mode_data.iterrows():
            pdr_str = f"{row['mean_pdr']:.2f} $\\pm$ {row['sd_pdr']:.2f}"
            delay_str = f"{row['mean_delay']:.2f} $\\pm$ {row['sd_delay']:.2f}"
            lines.append(f"{mode} & {row['n_senders']} & {pdr_str} & {delay_str} & {int(row['n_runs'])} \\\\")
    
    lines.append("\\bottomrule")
    lines.append("\\end{tabular}")
    lines.append("\\end{table}")
    
    with open(output_file, 'w') as f:
        f.write('\n'.join(lines))
    
    print(f"LaTeX table saved to {output_file}")

def plot_pdr_comparison(aggregated, output_file):
    """PDR 비교 그래프"""
    plt.figure(figsize=(10, 6))
    
    for mode in ['rpl-classic', 'rpl-lite', 'brpl']:
        mode_data = aggregated[aggregated['mode'] == mode].sort_values('n_senders')
        plt.errorbar(mode_data['n_senders'], mode_data['mean_pdr'], 
                     yerr=mode_data['sd_pdr'], marker='o', label=mode, 
                     linewidth=2, markersize=8, capsize=5)
    
    plt.xlabel('Number of Senders', fontsize=12, fontweight='bold')
    plt.ylabel('PDR (%)', fontsize=12, fontweight='bold')
    plt.title('Packet Delivery Ratio by Number of Senders', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)
    plt.ylim(0, 105)
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Plot saved to {output_file}")
    plt.close()

def plot_delay_comparison(aggregated, output_file):
    """Delay 비교 그래프"""
    plt.figure(figsize=(10, 6))
    
    for mode in ['rpl-classic', 'rpl-lite', 'brpl']:
        mode_data = aggregated[aggregated['mode'] == mode].sort_values('n_senders')
        plt.errorbar(mode_data['n_senders'], mode_data['mean_delay'], 
                     yerr=mode_data['sd_delay'], marker='o', label=mode, 
                     linewidth=2, markersize=8, capsize=5)
    
    plt.xlabel('Number of Senders', fontsize=12, fontweight='bold')
    plt.ylabel('Delay (ms)', fontsize=12, fontweight='bold')
    plt.title('Average Delay by Number of Senders', fontsize=14, fontweight='bold')
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    print(f"Plot saved to {output_file}")
    plt.close()

def main():
    print("=" * 60)
    print("RPL Benchmark Results Analysis")
    print("=" * 60)
    print()
    
    # 데이터 읽기
    print("Reading experiment results...")
    data = read_all_results('stage1')
    
    if data is None or len(data) == 0:
        print("No data to analyze!")
        return
    
    print(f"Total rows: {len(data)}")
    print(f"Modes found: {data['mode'].unique()}")
    print(f"Node counts: {sorted(data['n_senders'].unique())}")
    print()
    
    # 통계 요약
    print("Generating summary statistics...")
    summary = generate_summary(data)
    aggregated = aggregate_by_mode(summary)
    
    print("\nAggregated Results:")
    print(aggregated.to_string(index=False))
    print()
    
    # 출력 디렉토리 생성
    docs_dir = Path('/home/dev/WSN-IoT-lab/rpl-benchmark/docs')
    tables_dir = docs_dir / 'tables'
    figures_dir = docs_dir / 'figures'
    tables_dir.mkdir(parents=True, exist_ok=True)
    figures_dir.mkdir(parents=True, exist_ok=True)
    
    # LaTeX 테이블 생성
    print("Generating LaTeX table...")
    generate_latex_table(aggregated, tables_dir / 'stage1_summary.tex')
    
    # 그래프 생성
    print("Generating plots...")
    plot_pdr_comparison(aggregated, figures_dir / 'stage1_pdr.pdf')
    plot_delay_comparison(aggregated, figures_dir / 'stage1_delay.pdf')
    
    print()
    print("=" * 60)
    print("Analysis complete!")
    print("=" * 60)

if __name__ == '__main__':
    main()
