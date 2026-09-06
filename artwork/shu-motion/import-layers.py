#!/usr/bin/env python3
"""Import the generated toy component sheet using its local Vision alpha mask.

Original raster sources (including the torso/face/lettering) are never changed.
The user-approved local cutout workflow is reused here. Only new limb sprites
are normalized to animation canvases; the original character stays unscaled.
"""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sheet = HERE / 'source/limb-sheet.png'
source_hash = hashlib.sha256(sheet.read_bytes()).hexdigest()
source = Image.open(sheet).convert('RGBA')
mask = Image.open(HERE / 'processed/limb-sheet-mask.png').convert('L').filter(ImageFilter.MinFilter(7))
source.putalpha(mask)

def cell(column, row):
    im = source.crop((column * 512, row * 512, (column + 1) * 512, (row + 1) * 512))
    box = im.getchannel('A').point(lambda x: 255 if x > 4 else 0).getbbox()
    return im.crop(box)

def canvas_part(im, size, content):
    result = Image.new('RGBA', size)
    im = im.resize(content, Image.Resampling.LANCZOS)
    result.alpha_composite(im, ((size[0] - content[0]) // 2, (size[1] - content[1]) // 2))
    return result

layers = {
    'upper-arm': (canvas_part(cell(0, 0), (224, 576), (196, 544)), [.48, .13], [.53, .88]),
    'forearm': (canvas_part(cell(1, 0), (208, 624), (178, 588)), [.5, .10], [.5, .90]),
    'palm-back': (canvas_part(cell(2, 0), (240, 288), (206, 248)), [.5, .5], [.5, .9]),
    'fingers-front': (canvas_part(cell(0, 1).rotate(90, expand=True), (240, 288), (126, 100)), [.5, .5], [.5, .9]),
}

def leg(im):
    # Normalize the new toy's short leg and foot separately so the ankle stays
    # near the sole, rather than enlarging a foot whenever the knee bends.
    split = round(im.height * .60)
    result = Image.new('RGBA', (352, 672))
    stem = im.crop((0, 0, im.width, split)).resize((288, 472), Image.Resampling.LANCZOS)
    foot = im.crop((0, split - 2, im.width, im.height)).resize((288, 150), Image.Resampling.LANCZOS)
    result.alpha_composite(stem, (32, 28))
    result.alpha_composite(foot, (32, 496))
    return result

layers['leg-near'] = (leg(cell(1, 1)), [.43, .1], [.43, .75])
layers['leg-far'] = (leg(cell(2, 1)), [.43, .1], [.43, .75])
manifest_path = ROOT / 'boringNotch/components/Island/Shu25DAssets.json'
manifest = json.loads(manifest_path.read_text())
entries = {entry['id']: entry for entry in manifest['assets']}
records = []
for name, (im, pivot, end) in layers.items():
    output = HERE / 'processed' / (name + '.png')
    im.save(output, optimize=True)
    catalog = ROOT / 'boringNotch/Assets.xcassets' / ('Shu25D-' + name + '.imageset')
    catalog.mkdir(exist_ok=True)
    im.save(catalog / (name + '.png'), optimize=True)
    (catalog / 'Contents.json').write_text(json.dumps({'images':[{'filename':name + '.png', 'idiom':'universal'}], 'info':{'author':'xcode','version':1}}, indent=2) + '\n')
    box = im.getchannel('A').point(lambda x:255 if x > 4 else 0).getbbox()
    bounds = [box[0]/im.width, box[1]/im.height, (box[2]-box[0])/im.width, (box[3]-box[1])/im.height]
    entries[name] = {'id':name,'catalogName':'Shu25D-' + name,'pivot':pivot,'end':end,'contentBounds':bounds,
                     'notes':'Generated toy component, real Vision alpha, deterministic rig canvas; source sheet unchanged.'}
    records.append({'id':name,'size':im.size,'pivot':pivot,'end':end,'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
                    'alphaExtrema':im.getchannel('A').getextrema()})

for name in ['captain-base','captain-holding']:
    im = Image.open(ROOT / 'artwork/shu25d/processed' / (name + '.png')).convert('RGBA')
    box = im.getchannel('A').point(lambda x:255 if x > 4 else 0).getbbox()
    entries[name]['contentBounds'] = [box[0]/im.width,box[1]/im.height,(box[2]-box[0])/im.width,(box[3]-box[1])/im.height]

manifest['schemaVersion'] = 2
manifest['assets'] = list(entries.values())
manifest['animationSeconds'] = {'hoe':[0,6],'plant':[6,12],'water':[12,23],'pull':[23,30], 'turn':[30,33],
                               'roast':[33,51],'carry':[51,54],'place':[54,56],'returnHome':[56,60]}
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
assert hashlib.sha256(sheet.read_bytes()).hexdigest() == source_hash
(HERE / 'processed/import-record.json').write_text(json.dumps({'sourceSHA256':source_hash,
    'method':'Local macOS Vision foreground mask; sheet crop; new component canvas normalization',
    'authorization':'User approved local cutout workflow in this conversation; current plan explicitly requests separated imagegen limbs.',
    'originalCharacterModified':False, 'assets':records}, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(records, ensure_ascii=False))
