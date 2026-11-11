"""Render the project-owned wheel/bolt icon presets for both mobile launchers."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent.parent
catalogue = root / 'ios/Runner/Assets.xcassets'
base = json.loads((catalogue / 'AppIcon.appiconset/Contents.json').read_text(encoding='utf-8'))
presets = [
    ('AppIcon', 'ic_launcher', 'standard', '#2563eb', '#ffffff'),
    ('IconMaterial', 'ic_launcher_material', 'material', '#eaddff', '#21005d'),
    ('IconMidnight', 'ic_launcher_midnight', 'midnight', '#12151c', '#e7ecf5'),
    ('IconVolt', 'ic_launcher_volt', 'volt', '#c3f64b', '#172006'),
]
res = root / 'android/app/src/main/res'
for ios_name, android_name, key, background, foreground in presets:
    image = Image.new('RGB', (1024, 1024), background)
    draw = ImageDraw.Draw(image)
    draw.ellipse((190, 190, 834, 834), outline=foreground, width=66)
    draw.polygon([(550, 270), (365, 560), (488, 560), (451, 755), (664, 448), (540, 448)], fill=foreground)
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        target = res / f'mipmap-{density}' / f'{android_name}.png'
        target.parent.mkdir(parents=True, exist_ok=True)
        image.resize((size, size), Image.Resampling.LANCZOS).save(target)
    target = catalogue / f'{ios_name}.appiconset'
    target.mkdir(parents=True, exist_ok=True)
    contents = json.loads(json.dumps(base))
    for entry in contents['images']:
        if 'filename' not in entry:
            continue
        if ios_name != 'AppIcon':
            entry['filename'] = ios_name + '-' + entry['filename']
        pixels = round(float(entry['size'].split('x')[0]) * float(entry['scale'].replace('x', '')))
        image.resize((pixels, pixels), Image.Resampling.LANCZOS).save(target / entry['filename'])
    (target / 'Contents.json').write_text(json.dumps(contents, indent=2) + '\n', encoding='utf-8')
    drawable = res / 'drawable' / f'icon_{key}_foreground.xml'
    drawable.write_text(f'''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="1024" android:viewportHeight="1024">
    <path android:fillColor="{foreground}" android:fillType="evenOdd" android:pathData="M512,190 A322,322 0,1 1,511.99 190 Z M512,256 A256,256 0,1 1,511.99 256 Z" />
    <path android:fillColor="{foreground}" android:pathData="M550,270 L365,560 L488,560 L451,755 L664,448 L540,448 Z" />
</vector>
''', encoding='utf-8')
    for api in [26, 33]:
        adaptive = res / f'mipmap-anydpi-v{api}' / f'{android_name}.xml'
        adaptive.parent.mkdir(parents=True, exist_ok=True)
        mono = f'    <monochrome android:drawable="@drawable/icon_{key}_foreground" />\n' if api >= 33 else ''
        adaptive.write_text(f'''<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icon_{key}_background" />
    <foreground android:drawable="@drawable/icon_{key}_foreground" />
{mono}</adaptive-icon>
''', encoding='utf-8')
colors = '<resources>\n' + ''.join(f'    <color name="icon_{key}_background">{bg}</color>\n' for _,_,key,bg,_ in presets) + '</resources>\n'
(res / 'values/icon_colors.xml').write_text(colors, encoding='utf-8')
print('Generated four opaque iOS presets and Android adaptive/themed launcher icons.')
