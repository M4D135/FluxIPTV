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
    if theme in ('midnight','artDeco','future'):
        for row in range(10):
            for col in range(9):
                xx=(col-4)*1.5;yy=-.6+row*1.5
                cube('Architectural stone floor tile',(xx,yy,-.025),(1.49,1.49,.06),m['stone'],.008)
                if theme=='artDeco':
                    cube('Brass floor tile inlay',(xx+.746,yy,.009),(.012,1.49,.012),m['metal'],.002)
    else:
        # Individual staggered boards provide perspective, seams and reflections.
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

def architectural_signature(m,theme,width,depth,height,kind):
    """Theme changes are geometry, construction and light, never palette only."""
    if theme=='neo90':
        # Exposed steel mezzanine/trusses give the store and lobby a loft feel.
        for yy in (2.3,6.0,9.7):
            if yy>depth:continue
            for zz in (height-.36,height-.13):line('Exposed steel truss',[(-width/2+.2,yy,zz),(width/2-.2,yy,zz)],.032,m['metal'])
            for j in range(int(width)-1):line('Steel truss diagonal',[(-width/2+.6+j,yy,height-.36),(-width/2+1.1+j,yy,height-.13)],.017,m['metal'])
        for side in (-1,1):
            for row in range(16):
                yy=.4+row*.72
                cube('Retro side aisle floor inset',(side*(width/2-1.0),yy,.014),(1.3,.66,.025),m['black'] if row%2 else m['stone'],.006)
        if kind=='videoClub':
            text('Store neon welcome','VIDEO  /  CLUB',(-4.5,11.88,3.75),.12,m['secondary'])
    elif theme=='midnight':
        # Cinematic charcoal monoliths and long ceiling slots; no visible bulbs.
        for side in (-1,1):
            for yy in (2.2,6.2,10.2):
                cube('Monolithic dark stone pier',(side*(width/2-.22),yy,height/2),(.34,.62,height),m['stone'],.03)
                cube('Vertical inset grazing light',(side*(width/2-.42),yy-.20,height/2),(.025,.025,height-.55),m['warm'],.007)
        for xx in (-width*.24,width*.24):cube('Long floating ceiling slot',(xx,depth/2,height-.13),(.05,depth-.7,.024),m['warm'],.005)
        for side in (-1,1):
            cube('Floating black wall plinth',(side*(width/2-.33),depth/2,.19),(.42,depth-.7,.22),m['black'],.03)
    elif theme=='vintage70':
        # Heavy ceiling beams and rounded portals, with warm opaline pendants.
        for yy in (2.1,5.3,8.5,11.7):
            if yy>depth:continue
            cube('Seventies timber structural beam',(0,yy,height-.20),(width-.12,.24,.32),m['darkwood'],.03)
        for side in (-1,1):
            for yy in (3.3,7.4):
                cylinder('Opaline pendant brass stem',(side*3.3,yy,height-.60),.02,.85,m['metal'])
                sphere('Amber opaline pendant',(side*3.3,yy,height-1.0),(.48,.48,.48),m['warm'])
                area('Opaline warm pool',(side*3.3,yy,height-1.2),(side*3.3,yy,0),120,(1,.70,.38),.7)
        if kind=='cinema':arch_frame('Rounded cinema entrance',0,10.23,.03,4.2,4.08,m['wood'],.12)
        else:
            for side in (-1,1):arch_frame('Seventies shop portal',side*4.7,11.9,.1,2.8,3.95,m['wood'],.07)
    elif theme=='artDeco':
        # Repeated stepped frames and large brass rays change the entire ceiling.
        for yy in (1.3,5.5,9.7):
            for step in range(3):
                xx=width/2-.35-step*.22;zz=height-.16-step*.13
                line('Deco stepped architectural portal',[(-xx,yy,.12),(-xx,yy,zz),(xx,yy,zz),(xx,yy,.12)],.025,m['metal'])
        for side in (-1,1):
            for yy in (3.4,7.7):
                x=side*(width/2-.37)
                for j in range(7):
                    angle=-.9+j*.3
                    line('Brass fan wall detail',[(x,yy,2.45),(x,yy+math.sin(angle)*.62,2.45+math.cos(angle)*.9)],.014,m['metal'])
                sphere('Deco sconce opal',(x-side*.09,yy,2.43),(.20,.25,.25),m['warm'])
    elif theme=='zen':
        # Slatted pale timber canopy and rice-paper screens replace the neon mood.
        for yy in [1.1+j*.48 for j in range(int((depth-1.1)/.48))]:cube('Light oak ceiling baffle',(0,yy,height-.16),(width-.5,.075,.19),m['wood'],.012)
        for side in (-1,1):
            for j in range(4):
                yy=1.2+j*3.0
                cube('Shoji wall panel',(side*(width/2-.16),yy,2.0),(.06,1.6,2.7),m['cream'],.008)
                for dy in (-.8,-.4,0,.4,.8):cube('Oak screen vertical',(side*(width/2-.23),yy+dy,2.0),(.08,.025,2.75),m['wood'],.004)
                for zz in (.65,1.32,2,2.68,3.35):cube('Oak screen horizontal',(side*(width/2-.23),yy,zz),(.08,1.65,.025),m['wood'],.003)
            plant(m,side*(width/2-1.1),depth-1.0,1.6)
        area('Pale architectural daylight',(-width/2+.4,depth/2,2.8),(0,depth/2,1.2),1300,(.82,.91,1),4,3)
    elif theme=='future':
        # Heavy faceted structural ribs and double light channels, not thin neon only.
        porcelain=node_mat('Future architectural ceramic',rgb('78899D'),.30,.15)
        for yy in (1.3,4.6,7.9,11.2):
            if yy>depth:continue
            xx=width/2-.42
            pts=[(-xx,yy,.08),(-xx,yy,height-1.05),(-xx+1.0,yy,height-.22),(xx-1.0,yy,height-.22),(xx,yy,height-1.05),(xx,yy,.08)]
            line('Faceted structural portal',pts,.14,porcelain)
            line('Inset luminous portal',[(x,y-.16,z) for x,y,z in pts],.019,m['accent'])
        for side in (-1,1):
            cube('Future recessed floor light',(side*(width/2-.62),depth/2,.023),(.028,depth-.6,.025),m['secondary'],.006)


