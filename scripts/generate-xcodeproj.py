#!/usr/bin/env python3
"""Regenerate the shared and Apple TV-only Xcode projects from the same sources."""
from __future__ import annotations
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = sorted((ROOT / 'Sources' / 'FluxIPTVCore').glob('*.swift'))
MAC = sorted((ROOT / 'FluxIPTVMac').glob('*.swift'))
COMPAT = sorted((ROOT / 'FluxIPTVMac' / 'Compatibility').glob('*.[ch]'))
assert CORE and MAC and len(COMPAT) == 2


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

# Shared sources, distinct application targets and bundle IDs; the macOS ID is unchanged.
PLATFORMS = [
    dict(name='FluxIPTV', suffix='mac', sdk='macosx', supported='macosx', deployment='MACOSX_DEPLOYMENT_TARGET = 14.0;', bundle='com.m4d135.FluxIPTV', plist='Info.plist', family='', extra='CODE_SIGN_ENTITLEMENTS = FluxIPTVMac/FluxIPTV.entitlements; ENABLE_APP_SANDBOX = YES; SWIFT_OBJC_BRIDGING_HEADER = FluxIPTVMac/Compatibility/LegacyKeychainInteraction.h;'),
    dict(name='FluxIPTViOS', suffix='ios', sdk='iphoneos', supported='"iphoneos iphonesimulator"', deployment='IPHONEOS_DEPLOYMENT_TARGET = 17.0;', bundle='com.m4d135.FluxIPTV.ios', plist='Info-iOS.plist', family='TARGETED_DEVICE_FAMILY = "1,2";', extra='SUPPORTS_MACCATALYST = NO;'),
    dict(name='FluxIPTVTV', suffix='tv', sdk='appletvos', supported='"appletvos appletvsimulator"', deployment='TVOS_DEPLOYMENT_TARGET = 17.0;', bundle='com.m4d135.FluxIPTV.tv', plist='Info-tvOS.plist', family='TARGETED_DEVICE_FAMILY = 3;', extra='SWIFT_OBJC_BRIDGING_HEADER = FluxIPTVMac/Compatibility/LegacyKeychainInteraction.h;'),
]
META = ['Info.plist', 'Info-iOS.plist', 'Info-tvOS.plist', 'FluxIPTV.entitlements']

def k(p, key):
    # Retain the original Mac target ID / scheme compatibility.
    return key if p['suffix'] == 'mac' else key + '-' + p['suffix']

def bkey(p, file): return k(p, 'build ' + str(file.relative_to(ROOT)))

def ref_list(ids): return ' '.join(uid(i) + ',' for i in ids)

