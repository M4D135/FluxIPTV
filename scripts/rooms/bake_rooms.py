#!/usr/bin/env python3
"""Deterministic FLUX interiors, built entirely from geometry and shader nodes.

Requires Blender 4.3+. No downloaded models, photographic textures or image AI.
Run: blender -b -t 6 --python scripts/rooms/bake_rooms.py -- --all
"""
import argparse
import bpy
import hashlib
import json
import math
import os
import random
import sys
import tempfile
import time
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'FluxIPTVMac' / 'RoomBakes'
SEED = 82026
THEMES = {
    'neo90': dict(wall='292437', wood='653D2A', accent='19E9ED', secondary='F22A8A', fabric='622A4D', metal='B9ADA4', stone='4C4652'),
    'midnight': dict(wall='1D2532', wood='3E3835', accent='7FB4FF', secondary='795DBE', fabric='24344B', metal='8C97AA', stone='393E49'),
    'vintage70': dict(wall='66513D', wood='81512C', accent='F5B14D', secondary='DE6031', fabric='A95328', metal='B48B54', stone='7B6C54'),
    'artDeco': dict(wall='183A31', wood='3A3026', accent='FFD17A', secondary='48B497', fabric='185044', metal='BA8D41', stone='343D39'),
    'zen': dict(wall='9C9D95', wood='B68D5E', accent='C4E2E4', secondary='E9CC9F', fabric='8C9489', metal='B9BAB4', stone='9B9990'),
    'future': dict(wall='252D45', wood='4B5568', accent='26CEFF', secondary='9571FF', fabric='384568', metal='ABB9CB', stone='576275'),
}

def rgb(h, alpha=1):
    def linear(v):
        v=v/255
        return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
    return tuple(linear(int(h[i:i+2],16)) for i in (0,2,4))+(alpha,)

def mix(a, b, k):
    return tuple(a[i]*(1-k)+b[i]*k for i in range(len(a)))

def node_mat(name, color, rough=.5, metal=0, kind=None, scale=1):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n = m.node_tree.nodes
    links = m.node_tree.links
    bsdf = n.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = color
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if kind:
        tex = n.new('ShaderNodeTexNoise')
        tex.inputs['Scale'].default_value = scale
        tex.inputs['Detail'].default_value = 3
        tex.inputs['Roughness'].default_value = .7
        coords = n.new('ShaderNodeTexCoord')
        mapping = n.new('ShaderNodeMapping')
        links.new(coords.outputs['Generated'], mapping.inputs['Vector'])
        links.new(mapping.outputs['Vector'], tex.inputs['Vector'])
        if kind == 'wood':
            mapping.inputs['Scale'].default_value = (3, 45, 5)
            tex.inputs['Scale'].default_value = 1.4
        if kind == 'fabric':
            mapping.inputs['Scale'].default_value = (100, 100, 100)
            tex.inputs['Scale'].default_value = 1
            bsdf.inputs['Sheen Weight'].default_value = .08
            bsdf.inputs['Sheen Roughness'].default_value = .8
        ramp = n.new('ShaderNodeValToRGB')
        ramp.color_ramp.elements[0].position = .18
        ramp.color_ramp.elements[1].position = .82
        amp = .45 if kind == 'wood' else .15
        ramp.color_ramp.elements[0].color = tuple(c*(1-amp) for c in color[:3])+(1,)
        ramp.color_ramp.elements[1].color = tuple(min(1,c*(1+amp)) for c in color[:3])+(1,)
        links.new(tex.outputs['Fac'], ramp.inputs[0])
        links.new(ramp.outputs['Color'], bsdf.inputs['Base Color'])
        bump = n.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .16 if kind == 'wood' else .22
        bump.inputs['Distance'].default_value = .018 if kind == 'stone' else .008
        links.new(tex.outputs['Fac'], bump.inputs['Height'])
        links.new(bump.outputs['Normal'], bsdf.inputs['Normal'])
    return m

def glow(name, color, energy):
    m = node_mat(name, color, .3)
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Emission Color'].default_value = color
    bsdf.inputs['Emission Strength'].default_value = energy
    return m

