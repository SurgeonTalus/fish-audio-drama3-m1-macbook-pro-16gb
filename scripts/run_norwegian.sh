#!/bin/bash
# Norwegian attempt with Fish Audio Drama 3 (drama3-small).
#
# THIS IS EXPECTED TO PRODUCE UNUSABLE AUDIO.
# drama3-small was distilled on Japanese and English speech only, so it has
# no acoustic coverage for Norwegian. The result is a sentence with natural
# prosody and rhythm but the wrong words -- see audio/norwegian_unusable.wav.
#
# Usage: ./run_norwegian.sh [text_file] [reference_wav] [reference_text_file]

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"

BIN="$ROOT/bin/audiocpp_cli"
MODEL="$ROOT/models/drama3-small-IQ3_XXS.gguf"
TEXT_FILE="${1:-$HERE/norwegian_text.txt}"
REF_WAV="${2:-$ROOT/ref/voice_ref.wav}"
REF_TEXT_FILE="${3:-$HERE/reference_text.txt}"
OUT="${OUT:-$ROOT/out/norwegian_unusable.wav}"

for f in "$BIN" "$MODEL" "$TEXT_FILE" "$REF_WAV" "$REF_TEXT_FILE"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: missing required file: $f" >&2
        exit 1
    fi
done

mkdir -p "$ROOT/out"

REF_TEXT="$(cat "$REF_TEXT_FILE")"
TTS_TEXT="$(cat "$TEXT_FILE")"

cat <<'EOF'
WARNING: drama3-small supports Japanese and English only.
         Norwegian output is expected to be unusable. This script exists to
         reproduce that finding, not to produce a usable result.
EOF
echo

exec "$BIN" \
    --task clon \
    --family fish_drama3 \
    --backend metal \
    --mode offline \
    --model "$MODEL" \
    --voice-ref "$REF_WAV" \
    --request-option "reference_text=$REF_TEXT" \
    --text "$TTS_TEXT" \
    --max-tokens 400 \
    --seed 42 \
    --threads 10 \
    --session-option fish_drama3.cpu_expert_layers=0 \
    --session-option fish_drama3.context_length=2048 \
    --session-option fish_drama3.codec_backend=cpu \
    --session-option fish_drama3.codec_encoder_chunk_samples=65536 \
    --metrics \
    --out "$OUT"
