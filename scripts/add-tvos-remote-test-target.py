#!/usr/bin/env python3
"""Add the XCUIRemote target only to the disposable native-capture repository."""
from __future__ import annotations

import argparse
import copy
import hashlib
from pathlib import Path
import re
import xml.etree.ElementTree as ET


def uid(key: str) -> str:
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


def object_text(key: str, isa: str, fields: str) -> str:
    return f'\t\t{uid(key)} /* {key} */ = {{isa = {isa}; {fields} }};'


def replace_once(pattern: str, replacement, text: str) -> str:
    result, count = re.subn(pattern, replacement, text, flags=re.MULTILINE | re.DOTALL)
    if count != 1:
        raise ValueError(f"Expected one project anchor, found {count}: {pattern}")
    return result


def configure(smoke_repo: Path, bundle_id: str) -> None:
    smoke_repo = smoke_repo.resolve()
    fixture = smoke_repo / "FluxIPTVMac/FluxIPTVApp.swift"
    source = smoke_repo / "Tests/Native/TVRemoteNavigationTests.swift"
    project = smoke_repo / "FluxIPTV-AppleTV.xcodeproj"
    project_file = project / "project.pbxproj"
    if (smoke_repo / ".git").exists() or smoke_repo == Path(__file__).resolve().parent.parent:
        raise ValueError("Refusing to modify the working repository; use its disposable smoke copy.")
    if "@main @MainActor private struct TVCatalogUISmoke" not in fixture.read_text():
        raise ValueError("The temporary app entry point must already be the TV catalogue fixture.")
    if not source.is_file() or not project_file.is_file() or project_file.is_symlink():
        raise ValueError("The smoke copy is missing its regular project file or remote test source.")
    if not re.fullmatch(r"[A-Za-z0-9.-]+", bundle_id):
        raise ValueError("Invalid fixture bundle identifier.")

    text = project_file.read_text()
    if uid("remote-ui-target") in text:
        raise ValueError("This smoke copy already has the remote UI-test target.")

    def edit_object(key: str, change) -> None:
        nonlocal text
        pattern = (rf"^\t\t{uid(key)} /\* {re.escape(key)} \*/ = .*?"
                   rf"(?=^\t\t[0-9A-F]{{24}} /\*|^    \}};)")
        text = replace_once(pattern, lambda match: change(match.group()), text)

    def append_reference(block: str, field: str, reference: str) -> str:
        return replace_once(rf"(\b{field} = \()([^)]*)(\);)",
                            lambda match: match[1] + match[2] + f" {reference}," + match[3], block)

    # A command-line PRODUCT_BUNDLE_IDENTIFIER override would also rename the
    # UI runner. Set only the fixture application's two target configurations.
    for configuration in ("Debug", "Release"):
        edit_object(f"target-{configuration}-tv", lambda block: replace_once(
            r"PRODUCT_BUNDLE_IDENTIFIER = [^;]+;",
            f"PRODUCT_BUNDLE_IDENTIFIER = {bundle_id};", block))
    edit_object("root", lambda block: append_reference(block, "children", uid("remote-ui-group")))
    edit_object("products", lambda block: append_reference(block, "children", uid("remote-ui-product")))

    def extend_project(block: str) -> str:
        block = append_reference(block, "targets", uid("remote-ui-target"))
        return replace_once(r"TargetAttributes = \{", lambda _: (
            f"TargetAttributes = {{{uid('remote-ui-target')} = {{CreatedOnToolsVersion = 26.3; "
            f"TestTargetID = {uid('target-tv')};}}; "), block)

    edit_object("project", extend_project)
    objects = [
        object_text("remote-ui-source", "PBXFileReference",
                    'lastKnownFileType = sourcecode.swift; path = TVRemoteNavigationTests.swift; sourceTree = "<group>";'),
        object_text("remote-ui-group", "PBXGroup",
                    f'children = ({uid("remote-ui-source")},); path = Tests/Native; sourceTree = "<group>";'),
        object_text("remote-ui-build", "PBXBuildFile", f'fileRef = {uid("remote-ui-source")};'),
        object_text("remote-ui-product", "PBXFileReference",
                    'explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = FluxIPTVTVRemoteNavigationTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;'),
        object_text("remote-ui-sources", "PBXSourcesBuildPhase",
                    f'buildActionMask = 2147483647; files = ({uid("remote-ui-build")},); runOnlyForDeploymentPostprocessing = 0;'),
        object_text("remote-ui-frameworks", "PBXFrameworksBuildPhase",
                    'buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;'),
        object_text("remote-ui-resources", "PBXResourcesBuildPhase",
                    'buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;'),
        object_text("remote-ui-proxy", "PBXContainerItemProxy",
                    f'containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("target-tv")}; remoteInfo = FluxIPTVTV;'),
        object_text("remote-ui-dependency", "PBXTargetDependency",
                    f'target = {uid("target-tv")}; targetProxy = {uid("remote-ui-proxy")};'),
        object_text("remote-ui-target", "PBXNativeTarget",
                    f'buildConfigurationList = {uid("remote-ui-configs")}; '
                    f'buildPhases = ({uid("remote-ui-sources")}, {uid("remote-ui-frameworks")}, {uid("remote-ui-resources")},); '
                    f'buildRules = (); dependencies = ({uid("remote-ui-dependency")},); '
                    f'name = FluxIPTVTVRemoteNavigationTests; productName = FluxIPTVTVRemoteNavigationTests; '
                    f'productReference = {uid("remote-ui-product")}; productType = "com.apple.product-type.bundle.ui-testing";'),
    ]
    for configuration in ("Debug", "Release"):
        settings = (
            'CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0; '
            'GENERATE_INFOPLIST_FILE = YES; SDKROOT = appletvos; TVOS_DEPLOYMENT_TARGET = 17.0; '
            'TARGETED_DEVICE_FAMILY = 3; SUPPORTED_PLATFORMS = "appletvos appletvsimulator"; '
            'PRODUCT_BUNDLE_IDENTIFIER = com.m4d135.FluxIPTV.TVRemoteNavigationTests; PRODUCT_NAME = "$(TARGET_NAME)"; '
            'TEST_TARGET_NAME = FluxIPTVTV; ENABLE_TESTING_SEARCH_PATHS = YES; SKIP_INSTALL = YES; '
            'SWIFT_VERSION = 5.0; SWIFT_STRICT_CONCURRENCY = minimal; '
            'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";'
        )
        objects.append(object_text(f"remote-ui-{configuration}", "XCBuildConfiguration",
                                   f"buildSettings = {{{settings}}}; name = {configuration};"))
    objects.append(object_text("remote-ui-configs", "XCConfigurationList",
                               f'buildConfigurations = ({uid("remote-ui-Debug")}, {uid("remote-ui-Release")},); '
                               'defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;'))
    text = replace_once(r"\n    \};\n    rootObject = ",
                        lambda _: "\n" + "\n".join(objects) + "\n    };\n    rootObject = ", text)

    schemes = project / "xcshareddata/xcschemes"
    scheme = ET.parse(schemes / "FluxIPTVTV.xcscheme")
    entries = scheme.find("BuildAction/BuildActionEntries")
    action = scheme.find("TestAction")
    app_reference = scheme.find("BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference")
    if entries is None or action is None or app_reference is None:
        raise ValueError("The production scheme no longer has its expected build/test structure.")
    reference = {
        "BuildableIdentifier": "primary", "BlueprintIdentifier": uid("remote-ui-target"),
        "BuildableName": "FluxIPTVTVRemoteNavigationTests.xctest",
        "BlueprintName": "FluxIPTVTVRemoteNavigationTests",
        "ReferencedContainer": "container:FluxIPTV-AppleTV.xcodeproj",
    }
    entry = ET.SubElement(entries, "BuildActionEntry", {
        "buildForTesting": "YES", "buildForRunning": "NO", "buildForProfiling": "NO",
        "buildForArchiving": "NO", "buildForAnalyzing": "YES",
    })
    ET.SubElement(entry, "BuildableReference", reference)
    testables = action.find("Testables")
    if testables is None or len(testables):
        raise ValueError("Expected the fixture's existing scheme to have an empty Testables element.")
    testable = ET.SubElement(testables, "TestableReference", {"skipped": "NO", "parallelizable": "NO"})
    ET.SubElement(testable, "BuildableReference", reference)
    ET.SubElement(action, "MacroExpansion").append(copy.deepcopy(app_reference))
    project_file.write_text(text)
    scheme_path = schemes / "FluxIPTVTVRemoteNavigation.xcscheme"
    scheme.write(scheme_path, encoding="UTF-8", xml_declaration=True)
    print(f"Configured temporary XCUIRemote target: {scheme_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke-repository", required=True, type=Path)
    parser.add_argument("--app-bundle-id", required=True)
    args = parser.parse_args()
    try:
        configure(args.smoke_repository, args.app_bundle_id)
    except (OSError, ValueError, ET.ParseError) as error:
        parser.exit(1, f"Cannot configure temporary tvOS remote tests: {error}\n")
