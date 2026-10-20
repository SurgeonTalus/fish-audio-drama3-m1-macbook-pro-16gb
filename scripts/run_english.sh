#!/bin/bash
# English voice clone with Fish Audio Drama 3 (drama3-small) on Apple Silicon.
#
# English is the language this model actually supports alongside Japanese.
# The reference clip in this test was Norwegian, and the clone transferred
# to English cleanly -- so the reference language does not have to match
# the generation language.
#
# Usage: ./run_english.sh [text_file] [reference_wav] [reference_text_file]

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

BIN="$ROOT/bin/audiocpp_cli"
MODEL="$ROOT/models/drama3-small-IQ3_XXS.gguf"
TEXT_FILE="${1:-$HERE/english_text.txt}"
REF_WAV="${2:-$ROOT/ref/voice_ref.wav}"
REF_TEXT_FILE="${3:-$HERE/reference_text.txt}"
OUT="${OUT:-$ROOT/out/english_works.wav}"

for f in "$BIN" "$MODEL" "$TEXT_FILE" "$REF_WAV" "$REF_TEXT_FILE"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing required file: $f" >&2
        exit 1
    fi
done

mkdir -p "$ROOT/out"

REF_TEXT="$(cat "$REF_TEXT_FILE")"
TTS_TEXT="$(cat "$TEXT_FILE")"

echo "Model:    $(basename "$MODEL")"
echo "Reference: $REF_WAV"
echo "Output:   $OUT"
echo

# The session options below are what make this fit on a 16 GB Mac.
#   codec_backend=cpu                -> frees 747 MB of Metal memory (the codec)
#   codec_encoder_chunk_samples      -> chunks the reference encoder, lowers its peak
#   context_length=2048              -> stable prompt+reference+generation capacity
#   cpu_expert_layers=0              -> all 40 expert banks stay on the GPU (5.5x faster)
#   max-tokens=700                   -> ~33 s of audio; higher caps emit trailing silence
exec "$BIN" \
    --task clon \
    --family fish_drama3 \
    --backend metal \
    --mode offline \
    --model "$MODEL" \
    --voice-ref "$REF_WAV" \
    --request-option "reference_text=$REF_TEXT" \
    --text "$TTS_TEXT" \
    --max-tokens 700 \
    --seed 42 \
    --threads 10 \
    --session-option fish_drama3.cpu_expert_layers=0 \
    --session-option fish_drama3.context_length=2048 \
    --session-option fish_drama3.codec_backend=cpu \
    --session-option fish_drama3.codec_encoder_chunk_samples=65536 \
    --metrics \
    --out "$OUT"
