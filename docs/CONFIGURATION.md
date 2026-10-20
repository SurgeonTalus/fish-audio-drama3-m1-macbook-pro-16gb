# Runtime and configuration reference

Complete record of every setting used in this test run, for reproducing it or
porting it to another machine.

## Versions

| Component | Value |
|---|---|
| Runtime | `audio.cpp` `0.9.2-drama3-base-small` |
| Runtime commit | `507495611b22dc4593e0e5609e05e8096384e33f` (2026-10-18) |
| Compiler | `apple-clang 21.0.0.21000101` |
| Target | `Darwin arm64` |
| Build type | Release |
| Enabled backends | `cpu`, `metal` |
| Model | `drama3-small-IQ3_XXS.gguf` |
| Model size | 10,460,748,576 bytes (9.74 GiB) |
| Model SHA256 | `97d773973d756141a65432b08de76fd4bedbb44e8b98805755130e02d7fe2561` |
| Runtime archive | `audio-v0.9.2-drama3-base-small-bin-macos-arm64-metal.tar.gz` |
| Runtime SHA256 | `1281998c1acd170a7d92139853fe6ce6ab920e211d2ad3359775d43ad9ba616d` |

## Host

| Component | Value |
|---|---|
| Chip | Apple M1 Pro |
| Cores | 10 physical / 10 logical |
| Unified memory | 16 GB |
| OS | macOS 27.0.1 (build 26A434) |
| Metal working set | 12,713.12 MB (`recommendedMaxWorkingSetSize`) |

## CLI invocation (English clone, the working configuration)

```
./bin/audiocpp_cli \
  --task clon \
  --family fish_drama3 \
  --backend metal \
  --mode offline \
  --model models/drama3-small-IQ3_XXS.gguf \
  --voice-ref ref/voice_ref.wav \
  --request-option "reference_text=<transcript>" \
  --text "<text>" \
  --max-tokens 700 \
  --seed 42 \
  --threads 10 \
  --session-option fish_drama3.cpu_expert_layers=0 \
  --session-option fish_drama3.context_length=2048 \
  --session-option fish_drama3.codec_backend=cpu \
  --session-option fish_drama3.codec_encoder_chunk_samples=65536 \
  --metrics \
  --out out/english_works.wav
```

## Session options and their effect

| Option | Value | Effect |
|---|---|---|
| `fish_drama3.cpu_expert_layers` | `0` | Number of the 40 expert banks kept and evaluated on CPU. `0` = all on GPU. This is the single biggest performance lever: `0` gives RTF 4.7, `20` gives RTF 26.1. |
| `fish_drama3.context_length` | `2048` | Cache capacity for prompt + generated frames, including reference audio frames and history. 2048 was the largest value that stayed stable with a reference clip. |
| `fish_drama3.codec_backend` | `cpu` | Runs the Fish DAC codec on CPU instead of the selected backend. Frees a 747 MB Metal buffer. **Required on 16 GB.** |
| `fish_drama3.codec_encoder_chunk_samples` | `65536` | Reference-encoder convolution chunk size in samples at the codec sample rate. Must be `0` (full encode) or a positive multiple of `512`. Lowers peak memory of the reference encoder. |
| `fish_drama3.disk_experts` | *(default off)* | Reads routed expert weights from the GGUF on demand into a bounded cache. Not needed for `drama3-small` since the whole model fits. |
| `fish_drama3.expert_cache_size` | *(n/a)* | Resident expert slots per layer in `disk_experts` mode, 8–256. |
| `fish_drama3.pin_experts` | *(default off)* | Keeps full expert banks in pinned host RAM. Requires `disk_experts=true`. |
| `fish_drama3.profile_first_audio` | `true` (for diagnosis) | Emits first-audio stage timings to stderr. |
| `fish_drama3.codec_encoder_f32_accumulation` | *(default off)* | F32 accumulation in the F16 reference-encoder GEMMs. Documented for Vulkan; not needed on Metal. |
| `fish_drama3.codec_encoder_bf16_compute` | *(default on)* | BF16 reference-encoder arithmetic on CUDA. Metal is unaffected. |

## Request options

| Option | Value | Notes |
|---|---|---|
| `reference_text` | transcript of the reference clip | **Required** for cloning. An inaccurate transcript degrades the clone. |
| `max_tokens` | `700` | ~33 s of audio at 21.5 frames/second. Higher caps let the model emit trailing silence after the text ends. |
| `seed` | `42` | Reproducible takes within the same configuration. Changing quantisation or offload placement can change the sampled audio. |
| `temperature` | default (1.0) | See the sampling comparison below. |
| `top_p` | default (0.9) | |
| `top_k` | default (4097) | The default keeps every candidate for the semantic token and each tower codebook, so only `top_p` filters. This matches Fish's own Drama 3 Space, which dropped the `top_k=30` cap because `top_k=30` left takes stuck in silence. |

## Measured memory

| Component | Size | Backend |
|---|---|---|
| `drama3_backbone.weights` | 7,311.24 MB | Metal |
| `drama3.tower` | 1,154.41 MB | Metal |
| Fish DAC codec | 747.48 MB | Metal, or CPU with `codec_backend=cpu` |

Total Metal buffer: **~9.2 GB**.

Prefill cache with an 8 s reference: `rows=314 graph_mib=52.6 retained_mib=52.6 shapes=1 nodes=4453`

## Failure modes reproduced

### Silent OOM kill

```
vm.swapusage: total = 17408.00M  used = 15710.12M  free = 1697.88M
PhysMem: 15G used (3243M wired, 6064M compressor), 68M unused.
```

The process exits with **no error message and no log line**. This is the macOS
memory-status killer, not a model crash. Triggered by: full-length reference
audio (28.5 s) with the codec on Metal.

### Prefill stall with long reference audio

A 28.5 s reference produced a 314-row prefill that never completed on the
M1 Pro. An 8 s reference completes reliably.

### First-run Metal kernel compilation

~140 s of shader pipeline compilation on the first run, cached on disk
afterwards. Raw wall-clock from the first run is not comparable to later runs.

### `--metrics` and streaming

`--metrics` is supported in offline mode only and errors in streaming mode.

## Requirements for the reference clip

- 44.1 kHz, mono, PCM 16-bit (Drama 3 outputs 44.1 kHz mono)
- 8–12 s is the tested sweet spot on 16 GB
- An accurate `reference_text` is mandatory
- 48 kHz sources must be resampled with ffmpeg:
  `ffmpeg -i in.wav -ar 44100 -ac 1 -c:a pcm_s16le out.wav`