def setup(theme, width, height, samples):
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for pool in (bpy.data.meshes,bpy.data.curves,bpy.data.lights,bpy.data.cameras):
        for block in list(pool):
            if block.users==0:pool.remove(block)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    random.seed(SEED)
    scene = bpy.context.scene
    scene.render.engine = os.environ.get('FLUX_BAKE_ENGINE', 'CYCLES')
    if scene.render.engine == 'BLENDER_EEVEE_NEXT':
        scene.eevee.taa_render_samples = samples
        scene.eevee.use_gtao = True
        scene.eevee.gtao_distance = 3
        scene.eevee.gtao_quality = 1
        scene.eevee.use_fast_gi = True
    scene.cycles.device = 'CPU'
    scene.cycles.samples = samples
    try:
        scene.cycles.denoiser = 'OPENIMAGEDENOISE'
        scene.cycles.use_denoising = True
    except (TypeError,ValueError):
        scene.cycles.use_denoising = False
    scene.cycles.adaptive_threshold = .055
    scene.cycles.seed = SEED
    scene.cycles.max_bounces = 6
    scene.cycles.diffuse_bounces = 3
    scene.cycles.glossy_bounces = 3
    scene.cycles.transmission_bounces = 3
    scene.cycles.use_light_tree = True
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'JPEG'
    scene.render.image_settings.quality = 93
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    scene.view_settings.exposure = .25
    world = bpy.data.worlds.new('Interior daylight')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.18,.22,.30,1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .23 if theme=='zen' else .11
    scene.world = world
    p = THEMES[theme]
    mat = {}
    mat['wall'] = node_mat('Mineral plaster', rgb(p['wall']), .82, kind='plaster', scale=160)
    mat['wood'] = node_mat('Walnut oak grain', rgb(p['wood']), .36, kind='wood')
    mat['darkwood'] = node_mat('Dark interior timber', mix(rgb(p['wood']), (0,0,0,1),.42), .52, kind='wood')
    mat['metal'] = node_mat('Brushed metal trim', rgb(p['metal']), .27, .78)
    mat['fabric'] = node_mat('Upholstery woven fabric', rgb(p['fabric']), .88, kind='fabric')
    mat['cream'] = node_mat('Linen warm white', rgb('BEB4A1'), .93, kind='fabric')
    mat['stone'] = node_mat('Honed architectural stone', rgb(p['stone']), .40, kind='stone', scale=48)
    mat['black'] = node_mat('Satin black', rgb('11141B'), .34, .12)
    mat['plastic'] = node_mat('Case injection moulded plastic', rgb('18191F'), .31)
    mat['accent'] = glow('Accent linear light',rgb(p['accent']),4)
    mat['secondary'] = glow('Secondary linear light',rgb(p['secondary']),3.2)
    mat['warm'] = glow('Warm practical lamp',rgb('FFE0A1'),3.5)
    mat['letter'] = glow('Warm backlit letters',rgb('FFE7BD'),1.2)
    mat['ceiling'] = node_mat('Ceiling charcoal',rgb('292B30') if theme!='zen' else rgb('96978F'),.9,kind='plaster',scale=100)
    return mat

def external_denoise(path):
    """Run optional OIDN in its own process to isolate native TBB dependencies.

    Official Blender builds normally include OIDN. If not, set
    FLUX_DENOISE_PYTHON to an external Python with numpy and oidn installed.
    HDR pixels remain linear until Blender writes the final JPG.
    """
    python=os.environ.get('FLUX_DENOISE_PYTHON')
    if not python:return False
    import numpy as np
    import subprocess
    scene=bpy.context.scene
    with tempfile.TemporaryDirectory(prefix='flux-linear-') as tmp:
        raw=Path(tmp)/'linear.exr'
        scene.render.image_settings.file_format='OPEN_EXR'
        scene.render.image_settings.color_depth='32'
        bpy.data.images['Render Result'].save_render(str(raw),scene=scene)
        source=bpy.data.images.load(str(raw),check_existing=False)
        w,h=source.size
        pixels=np.empty(w*h*4,dtype=np.float32)
        source.pixels.foreach_get(pixels)
        color=np.ascontiguousarray(pixels.reshape(h,w,4)[:,:,:3])
        data=Path(tmp)/'color.npy';output=Path(tmp)/'clean.npy'
        np.save(data,color)
        env=os.environ.copy()
        if env.get('FLUX_DENOISE_PYTHONPATH'):
            env['PYTHONPATH']=env['FLUX_DENOISE_PYTHONPATH']
        if env.get('FLUX_DENOISE_LIBPATH'):
            env['LD_LIBRARY_PATH']=env['FLUX_DENOISE_LIBPATH']
        subprocess.run([python,str(Path(__file__).with_name('denoise_linear.py')),str(data),str(output)],env=env,check=True)
        out=np.load(output)
        if out.shape!=color.shape or not np.isfinite(out).all():
            raise RuntimeError('Invalid denoised frame')
        pixels=pixels.reshape(h,w,4);pixels[:,:,:3]=out
        denoised=bpy.data.images.new('Denoised linear interior',width=w,height=h,alpha=True,float_buffer=True)
        denoised.pixels.foreach_set(pixels.ravel())
        scene.render.image_settings.file_format='JPEG'
        scene.render.image_settings.color_depth='8'
        denoised.save_render(str(path),scene=scene)
        bpy.data.images.remove(source);bpy.data.images.remove(denoised)
    return True


def assign(o, mat):
    o.data.materials.append(mat)
    return o

