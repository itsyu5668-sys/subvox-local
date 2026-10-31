# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller spec — Subvox Local Python backend, Intel Mac (x86_64).

Build on the Intel Mac (macOS 14+) with:
    cd <repo root>
    uv run pyinstaller packaging/PyInstaller.spec --noconfirm

Output (one-dir):  dist/subvox-local/subvox-local
The .app builder (packaging/build_app.sh) copies that whole directory
into Subvox Local.app/Contents/Resources/subvox-backend/.

UNTESTED ON INTEL MAC: this spec was written on a Linux VM (no macOS,
no PyInstaller run here). Expect the first build to surface missing
hidden imports — read the build warnings, add them here, rebuild.
Do not claim the bundle works until `dist/subvox-local/subvox-local
doctor` runs clean on the Intel Mac.

Design notes:
  * one-dir, NOT one-file: torch + mediapipe are huge; one-file would
    re-extract ~1 GB on every launch. One-dir starts fast after the
    first extraction (there is none — files stay on disk).
  * console=True: the backend is a CLI; the Swift menu-bar app reads
    its stdout/stderr. A windowed build would swallow logs.
  * target_arch='x86_64': Intel only. (Apple Silicon builds use the
    arm64 spec — not written; the old MLX path is a separate build.)
  * MLX is EXCLUDED on purpose: mlx / mlx_lm have no x86_64 wheels
    and must never be bundled here. Intel cleanup is GGUF via
    llama-cpp (llama_cpp hidden import below) once the cleanup branch
    lands; until then cleanup falls back to offline rules.
  * Models are NOT bundled (6 GB). The launcher symlinks the user's
    ~/Library/Application Support/Subvox Local/models/ into the
    bundle so src/subvox_local/paths.py finds them at
    <bundle>/Resources/subvox-backend/models/ (paths.py resolves
    MODELS from the repo/bundle root — see packaging/launcher.sh).
  * The backend imports the vendored Lipflow code at runtime
    (src/subvox_local/face.py, adapt.py, lm_train.py add
    lipflow-upstream/ to sys.path and `from lipflow... import ...`).
    PyInstaller cannot see those dynamic imports, so this spec
    collects the whole `lipflow` and `espnet` packages from
    lipflow-upstream/ and ships lipflow's data files (mean_face.npy).
"""

import os
from PyInstaller.utils.hooks import collect_all, collect_data_files

REPO = os.path.abspath(os.path.join(SPECPATH, ".."))
UPSTREAM = os.path.join(REPO, "lipflow-upstream")

# --- collect big packages wholesale (hooks miss their data files) ------
_mp_tmp, _mp_bin, _mp_data = collect_all("mediapipe")
_sp_tmp, _sp_bin, _sp_data = collect_all("sentencepiece")
_av_tmp, _av_bin, _av_data = collect_all("av")

datas = [
    # Lipflow data files the backend reads at runtime.
    (os.path.join(UPSTREAM, "lipflow", "mean_face.npy"), "lipflow"),
    (os.path.join(UPSTREAM, "lipflow", "data"), "lipflow/data"),
]
datas += _mp_data + _sp_data + _av_data
binaries = _mp_bin + _sp_bin + _av_bin
hiddenimports = (
    _mp_tmp + _sp_tmp + _av_tmp + [
        # Core backend deps (lazy imports PyInstaller analysis misses).
        "torch", "torch.nn", "torch.nn.functional",
        "numpy", "cv2", "sentencepiece", "sounddevice",
        "pynput", "pynput.keyboard", "pynput.mouse",
        "PIL", "PIL.Image",
        # GGUF cleanup via llama.cpp (Intel). The cleanup branch that
        # imports this has not landed yet; the import is bundled now so
        # the frozen app is ready for it. If the build fails on this
        # entry, install llama-cpp-python in the build venv first
        # (build_app.sh does) and rebuild — do not silently drop it.
        "llama_cpp",
        # Vendored Lipflow code (imported dynamically at runtime).
        "lipflow", "lipflow.vsr", "lipflow.face", "lipflow.personal",
        "lipflow.train_lm", "lipflow.train_vsr", "lipflow.av",
        "lipflow.cleanup", "lipflow.dictation", "lipflow.doctor",
        "lipflow.hotkey", "lipflow.hud", "lipflow.camera",
        "lipflow.mic", "lipflow.context", "lipflow.corrections",
        "lipflow.offline",
        # Vendored ESPnet (Lipflow's VSR model code).
        "espnet", "espnet.asr", "espnet.nets", "espnet.utils",
        "espnet.asr.asr_utils", "espnet.nets.pytorch_backend",
    ]
)

a = Analysis(
    [os.path.join(REPO, "src", "subvox_local", "__main__.py")],
    pathex=[os.path.join(REPO, "src"), UPSTREAM],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # MLX must never be bundled on Intel — and the Apple Silicon-only
    # PyObjC frameworks are only needed for the menu-bar/hotkey path
    # on macOS; keep them (they are darwin-only deps in pyproject.toml).
    excludes=["mlx", "mlx_lm", "tkinter", "matplotlib", "torch.test"],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="subvox-local",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,  # UPX breaks macOS code signing; never enable for .app use.
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch="x86_64",
    codesign_identity=None,  # signing happens later, on the whole .app
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="subvox-local",
)
