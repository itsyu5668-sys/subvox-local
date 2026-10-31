"""Offline cleanup rules. Pure Python, no MLX, no network."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from subvox_local.cleanup import basic_cleanup, clean_top3


def test_basic_cleanup():
    assert basic_cleanup("hello world") == "Hello world."
    assert basic_cleanup("i am here") == "I am here."
    assert basic_cleanup("born in new york city and graduated in nineteen forty three") == \
        "Born in new york city and graduated in 1943."
    # Year edge cases (reviewer-found bugs: "ninety" was missing, round
    # decades and "nineteen hundred" were half-converted or left raw).
    assert basic_cleanup("born in nineteen ninety nine") == "Born in 1999."
    assert basic_cleanup("born in nineteen forty") == "Born in 1940."
    assert basic_cleanup("born in nineteen twenty") == "Born in 1920."
    assert basic_cleanup("born in nineteen hundred and five") == \
        "Born in nineteen hundred and five."


def test_clean_top3_falls_back_to_basic_off_mac(monkeypatch):
    # Fallback path: when no local GGUF backend is available (no
    # llama-cpp and/or no GGUF file), auto -> basic rules. Force that
    # state here so the test is deterministic on any machine, including
    # one where the GGUF model IS downloaded (Intel Mac / this VM).
    import subvox_local.cleanup as _c
    monkeypatch.setattr(_c.LocalCleaner, "available", lambda self: False)
    out = clean_top3(["hello world", "hallo world"], backend="auto")
    assert out == "Hello world."


def test_no_mlx_imports_intel():
    # Intel Mac: MLX is Apple Silicon only and must not be imported
    # anywhere in the backend. GGUF via llama-cpp is the cleanup backend.
    import pathlib, re
    src = pathlib.Path(__file__).resolve().parents[1] / "src" / "subvox_local"
    bad = re.compile(r"^\s*(import|from)\s+mlx", re.M)
    for p in src.glob("*.py"):
        text = p.read_text()
        assert not bad.search(text), p
        assert "import mlx_lm" not in text, p


def test_no_cloud_imports():
    # NOT to use them, so check for actual imports/calls, not mentions.
    import pathlib, re
    src = pathlib.Path(__file__).resolve().parents[1] / "src" / "subvox_local"
    bad = re.compile(r"^\s*(import|from)\s+(anthropic|openai)\b", re.M)
    for p in src.glob("*.py"):
        text = p.read_text()
        assert not bad.search(text), p
        assert "ANTHROPIC_API_KEY" not in text, p
        assert "OPENAI_API_KEY" not in text, p
