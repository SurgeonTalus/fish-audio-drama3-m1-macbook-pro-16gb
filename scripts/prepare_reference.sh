#!/bin/bash
# Resample a voice reference to the format Drama 3 expects: 44.1 kHz, mono, PCM 16-bit.
#
# Usage: ./prepare_reference.sh /path/to/your/voice.wav [seconds]
#
# Keeping the reference SHORT (8-12 s) is important on a 16 GB Mac.
# A 28.5 s reference produced a 314-row prefill that never completed on an
# M1 Pro. An 8 s reference prefills in ~172 rows and completes reliably.

set -euo pipefail

IN="${1:?Usage: $0 <input.wav> [seconds]}"
SECONDS_CUT="${2:-8}"

if [ ! -f "$IN" ]; then
    echo "ERROR: file not found: $IN" >&2
    exit 1
fi

OUT_DIR="$(dirname "$0")/../ref"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/voice_ref.wav"

ffmpeg -y -i "$IN" -t "$SECONDS_CUT" -ar 44100 -ac 1 -c:a pcm_s16le "$OUT" 2>/dev/null

echo "Reference written to: $OUT"
ffprobe -v error -show_entries stream=sample_rate,channels,bits_per_sample \
        -show_entries format=duration -of default=nw=1 "$OUT"

cat <<'EOF'

Next: pass this file with --voice-ref and supply its transcript with
      --request-option "reference_text=<transcript>".
      reference_text is REQUIRED for voice cloning.
EOF
