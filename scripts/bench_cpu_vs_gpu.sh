#!/bin/bash
# Metal vs CPU comparison for Fish Audio Drama 3 (drama3-small).
#
# Measures the real-time factor (RTF) of the same short line with the
# expert banks either on the GPU or partly on the CPU.
#
# Result on an M1 Pro 16 GB (10 cores):
#   cpu_expert_layers=0   (all on Metal) -> RTF 4.7   (2.8 s audio in 13 s)
#   cpu_expert_layers=20  (20 on CPU)   -> RTF 26.1  (2.8 s audio in 73 s)
#
# Metal is 5.5x faster. CPU offload is a memory fallback, not a speed knob.
#
# Note on timing: the FIRST run on a machine spends ~140 s compiling Metal
# shader pipelines. Do not compare raw wall-clock between the first and
# later runs -- use the reported RTF.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

BIN="$ROOT/bin/audiocpp_cli"
MODEL="$ROOT/models/drama3-small-IQ3_XXS.gguf"
TEXT="Mal et A4-ark i grønne og gule nyanser. Mal en stor sirkel på 25,5 cm."

mkdir -p "$ROOT/out"

run_one () {
    local layers="$1" label="$2"
    local start end
    start=$(date +%s)
    "$BIN" \
        --task tts \
        --family fish_drama3 \
        --backend metal \
        --mode offline \
        --model "$MODEL" \
        --text "$TEXT" \
        --max-tokens 60 \
        --seed 42 \
        --threads 10 \
        --session-option "fish_drama3.cpu_expert_layers=$layers" \
        --session-option fish_drama3.context_length=1024 \
        --session-option fish_drama3.codec_backend=cpu \
        --metrics \
        --out "$ROOT/out/bench_tts_${label}.wav" > "$ROOT/out/bench_${label}.log" 2>&1
    end=$(date +%s)
    printf 'cpu_expert_layers=%-3s label=%-8s wall=%ss\n' "$layers" "$label" "$((end-start))"
    grep -E 'metrics\.(rtf|audio_duration_ms)' "$ROOT/out/bench_${label}.log" | sed 's/^/    /'
}

run_one 0  gpu_metal
run_one 20 cpu20_experts
run_one 40 cpu_all

echo
echo "Compare the metrics.rtf values, not the wall-clock numbers."