def cube(name, loc, size, mat, bevel=.025, rotation=0):
    x,y,z=(v/2 for v in size)
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata([(-x,-y,-z),(-x,-y,z),(-x,y,-z),(-x,y,z),(x,-y,-z),(x,-y,z),(x,y,-z),(x,y,z)],[],[(0,4,6,2),(1,3,7,5),(0,1,5,4),(2,6,7,3),(0,2,3,1),(4,5,7,6)])
    mesh.update()
    o=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(o)
    o.location=loc
    o.rotation_euler.z=rotation
    assign(o,mat)
    if bevel:
        mod=o.modifiers.new('Soft machined edge','BEVEL')
        mod.width=min(bevel,min(size)*.23)
        mod.segments=3
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o

def sphere(name, loc, size, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=loc)
    o=bpy.context.object
    o.name=name
    o.scale=tuple(v/2 for v in size)
    assign(o,mat)
    for poly in o.data.polygons: poly.use_smooth=True
    return o

def cylinder(name, loc, radius, depth, mat, vertices=32, rotation=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc,rotation=rotation)
    o=bpy.context.object
    o.name=name
    assign(o,mat)
    mod=o.modifiers.new('Rounded lip','BEVEL'); mod.width=.008; mod.segments=2
    o.modifiers.new('Smooth normals','WEIGHTED_NORMAL')
    return o

def line(name, points, radius, mat):
    cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=12
    cu.bevel_depth=radius;cu.bevel_resolution=3
    sp=cu.splines.new('POLY');sp.points.add(len(points)-1)
    for pt,co in zip(sp.points,points): pt.co=(*co,1)
    o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o);assign(o,mat)
    return o

def text(name, label, loc, size, mat, rotation=(math.pi/2,0,0), align='CENTER'):
    cu=bpy.data.curves.new(name,'FONT');cu.body=label;cu.align_x=align;cu.align_y='CENTER'
    cu.size=size;cu.extrude=.003;cu.bevel_depth=.001
    o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o)
    o.location=loc;o.rotation_euler=rotation;assign(o,mat)
    return o

def area(name, loc, target, energy, color=(1,.84,.64), size=3, size_y=None):
    data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.color=color
    if size_y: data.shape='RECTANGLE';data.size=size;data.size_y=size_y
    else:data.shape='DISK';data.size=size
    o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);o.location=loc
    if 'fill' in name.lower() or 'bounce' in name.lower():
        # Photography-style bounce cards illuminate fabric without making a
        # false bright rectangle on the resting television glass.
        o.visible_glossy=False
        data.specular_factor=0
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    return o

def camera(loc, target, lens=24):
    bpy.ops.object.camera_add(location=loc)
    o=bpy.context.object;o.name='Architectural camera';o.data.lens=lens
    o.data.sensor_width=36;o.data.clip_start=.05;o.data.clip_end=100
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    bpy.context.scene.camera=o

def shell(m, theme, width=13, depth=13, height=4.2):
    # Individual staggered boards provide genuine perspective, seams and reflections.
    for row in range(29):
        y=-1.6+row*.51
        shift=(row%3)*.78
        for col in range(7):
            x=-7.5+col*2.35+shift
            if x+1.16<-width/2 or x-1.16>width/2:continue
            cube('Floor board',(x,y,-.055),(2.34,.50,.11),m['wood'],.008)
    cube('Back plaster wall',(0,depth+.10,height/2),(width+.3,.20,height),m['wall'],.02)
    for side in (-1,1):
        cube('Side plaster wall',(side*(width/2+.1),depth/2-.7,height/2),(.20,depth+1.6,height),m['wall'],.01)
        cube('Wood skirting',(side*(width/2-.015),depth/2-.7,.12),(.09,depth+1.6,.24),m['darkwood'],.015)
        cube('Ceiling perimeter trim',(side*(width/2-.1),depth/2, height-.12),(.18,depth,.12),m['metal'],.01)
    cube('Ceiling',(0,depth/2-.8,height+.08),(width+.4,depth+1.8,.16),m['ceiling'],0)
    cube('Back skirting',(0,depth-.04,.12),(width,.09,.24),m['darkwood'],.01)
    if theme=='artDeco':
        for x in (-5.8,-4.4,-3,3,4.4,5.8):
            for dx in (-.065,0,.065):cube('Deco wall inlay',(x+dx,depth-.03,height/2),(.018,.025,height-.3),m['metal'],0)

def ceiling_lights(m, depth, width=13, height=4.2, theme='neo90'):
    for y in (2.0,5.4,8.8,12):
        if y>depth-.3:continue
        cube('Ceiling beam',(0,y,height-.10),(width,.14,.16),m['black'],.025)
        for x in (-3.2,3.2):
            cylinder('Recessed light housing',(x,y,height-.14),.17,.12,m['black'])
            cylinder('Recessed glowing diffuser',(x,y,height-.21),.12,.018,m['warm'])
            area('Warm ceiling pool',(x,y,height-.23),(x,y,0),180 if theme!='zen' else 280,size=1.1)
    if theme in ('neo90','future','midnight'):
        for side in (-1,1):
            cube('Neon track',(side*(width/2-.42),depth/2,height-.19),(.09,depth-.7,.06),m['accent'] if side<0 else m['secondary'],.01)
            c=rgb(THEMES[theme]['accent' if side<0 else 'secondary'])[:3]
            area('Neon wash',(side*(width/2-.50),depth/2,height-.35),(side*width/2,depth/2,2),170,c,size=5,size_y=.6)

