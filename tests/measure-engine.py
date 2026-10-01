"""Compatibility entry point for the generic offline synthetic benchmark."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/benchmark.py"),
               run_name="__main__")
