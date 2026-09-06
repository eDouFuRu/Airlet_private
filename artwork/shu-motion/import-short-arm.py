#!/usr/bin/env python3
"""Import the user-requested single-piece short arm using the approved cyan matte workflow."""
from pathlib import Path
import hashlib, importlib.util, json
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
spec = importlib.util.spec_from_file_location('shu_import', ROOT / 'artwork/shu25d/import-assets.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
helper.np, helper.Image = np, Image
helper.ImageChops, helper.ImageDraw, helper.ImageFilter = ImageChops, ImageDraw, ImageFilter
source = HERE / 'source/short-arm.png'
digest = hashlib.sha256(source.read_bytes()).hexdigest()
original = Image.open(source).convert('RGBA')
arm, matte = helper.cyan_matte(original)
arm, points, trim = helper.trim_with_padding(arm, {'pivot':(479,414),'end':(563,1063)}, .06)
target = HERE / 'processed/short-arm.png'
helper.save_png(arm, target)
asset = ROOT / 'boringNotch/Assets.xcassets/Shu25D-short-arm.imageset'
asset.mkdir(exist_ok=True)
catalog = arm.copy()
catalog.thumbnail((1024,1024), Image.Resampling.LANCZOS)
helper.save_png(catalog, asset / 'short-arm.png')
helper.atomic_json(asset / 'Contents.json', {'images':[{'filename':'short-arm.png','idiom':'universal'}], 'info':{'author':'xcode','version':1}})
p = ROOT / 'boringNotch/components/Island/Shu25DAssets.json'
m = json.loads(p.read_text())
m['assets'] = [e for e in m['assets'] if e['id'] != 'short-arm']
m['assets'].append({'id':'short-arm','catalogName':'Shu25D-short-arm',**points,
                    'notes':'One continuous short sleeve-arm-mitten sprite, no elbow or palm seam. Supersedes the rejected visible two-piece arm.'})
helper.atomic_json(p,m)
record={'sourceSHA256':digest,'sourceSize':original.size,'outputSize':arm.size,'landmarks':points,'matte':matte,'trim':trim,
        'alpha':helper.check_alpha(arm),'outputSHA256':hashlib.sha256(target.read_bytes()).hexdigest(),
        'authorization':'User explicitly requested a shorter, cute single-piece arm after native review; existing local cutout authorization applies.'}
helper.atomic_json(HERE / 'processed/short-arm-import.json', record)
assert hashlib.sha256(source.read_bytes()).hexdigest()==digest
print(json.dumps(record,ensure_ascii=False))
