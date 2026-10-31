# Licenses — read this before shipping anything

> **CHARGING BLOCKER — DO NOT HIDE THIS:** the LRS3 Auto-AVSR
> weights in this repo (visual-only + audio-visual, plus the subword
> LM on the same lineage) are **non-commercial research use only**.
> You **cannot legally ship or charge for Subvox Local with those
> weights as-is** — not as a subscription, not as a one-time purchase.
> The paid version is blocked until this is resolved. Commercial
> path (get a licence / swap to a commercially licensed model /
> train your own / ship a research-only free version now and a paid
> version later) and the full charging plan are in
> `docs/CHARGING_PLAN.md` §5. A research-only free version is the
> only version that can ship today. No real checkout, Stripe key,
> or licence server exists in this repo.

## Code in this repo

- **Subvox Local new code** (`src/subvox_local/`, `scripts/`, `swift/`,
  `docs/`, `tests/`): MIT, same as Lipflow. Free to use / modify.
- **Lipflow vendored copy** (`lipflow-upstream/`): MIT, Copyright (c)
  2026 Amy Zhou. See `lipflow-upstream/LICENSE`. Bundled third-party
  code keeps its own license — see `lipflow-upstream/NOTICE`:
  ESPnet (Apache 2.0), Auto-AVSR preprocessing (Apache 2.0, Pingchuan
  Ma et al., Imperial College London), web2 word list (public domain),
  Chaplin by Amanvir Parhar (MIT).
- **Original Subvox** (reference only, `/tmp/subvox`, joeblau/subvox):
  MIT.

## Model weights — the important part

| Weights | License | Commercial use? |
|---|---|---|
| Auto-AVSR LRS3 visual-only (`models/vsr/`) | **LRS3 dataset licence — non-commercial research use only** | **NO** |
| Subword LM (`models/lm/`) | Same LRS3 lineage — treat as non-commercial research only | **NO** |
| Auto-AVSR audio-visual (`models/av/`) | Same LRS3 lineage — treat as non-commercial research only | **NO** |
| MediaPipe FaceLandmarker (`models/face_landmarker.task`) | Apache 2.0 (Google MediaPipe) | Yes, per Apache 2.0 |
| Qwen3-0.6B / 1.7B 4-bit MLX (`models/qwen3-*-mlx/`) | Apache 2.0 (Qwen3, Alibaba) — check the HF model card at download time | Yes, per Apache 2.0 |
| AV-HuBERT Large (`models/avhubert/model.pt`) | Apache 2.0 per the HF repo `vumichien/AV-HuBERT` (tags: license:apache-2.0, dataset:LRS3) | Yes, per Apache 2.0 — but note it was trained on LRS3, so keep the research-use caution in mind for any commercial claim |

Lipflow states it plainly in its README and NOTICE, and this repo
repeats it: **"The LRS3-trained weights are for non-commercial research
use."** and **"The model weights that setup.sh downloads come from the
LRS3 dataset, which is for non-commercial research use only."**

### What that means for Francis

- Building this for your own use / research on your Mac: fine.
- Selling it, putting it in a paid app, or shipping it commercially
  with the LRS3 weights: **not allowed on those weights**. You would
  need different weights (train your own, license a commercial VSR
  model, or use a commercially-licensed base) before any commercial
  launch. Do not skip this step.
- The code (MIT/Apache) is not the blocker — the weights are.

## Hugging Face model pages (check licence + files at download time)

- https://huggingface.co/Amanvir/LRS3_V_WER19.1
- https://huggingface.co/Amanvir/lm_en_subword
- https://huggingface.co/nguyenvulebinh/auto_avsr_av_trlrwlrs2lrs3vox2avsp_base
- https://huggingface.co/mlx-community/Qwen3-0.6B-4bit
- https://huggingface.co/mlx-community/Qwen3-1.7B-4bit
- https://huggingface.co/vumichien/AV-HuBERT