def cinema(m,theme):
    depth=13;H=4.55
    shell(m,theme,13,depth,H);ceiling_lights(m,depth,13,H,theme)
    architectural_signature(m,theme,13,depth,H,'cinema')
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
    camera((.45 if theme=='midnight' else 0,-.9,2.06 if theme=='artDeco' else 1.95),(0,8,1.93),23.5 if theme=='vintage70' else 23)

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
    architectural_signature(m,theme,13,depth,H,'videoClub')
    cases=sleeve_materials(m)
    for i in range(5):shelf(m,cases,(i-2)*2.42,12.15,width=2.30,height=3.0,number=i)
    for side in (-1,1):
        for j in range(4):shelf(m,cases,side*6.12,1.9+j*2.52,width=2.40,height=3.0,rotation=-side*math.pi/2,number=j+7)
    cube('Video store back sign',(0,12.05,3.52),(7.4,.18,.67),m['black'],.07)
    text('Video club sign','F L U X   V I D E O C L U B',(0,11.94,3.62),.275,m['accent'])
    text('Collection sign','LES SERIES  /  COFFRETS & SAISONS',(0,11.94,3.34),.095,m['letter'])
    for side in (-1,1):
        x=side*({'zen':4.25,'midnight':4.45,'vintage70':3.65,'artDeco':3.95,'future':4.25}.get(theme,3.90))
        for y in ((6.4,) if theme in ('zen','midnight') else (4.9,8.9)):
            if theme in ('vintage70','future'):
                cylinder('Rounded display island',(x,y,.57),1.18,1.02,m['darkwood'],48 if theme=='vintage70' else 6)
                cylinder('Display island top',(x,y,1.13),1.25,.12,m['wood'] if theme=='vintage70' else m['stone'],48 if theme=='vintage70' else 6)
            else:
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
        # Keep the camera's central line to the shop sign completely clear.
        # The two globes belong above the lateral display aisles.
        for x in (-2.8,2.8):
            y=5.7
            cylinder('Pendant stem',(x,y,3.64),.025,.8,m['metal'])
            sphere('Amber globe pendant',(x,y,3.20),(.63,.63,.63),m['warm'])
            area('Amber pendant',(x,y,3.15),(x,y,0),160,(1,.66,.30),1)
    elif theme=='artDeco':
        for side in (-1,1):
            for j in range(5):
                x=side*(2.8+j*.18)
                line('Deco crown',[(x,11.89,3.20),(x,11.89,3.95-j*.09)],.012,m['metal'])
    elif theme=='zen':
        for y in (3,6,9):
            cube('Oak ceiling baffle',(0,y,3.92),(12,.13,.22),m['wood'],.02)
    area('Video club welcoming fill',(0,-.5,3.1),(0,7,1.4),950,(.83,.86,1),6)
    camera((.4 if theme=='zen' else 0,-.25,1.90),(0,8.6,1.80),23 if theme in ('midnight','zen') else 22)

