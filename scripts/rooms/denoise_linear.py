#!/usr/bin/env python3
"""Optional OIDN 1.4.3 HDR denoising, isolated from Blender's native libraries.

pip install oidn==0.2.1 numpy pillow
The binary/library dependency is a build-time tool, never an application asset.
"""
import ctypes
import sys
from pathlib import Path
import numpy as np
import oidn

source=np.load(sys.argv[1]).astype(np.float32)
if source.ndim!=3 or source.shape[2]!=3 or not np.isfinite(source).all():
    raise ValueError('Expected finite H×W×3 linear HDR pixels')
source=np.ascontiguousarray(source)
output=np.empty_like(source)
device=oidn.NewDevice();oidn.CommitDevice(device)
filter=oidn.NewFilter(device,'RT')
try:
    for name,data in [('color',source),('output',output)]:
        oidn.SetSharedFilterImage(filter,name,data,oidn.FORMAT_FLOAT3,data.shape[1],data.shape[0])
    # The published binding exposes the image API; use the same library's
    # public C entry point to flag the linear HDR input.
    library=oidn.__dict__['__lib_oidn']
    set_bool=library.oidnSetFilter1b
    set_bool.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_bool]
    set_bool.restype=None
    set_bool(filter,b'hdr',True)
    oidn.CommitFilter(filter);oidn.ExecuteFilter(filter)
    error=oidn.GetDeviceError(device)
    if error:raise RuntimeError('OpenImageDenoise error %d'%error)
    np.save(sys.argv[2],output)
finally:
    oidn.ReleaseFilter(filter);oidn.ReleaseDevice(device)