def poster(m, x, y, z, w, h, index, label=True, orientation=0):
    # Procedural graphic art made of layered geometry, shared poster identities.
    colors=['286E84','A36538','7A294B','416158','806E50','3D496F']
    ink=node_mat('Poster ink %02d'%index,rgb(colors[index%len(colors)]),.69)
    paper=node_mat('Poster paper %02d'%index,rgb('D4C6A8'),.75)
    parts=[]
    parts.append(cube('Lightbox stone surround',(x,y,z),(w+.16,.14,h+.16),m['black'],.04))
    parts.append(cube('Illuminated frame',(x,y-.085,z),(w+.05,.035,h+.05),m['letter'],.012))
    parts.append(cube('Original geometric poster',(x,y-.11,z),(w,.025,h),ink,.006))
    parts.append(sphere('Graphic moon',(x+w*.13,y-.129,z+h*.12),(w*.51,.018,w*.51),paper))
    for j in range(4):
        parts.append(cube('Graphic horizon',(x-w*.12+j*w*.08,y-.145-j*.001,z-h*.22+j*h*.065),(w*.78,.014,h*.055),m['black'],0,rotation=0))
    if label:
        words=['LES NUITS','HORIZONS','ORIGINES','VOYAGES','LES MONDES','SILLAGES']
        parts.append(text('Poster title',words[index%6],(x,y-.163,z-h*.34),w*.105,paper))
    if orientation:
        center=Vector((x,y,z))
        for o in parts:
            p=o.location-center
            o.location=center+Vector((p.x*math.cos(orientation)-p.y*math.sin(orientation),p.x*math.sin(orientation)+p.y*math.cos(orientation),p.z))
            o.rotation_euler.z+=orientation

def cinema(m,theme):
    depth=13;H=4.55
    shell(m,theme,13,depth,H);ceiling_lights(m,depth,13,H,theme)
    # Velvet carpet and contrasting stone path create a lobby, rather than a store.
    carpet=node_mat('Cinema velvet carpet',rgb('4A1825') if theme!='zen' else rgb('5D554D'),.94,kind='fabric')
    cube('Carpet runner',(0,6.1,.016),(4.15,14,.025),carpet,.006)
    for x in (-2.09,2.09):cube('Carpet brass edging',(x,6.1,.025),(.022,14,.022),m['metal'],.004)
    # Projecting wall establishes an actual screening-room entrance.
    cube('Projection lobby left pier',(-3.7,10.6,1.88),(3.45,.35,3.76),m['stone'],.045)
    cube('Projection lobby right pier',(3.7,10.6,1.88),(3.45,.35,3.76),m['stone'],.045)
    cube('Marquee lintel',(0,10.6,3.77),(10.9,.46,.65),m['black'],.05)
    for x in (-2.03,2.03):
        cube('Door brass jamb',(x,10.36,1.75),(.08,.09,3.50),m['metal'],.01)
        cube('Recessed doorway light',(x*.97,10.49,1.75),(.024,.04,3.46),m['warm'],.006)
    cube('Door top border',(0,10.36,3.50),(4.12,.09,.08),m['metal'],.01)
    text('Cinema marquee','F L U X   C I N E M A',(0,10.33,3.85),.29,m['letter'])
    text('Screening caption','LA SEANCE COMMENCE ICI',(0,10.32,3.59),.075,m['letter'])
    # Curtain folds and sliver of an illuminated screen are visible through entry.
    curtain=node_mat('Pleated cinema curtains',rgb(THEMES[theme]['fabric']),.91,kind='fabric')
    for side in (-1,1):
        for j in range(8):
            x=side*(1.85+j*.13)
            sphere('Heavy velvet fold',(x,11.2,1.73),(.22,.24,3.39),curtain)
    screen=glow('Resting theatre screen',rgb('697B92'),.42)
    cube('Cinema screen',(0,12.87,2.1),(4.0,.035,1.8),screen,.02)
    for row in range(3):
        for x in (-1.1,-.55,0,.55,1.1):
            y=11.5+row*.53
            cube('Screening seat back',(x,y,.70+row*.07),(.45,.16,.63),curtain,.10)
            cube('Screening seat cushion',(x,y+.19,.42+row*.07),(.43,.40,.14),curtain,.055)
    area('Theatre reflected blue',(0,12.6,2.25),(0,9.7,1.1),120,(.47,.66,1),3,1.2)
    # Large backlit posters define the cinema's identity on either side.
    for side in (-1,1):
        for j,y in enumerate((3.1,6.65,9.2)):
            poster(m,side*6.24,y,2.28,1.35,2.05,j+(3 if side>0 else 0),orientation=-side*math.pi/2)
        for y in (1.5,4.85,8.35):
            cube('Fluted pilaster',(side*6.05,y,1.85),(.27,.37,3.7),m['darkwood'],.03)
            for d in (-.10,0,.10):cube('Pilaster brass flute',(side*5.89,y+d,1.85),(.02,.018,3.45),m['metal'],.004)
    poster(m,-3.75,10.37,2.05,1.28,1.97,1)
    poster(m,3.75,10.37,2.05,1.28,1.97,4)
    # Rounded velvet benches, brass feet, ticket kiosk and subtle rope line.
    for side in (-1,1):
        x=side*4.65
        cube('Velvet lounge bench',(x,5.5,.53),(1.35,2.35,.32),m['fabric'],.14)
        cube('Velvet lounge back',(side*5.20,5.5,.91),(.20,2.3,.75),m['fabric'],.09)
        for y in (4.65,6.35):
            for xx in (x-.43,x+.43):cylinder('Bench brass foot',(xx,y,.20),.035,.40,m['metal'])
    for side in (-1,1):
        x=side*2.30
        for y in (8.0,9.65):
            cylinder('Rope post base',(x,y,.06),.18,.12,m['metal'])
            cylinder('Rope post',(x,y,.60),.027,1.15,m['metal'])
            sphere('Rope post cap',(x,y,1.19),(.11,.11,.11),m['metal'])
        line('Velvet rope',[(x,8,1.14),(x,8.3,1.02),(x,8.82,.94),(x,9.35,1.02),(x,9.65,1.14)],.035,carpet)
    if theme=='artDeco':
        for j in range(9):
            x=(j-4)*.33
            line('Art deco fan',[(x,10.25,4.18),(x*1.7,10.25,4.43)],.012,m['metal'])
    if theme=='future':
        for y in (1.2,4.5,7.8):
            line('Architectural light portal',[(-5.8,y,.2),(-5.8,y,4.13),(5.8,y,4.13),(5.8,y,.2)],.018,m['accent'])
    area('Lobby fill',(0,-.5,3.25),(0,7,1.4),750,(.8,.85,1),6)
    camera((0,-.9,1.95),(0,8,1.93),23)

