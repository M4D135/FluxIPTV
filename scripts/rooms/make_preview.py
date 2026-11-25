#!/usr/bin/env python3
"""Create a labelled contact sheet of the delivered room renders (Pillow)."""
import argparse
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[2]
ASSETS=ROOT/'FluxIPTVMac'/'RoomBakes'
OUT=Path(__file__).with_name('room-previews.jpg')
parser=argparse.ArgumentParser()
parser.add_argument('--assets-dir',type=Path,default=ASSETS)
parser.add_argument('--output',type=Path,default=OUT)
args=parser.parse_args();ASSETS=args.assets_dir;OUT=args.output
THEMES=[('neo90','Néo 80–90'),('midnight','Cinéma de minuit'),('vintage70','Années 70'),('artDeco','Art déco'),('zen','Scandinave'),('future','Futur néon')]
KINDS=[('cinema','FILMS · CINÉMA'),('videoClub','SÉRIES · VIDÉOCLUB'),('livingRoom','TV · SALON')]

def font(size):
    for p in ('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf','/System/Library/Fonts/Supplemental/Arial.ttf'):
        if Path(p).exists():return ImageFont.truetype(p,size)
    return ImageFont.load_default(size=size)

canvas=Image.new('RGB',(1488,2024),'#13151b');draw=ImageDraw.Draw(canvas)
draw.text((24,20),'FLUX · LES TROIS ESPACES',font=font(32),fill='#f3f0e8')
draw.text((24,62),'Dix-huit décors 3D · Six architectures · Sources 4K · Version 0.8.6',font=font(18),fill='#a7a9b4')
for col,(_,label) in enumerate(KINDS):draw.text((24+col*488,108),label,font=font(20),fill='#f3f0e8')
for row,(theme,title) in enumerate(THEMES):
    y=150+row*306
    draw.text((24,y),title,font=font(20),fill='#cfb68b')
    for col,(kind,_) in enumerate(KINDS):
        image=Image.open(ASSETS/f'{kind}-{theme}.jpg').convert('RGB')
        image=image.resize((472,266),Image.Resampling.LANCZOS)
        canvas.paste(image,(24+col*488,y+30))
draw.text((24,1990),'Décors seuls · Les pochettes, commandes et catalogues sont ajoutés par l’application.',font=font(17),fill='#a7a9b4')
canvas.save(OUT,quality=93)
print(OUT)
