"""Compatibility entry point for the standalone release's offline speech test."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).with_name("bundled-smoke.py")), run_name="__main__")
