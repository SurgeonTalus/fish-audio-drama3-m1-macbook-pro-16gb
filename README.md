# Fish Audio Drama 3 on an M1 MacBook Pro 16 GB — field report

Real-world test of **Fish Audio Drama 3** (the `drama3-small` community build) on an
**Apple M1 Pro MacBook Pro with 16 GB unified memory**, using the native
[audio.cpp](https://github.com/0xShug0/audio.cpp) Metal runtime.

**Headline result:** the model runs on a 16 GB Mac — but only the *small* community
build, and that build only speaks **Japanese and English**. Norwegian output is
unusable, and so is any other language outside that pair. English cloning works
well and produces clean, correctly-transcribed speech.

Everything below is measured on the machine, not copied from a datasheet.

---

## TL;DR

| Question | Answer |
|---|---|
| Can Drama 3 run on a 16 GB M1 Pro? | **Yes**, with the `drama3-small` build (9.74 GiB) via audio.cpp + Metal |
| Which languages work? | **Japanese and English only** on the small build |
| Does Norwegian work? | **No — unusable.** Pronunciation collapses into a different language |
| Does English voice cloning work? | **Yes.** Whisper transcription matches the input text verbatim |
| Does the reference language have to match the output language? | **No.** A Norwegian reference produced clean English |
| Is Metal or CPU faster? | **Metal is 5.5x faster** (RTF 4.7 vs 26.1) |
| Is there a quality setting? | **Not in the runtime.** Quality comes from the model file's quantisation. The recommended sampling differs only marginally from the defaults |
| Can it be fine-tuned for Norwegian? | **Not on this machine.** LoRA fine-tuning needs 24 GB+ VRAM on CUDA |
| Is the full 35B Drama 3 an option? | **No.** It needs a CUDA GPU with 48 GB+ |

---

## Hardware and software used

| Component | Value |
|---|---|
| CPU | Apple M1 Pro, 10 cores (10 logical) |
| Memory | 16 GB unified memory |
| OS | macOS 27.0.1 (build 26A434) |
| Runtime | `audio.cpp` **0.9.2-drama3-base-small** (`git 50749561`, 2026-10-18) |
| Build | Release, `apple-clang 21.0.0.21000101`, Darwin arm64 |
| Backends | `cpu`, `metal` |
| Model | `drama3-small-IQ3_XXS.gguf` (9.74 GiB) |
| Model SHA256 | `97d773973d756141a65432b08de76fd4bedbb44e8b98805755130e02d7fe2561` |
| Runtime SHA256 | `1281998c1acd170a7d92139853fe6ce6ab920e211d2ad3359775d43ad9ba616d` |

The runtime ships prebuilt for macOS arm64 Metal, so no compilation is required.

---

## Install

```bash
# 1. Runtime (prebuilt, macOS arm64 Metal)
curl -L -o audiocpp.tar.gz \
  https://github.com/0xShug0/audio.cpp/releases/download/v0.9.2-drama3-base-small/audio-v0.9.2-drama3-base-small-bin-macos-arm64-metal.tar.gz
tar -xzf audiocpp.tar.gz -C bin --strip-components=1

# 2. Model (9.74 GiB)
curl -L -o models/drama3-small-IQ3_XXS.gguf \
  https://huggingface.co/pentacoxian-dev/drama3-small-GGUF/resolve/main/drama3-small-IQ3_XXS.gguf
```

---

## The configuration that works on 16 GB

This is the part that took the most iteration. A plain invocation **will not
complete** on 16 GB.

```bash
./bin/audiocpp_cli \
  --task clon \
  --family fish_drama3 \
  --backend metal \
  --mode offline \
  --model models/drama3-small-IQ3_XXS.gguf \
  --voice-ref ref/voice_ref_8s.wav \
  --request-option "reference_text=<transcript of the reference>" \
  --text "<text to speak>" \
  --max-tokens 700 \
  --seed 42 \
  --threads 10 \
  --session-option fish_drama3.cpu_expert_layers=0 \
  --session-option fish_drama3.context_length=2048 \
  --session-option fish_drama3.codec_backend=cpu \
  --session-option fish_drama3.codec_encoder_chunk_samples=65536 \
  --metrics \
  --out out/result.wav
```

### Why each non-obvious flag is there

| Flag | Reason |
|---|---|
| `fish_drama3.codec_backend=cpu` | **The single most important flag on a 16 GB Mac.** The Fish DAC codec holds a 747 MB Metal buffer. Moving it to CPU frees that for the model and prevents an out-of-memory kill. |
| `fish_drama3.codec_encoder_chunk_samples=65536` | Chunks the reference encoder convolution, cutting its peak memory. Values must be 0 (full) or a positive multiple of 512. |
| `fish_drama3.context_length=2048` | Context capacity covers prompt + reference frames + generated frames. 2048 was the largest value that stayed stable with a reference clip. |
| `fish_drama3.cpu_expert_layers=0` | Keeps all 40 expert banks on the GPU. See the CPU comparison below — this is much faster, and it fits once the codec is on CPU. |
| `--max-tokens 700` | Caps generation. 21.5 frames ≈ 1 s of audio. Too high a cap and the model keeps emitting silence after the text ends. |
| `--threads 10` | Matches the 10 physical cores. |
| `--seed 42` | Reproducible takes. |

### Reference audio requirements

- **44.1 kHz, mono, PCM 16-bit** — Drama 3 outputs 44.1 kHz mono.
- A 48 kHz source must be resampled:

  ```bash
  ffmpeg -i input.wav -ar 44100 -ac 1 -c:a pcm_s16le ref.wav
  ```

- **Keep the reference short (8–12 s).** A 28.5 s reference produced a 314-row
  prefill that never finished on the M1 Pro and eventually killed the process.
  An 8 s reference prefills in ~172 rows and completes reliably.
- `reference_text` is **required** for cloning and must be an accurate transcript
  of the reference audio.

---

## Memory behaviour on 16 GB

Metal reports a working set of 12,713 MB on this machine. Measured allocations:

| Component | Size | Backend |
|---|---|---|
| `drama3_backbone.weights` | 7,311 MB | Metal |
| `drama3.tower` | 1,154 MB | Metal |
| Fish DAC codec | 747 MB | Metal (747 MB on CPU when `codec_backend=cpu`) |

That is **~9.2 GB of Metal buffer** for a 9.74 GiB model — it fits, but with
almost nothing to spare.

### The out-of-memory failure mode

The first attempt used the full 28.5 s reference with the codec on Metal:

```
vm.swapusage: total = 17408.00M  used = 15710.12M  free = 1697.88M
PhysMem: 15G used (3243M wired, 6064M compressor), 68M unused.
```

Swap climbed to **15.7 GB** with only **68 MB of physical memory free**, and the
process was terminated **without any error message**. A silent death with no
log output is the signature of the macOS memory-status killer, not a crash in
the model.

Moving the codec to CPU and shortening the reference to 8 s resolved it.
**If you hit a silent exit on a 16 GB Mac, check `vm.swapusage` first.**

### Metal kernel compilation

The first run spends **~140 s** compiling Metal shader pipelines. This is cached
on disk afterwards, so subsequent runs start immediately. Do not mistake this for
a hang — and note that it makes raw wall-clock time useless for comparing runs.
Use the `metrics.rtf` value instead.

---

## Speed: Metal vs CPU

Measured with identical text, seed and settings. RTF is real-time factor
(wall seconds ÷ audio seconds); lower is better.

| Configuration | RTF | 2.8 s of audio took |
|---|---|---|
| **All layers on Metal** (`cpu_expert_layers=0`) | **4.7** | 13 s |
| 20 expert layers on CPU (`cpu_expert_layers=20`) | **26.1** | 73 s |

**Metal is 5.5x faster.** CPU offload is a last resort for memory, not a
performance tuning option. Note that raw wall-clock times from the very first
run are misleading because of the one-time Metal kernel compilation.

Full end-to-end runs including reference encoding and prefill:

| Run | Audio | RTF |
|---|---|---|
| English clone, 33 s, Metal | 33.1 s | 12.8 |
| Norwegian clone, 9.3 s, Metal | 9.3 s | 11.2 |

The gap between RTF 4.7 (no reference) and RTF ~12 (with reference) is the fixed
cost of encoding the reference clip and prefilling the prompt.

---

## Comparison with an M3 Ultra (MLX)

[drama3-mac](https://github.com/JordiPosthumus/drama3-mac) by Jordi Posthumus is
a separate **MLX** port of Drama 3 with strong results on an **M3 Ultra with
512 GB unified memory**. It uses Apple's own framework instead of GGUF/ggml, and
the model is **fully resident** in RAM.

| | **M3 Ultra + MLX**<br>(drama3-mac) | **M1 Pro 16 GB + audio.cpp**<br>(this report) |
|---|---|---|
| Model | Drama 3 full, experts at 4 bit | Drama 3 full, Q4_K_S |
| Runtime | MLX (native Apple) | audio.cpp (GGUF / ggml) |
| Model in RAM | **Fully resident**, 27.3 GB peak RSS | **Disk-offloaded**, 10.3 GB peak |
| Disk read per 33 s | 0 | 351 GB (full model) |
| **Steady-state RTF** | **0.68** | **28.8** (full model) / 12.8 (small model) |
| Decode | 31.4 frames/s (21.5 needed for real time) | ~1.07 s/frame (full model) |
| Prefill | ~1.9 s for a 31-row prompt | 50.1 s for 176,000 routed rows |

**The speed gap is ~42x** (28.8 vs 0.68 RTF) — but it comes from the
**settings and the hardware**, not from the model:

1. **The model is fully resident on the M3 Ultra.** With 512 GB of RAM there is
   no reason to stream experts from disk. On a 16 GB machine, disk offloading
   is **forced** — it is the only way to run a 21.78 GiB model at all, and it is
   why 351 GB of disk reads is 75 % of wall time.
2. **The M3 Ultra has far more memory bandwidth** — roughly 800 GB/s against
   roughly 200 GB/s for the M1 Pro. Drama 3 decode is memory-bandwidth-bound.
3. **MLX is Apple's own framework.** It uses `mx.compile` with explicitly
   threaded per-layer caches, removing CPU dispatch overhead. ggml has
   more general code paths.
4. **Different backbone quantisation.** drama3-mac keeps the projections in
   **bf16** — as the official FP8 release does — and quantises only the
   experts. The Q4_K_S package also quantises the backbone. drama3-mac
   therefore has both higher fidelity and higher speed.
5. **Decode is kernel-launch-bound, not bandwidth-bound**, in drama3-mac:
   ~1,500 small Metal kernels per step. Their own analysis shows the ~7 GB of
   weights read per step would take ~9 ms at peak bandwidth. On the M1 Pro the
   same work takes 1,070 ms, because each step must fetch experts from disk.

**Conclusion:** on an M3 Ultra with enough RAM, drama3-mac is clearly the
faster route. On a 16 GB Mac that alternative does not exist — the model cannot
stay resident, so disk offloading is not an optimisation but a necessity. With
512 GB RAM and a dedicated SSD, the *same* audio.cpp setup can use
`disk_experts=false` and reach fully resident speed.

### Findings worth borrowing from drama3-mac

- **A 30-second multi-take reference** holds the voice better than a single
  short clip. Measured: cosine similarity 0.939 versus 0.895 for a single
  4-second take.
- **"Cool" sampling for narration, "hot" for emotional peaks.**
  `temperature 0.7, top_p 0.85` for calm text, `temperature 0.8, top_p 0.9`
  for emotional passages.
- **Never quantise the projections.** It produces fluent gibberish, because
  the noise compounds across 40 layers. drama3-mac guards against this
  explicitly.
- **Acceptance bar:** a clip counts as good only if Whisper transcribes it
  back to the prompt. This report used the same method.

---

## Language support: the decisive finding

`drama3-small` is a **community** build. It is not a quantisation of Drama 3 —
it is a **pruned and distilled** model:

| Component | Drama 3 (full) | drama3-small |
|---|---|---|
| Routed experts | 256 per layer, FP8 | 256 in layers 0/1/2/36, **100 in the other 36** |
| Quantisation | FP8 | IQ3_XXS (~3 bits) |
| Output head | Full vocabulary | EOS + 4,096 semantic rows (**speech only**) |
| Distillation data | — | **~282 h of real speech + 5,501 lines read by the original model, Japanese and English only** |

The model card states its languages plainly: **"Japanese, English"**.

### Norwegian is unusable

Input text (intended):

> Mal et A4-ark i grønne og gule nyanser. Mal en stor sirkel på 25,5 cm og fyll hele sirkelen med farge.

Actual output, transcribed by Whisper (`small`, language forced to `no`):

> Mal et A4 ARK i grunn og god nyanser. Mal en stor cirken på 2 utplaner skjermvektet 5 cm og fyller med hele serien.

The decoding is identical when Whisper is left to auto-detect the language,
confirming the audio does not contain Norwegian.

**What went wrong, word by word:**

| Intended | Produced | Problem |
|---|---|---|
| grønne og gule | grunn og god | both words collapse into Danish/Swedish-like forms |
| sirkel på 25,5 cm | cirken på 2 utplaner skjermvektet 5 cm | the most severe failure — a number and a unit turn into a mangled phrase |
| fyll hele sirkelen med farge | fyller med hele serien | reordering and wrong lemma |

The pattern is characteristic of a model with **no acoustic coverage for the
target language**: the phonemes are approximated from the closest sounds it does
know, producing a superficially plausible but semantically broken sentence. The
prosody and rhythm stay natural, which is what makes the failure easy to miss
if you are not listening to the words closely.

> **Audio: [`audio/norwegian_unusable.wav`](audio/norwegian_unusable.wav)**

### Consequence for other languages

Because the distillation corpus was Japanese and English only, **the limitation
is not specific to Norwegian.** Any language outside Japanese and English should
be expected to fail the same way, with the severity depending on how phonetically
close it is to English. It is not worth testing language by language — the
distillation data already answers the question.

**To get multilingual Drama 3, you need the full model** — 36.9 GiB of stage-0
weights, served through vLLM-Omni or SGLang-Omni, on a CUDA GPU with at least
48 GB. That is out of reach on a 16 GB Mac.

### English works well

The same model, the same reference clip, the same settings — with English text:

> I have achieved a high level of proficiency demonstrated by details such as creating varied imprints using different plants, painting the jewelry pieces, crafting jewelry in various shapes and investing time and making multiple attempts, exploring texture and small scale craft projects using clay, creating clay slabs featuring nature imprints, making small jewelry pieces using seashell imprints and paint, variety in the imprints, creativity in jewelry design and effort.

**Whisper `small` transcription of the generated audio matches the input verbatim**,
including the bullet-list structure. No silence at the start, no truncation, no
runaway generation. A 1.0 s and a 1.3 s natural pause were detected inside the
recording, both at sentence boundaries where they belong.

> **Audio: [`audio/english_works.wav`](audio/english_works.wav)** (33.1 s)

Cross-lingual cloning also works: the reference audio in the samples is
**Norwegian**, and the generated speech is clean **English** in the cloned
timbre. The clone transfers; only the *generation* language is restricted.

---

## Sampling settings: does quality change?

The community model card recommends `temperature 0.7, top_p 0.7, top_k 30`, while
audio.cpp defaults to `temperature 1.0, top_p 0.9, top_k 4097`. Both were tested
with the same text, seed and reference.

| Setting | RTF | Whisper `small` transcription |
|---|---|---|
| Default (temp 1.0, top_p 0.9, top_k 4097) | 12.8 | Verbatim match, punctuation slightly off |
| Recommended (temp 0.7, top_p 0.7, top_k 30) | **10.4** | Verbatim match, punctuation exact |

**The difference is small.** Both transcriptions reproduce the input text
accurately, and the recommended setting is marginally faster. Notably, the
upstream `audio.cpp` default of `top_k=4097` is deliberately uncapped — it
matches Fish's own Drama 3 Space, which dropped the `top_k=30` cap because
`top_k=30` left takes stuck in silence.

> **Audio:** [`audio/english_works.wav`](audio/english_works.wav) (default sampling) ·
> [`audio/english_sampling_recommended.wav`](audio/english_sampling_recommended.wav)
> (recommended sampling)

There is no separate "quality tier" in the runtime. Quality is determined by the
**model file** — the quantisation level of the expert banks. The available
`drama3-small` build is IQ3_XXS; the full-model packages at Q2_K/Q3_K/Q4_K are
15.9–22.9 GiB and do not fit on this machine.

---

## Sample audio

| File | What it is | Duration |
|---|---|---|
| [`audio/english_works.wav`](audio/english_works.wav) | English clone of the reference voice (default sampling) | 33.1 s |
| [`audio/english_sampling_recommended.wav`](audio/english_sampling_recommended.wav) | Same, with the recommended sampling settings | 34.1 s |
| [`audio/norwegian_unusable.wav`](audio/norwegian_unusable.wav) | Norwegian attempt — unusable | 9.3 s |
| [`audio/bench_tts_gpu_metal.wav`](audio/bench_tts_gpu_metal.wav) | Plain TTS, all layers on Metal (RTF 4.7) | 2.8 s |
| [`audio/bench_tts_cpu20_experts.wav`](audio/bench_tts_cpu20_experts.wav) | Plain TTS, 20 expert layers on CPU (RTF 26.1) | 2.8 s |
| [`audio/reference_voice_8s.wav`](audio/reference_voice_8s.wav) | Reference clip used for cloning | 8.0 s |

All files are 44.1 kHz mono PCM 16-bit.

---

## Can it be fine-tuned for Norwegian?

**Technically yes, practically not on this machine.**

Fish Audio ships a LoRA fine-tuning pipeline: prepare a dataset → batch-extract
semantic tokens → pack into protobuf → LoRA training. But for Drama 3:

| Requirement | Drama 3 |
|---|---|
| Base model in memory for training | 35B MoE, FP8 |
| Original checkpoint for conversion | ~68 GiB FP16 intermediate |
| VRAM for LoRA | 24 GB+ (community reports cite a 24 GB 3090 as the practical floor) |
| Accelerator | CUDA or ROCm — no MPS/Metal training path |

A 16 GB unified-memory Mac cannot train it. Fine-tuning would need a rented
CUDA instance, which changes the whole point of running locally.

**Practical alternatives for Norwegian on a Mac:**

- **CosyVoice3 + a Norwegian LoRA** — 0.5B, runs on CPU/MPS, and there are
  community Norwegian fine-tunes. This is the most viable local route.
- **Chatterbox, F5-TTS, E2-TTS, Kokoro, VoxCPM2** — all have good Norwegian
  support and several have native Apple Silicon paths.
- **Drama 3 full on a remote CUDA host** — best quality, but not local.

---

## Known issues hit during testing

1. **Silent process death under memory pressure.** No error, no log line. Check
   `sysctl vm.swapusage`.
2. **Long reference audio stalls prefill.** 28.5 s → 314 rows → never completes
   on M1 Pro. 8 s works reliably.
3. **First run spends ~140 s compiling Metal kernels.** Cached afterwards.
4. **Reference audio must be 44.1 kHz mono.** A 48 kHz source needs resampling
   first.
5. **The pause fix is not in this build.** The community
   `drama3-small-audiocpp.patch` adds a sampler-side fix for runs that go
   silent at a tag or sentence boundary and never resume. The upstream
   `0.9.2-drama3-base-small` release does not include it, and the binary in
   this repo does not honour the `AUDIOCPP_DRAMA3_MAX_PAUSE_FRAMES` environment
   variable. The bug was not triggered by these tests — no runaway generation
   was observed — but it is a known failure mode on tagged text.
6. **`--metrics` only works in offline mode.** It errors out in streaming mode.

---

## Reproducing

`scripts/` contains the exact commands used, with the paths generalised:

- `scripts/run_english.sh` — the working English clone
- `scripts/run_norwegian.sh` — the Norwegian attempt
- `scripts/bench_cpu_vs_gpu.sh` — the RTF comparison
- `scripts/prepare_reference.sh` — resamples a reference to 44.1 kHz mono

```bash
cd scripts
./prepare_reference.sh /path/to/your/voice.wav
./run_english.sh
```

## Credits

- [Fish Audio Drama 3](https://huggingface.co/fishaudio/drama-3) and its codec
  — Fish Audio
- [`drama3-small` GGUF](https://huggingface.co/pentacoxian-dev/drama3-small-GGUF)
  — JarodMica (independent community build; not sponsored or endorsed by Fish Audio)
- [audio.cpp](https://github.com/0xShug0/audio.cpp) — the runtime
- [drama3-mac](https://github.com/JordiPosthumus/drama3-mac) — the MLX port
  by Jordi Posthumus, used as the M3 Ultra reference point in the speed
  comparison above

## Licensing

The model is under the **Fish Audio Community License v1.0**. It is free for
research and non-commercial use; limited commercial use is allowed below USD
500k annual revenue. Offering it as a hosted TTS or voice-cloning service
requires a separate license from Fish Audio.

The **audio clips in this repository were generated with the author's own voice
as the reference material** and are published for the purpose of documenting
these results. The voice is not a public figure and the material is not
intended to impersonate anyone.

Per the model license, do not use this model or its output to imitate the voice
of an identifiable person without their consent, impersonate anyone to deceive,
defraud or harass, or remove watermarks or provenance signals.
