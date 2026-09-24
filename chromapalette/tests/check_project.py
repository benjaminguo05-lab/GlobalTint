"""Validate deployment contracts; CI additionally compiles and inspects both CPU slices."""
import argparse, io, pathlib, plistlib, re, tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

def check_sources():
    for name in ('ChromaApps', 'ChromaSystem'):
        with (ROOT / (name + '.plist')).open('rb') as f:
            v = plistlib.load(f)
        assert v['Filter']['Bundles']
    with (ROOT / 'ChromaSystem.plist').open('rb') as f:
        assert plistlib.load(f)['Filter']['Bundles'] == ['com.apple.springboard']
    with (ROOT / 'layout/Library/PreferenceLoader/Preferences/ChromaPalette.plist').open('rb') as f:
        entry = plistlib.load(f)['entry']
    assert entry['bundle'] == 'ChromaPrefs'
    prefs = (ROOT / 'prefs/Prefs.m').read_text(encoding='utf-8')
    assert '@interface ' + entry['detail'] in prefs
    info=plistlib.loads((ROOT / 'prefs/Info.plist').read_bytes())
    assert info['NSPrincipalClass'] == entry['detail']
    assert info['CFBundleExecutable'] == entry['bundle']
    for p in ROOT.rglob('*.plist'):
        if '.theos' not in p.parts: plistlib.loads(p.read_bytes())
    src = '\n'.join(p.read_text(encoding='utf-8') for p in ROOT.rglob('*') if p.suffix in ('.m', '.mm', '.h') and '.theos' not in p.parts)
    assert '/var/jb/' not in src
    assert 'THEOS_PACKAGE_SCHEME := roothide' in (ROOT / 'Makefile').read_text()
    schema = (ROOT / 'shared/Schema.m').read_text(encoding='utf-8')
    groups = {}
    current = None
    for line in schema.splitlines():
        g = re.search(r'G\(@"(\w+)"', line)
        if g: current = g.group(1); groups[current] = set()
        r = re.search(r'R\(@"(\w+)"', line)
        if r and current:
            assert r.group(1) not in groups[current]
            groups[current].add(r.group(1))
    for group, role in re.findall(r'CPColor\(@"(\w+)",@"(\w+)"', src):
        assert role in groups.get(group, set()), (group, role)
    assert {'navigation','toolbar','table','cell','switch','slider','keyboard','status','controlcenter'} <= groups.keys()
    print(f'Project contracts OK: {len(groups)} component groups, {sum(map(len, groups.values()))} color roles.')

def ar_members(data):
    assert data[:8] == b'!<arch>\n'
    pos=8
    while pos < len(data):
        header=data[pos:pos+60]
        assert len(header)==60 and header[58:60]==b'`\n'
        n=int(header[48:58]); name=header[:16].decode().strip().rstrip('/')
        yield name, data[pos+60:pos+60+n]
        pos += 60+n+(n%2)

def check_deb(path):
    archives=dict(ar_members(path.read_bytes()))
    control=next(v for k,v in archives.items() if k.startswith('control.tar'))
    payload=next(v for k,v in archives.items() if k.startswith('data.tar'))
    with tarfile.open(fileobj=io.BytesIO(control), mode='r:*') as tf:
        member=next(m for m in tf if m.name.strip('./')=='control')
        text=tf.extractfile(member).read().decode()
        assert 'Architecture: iphoneos-arm64e' in text
        assert 'com.opa334.libsandy' in text
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:*') as tf:
        files={m.name.removeprefix('./').lstrip('/'):m for m in tf if m.isfile()}
        required=[
            'Library/MobileSubstrate/DynamicLibraries/ChromaApps.dylib',
            'Library/MobileSubstrate/DynamicLibraries/ChromaApps.plist',
            'Library/MobileSubstrate/DynamicLibraries/ChromaSystem.dylib',
            'Library/MobileSubstrate/DynamicLibraries/ChromaSystem.plist',
            'Library/PreferenceBundles/ChromaPrefs.bundle/ChromaPrefs',
            'Library/PreferenceBundles/ChromaPrefs.bundle/Info.plist',
            'Library/PreferenceLoader/Preferences/ChromaPalette.plist',
            'Library/libSandy/com.benja.chromapalette.plist']
        for name in required:
            assert name in files, f'Missing {name}'
            if name.endswith('.dylib') or name.endswith('/ChromaPrefs'):
                data=tf.extractfile(files[name]).read()
                assert data[:4] in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'), f'{name}: expected universal Mach-O'
        assert not any(k.startswith('var/jb/') for k in files)
    print(f'Debian package contracts OK: {path.name}')

if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--deb', nargs='*', type=pathlib.Path)
    args=parser.parse_args(); check_sources()
    for p in args.deb or []: check_deb(p)