def cushion(m,name,loc,size,material=None):
    o=cube(name,loc,size,material or m['fabric'],min(size)*.32)
    o.modifiers['Soft machined edge'].segments=6
    o.modifiers['Soft machined edge'].width=min(size)*.42
    # Fine stitched welt, modeled at the cushion edge, survives a 4K close view.
    if 'cushion' in name.lower() or 'pillow' in name.lower():
        flat=size[2]<size[1]
        a=size[0]/2-.025;b=(size[1] if flat else size[2])/2-.022;r=min(.07,a*.2,b*.25)
        points=[]
        for cx,cy,start in ((a-r,b-r,0),(-a+r,b-r,90),(-a+r,-b+r,180),(a-r,-b+r,270)):
            for j in range(6):
                angle=math.radians(start+j*90/5)
                xx=cx+r*math.cos(angle);yy=cy+r*math.sin(angle)
                points.append((loc[0]+xx,loc[1]+yy,loc[2]+size[2]/2-.013) if flat else (loc[0]+xx,loc[1]-size[1]/2+.012,loc[2]+yy))
        points.append(points[0]);line('Upholstery stitched piping',points,.0045,material or m['fabric'])
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

def arch_frame(name, x, y, z, width, height, material, radius=.055):
    # Genuine curved moulding / portal; its crown is visible in perspective.
    spring=z+height-width/2
    points=[(x-width/2,y,z),(x-width/2,y,spring)]
    points += [(x+math.cos(a)*width/2,y,spring+math.sin(a)*width/2) for a in [math.pi-i*math.pi/32 for i in range(33)]]
    points.append((x+width/2,y,z))
    return line(name,points,radius,material)

def lounge_sofa(m,x,y,width=4.5,material=None,low=False,rotation=0):
    material=material or m['fabric']; base=.33 if low else .43
    before=set(bpy.context.scene.objects)
    cushion(m,'Sofa upholstered base',(x,y,base),(width,1.55,.44),material)
    cushion(m,'Sofa upholstered back',(x,y-.63,base+.49),(width,.27,.95),material)
    n=max(2,round(width/1.4))
    for i in range(n):
        xx=x+(i-(n-1)/2)*(width-.52)/n
        cushion(m,'Sofa seat cushion',(xx,y+.06,base+.31),((width-.58)/n-.035,1.15,.23),material)
        cushion(m,'Sofa back cushion',(xx,y-.43,base+.60),((width-.58)/n-.035,.25,.62),material)
    for side in (-1,1):
        cushion(m,'Sofa arm',(x+side*(width/2-.18),y,base+.35),(.35,1.50,.71),material)
        cushion(m,'Loose linen cushion',(x+side*(width/2-.65),y-.35,base+.74),(.47,.22,.46),m['cream'])
    for xx in (x-width/2+.35,x+width/2-.35):
        for yy in (y-.5,y+.5):cylinder('Sofa slender feet',(xx,yy,.12),.04,.24,m['metal'])
    if rotation:
        for o in set(bpy.context.scene.objects)-before:
            p=o.location-Vector((x,y,0))
            o.location=Vector((x+math.cos(rotation)*p.x-math.sin(rotation)*p.y,y+math.sin(rotation)*p.x+math.cos(rotation)*p.y,p.z));o.rotation_euler.z+=rotation

