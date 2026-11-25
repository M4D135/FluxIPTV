#!/usr/bin/env python3
"""Validate the 18 distributable room bakes without Blender or image libraries."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'FluxIPTVMac'/'RoomBakes'
THEMES=('neo90','midnight','vintage70','artDeco','zen','future')
KINDS=('cinema','videoClub','livingRoom')

def jpeg_size(path):
    data=path.read_bytes()
    if not data.startswith(b'\xff\xd8') or not data.endswith(b'\xff\xd9'):
        raise ValueError('Invalid or truncated JPEG: '+path.name)
    i=2
    while i<len(data)-4:
        if data[i]!=255:raise ValueError('Invalid JPEG segment')
        while data[i]==255:i+=1
        marker=data[i];i+=1
        if marker in (0xd8,0xd9,0x01) or 0xd0<=marker<=0xd7:continue
        length=struct.unpack_from('>H',data,i)[0]
        if length<2 or i+length>len(data):raise ValueError('Truncated JPEG segment')
        if marker in (0xc0,0xc1,0xc2):
            h,w=struct.unpack_from('>HH',data,i+3)
            return w,h
        if marker==0xda:break
        i+=length
    raise ValueError('Missing JPEG dimensions: '+path.name)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--directory',type=Path,default=OUT)
    out=parser.parse_args().directory
    manifest=json.loads((out/'manifest.json').read_text())
    expected={f'{kind}-{theme}.jpg' for kind in KINDS for theme in THEMES}
    entries={x['file']:x for x in manifest['files']}
    if len(manifest['files'])!=18 or set(entries)!=expected:
        raise ValueError('The manifest must contain exactly the 18 room/theme combinations')
    if (manifest['width'],manifest['height'])!=(3840,2160):
        raise ValueError('Final bakes must be 3840×2160')
    total=0
    for name in sorted(expected):
        path=out/name
        data=path.read_bytes();entry=entries[name]
        if jpeg_size(path)!=(3840,2160):raise ValueError('Wrong dimensions: '+name)
        if hashlib.sha256(data).hexdigest()!=entry['sha256']:raise ValueError('Digest mismatch: '+name)
        if len(data)!=entry['bytes']:raise ValueError('Byte count mismatch: '+name)
        if entry['engine']!='CYCLES' or entry['denoising']!='OpenImageDenoise':
            raise ValueError('Unexpected production renderer: '+name)
        total+=len(data)
    if len({x['sha256'] for x in entries.values()})!=18:
        raise ValueError('Duplicate frames across environments/themes')
    root=ROOT
    for name,digest in manifest.get('source_files',{}).items():
        if hashlib.sha256((root/name).read_bytes()).hexdigest()!=digest:
            raise ValueError('Generator source digest mismatch: '+name)
    print(f'18 rooms verified: 3840×2160, distinct hashes, Cycles/OIDN, {total:,} bytes')

if __name__=='__main__':main()
