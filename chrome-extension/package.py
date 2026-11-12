"""Create an allowlisted, credential-free Chrome release with its pinned dependency."""
from pathlib import Path
import hashlib, json, zipfile
root=Path(__file__).resolve().parent
output=root/'dist';output.mkdir(exist_ok=True)
archive=output/'eloter-Chrome.zip'
files=[root/'README.md']
files+=sorted((root/'extension').rglob('*'))
files+=[root/'companion'/n for n in ('bridge.mjs','tunnel.mjs','package.json','package-lock.json')]
files+=sorted((root/'companion/node_modules/ws').rglob('*'))
assert json.loads((root/'companion/node_modules/ws/package.json').read_text())['version']=='8.22.2'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in files:
        if p.is_file():z.write(p,'eloter-Chrome/'+p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert not any('Connection.json' in name or '.git/' in name for name in z.namelist())
    assert 'eloter-Chrome/extension/manifest.json' in z.namelist()
(output/'SHA256SUMS.txt').write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  '+archive.name+'\n')
print(f'{archive.name}: {archive.stat().st_size:,} bytes; ZIP CRC passed')