def television(m,x=0,y=9.48,z=2.08,width=4.8,console=True,backlight=True):
    height=width*9/16
    if backlight:cube('TV soft rear glow',(x,y+.10,z),(width+.1,.045,height+.1),m['accent'],.04)
    cube('TV graphite chassis',(x,y,z),(width,.13,height),m['black'],.037)
    glass=node_mat('Television inactive optical glass',rgb('101821'),.12,.3)
    cube('TV inactive glass',(x,y-.073,z),(width-.10,.012,height-.10),glass,.018)
    if console:
        cube('Low media console',(x,y-.22,.47),(width+1.2,.91,.56),m['wood'],.037)
        for i in range(5):
            xx=x+(i-2)*(width+1.1)/5
            cube('Media console door',(xx,y-.695,.47),((width+1.1)/5-.035,.025,.48),m['wood'],.008)
        cube('Slim soundbar',(x,y-.3,.83),(1.86,.22,.12),m['black'],.045)

def coffee_objects(m,x,y,z):
    book=node_mat('Linen art book',rgb('777B78'),.75)
    cube('Art book',(x-.43,y-.10,z),(.55,.40,.07),book,.012,rotation=.14)
    cube('Art book paper',(x-.43,y-.10,z+.035),(.53,.38,.033),m['cream'],.003,rotation=.14)
    magazine=node_mat('Printed journal cover',rgb('526473'),.7)
    cube('Design journal',(x+.19,y-.30,z-.018),(.41,.28,.028),magazine,.003,rotation=-.19)
    for j in range(3):cube('Journal geometric artwork',(x+.12+j*.065,y-.31,z+.001),(.025,.16,.002),m['cream'],0,rotation=-.19)
    cylinder('Ceramic low bowl',(x+.49,y+.13,z+.03),.20,.10,m['stone'])
    for j in range(3):sphere('Bowl decorative stones',(x+.43+j*.06,y+.12,z+.095),(.10,.09,.08),m['darkwood'])

def pendant(m,x,y,z,shape='globe'):
    cylinder('Suspended pendant cable',(x,y,(3.72+z)/2),.012,3.72-z,m['black'])
    if shape=='globe':sphere('Opaline pendant globe',(x,y,z),(.48,.48,.48),m['warm'])
    elif shape=='paper':
        sphere('Paper lantern shade',(x,y,z),(.78,.78,.52),m['cream'])
        for k in range(9):
            h=(k-4)*.05;rad=.38*math.sqrt(max(.1,1-(h/.29)**2))
            line('Paper lantern bamboo ring',[(x+rad*math.cos(a*math.tau/48),y+rad*math.sin(a*math.tau/48),z+h) for a in range(49)],.007,m['wood'])
    else:cylinder('Pendant metal shade',(x,y,z),.42,.19,m['metal'])
    area('Pendant warm pool',(x,y,z-.17),(x,y,0),110,(1,.78,.48),.65)

def tall_window(m,x,y,width=4.0,height=2.7,day=False,shoji=False):
    pane=glow('Daylight window' if day else 'Evening window',rgb('9FAFBC') if day else rgb('244266'),.23 if day else .24)
    cube('Tall side window',(x,y,2.0),(.035,width,height),pane,.007)
    frame=m['wood'] if shoji else m['metal']
    for yy in (y-width/2,y,y+width/2):cube('Window vertical frame',(x+.04,yy,2),(.08,.065,height+.1),frame,.009)
    for zz in (2-height/2,2+height/2):cube('Window horizontal frame',(x+.04,y,zz),(.08,width+.12,.065),frame,.009)
    if shoji:
        for j in range(1,7):cube('Shoji oak lattice',(x+.06,y-width/2+j*width/7,2),(.06,.025,height),frame,.004)
        for zz in (1.25,1.75,2.25,2.75):cube('Shoji horizontal lattice',(x+.06,y,zz),(.06,width,.025),frame,.003)
    area('Window diffuse fill',(x+.15,y,2.15),(0,5,1),850 if day else 500,(.79,.87,1) if day else (.42,.64,1),height,width)