def sleeve_materials(m):
    colors=['293E52','7A4939','8A7351','423348','526653','6D3546','344F61','777063','2C3038','546174','9A8B6B','3B4A3F']
    return [node_mat('Collector sleeve %02d'%i,rgb(c),.43) for i,c in enumerate(colors)]

def shelf(m, cases, x, y, width=2.18, height=2.9, rotation=0, number=0):
    made=[]
    def part(name,loc,size,mat,bevel=.015):
        o=cube(name,(x+loc[0],y+loc[1],loc[2]),size,mat,bevel)
        made.append(o);return o
    part('Bookcase recessed back',(0,.22,height/2),(width,.065,height),m['darkwood'])
    for side in (-1,1):part('Bookcase solid side',(side*(width/2-.045),0,height/2),(.09,.55,height),m['wood'])
    part('Bookcase plinth',(0,0,.12),(width+.08,.61,.24),m['darkwood'])
    for row in range(6):
        z=.27+row*.48
        part('Solid shelf',(0,0,z),(width,.56,.055),m['wood'],.009)
        part('Shelf facing lip',(0,-.285,z-.014),(width,.036,.065),m['wood'],.008)
        if row==5:continue
        part('Under shelf warm LED',(0,-.13,z+.448),(width-.15,.018,.012),m['warm'],.003)
        at=-width/2+.11
        while at<width/2-.13:
            w=random.uniform(.061,.095)
            h=random.uniform(.365,.408)
            mat=random.choice(cases)
            # Most are vertical thick collectors; occasional pairs separated by a gap.
            p=part('Season collector case',(at+w/2,-.006,z+.033+h/2),(w-.008,.32,h),mat,.006)
            part('Printed spine top',(at+w/2,-.170,z+.033+h*.84),(w*.67,.005,.018),m['cream'],0)
            if random.random()>.26:
                for k in range(random.randrange(2,4)):
                    part('Printed spine lettering',(at+w/2,-.171,z+.033+h*.52+k*.027),(w*.45,.004,.008),m['cream'],0)
            at+=w
            if random.random()>.975:at+=.10
    part('Bookcase cornice',(0,0,height-.04),(width+.10,.61,.12),m['wood'])
    if rotation:
        for o in made:
            dx=o.location.x-x;dy=o.location.y-y
            o.location.x=x+dx*math.cos(rotation)-dy*math.sin(rotation)
            o.location.y=y+dx*math.sin(rotation)+dy*math.cos(rotation)
            o.rotation_euler.z+=rotation

