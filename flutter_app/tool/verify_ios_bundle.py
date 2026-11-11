"""Verify Windows-built iOS icons and version metadata before installation."""

import argparse
import json
import plistlib
import struct
from pathlib import Path
from zipfile import ZipFile


def verify(read, expected_version, expected_build):
    plist = plistlib.loads(read('Info.plist'))
    assert plist['CFBundleShortVersionString'] == expected_version, 'Wrong version'
    assert plist['CFBundleVersion'] == expected_build, 'Wrong build number'
    assets = Path(__file__).resolve().parents[1] / 'ios/Runner/Assets.xcassets'
    for preset in ['AppIcon', 'IconMaterial', 'IconMidnight', 'IconVolt']:
        catalogue = assets / f'{preset}.appiconset'
        images = json.loads((catalogue / 'Contents.json').read_text())['images']
        for idiom, key in [('iphone', 'CFBundleIcons'), ('ipad', 'CFBundleIcons~ipad')]:
            record = plist[key]['CFBundlePrimaryIcon'] if preset == 'AppIcon' else plist[key]['CFBundleAlternateIcons'][preset]
            names = record['CFBundleIconFiles']
            for image in images:
                if image['idiom'] != idiom:
                    continue
                name = image['filename']
                assert name in names, f'Undeclared {idiom} icon: {name}'
                data = read(name)
                assert data == (catalogue / name).read_bytes(), f'Icon changed: {name}'
                assert data[:8] == b'\x89PNG\r\n\x1a\n', f'Invalid PNG: {name}'
                width, height, depth, colour = struct.unpack('>IIBB', data[16:26])
                pixels = round(float(image['size'].split('x')[0]) * float(image['scale'][:-1]))
                assert width == height == pixels, f'Wrong icon dimensions: {name}'
                assert depth == 8 and colour == 2, f'Icon must be opaque RGB: {name}'
    native = read('Frameworks/libFlutterPluginsGenerated.dylib')
    for marker in [b'PlatformFeaturesPlugin', b'escooter/platform', b'escooter/phone_speed', b'authorizeLocation', b'setIcon']:
        assert marker in native, f'Missing compiled platform bridge: {marker!r}'
    assert plist.get('NSLocationWhenInUseUsageDescription'), 'Missing location explanation'
    assert 'location' not in plist.get('UIBackgroundModes', []), 'Unexpected background location mode'
    print(f'Verified four iPhone/iPad icon presets and foreground-location metadata, version {expected_version}+{expected_build}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path, help='.app directory or unsigned .ipa')
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    args = parser.parse_args()
    if args.bundle.is_dir():
        verify(lambda name: (args.bundle / name).read_bytes(), args.version, args.build)
    else:
        with ZipFile(args.bundle) as archive:
            roots = [name[:-len('Info.plist')] for name in archive.namelist()
                     if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('.app/Info.plist')]
            assert len(roots) == 1, 'Expected one main app in Payload'
            verify(lambda name: archive.read(roots[0] + name), args.version, args.build)