def living_room(m,theme):
    depth=10;H=3.9;width=11.5
    shell(m,theme,width,depth,H)
    rug=node_mat('Handwoven living rug',mix(rgb(THEMES[theme]['fabric']),rgb('B5AA95'),.40),.97,kind='fabric')
    # Every theme has its own architecture, composition and furniture silhouette.
    if theme=='neo90':
        # A metropolitan loft: exposed trusses, neon signs and split leather lounge.
        brick=node_mat('Loft warm exposed brick',rgb('49372F'),.86,kind='stone',scale=45)
        for row in range(18):
            for col in range(19):
                xx=(col-9)*.60+(row%2)*.3
                cube('Individual loft brick',(xx,9.84,.14+row*.215),(.57,.12,.196),brick,.007)
        for yy in (1.5,4.7,7.9):
            for zz in (3.62,3.82):line('Steel loft truss',[(-5.65,yy,zz),(5.65,yy,zz)],.035,m['metal'])
            for j in range(11):line('Truss diagonal',[(-5.5+j,yy,3.62),(-5+j,yy,3.82)],.020,m['metal'])
        television(m,x=.5,y=9.46,width=4.65)
        cube('Loft rug',(0,4.2,.022),(6.4,4.7,.04),rug,.04)
        lounge_sofa(m,-.8,1.6,4.5);lounge_sofa(m,3.8,3.7,2.4,rotation=math.pi/2)
        cube('Glass low table frame',(-.2,4.3,.31),(2.6,1.3,.54),m['black'],.04)
        cube('Stone low table top',(-.2,4.3,.61),(2.75,1.42,.08),m['stone'],.035);coffee_objects(m,-.2,4.3,.72)
        tall_window(m,-5.58,5.0,4.8,2.85)
        for x in (-4.8,4.8):line('Loft vertical neon',[(x,9.65,.3),(x,9.65,3.55)],.022,m['secondary'] if x>0 else m['accent'])
        for side in (-1,1):
            cube('Loft cove channel',(side*5.30,5,3.72),(.12,9.4,.07),m['accent'] if side<0 else m['secondary'],.012)
            area('Loft neon wall wash',(side*5.2,7,2.9),(side*5.7,7,2),200,rgb(THEMES[theme]['secondary' if side>0 else 'accent'])[:3],3)
        plant(m,-4.65,8.65,1.3);poster(m,4.4,9.69,2.1,1.2,1.8,2)
        camera((.55,-1.7,2.55),(.25,6.8,1.65),24)
    elif theme=='midnight':
        # A dark penthouse with full height glazing and real city silhouettes.
        glass=glow('Blue hour architectural glass',rgb('102439'),.35)
        cube('Panoramic rear glazing',(0,9.78,2.02),(11.3,.05,3.7),glass,.005)
        city=node_mat('Distant city silhouettes',rgb('132130'),.85)
        window=glow('City warm windows',rgb('BCA179'),.6)
        for j in range(22):
            xx=-5.3+j*.5;hh=random.uniform(.45,2.65)
            cube('City building silhouette',(xx,9.73,hh/2),(.40,.04,hh),city,.003)
            for level in range(int(hh/.2)):
                if random.random()>.45:cube('Distant city window',(xx-.06,9.70,.20+level*.2),(.08,.01,.055),window,0)
        for x in (-5.5,-3.6,-1.8,0,1.8,3.6,5.5):cube('Panoramic black mullion',(x,9.58,1.95),(.045,.1,3.9),m['black'],.005)
        stone=node_mat('Charcoal vein stone',rgb('222A30'),.31,kind='stone',scale=5)
        cube('Floating TV monolith',(-1.05,8.75,1.83),(5.2,.40,3.4),stone,.035)
        television(m,-1.05,8.47,2.02,4.75,console=False,backlight=False)
        cube('Floating media ledge',(-1.05,8.12,.57),(5.9,.75,.18),m['black'],.045)
        cube('Penthouse broad rug',(.2,4.0,.025),(7,4.6,.045),rug,.04)
        lounge_sofa(m,-.35,1.65,5.1)
        lounge_sofa(m,3.6,6.6,2.15,rotation=-math.pi*.28)
        for x,y,s in ((-.7,4.3,1.8),(1.1,4.5,1.1)):
            cylinder('Round nesting stone table',(x,y,.5),s/2,.10,stone,64)
            cylinder('Table sculpted plinth',(x,y,.27),s*.25,.46,m['black'],48)
        coffee_objects(m,-.7,4.3,.61)
        line('Penthouse arc lamp',[(4.6,4.4,0),(4.6,4.4,2.65),(4.3,4.4,3.0),(3.8,4.4,3.18),(3.2,4.4,3.18)],.027,m['metal'])
        sphere('Arc lamp globe',(3.2,4.4,3.08),(.35,.35,.35),m['warm'])
        area('Arc lamp pool',(3.2,4.4,2.9),(3.2,4.4,0),160,(1,.75,.47),.6)
        for yy in (1.1,5.3):cube('Penthouse ceiling reveal',(0,yy,3.82),(10.7,.025,.024),m['warm'],.006)
        tall_window(m,-5.58,5.6,6.2,3.55);plant(m,4.7,8.7,1.35)
        camera((1.85,-1.8,2.45),(-.4,6.5,1.6),25)
    elif theme=='vintage70':
        # Low, warm, seventies conversation pit with travertine and smoked timber.
        travertine=node_mat('Warm travertine fireplace wall',rgb('A08663'),.72,kind='stone',scale=20)
        cube('Travertine feature wall',(0,9.76,1.95),(11.3,.25,3.9),travertine,.025)
        for x in (-4.2,4.2):arch_frame('Rounded seventies alcove',x,9.53,.15,2.2,3.2,m['darkwood'],.11)
        for x in (-4.2,4.2):
            for z in (.65,1.3,1.95):cube('Alcove walnut shelf',(x,9.34,z),(1.75,.35,.075),m['wood'],.025)
            sphere('Alcove ceramic vase',(x,9.25,1.62),(.38,.38,.59),m['stone'])
        television(m,0,9.44,2.15,4.75,backlight=False)
        cube('Conversation pit timber rim',(0,3.2,.095),(7.8,5.8,.18),m['wood'],.06)
        cube('Deep wool conversation rug',(0,3.2,.20),(7.4,5.4,.035),rug,.05)
        lounge_sofa(m,0,1.1,5.4,low=True)
        lounge_sofa(m,-3.1,3.45,3.6,low=True,rotation=-math.pi/2)
        lounge_sofa(m,3.1,3.45,3.6,low=True,rotation=math.pi/2)
        cylinder('Circular travertine table',(0,4.05,.57),1.25,.16,travertine,64)
        cylinder('Table cylindrical timber base',(0,4.05,.33),.69,.55,m['darkwood'],48)
        coffee_objects(m,0,4.05,.73)
        for x,y,z in ((-2.25,6.7,2.9),(0,6.7,3.15),(2.25,6.7,2.9)):pendant(m,x,y,z)
        for yy in (1.5,3.8,6.1,8.4):cube('Deep walnut ceiling beam',(0,yy,3.72),(11.4,.22,.28),m['darkwood'],.025)
        tall_window(m,-5.58,6.2,4.8,2.85,day=True)
        plant(m,4.9,8.7,1.5)
        camera((.4,-2.0,2.6),(0,6.3,1.5),24)
    elif theme=='artDeco':
        # A hotel salon, brass arcs, coffered ceiling and scalloped club furniture.
        for x in (-4.1,0,4.1):
            arch_frame('Tall Art Deco wall arch',x,9.68,.15,3.65,3.6,m['metal'],.038)
            arch_frame('Inset Art Deco gold arch',x,9.66,.22,3.42,3.43,m['metal'],.016)
        for x in (-5.65,-2.1,2.1,5.65):
            cube('Deco fluted wall pier',(x,9.56,1.8),(.26,.30,3.6),m['black'],.02)
            for dx in (-.075,0,.075):cube('Brass wall flute',(x+dx,9.38,1.8),(.018,.02,3.45),m['metal'],.004)
        television(m,0,9.38,2.05,4.7,backlight=False)
        for zz,ww in ((3.66,10.7),(3.74,10.2),(3.82,9.7)):
            for xx in (-ww/2,ww/2):cube('Stepped ceiling gold frame',(xx,5,zz),(.035,8.5,.03),m['metal'],.005)
            for yy in (.75,9.25):cube('Stepped ceiling gold frame',(0,yy,zz),(ww,.035,.03),m['metal'],.005)
        cube('Deco thick rug',(0,4.3,.022),(7.2,5.7,.04),rug,.05)
        for x in (-3.4,3.4):cube('Rug brass toned border',(x,4.3,.046),(.025,5.35,.008),m['cream'],.003)
        lounge_sofa(m,0,1.55,5.3)
        for side in (-1,1):lounge_sofa(m,side*3.8,5.9,2.1,rotation=-side*.40)
        cube('Deco marble table',(0,4.3,.58),(2.8,1.45,.13),m['stone'],.06)
        for x in (-1.1,1.1):
            for y in (3.8,4.8):cylinder('Deco brass table leg',(x,y,.31),.035,.58,m['metal'])
        coffee_objects(m,0,4.3,.72)
        for i in range(12):
            a=i*math.tau/12;x=.7*math.cos(a);y=6.2+.7*math.sin(a)
            cylinder('Chandelier golden stem',(x,y,3.18),.024,.52,m['metal'])
            sphere('Chandelier opaline globe',(x,y,2.94),(.20,.20,.28),m['warm'])
        cylinder('Chandelier central stem',(0,6.2,3.5),.03,.70,m['metal'])
        area('Chandelier soft pool',(0,6.2,2.8),(0,6.2,0),320,(1,.78,.43),1.7)
        tall_window(m,-5.58,5.0,4.7,3.15);plant(m,4.8,8.6,1.3)
        camera((1.0,-2.05,2.65),(0,6.8,1.6),25)
    elif theme=='zen':
        # Quiet light-filled oak and rice-paper architecture, lower furniture.
        for j in range(28):cube('Pale oak screen fin',(-5.38+j*.40,9.65,1.95),(.09,.20,3.9),m['wood'],.015)
        cube('Floating pale plaster TV panel',(0,9.42,1.95),(5.5,.16,3.1),m['wall'],.05)
        television(m,0,9.25,1.95,4.5,backlight=False)
        cube('Natural sisal rug',(0,4.3,.025),(6.5,5.4,.04),rug,.035)
        lounge_sofa(m,-.8,1.5,4.6,low=True)
        lounge_sofa(m,3.6,5.7,1.9,low=True,rotation=-.5)
        sphere('Organic light oak low table',(-.2,4.35,.43),(2.8,1.55,.13),m['wood'])
        for x in (-.9,.6):cube('Wide oak table foot',(x,4.35,.24),(.19,.75,.42),m['wood'],.045)
        coffee_objects(m,-.2,4.35,.56)
        tall_window(m,-5.58,5.1,7.0,3.4,day=True,shoji=True)
        for yy in (1.7,3.9,6.1,8.3):cube('Light oak ceiling beam',(0,yy,3.8),(11.4,.13,.16),m['wood'],.02)
        pendant(m,.2,6.1,2.9,'paper');plant(m,4.5,8.7,1.6)
        for j in range(3):
            cube('Floating oak shelf',(4.35,9.42,.9+j*.65),(1.9,.45,.07),m['wood'],.02)
            sphere('Hand thrown ceramic',(4.1+j*.2,9.25,1.1+j*.65),(.22,.22,.34),m['cream'])
        camera((1.2,-1.95,2.45),(0,6.7,1.5),24.5)
    else:
        # A future pavilion: faceted portals and smooth floating stone furniture.
        porcelain=node_mat('White ceramic architectural shell',rgb('9DAAB7'),.30,.12,kind='stone',scale=90)
        for j,yy in enumerate((2.2,4.8,7.4,9.7)):
            pts=[(-5.4,yy,0),(-5.4,yy,2.6),(-4.3,yy,3.72),(4.3,yy,3.72),(5.4,yy,2.6),(5.4,yy,0)]
            line('Sculptural faceted pavilion rib',pts,.17,porcelain)
            line('Inset faceted light channel',[(x,y-.18,z) for x,y,z in pts],.018,m['accent'] if j%2 else m['secondary'])
        cube('Raised future TV wall',(0,9.62,1.95),(6.2,.20,3.6),porcelain,.14)
        television(m,0,9.40,2.13,4.92,console=False)
        sphere('Floating media console',(0,9.10,.52),(6.4,.85,.28),m['black'])
        cube('Future stone floor',(0,5,-.004),(11.4,12,.04),m['stone'],.01)
        soft=node_mat('Future ivory woven upholstery',rgb('A0A9B3'),.86,kind='fabric')
        lounge_sofa(m,-.5,1.45,5.0,material=soft,low=True)
        lounge_sofa(m,3.6,5.3,2.1,material=soft,low=True,rotation=-.5)
        cylinder('Hexagonal low table',(-.2,4.3,.45),1.4,.15,porcelain,6,rotation=(0,0,math.pi/6))
        cylinder('Hexagonal table pedestal',(-.2,4.3,.22),.85,.42,m['black'],6,rotation=(0,0,math.pi/6))
        coffee_objects(m,-.2,4.3,.58)
        tall_window(m,-5.58,5.5,6.7,3.1)
        for side in (-1,1):
            cube('Recessed floor light',(side*4.95,5,.04),(.03,9,.02),m['accent'] if side<0 else m['secondary'],.006)
            area('Pavilion ambient wash',(side*5,7,2),(side*5.65,7,2),220,rgb(THEMES[theme]['accent' if side<0 else 'secondary'])[:3],3)
        plant(m,4.5,8.9,1.25)
        camera((1.2,-2.05,2.55),(0,6.6,1.6),24)
    # Large photographic bounce sources: believable material fall-off, no fake UI.
    area('Living room ceiling bounce',(0,5.4,3.60),(0,5,0),680 if theme!='zen' else 900,(1,.86,.70),4.5)
    area('Living room foreground fill',(0,-.6,3.0),(0,5,1),450 if theme!='midnight' else 300,(.79,.85,1),5)