def video_club(m,theme):
    depth=12.5;H=4.2
    shell(m,theme,13,depth,H);ceiling_lights(m,depth,13,H,theme)
    cases=sleeve_materials(m)
    for i in range(5):shelf(m,cases,(i-2)*2.42,12.15,width=2.30,height=3.0,number=i)
    for side in (-1,1):
        for j in range(4):shelf(m,cases,side*6.12,1.9+j*2.52,width=2.40,height=3.0,rotation=-side*math.pi/2,number=j+7)
    cube('Video store back sign',(0,12.05,3.52),(7.4,.18,.67),m['black'],.07)
    text('Video club sign','F L U X   V I D E O C L U B',(0,11.94,3.62),.275,m['accent'])
    text('Collection sign','LES SERIES  /  COFFRETS & SAISONS',(0,11.94,3.34),.095,m['letter'])
    for side in (-1,1):
        x=side*3.90
        for y in (5.1,8.9):
            cube('Display cabinet base',(x,y,.57),(1.38,2.35,1.02),m['darkwood'],.07)
            cube('Display table top',(x,y,1.13),(1.52,2.49,.12),m['wood'],.04)
            for col in (-1,1):
                for k in range(7):
                    yy=y-.92+k*.30
                    cube('Displayed collector box',(x+col*.32,yy,1.43),(.47,.12,.50),cases[(k+col)%len(cases)],.012)
                    cube('Display printed title',(x+col*.32,yy-.064,1.53),(.34,.006,.025),m['cream'],.002)
                    cube('Display printed subtitle',(x+col*.32,yy-.064,1.47),(.24,.006,.010),m['cream'],0)
    for side in (-1,1):
        x=side*5.76
        text('Aisle classification','COFFRETS',(x,7.8,3.37),.15,m['letter'],rotation=(math.pi/2,0,-side*math.pi/2))
    if theme in ('neo90','future'):
        for side in (-1,1):
            line('Suspended neon aisle',[(side*5.6,1,3.6),(side*5.6,11.5,3.6),(side*2.1,11.5,3.6)],.018,m['accent'] if side<0 else m['secondary'])
    elif theme=='vintage70':
        for y in (4.8,8.1):
            cylinder('Pendant stem',(0,y,3.64),.025,.8,m['metal'])
            sphere('Amber globe pendant',(0,y,3.20),(.63,.63,.63),m['warm'])
            area('Amber pendant',(0,y,3.15),(0,y,0),160,(1,.66,.30),1)
    elif theme=='artDeco':
        for side in (-1,1):
            for j in range(5):
                x=side*(2.8+j*.18)
                line('Deco crown',[(x,11.89,3.20),(x,11.89,3.95-j*.09)],.012,m['metal'])
    elif theme=='zen':
        for y in (3,6,9):
            cube('Oak ceiling baffle',(0,y,3.92),(12,.13,.22),m['wood'],.02)
    area('Video club welcoming fill',(0,-.5,3.1),(0,7,1.4),950,(.83,.86,1),6)
    camera((0,-.25,1.88),(0,8.6,1.80),22)

def cushion(m,name,loc,size,material=None):
    o=cube(name,loc,size,material or m['fabric'],min(size)*.32)
    o.modifiers['Soft machined edge'].segments=5
    return o

def plant(m, x,y,scale=1):
    pot=node_mat('Clay planter',rgb('766452'),.83,kind='stone',scale=45)
    leaf=node_mat('Leaf soft wax',rgb('294A24'),.42)
    cylinder('Plant pot',(x,y,.28*scale),.31*scale,.56*scale,pot)
    cylinder('Dark soil',(x,y,.56*scale),.27*scale,.02,m['darkwood'])
    for j in range(7):
        a=j*2.399
        h=(1.1+.21*random.random())*scale
        dx=math.cos(a)*.33*scale;dy=math.sin(a)*.33*scale
        line('Plant branch',[(x,y,.52*scale),(x+dx*.4,y+dy*.4,h*.7),(x+dx,y+dy,h)],.010*scale,m['darkwood'])
        for k in range(3):
            z=h*(.62+.13*k)
            px=x+dx*(.52+.22*k);py=y+dy*(.52+.22*k)
            o=sphere('Broad plant leaf',(px,py,z),(.41*scale,.14*scale,.045*scale),leaf)
            o.rotation_euler=(.3,(-.2 if k%2 else .4),a)

