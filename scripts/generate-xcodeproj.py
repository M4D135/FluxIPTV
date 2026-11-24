#!/usr/bin/env python3
"""Regenerate a deterministic, dependency-free Xcode project for the macOS app."""
from __future__ import annotations
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = sorted((ROOT / 'Sources' / 'FluxIPTVCore').glob('*.swift'))
MAC = sorted((ROOT / 'FluxIPTVMac').glob('*.swift'))
assert CORE and MAC


def uid(value: str) -> str:
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()


def item(key: str, isa: str, body: str) -> str:
    return f'\t\t{uid(key)} /* {key} */ = {{isa = {isa}; {body.rstrip()}{"" if body.rstrip().endswith(";") else ";"} }};'


def refs(files, phase=''):
    return ' '.join(f'{uid(str(p))} /* {p.name}{phase} */,' for p in files)


def bfile(p):
    return uid('build ' + str(p.relative_to(ROOT)))


def fref(p):
    return uid('file ' + str(p.relative_to(ROOT)))

objects = []
for file in CORE + MAC:
    path = str(file.relative_to(ROOT))
    objects.append(f'\t\t{bfile(file)} /* {file.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fref(file)} /* {file.name} */; }};')

for file in CORE + MAC:
    objects.append(f'\t\t{fref(file)} /* {file.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file.name}; sourceTree = "<group>"; }};')
for name in ['Info.plist', 'FluxIPTV.entitlements']:
    objects.append(f'\t\t{uid("meta " + name)} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {name}; sourceTree = "<group>"; }};')
objects.append(f'\t\t{uid("product")} /* FluxIPTV.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FluxIPTV.app; sourceTree = BUILT_PRODUCTS_DIR; }};')

objects.append(item('root', 'PBXGroup', f'''children = (
    {uid('core-parent')} /* Sources */,
    {uid('mac-parent')} /* FluxIPTVMac */,
    {uid('products')} /* Products */,
); sourceTree = "<group>"'''))
objects.append(item('core-parent', 'PBXGroup', f'children = ({uid("core")} /* FluxIPTVCore */,); path = Sources; sourceTree = "<group>"'))
objects.append(item('core', 'PBXGroup', 'children = (' + ' '.join(f'{fref(p)} /* {p.name} */,' for p in CORE) + '); path = FluxIPTVCore; sourceTree = "<group>"'))
objects.append(item('mac-parent', 'PBXGroup', 'children = (' + ' '.join(f'{fref(p)} /* {p.name} */,' for p in MAC) + ' ' + ' '.join(f'{uid("meta " + s)} /* {s} */,' for s in ['Info.plist', 'FluxIPTV.entitlements']) + '); path = FluxIPTVMac; sourceTree = "<group>"'))
objects.append(item('products', 'PBXGroup', f'children = ({uid("product")} /* FluxIPTV.app */,); name = Products; sourceTree = "<group>"'))

objects.append(item('sources-phase', 'PBXSourcesBuildPhase', 'buildActionMask = 2147483647; files = (' + ' '.join(f'{bfile(p)} /* {p.name} in Sources */,' for p in MAC + CORE) + '); runOnlyForDeploymentPostprocessing = 0'))
objects.append(item('frameworks-phase', 'PBXFrameworksBuildPhase', 'buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0'))
objects.append(item('resources-phase', 'PBXResourcesBuildPhase', 'buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0'))
objects.append(item('target', 'PBXNativeTarget', f'''buildConfigurationList = {uid('target-configs')} /* Build configuration list for PBXNativeTarget "FluxIPTV" */;
    buildPhases = ({uid('sources-phase')} /* Sources */, {uid('frameworks-phase')} /* Frameworks */, {uid('resources-phase')} /* Resources */,);
    buildRules = (); dependencies = (); name = FluxIPTV; productName = FluxIPTV;
    productReference = {uid('product')} /* FluxIPTV.app */; productType = "com.apple.product-type.application"'''))
objects.append(item('project', 'PBXProject', f'''attributes = {{BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 1600; TargetAttributes = {{{uid('target')} = {{CreatedOnToolsVersion = 16.0; }}; }}; }};
    buildConfigurationList = {uid('project-configs')} /* Build configuration list for PBXProject "FluxIPTV" */;
    compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; hasScannedForEncodings = 0;
    knownRegions = (fr, en, Base,); mainGroup = {uid('root')};
    productRefGroup = {uid('products')} /* Products */; projectDirPath = "";
    projectRoot = ""; targets = ({uid('target')} /* FluxIPTV */,)'''))

for config in ['Debug', 'Release']:
    objects.append(item(f'project-{config}', 'XCBuildConfiguration', f'''buildSettings = {{
        ALWAYS_SEARCH_USER_PATHS = NO;
        CLANG_ENABLE_MODULES = YES;
        CLANG_ENABLE_OBJC_ARC = YES;
        MACOSX_DEPLOYMENT_TARGET = 14.0;
        SDKROOT = macosx;
        SWIFT_OPTIMIZATION_LEVEL = {'"-Onone"' if config == 'Debug' else '"-O"'};
    }}; name = {config}'''))
    objects.append(item(f'target-{config}', 'XCBuildConfiguration', f'''buildSettings = {{
        CODE_SIGN_ENTITLEMENTS = FluxIPTVMac/FluxIPTV.entitlements;
        CODE_SIGN_STYLE = Automatic;
        CURRENT_PROJECT_VERSION = 1;
        ENABLE_APP_SANDBOX = YES;
        GENERATE_INFOPLIST_FILE = NO;
        INFOPLIST_FILE = FluxIPTVMac/Info.plist;
        MACOSX_DEPLOYMENT_TARGET = 14.0;
        MARKETING_VERSION = 0.1.0;
        PRODUCT_BUNDLE_IDENTIFIER = com.m4d135.FluxIPTV;
        PRODUCT_NAME = "$(TARGET_NAME)";
        SWIFT_VERSION = 5.0;
        SWIFT_STRICT_CONCURRENCY = minimal;
        SUPPORTED_PLATFORMS = macosx;
        {'ONLY_ACTIVE_ARCH = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config == 'Debug' else ''}
    }}; name = {config}'''))

objects.append(item('project-configs', 'XCConfigurationList', f'buildConfigurations = ({uid("project-Debug")} /* Debug */, {uid("project-Release")} /* Release */,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release'))
objects.append(item('target-configs', 'XCConfigurationList', f'buildConfigurations = ({uid("target-Debug")} /* Debug */, {uid("target-Release")} /* Release */,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release'))

text = '''// !$*UTF8*$!\n{\n    archiveVersion = 1;\n    classes = {};\n    objectVersion = 56;\n    objects = {\n''' + '\n'.join(objects) + f'''\n    }};\n    rootObject = {uid('project')} /* Project object */;\n}}\n'''
output = ROOT / 'FluxIPTV.xcodeproj' / 'project.pbxproj'
output.write_text(text)
print(f'Generated {output} ({len(MAC)+len(CORE)} Swift files)')
