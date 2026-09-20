# RoboCop Release Builder | Author: Joe "Gambit" Bradford
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--payload-from',type=Path)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
manifest_path=root/'Installer/manifest.json'
manifest=json.loads(manifest_path.read_text())

def digest(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

if args.payload_from:
    with zipfile.ZipFile(args.payload_from) as archive:
        for entry in manifest['files']:
            name=entry['path']
            if not name.startswith(('Payload/Paks/','Runtime/')):continue
            matches=[m for m in archive.namelist() if m==name or m.endswith('/'+name)]
            if len(matches)!=1:raise SystemExit('Expected one payload member: '+name)
            content=archive.read(matches[0])
            if len(content)!=entry['size'] or hashlib.sha256(content).hexdigest()!=entry['sha256']:
                raise SystemExit('Input asset/runtime differs from the release manifest: '+name)
            target=root/name;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
for entry in manifest['files']:
    path=root/entry['path']
    if not path.is_file():raise SystemExit('Missing '+str(path)+'; build native code and provide --payload-from with the full player ZIP.')
    if entry['path'].startswith('Payload/RoboCopGameplay/'):
        entry['size']=path.stat().st_size;entry['sha256']=digest(path)
    elif digest(path)!=entry['sha256'] or path.stat().st_size!=entry['size']:
        raise SystemExit('Asset/runtime differs from the release manifest: '+entry['path'])
manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
allowed={'Installer','Payload','Runtime','Source'}
root_files={'Install_RoboCop.bat','README.txt','README.md','CHANGELOG.md','GitHub_Update_Instructions.txt'}
with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for path in sorted(root.rglob('*')):
        if not path.is_file():continue
        rel=path.relative_to(root)
        if rel.parts[0] not in allowed and str(rel) not in root_files:continue
        if any(part.startswith('.') or part=='__pycache__' for part in rel.parts):continue
        if path.suffix.lower() in {'.exe','.zip','.pdb','.lib','.sav','.log','.pyc'}:continue
        if rel.parts[0]=='Payload' and str(rel).replace('\\','/') not in {p['path'] for p in manifest['files']}:continue
        archive.write(path,Path('RoboCop_Installer')/rel)
print(output)
