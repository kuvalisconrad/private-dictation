"""Sign nested executable code before the outer app with Developer ID."""
from pathlib import Path
import subprocess
import sys

app, identity = Path(sys.argv[1]), sys.argv[2]
entitlements = Path(__file__).with_name('release-entitlements.plist')
mach_o_headers = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
for path in sorted(app.rglob('*'), key=lambda item: len(item.parts), reverse=True):
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as file:
            header = file.read(4)
        if header in mach_o_headers:
            subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp', '--options', 'runtime',
                            '--entitlements', str(entitlements), str(path)], check=True)
subprocess.run(['codesign', '--force', '--sign', identity, '--timestamp', '--options', 'runtime',
                '--entitlements', str(entitlements), str(app)], check=True)
