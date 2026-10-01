"""Copy upstream license texts and version metadata into each release."""
import importlib.metadata as metadata
import json
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
destination = root / 'licenses'
destination.mkdir(exist_ok=True)
packages = []
for line in (root / 'requirements.txt').read_text().splitlines():
    if line and not line.startswith('#'):
        packages.append(line.split('==')[0])
packages.append('pyinstaller')  # The bootloader's distribution exception.
inventory = []
for package in packages:
    distribution = metadata.distribution(package)
    name = distribution.metadata['Name']
    version = distribution.version
    folder = destination / (name + '-' + version)
    folder.mkdir(exist_ok=True)
    license_files = []
    for file in distribution.files or []:
        if any(term in file.name.upper() for term in ['LICENSE', 'LICENCE', 'COPYING', 'NOTICE']):
            source = distribution.locate_file(file)
            if source.is_file():
                relative = Path(str(file))
                target = folder / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, target)
                license_files.append(str(target.relative_to(destination)))
    inventory.append({'name': name, 'version': version,
                      'license': distribution.metadata.get('License-Expression') or distribution.metadata.get('License'),
                      'project_urls': distribution.metadata.get_all('Project-URL') or [],
                      'license_files': license_files})
python_license = Path(sys.base_prefix) / 'lib/python3.12/LICENSE.txt'
if not python_license.exists():
    raise RuntimeError('Python runtime license not found; include it before distributing.')
shutil.copyfile(python_license, destination / 'Python-3.12-LICENSE.txt')
(destination / 'dependency-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
(destination / 'python-runtime.json').write_text(json.dumps({
    'version': sys.version, 'license': 'PSF-2.0 and included upstream notices',
    'source': 'https://github.com/python/cpython',
}, indent=2) + '\n')
if any(not entry['license_files'] for entry in inventory):
    raise RuntimeError('Missing license texts: ' + ', '.join(entry['name'] for entry in inventory if not entry['license_files']))
print('Collected upstream license texts for', len(inventory), 'packages and Python.')
