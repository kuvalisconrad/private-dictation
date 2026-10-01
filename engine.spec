"""Standalone Apple Silicon engine. Include MLX's native Metal library explicitly."""
from pathlib import Path
from PyInstaller.utils.hooks import collect_data_files, collect_dynamic_libs, collect_submodules, copy_metadata

root = Path(SPECPATH)
datas = [(str(root / 'model-manifest.json'), '.')]
datas += collect_data_files('mlx', includes=['lib/*.metallib'])
datas += collect_data_files('mlx_qwen3_asr')
binaries = collect_dynamic_libs('mlx')
for package in ['mlx', 'mlx-metal', 'mlx-qwen3-asr', 'huggingface-hub', 'numpy', 'regex', 'truststore']:
    datas += copy_metadata(package)

a = Analysis([str(root / 'Sources/worker.py')], pathex=[str(root)], binaries=binaries,
             datas=datas, hiddenimports=collect_submodules('mlx_qwen3_asr') + collect_submodules('mlx') + ['truststore._macos'],
             hookspath=[], hooksconfig={}, runtime_hooks=[],
             excludes=['torch', 'transformers', 'scipy', 'pandas', 'matplotlib', 'pytest', 'tkinter'],
             noarchive=False, optimize=1)
pyz = PYZ(a.pure)
exe = EXE(pyz, a.scripts, [], exclude_binaries=True, name='PrivateDictationEngine',
          debug=False, bootloader_ignore_signals=False, strip=False, upx=False,
          console=True, target_arch='arm64', codesign_identity=None, entitlements_file=None)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name='Engine')