def generate(platforms, project_name):
    objects = []
    compat = COMPAT if any(p['suffix'] in ('mac', 'tv') for p in platforms) else []
    for file in CORE + MAC:
        objects.append(f'\t\t{fref(file)} /* {file.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file.name}; sourceTree = "<group>"; }};')
    for file in compat:
        file_type = 'sourcecode.c.c' if file.suffix == '.c' else 'sourcecode.c.h'
        objects.append(f'\t\t{fref(file)} /* {file.name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {file.name}; sourceTree = "<group>"; }};')
    if compat:
        objects.append(item('compat', 'PBXGroup', 'children = (' + ' '.join(f'{fref(p)},' for p in compat) + '); path = Compatibility; sourceTree = "<group>"'))
    for name in META:
        objects.append(f'\t\t{uid("meta " + name)} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {name}; sourceTree = "<group>"; }};')
    objects.append(item('room-resources', 'PBXFileReference', 'lastKnownFileType = folder; path = RoomBakes; sourceTree = "<group>"'))
    objects.append(item('root', 'PBXGroup', f'children = ({uid("core-parent")}, {uid("mac-parent")}, {uid("products")},); sourceTree = "<group>"'))
    objects.append(item('core-parent', 'PBXGroup', f'children = ({uid("core")},); path = Sources; sourceTree = "<group>"'))
    objects.append(item('core', 'PBXGroup', 'children = (' + ' '.join(f'{fref(p)},' for p in CORE) + '); path = FluxIPTVCore; sourceTree = "<group>"'))
    objects.append(item('mac-parent', 'PBXGroup', 'children = (' + ' '.join(f'{fref(p)},' for p in MAC) + ' ' + ref_list(['meta '+s for s in META] + ['room-resources'] + (['compat'] if compat else [])) + '); path = FluxIPTVMac; name = FluxIPTVShared; sourceTree = "<group>"'))
    objects.append(item('products', 'PBXGroup', f'children = ({ref_list([k(p, "product") for p in platforms])}); name = Products; sourceTree = "<group>"'))
    objects.append(item('vlc-package', 'XCRemoteSwiftPackageReference', 'repositoryURL = "https://github.com/videolan/vlckit.git"; requirement = {kind = revision; revision = 7f98c70f9f0c11fbdf828220890bd6280361ae99; }'))
    package_keys = ['vlc-package']
    if any(p['suffix'] == 'tv' for p in platforms):
        objects.append(item('youtube-package', 'XCLocalSwiftPackageReference', 'relativePath = Vendor/YouTubeKit'))
        package_keys.append('youtube-package')

    for p in platforms:
        n=p['name']; u=lambda key:uid(k(p,key))
        objects.append(item(k(p,'product'), 'PBXFileReference', f'explicitFileType = wrapper.application; includeInIndex = 0; path = {n}.app; sourceTree = BUILT_PRODUCTS_DIR'))
        target_sources = CORE + MAC + ([file for file in compat if file.suffix == '.c'] if p['suffix'] in ('mac', 'tv') else [])
        for file in target_sources:
            objects.append(item(bkey(p,file), 'PBXBuildFile', f'fileRef = {fref(file)}'))
        objects.append(item(k(p,'sources-phase'), 'PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = ({ref_list([bkey(p,file) for file in target_sources])}); runOnlyForDeploymentPostprocessing = 0'))
        use_vlc = p['suffix'] != 'mac'
        if use_vlc:
            objects.append(item(k(p,'vlc-product'), 'XCSwiftPackageProductDependency', f'package = {uid("vlc-package")}; productName = VLCKit'))
            objects.append(item(k(p,'vlc-build'), 'PBXBuildFile', f'productRef = {u("vlc-product")}'))
        framework_keys = [k(p, 'vlc-build')] if use_vlc else []
        product_keys = [k(p, 'vlc-product')] if use_vlc else []
        if p['suffix'] == 'tv':
            objects.append(item(k(p,'youtube-product'), 'XCSwiftPackageProductDependency', f'package = {uid("youtube-package")}; productName = YouTubeKit'))
            objects.append(item(k(p,'youtube-build'), 'PBXBuildFile', f'productRef = {u("youtube-product")}'))
            framework_keys.append(k(p, 'youtube-build'))
            product_keys.append(k(p, 'youtube-product'))
        objects.append(item(k(p,'frameworks-phase'), 'PBXFrameworksBuildPhase', f'buildActionMask = 2147483647; files = ({ref_list(framework_keys)}); runOnlyForDeploymentPostprocessing = 0'))
        objects.append(item(k(p,'room-build'), 'PBXBuildFile', f'fileRef = {uid("room-resources")}'))
        objects.append(item(k(p,'resources-phase'), 'PBXResourcesBuildPhase', f'buildActionMask = 2147483647; files = ({u("room-build")},); runOnlyForDeploymentPostprocessing = 0'))
        objects.append(item(k(p,'target'), 'PBXNativeTarget', f'buildConfigurationList = {u("target-configs")}; buildPhases = ({u("sources-phase")}, {u("frameworks-phase")}, {u("resources-phase")},); buildRules = (); dependencies = (); packageProductDependencies = ({ref_list(product_keys)}); name = {n}; productName = {n}; productReference = {u("product")}; productType = "com.apple.product-type.application"'))
        for config in ['Debug','Release']:
            settings = f"""
            CODE_SIGN_STYLE = Automatic;
            CURRENT_PROJECT_VERSION = 26;
            GENERATE_INFOPLIST_FILE = NO;
            INFOPLIST_FILE = FluxIPTVMac/{p['plist']};
            SDKROOT = {p['sdk']};
            {p['deployment']}
            {p['family']}
            {p['extra']}
            LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/{'../Frameworks' if p['suffix'] == 'mac' else 'Frameworks'}";
            {'ENABLE_DEBUG_DYLIB = NO;' if p['suffix'] == 'mac' else ''}
            MARKETING_VERSION = 0.8.8;
            PRODUCT_BUNDLE_IDENTIFIER = {p['bundle']};
            PRODUCT_NAME = "$(TARGET_NAME)";
            SWIFT_VERSION = 5.0;
            SWIFT_STRICT_CONCURRENCY = minimal;
            SUPPORTED_PLATFORMS = {p['supported']};
            {'ONLY_ACTIVE_ARCH = YES; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if config == 'Debug' else ''}
            """
            objects.append(item(k(p,f'target-{config}'), 'XCBuildConfiguration', f'buildSettings = {{{settings}}}; name = {config}'))
        objects.append(item(k(p,'target-configs'), 'XCConfigurationList', f'buildConfigurations = ({u("target-Debug")}, {u("target-Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release'))

    attrs=' '.join(f'{uid(k(p,"target"))} = {{CreatedOnToolsVersion = 16.0;}};' for p in platforms)
    objects.append(item('project', 'PBXProject', f'attributes = {{BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 1600; TargetAttributes = {{{attrs}}}; }}; buildConfigurationList = {uid("project-configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; hasScannedForEncodings = 0; knownRegions = (fr, en, Base,); mainGroup = {uid("root")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; packageReferences = ({ref_list(package_keys)}); targets = ({ref_list([k(p,"target") for p in platforms])})'))
    for config in ['Debug','Release']:
        opt = '"-Onone"' if config == 'Debug' else '"-O"'
        objects.append(item(f'project-{config}', 'XCBuildConfiguration', f'buildSettings = {{ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; SWIFT_OPTIMIZATION_LEVEL = {opt}; }}; name = {config}'))
    objects.append(item('project-configs','XCConfigurationList', f'buildConfigurations = ({uid("project-Debug")}, {uid("project-Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release'))
    text = '// !$*UTF8*$!\n{\n    archiveVersion = 1;\n    classes = {};\n    objectVersion = 56;\n    objects = {\n' + '\n'.join(objects) + f'\n    }};\n    rootObject = {uid("project")};\n}}\n'
    project = ROOT / project_name
    project.mkdir(exist_ok=True)
    output = project / 'project.pbxproj'
    output.write_text('\n'.join(line.rstrip() for line in text.splitlines()) + '\n')
    # Each project has only its own shared schemes and keeps stable target IDs.
    scheme_dir = project / 'xcshareddata' / 'xcschemes'
    scheme_dir.mkdir(parents=True, exist_ok=True)
    base = (ROOT / 'FluxIPTV.xcodeproj' / 'xcshareddata' / 'xcschemes' / 'FluxIPTV.xcscheme').read_text()
    for p in platforms:
        n = p['name']
        scheme = base.replace(uid('target'), uid(k(p, 'target'))).replace('BuildableName="FluxIPTV.app"', f'BuildableName="{n}.app"').replace('BlueprintName="FluxIPTV"', f'BlueprintName="{n}"').replace('container:FluxIPTV.xcodeproj', f'container:{project_name}')
        if p['suffix'] == 'tv':
            # The normal Apple TV launch installs the optimized app without a
            # debugger. Debug remains available for development and UI fixtures.
            scheme = scheme.replace('<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"',
                                    '<LaunchAction buildConfiguration="Release" selectedDebuggerIdentifier="" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn"')
        (scheme_dir / f'{n}.xcscheme').write_text(scheme)
    workspace = project / 'project.xcworkspace'
    workspace.mkdir(exist_ok=True)
    (workspace / 'contents.xcworkspacedata').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
    print(f'Generated {output} ({len(MAC) + len(CORE)} shared Swift files, {len(platforms)} targets)')


generate(PLATFORMS, 'FluxIPTV.xcodeproj')
generate([p for p in PLATFORMS if p['suffix'] == 'tv'], 'FluxIPTV-AppleTV.xcodeproj')
