"""Fast-setup sentences cover every viseme class. Pure Python, no torch."""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from subvox_local.sentences import FAST_10, QUICK_6, STAGE2, HELD_OUT_STAGE1
from subvox_local.visemes import coverage, ALL_CLASSES


def test_fast10_covers_all_visemes():
    cov = coverage(FAST_10)
    assert cov["missing"] == [], f"FAST_10 missing visemes: {cov['missing']}"
    assert set(cov["covered"]) == ALL_CLASSES


def test_quick6_covers_all_visemes():
    cov = coverage(QUICK_6)
    assert cov["missing"] == [], f"QUICK_6 missing visemes: {cov['missing']}"


def test_counts():
    assert len(FAST_10) == 10
    assert len(QUICK_6) == 6
    assert len(STAGE2) == 4
    assert len(set(QUICK_6) | set(STAGE2)) == 10
    assert len(HELD_OUT_STAGE1) == 2
    for s in FAST_10:
        assert 5 <= len(s.split()) <= 12, s


def test_wer():
    from subvox_local.wer import word_error_rate
    assert word_error_rate("hello world", "hello world") == 0.0
    assert word_error_rate("hello world", "hello") == 0.5
    assert word_error_rate("a b c", "x y z") == 1.0
    assert word_error_rate("", "") == 0.0
