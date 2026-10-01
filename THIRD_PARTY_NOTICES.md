# Third-party notices

Private Dictation's own source is licensed under MIT (see `LICENSE`). This does not
relicense its dependencies or confer rights to their trademarks. Complete
upstream license and copyright texts ship in `licenses/` and in every app's
`Contents/Resources/licenses/`. The machine-readable dependency inventory records
versions, upstream source links, and the location of each license text.
Private Dictation source: <https://github.com/kuvalisconrad/private-dictation>.

## Speech model (downloaded separately)

Qwen3-ASR-1.7B is published by the Qwen team under Apache License 2.0. Private
Dictation downloads unmodified public model files from
<https://huggingface.co/Qwen/Qwen3-ASR-1.7B> at pinned revision
`7278e1e70fe206f11671096ffdd38061171dd6e5`. `model-manifest.json` records exact
file sizes and SHA-256 checksums. Model files are not embedded in the app archive.
The license text is included as `licenses/Qwen3-ASR-APACHE-2.0.txt`.
Upstream source: <https://github.com/QwenLM/Qwen3-ASR>.
No affiliation or endorsement by Qwen, Alibaba, Apple, or Hugging Face is implied.

## Included inference and runtime dependencies

- mlx-qwen3-asr 0.4.4, copyright 2025 dmoon, Apache-2.0.
  Source: <https://github.com/moona3k/mlx-qwen3-asr>. Bundled unmodified.
- MLX and MLX Metal 0.32.3, Apple/MLX contributors, MIT.
  Source: <https://github.com/ml-explore/mlx>. Bundled unmodified official
  macOS 14-compatible Apple Silicon wheels, including their Metal shader library.
- CPython 3.12.14, Python Software Foundation and contributors, PSF license and
  upstream notices. Source: <https://github.com/python/cpython>.
  The release uses Astral's unmodified standalone distribution `20260929`,
  including OpenSSL 3.5.9. The pinned archive's SHA-256 is
  `de6b8f94fa765639b423ea353ab340669704c7186f96ee3cab389dcfde770c3c`.
  Source and build recipes: <https://github.com/astral-sh/python-build-standalone>.
  OpenSSL is Apache-2.0; its license text ships alongside Python's.
  The frozen runtime also includes upstream native dependency notices for
  libffi, bzip2, Expat, liblzma, libuuid, mpdecimal, SQLite, libedit, zlib, and
  HACL hashing code in `licenses/Python-native-dependencies/`. Its inventory is
  derived from the checksum-verified full standalone Python build metadata.
- NumPy 2.5.3, BSD and incorporated upstream licenses. Its full wheel notices
  include its bundled numerical-library and other source notices.
- Hugging Face Hub and hf-xet, Apache-2.0; used by the model-loading library.
  Telemetry and Hub network access are disabled during dictation.
- The remaining exact runtime dependencies appear in `requirements.txt` and
  `licenses/dependency-inventory.json`; their complete upstream notices are
  reproduced in `licenses/`.
- tqdm 4.70.1 includes MPL-2.0-covered files and MIT contributions. Those files
  are unmodified. Their corresponding source is freely available from the
  upstream source distribution at <https://pypi.org/project/tqdm/4.70.1/#files>
  and <https://github.com/tqdm/tqdm>. The complete MPL text is included as
  `licenses/MPL-2.0.html`; this project's MIT license does not restrict your rights
  to the MPL-covered files.
- The PyInstaller 6.16.0 bootloader carries GPL terms with its special distribution
  exception allowing bundled applications, including commercial applications,
  to retain their own license. Its full license and exception are included.
  Source: <https://github.com/pyinstaller/pyinstaller>.

Dependencies are not modified by this project. Native binaries are relocated and
signed during packaging. Commercial distribution is subject to retaining these
notices and complying with each upstream license. Any separately installed
replacement model must be reviewed under its own license before distribution.