def render_one(kind,theme,args):
    start=time.time()
    m=setup(theme,args.width,args.height,args.samples)
    {'cinema':cinema,'videoClub':video_club,'livingRoom':living_room}[kind](m,theme)
    output=Path(args.output_dir).resolve() if args.output_dir else OUT
    output.mkdir(parents=True,exist_ok=True)
    path=output/f'{kind}-{theme}.jpg'
    bpy.context.scene.render.filepath=str(path)
    bpy.ops.wm.save_as_mainfile(filepath=str(output/f'{kind}-{theme}.blend')) if args.save_scene else None
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
    parser.add_argument('--all-themes',action='store_true',help='Render all six themes of --kind')
    parser.add_argument('--width',type=int,default=3840)
    parser.add_argument('--height',type=int,default=2160)
    parser.add_argument('--samples',type=int,default=24)
    parser.add_argument('--save-scene',action='store_true')
    parser.add_argument('--output-dir',help='Keep test renders separate from distributable resources')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    jobs=[(k,t) for k in ('cinema','videoClub','livingRoom') for t in THEMES] if args.all else ([(args.kind,t) for t in THEMES] if args.all_themes else [(args.kind,args.theme)])
    entries=[render_one(k,t,args) for k,t in jobs]
    manifest=dict(schema=1,generator='Blender procedural geometry and materials',blender=bpy.app.version_string,seed=SEED,width=args.width,height=args.height,samples=args.samples,external_models=False,external_textures=False,image_generation_ai=False,files=entries)
    manifest['color_management']=dict(view='AgX',look='AgX - Medium High Contrast',exposure=.25)
    manifest['source_files']={str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in (Path(__file__),Path(__file__).with_name('denoise_linear.py'))}
    name='manifest.json' if args.all else (f'{args.kind}-themes.preview.json' if args.all_themes else f'{args.kind}-{args.theme}.render.json')
    output=Path(args.output_dir).resolve() if args.output_dir else OUT
    (output/name).write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    if args.all:
        # The complete manifest supersedes the sidecars of reduced test renders.
        for stale in output.glob('*.render.json'):stale.unlink()

if __name__=='__main__':main()
