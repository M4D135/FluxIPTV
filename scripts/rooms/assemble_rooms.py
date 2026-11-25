#!/usr/bin/env python3
"""Assemble independently rendered rooms; reject mixed source/settings batches."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

THEMES=('neo90','midnight','vintage70','artDeco','zen','future')
KINDS=('cinema','videoClub','livingRoom')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--input-dir',required=True)
    parser.add_argument('--output-dir',required=True)
    args=parser.parse_args()
    source=Path(args.input_dir);target=Path(args.output_dir)
    target.mkdir(parents=True,exist_ok=True)
    manifests=[];entries=[]
    for kind in KINDS:
        for theme in THEMES:
            name=f'{kind}-{theme}'
            meta=json.loads((source/f'{name}.render.json').read_text())
            if len(meta['files'])!=1 or meta['files'][0]['file']!=f'{name}.jpg':
                raise ValueError('Unexpected render sidecar: '+name)
            image=source/f'{name}.jpg';data=image.read_bytes();entry=meta['files'][0]
            if hashlib.sha256(data).hexdigest()!=entry['sha256'] or len(data)!=entry['bytes']:
                raise ValueError('Render digest mismatch: '+name)
            manifests.append({k:v for k,v in meta.items() if k!='files'})
            entries.append(entry)
            shutil.copy2(image,target/image.name)
    first=manifests[0]
    if any(m!=first for m in manifests[1:]):
        raise ValueError('Room jobs used different Blender versions, settings or source files')
    if (first['width'],first['height'])!=(3840,2160):
        raise ValueError('Production frames must be native 3840×2160')
    first['files']=entries
    (target/'manifest.json').write_text(json.dumps(first,ensure_ascii=False,indent=2)+'\n')
    print(f'Assembled {len(entries)} native 4K frames from identical source and settings')

if __name__=='__main__':main()
