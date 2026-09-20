# RoboCop Release Builder | Author: Joe "Gambit" Bradford
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--model', type=Path, required=True)
parser.add_argument('--portrait', type=Path, required=True)
parser.add_argument('--ue4ss', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
manifest_path = root / 'Installer/manifest.json'
manifest = json.loads(manifest_path.read_text())

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

if digest(args.ue4ss) != manifest['ue4ssArchiveSha256']:
    raise SystemExit('UE4SS archive differs from the pinned, tested upstream release.')

def copy_member(archive, suffix, destination):
    matches = [name for name in archive.namelist() if name == suffix or name.endswith('/' + suffix)]
    if len(matches) != 1:
        raise SystemExit(f'Expected exactly one archive member for {suffix}: {matches}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(archive.read(matches[0]))

for archive_path, stem in [(args.model, 'RoboCop_Worker02_P'), (args.portrait, 'zz_RoboCop_Portrait_P')]:
    with zipfile.ZipFile(archive_path) as archive:
        for extension in ['pak', 'utoc', 'ucas']:
            name = stem + '.' + extension
            copy_member(archive, name, root / 'Payload/Paks' / name)
with zipfile.ZipFile(args.ue4ss) as archive:
    for name in ['dwmapi.dll', 'ue4ss/UE4SS.dll', 'ue4ss/UE4SS-settings.ini', 'ue4ss/LICENSE']:
        copy_member(archive, name, root / 'Runtime' / name)

for entry in manifest['files']:
    path = root / entry['path']
    if not path.is_file():
        raise SystemExit(f'Missing {path}; build the native helper first.')
    if entry['path'] == 'Payload/RoboCopGameplay/robocop_native.dll':
        entry['sha256'] = digest(path)
        entry['size'] = path.stat().st_size
    elif digest(path) != entry['sha256'] or path.stat().st_size != entry['size']:
        raise SystemExit(f'Input differs from the release manifest: {path}')
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
output = args.output.resolve()
output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for path in sorted(root.rglob('*')):
        if not path.is_file() or path.resolve() == output:
            continue
        rel = path.relative_to(root)
        if any(part.startswith('.') or part == '__pycache__' for part in rel.parts) or path.suffix == '.zip':
            continue
        archive.write(path, Path('RoboCop_Installer') / rel)
print(output)