def living_room(m,theme):
    depth=10;H=3.75;width=11.5
    shell(m,theme,width,depth,H)
    # Soft sofa facing the television; architectural view shows the real room.
    rug=node_mat('Handwoven large rug',mix(rgb(THEMES[theme]['fabric']),rgb('B3AA94'),.40),.98,kind='fabric')
    cube('Large living room rug',(0,4.30,.022),(6.30,5.10,.043),rug,.04)
    # Low television wall with many separate wooden slats.
    cube('Television wall panel',(0,9.82,1.95),(6.6,.12,3.5),m['darkwood'],.02)
    for j in range(52):cube('Walnut wall slat',((j-25.5)*.123,9.72,1.97),(.082,.11,3.42),m['wood'],.012)
    cube('Television backlight',(0,9.48,2.20),(4.93,.08,2.82),m['accent'],.06)
    cube('Television graphite frame',(0,9.38,2.20),(4.87,.11,2.76),m['black'],.05)
    screen=node_mat('Television resting glass',rgb('101A25'),.115,.25)
    cube('Television glass',(0,9.315,2.20),(4.72,.014,2.61),screen,.02)
    # Very subtle screen reflection pattern in geometry, no programme or fake UI.
    refl=node_mat('Screen soft reflected window',rgb('182638'),.27,.15)
    cube('Screen reflected window',(-1.45,9.302,2.49),(.55,.004,1.46),refl,.02)
    cube('Television console',(0,9.10,.58),(5.95,1.01,.67),m['wood'],.045)
    cube('Console top',(0,9.09,.96),(6.05,1.09,.07),m['wood'],.025)
    for j in range(5):
        x=(j-2)*1.17
        cube('Console door',(x,8.58,.59),(1.13,.04,.54),m['wood'],.013)
        cube('Console brushed handle',(x,8.545,.76),(.21,.028,.018),m['metal'],.005)
    for x in (-2.55,2.55):
        for y in (8.72,9.44):cylinder('Console metal leg',(x,y,.18),.033,.36,m['metal'])
    cube('Soundbar',(0,8.94,1.06),(1.95,.20,.13),m['black'],.05)
    # Sofa foreground, modular form, precise cushions and contrasting pillows.
    cube('Sofa base',(0,1.89,.43),(4.55,1.47,.52),m['fabric'],.14)
    cube('Sofa back',(0,1.25,.92),(4.47,.27,1.11),m['fabric'],.12)
    for j in (-1,0,1):
        cushion(m,'Seat cushion',(j*1.30,1.98,.76),(1.27,1.17,.22))
        cushion(m,'Back cushion',(j*1.30,1.49,1.08),(1.26,.23,.62))
    for side in (-1,1):
        cushion(m,'Sofa upholstered arm',(side*2.16,1.93,.88),(.35,1.51,.73))
        o=cushion(m,'Soft linen pillow',(side*1.63,1.65,1.12),(.51,.20,.51),m['cream'])
        o.rotation_euler.y=side*.15
    for x in (-1.85,1.85):
        for y in (1.40,2.32):cylinder('Sofa foot',(x,y,.14),.045,.28,m['metal'])
    # Travertine coffee table, books, ceramic vessels.
    sphere('Oval coffee table',(0,4.63,.52),(2.67,1.28,.14),m['stone'])
    for x in (-.76,.76):cube('Coffee table sculpted foot',(x,4.63,.27),(.19,.63,.52),m['darkwood'],.06)
    book=node_mat('Coffee table book cover',rgb('4C5968'),.65)
    cube('Coffee table art book',(-.56,4.53,.64),(.54,.37,.07),book,.009,rotation=.13)
    cube('Art book page block',(-.56,4.53,.67),(.52,.35,.036),m['cream'],.004,rotation=.13)
    cylinder('Ceramic bowl',(0.57,4.75,.67),.21,.11,m['stone'])
    for j in range(3):sphere('Decorative bowl stones',(.49+j*.065,4.74,.75),(.13,.12,.09),m['darkwood'])
    # Single lounge chair on the right, upholstery has real volume and wood legs.
    x=3.75;y=6.10
    cushion(m,'Armchair base',(x,y,.52),(1.31,1.13,.45))
    cushion(m,'Armchair back',(x,y+.46,.99),(1.30,.25,1.05))
    for side in (-1,1):cushion(m,'Armchair arm',(x+side*.62,y,.80),(.19,1.14,.51))
    cushion(m,'Armchair seat',(x,y-.03,.79),(1.06,.95,.21))
    for xx in (x-.47,x+.47):
        for yy in (y-.40,y+.40):cylinder('Armchair foot',(xx,yy,.18),.035,.36,m['darkwood'])
    # Windows, softly pleated linen curtains and cold exterior reflections.
    cube('Window frame',(-5.58,6.10,2.08),(.12,4.03,2.77),m['black'],.025)
    window=glow('Evening window',rgb('556E87') if theme!='zen' else rgb('BFCAD0'),.22)
    cube('Window glass',(-5.50,6.10,2.08),(.035,3.81,2.54),window,.006)
    for yy in (4.22,6.1,7.98):cube('Window mullion',(-5.45,yy,2.08),(.07,.045,2.6),m['metal'],.007)
    for side in (-1,1):
        for j in range(10):
            yy=6.10+side*(1.57-j*.072)
            sphere('Linen curtain fold',(-5.19,yy,1.90),(.22,.16,3.34),m['cream'])
    line('Curtain rod',[(-5.14,3.96,3.62),(-5.14,8.24,3.62)],.028,m['metal'])
    area('Window soft fill',(-5.06,6.10,2.25),(0,5,1),420 if theme!='zen' else 1000,(.65,.78,1),2.5,3.4)
    # Floor lamp, open side shelving and a leafy plant.
    cylinder('Standing lamp base',(4.52,8.35,.065),.28,.13,m['metal'])
    cylinder('Standing lamp stem',(4.52,8.35,1.30),.025,2.6,m['metal'])
    bpy.ops.mesh.primitive_cone_add(vertices=48,radius1=.43,radius2=.28,depth=.56,location=(4.52,8.35,2.64))
    assign(bpy.context.object,m['cream']);bpy.context.object.name='Linen lamp shade'
    sphere('Lamp globe',(4.52,8.35,2.43),(.20,.20,.20),m['warm'])
    area('Warm lamp pool',(4.52,8.35,2.39),(4.52,8.35,0),180,(1,.73,.42),.45)
    plant(m,-4.28,8.87,1.4)
    for z in (.58,1.12,1.66,2.20):cube('Right wall open shelf',(5.40,8.90,z),(.51,1.66,.065),m['wood'],.015)
    for y in (8.1,9.7):cube('Wall shelf upright',(5.56,y,1.42),(.11,.055,2.35),m['metal'],.009)
    for j in range(10):cube('Shelf books',(5.23,8.28+j*.11,.84),(.27,.074,.45),m['cream'] if j%3 else book,.004)
    sphere('Ceramic vase',(5.25,8.65,1.45),(.25,.25,.54),m['stone'])
    if theme in ('neo90','future','midnight'):
        cube('Television wall cove',(0,9.36,3.67),(6.65,.08,.04),m['accent'],.01)
        area('TV ambient wash',(0,9.6,2.15),(0,10,2.15),120,rgb(THEMES[theme]['accent'])[:3],3.5,2)
    if theme=='artDeco':
        for j in range(7):
            x=(j-3)*.30
            line('Art deco ceiling fan',[(x,9.53,3.47),(x*1.6,9.53,3.68)],.009,m['metal'])
    if theme=='vintage70':
        sphere('Opaline ceiling pendant',(0,6.1,3.1),(.65,.65,.65),m['warm'])
        cylinder('Pendant cable',(0,6.1,3.47),.012,.55,m['black'])
    else:
        for x in (-2.7,2.7):
            cylinder('Living room ceiling spot',(x,5.9,3.67),.12,.08,m['warm'])
    area('Living room warm bounce',(0,5.7,3.48),(0,5,0),700 if theme!='zen' else 850,(1,.84,.65),4)
    area('Living room foreground fill',(0,-.5,3.05),(0,5,1),340,(.78,.84,1),5)
    camera((1.3,-1.95,2.65),(0,6.5,1.50),23.5)

def render_one(kind,theme,args):
    start=time.time()
    m=setup(theme,args.width,args.height,args.samples)
    {'cinema':cinema,'videoClub':video_club,'livingRoom':living_room}[kind](m,theme)
    OUT.mkdir(parents=True,exist_ok=True)
    path=OUT/f'{kind}-{theme}.jpg'
    bpy.context.scene.render.filepath=str(path)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/f'{kind}-preview.blend')) if args.save_scene else None
    bpy.ops.render.render(write_still=True)
    scene=bpy.context.scene
    denoised=scene.render.engine=='CYCLES' and (scene.cycles.use_denoising or external_denoise(path))
    result=dict(file=path.name,bytes=path.stat().st_size,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),seconds=round(time.time()-start,2),objects=len(scene.objects),engine=scene.render.engine,denoising='OpenImageDenoise' if denoised else 'none')
    print('FLUX_RESULT '+json.dumps(result),flush=True)
    return result

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--kind',choices=['cinema','videoClub','livingRoom'],default='cinema')
    parser.add_argument('--theme',choices=list(THEMES),default='neo90')
    parser.add_argument('--all',action='store_true')
    parser.add_argument('--width',type=int,default=1920)
    parser.add_argument('--height',type=int,default=1080)
    parser.add_argument('--samples',type=int,default=24)
    parser.add_argument('--save-scene',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    jobs=[(k,t) for k in ('cinema','videoClub','livingRoom') for t in THEMES] if args.all else [(args.kind,args.theme)]
    entries=[render_one(k,t,args) for k,t in jobs]
    manifest=dict(schema=1,generator='Blender procedural geometry and materials',blender=bpy.app.version_string,seed=SEED,width=args.width,height=args.height,samples=args.samples,external_models=False,external_textures=False,image_generation_ai=False,files=entries)
    name='manifest.json' if args.all else f'{args.kind}-{args.theme}.render.json'
    (OUT/name).write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    if args.all:
        # The complete manifest supersedes the sidecars of reduced test renders.
        for stale in OUT.glob('*.render.json'):stale.unlink()

if __name__=='__main__':main()
