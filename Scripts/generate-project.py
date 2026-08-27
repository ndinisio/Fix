"""Regenerates Fix.xcodeproj/project.pbxproj from the files on disk.

Xcode maintains the project file itself when you add files through its UI, so
you only need this if you have added or removed sources from the filesystem —
for example after a scripted change or a merge that touched the layout.

    python3 Scripts/generate-project.py

Every Swift file under Fix/ joins the app target, every file under FixTests/
joins the test target, asset catalogues go to the Resources phase, and groups
mirror the folder structure. Run it from the repository root. The scheme's
target identifiers are derived from the same seeds, so they stay valid."""
import hashlib, os, pathlib, sys

ROOT = pathlib.Path('.')

# There must be exactly one project, at the repository root. A second one —
# usually a leftover template that a case-insensitive filesystem merged into the
# sources folder — silently shadows this one in Xcode's file browser.
projects = [p for p in ROOT.glob('**/*.xcodeproj') if '.git' not in p.parts]
if len(projects) > 1:
    print('More than one .xcodeproj found. Remove the stray ones before continuing:')
    for project in sorted(projects):
        print('  ', project)
    raise SystemExit(1)
if projects and projects[0].parent != ROOT:
    print(f'The project must sit at the repository root, not {projects[0]}')
    raise SystemExit(1)

def uid(seed):
    """Deterministic 24-character uppercase hex id."""
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()

icons = [p for p in ROOT.glob('Fix/**/*.icon') if '.git' not in p.parts]
appiconsets = [p for p in ROOT.glob('Fix/**/AppIcon.appiconset')]
clashing = [p for p in icons if p.stem == 'AppIcon']
if clashing and appiconsets:
    print('Both an Icon Composer icon and an app icon set are named AppIcon:')
    for path in clashing + appiconsets:
        print('  ', path)
    print('Keep one. Delete the AppIcon.appiconset folder if you are using the .icon file.')
    raise SystemExit(1)

FILE_TYPES = {
    '.swift': 'sourcecode.swift',
    '.xcassets': 'folder.assetcatalog',
    '.icon': 'folder.iconcomposer.icon',
    '.plist': 'text.plist.xml',
    '.xcconfig': 'text.xcconfig',
    '.md': 'net.daringfireball.markdown',
    '.json': 'text.json',
}

objects = []          # lines for the objects section
sources = {'app': [], 'tests': []}
resources = {'app': [], 'tests': []}

def add(line):
    objects.append(line)

def file_ref(path, name=None):
    """PBXFileReference for a path relative to its parent group."""
    fid = uid('file:' + str(path))
    ext = pathlib.Path(path).suffix
    ftype = FILE_TYPES.get(ext, 'text')
    base = name or pathlib.Path(path).name
    add(f'\t\t{fid} /* {base} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; '
        f'path = "{base}"; sourceTree = "<group>"; }};')
    return fid

def build_file(fid, path, target, phase):
    bid = uid(f'build:{target}:{path}')
    base = pathlib.Path(path).name
    add(f'\t\t{bid} /* {base} in {phase} */ = {{isa = PBXBuildFile; fileRef = {fid} /* {base} */; }};')
    (sources if phase == 'Sources' else resources)[target].append((bid, base))
    return bid

def walk(directory, target):
    """Builds a PBXGroup for `directory`, returning its id."""
    children = []
    entries = sorted(directory.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
    for entry in entries:
        rel = entry.relative_to(ROOT)
        if entry.name.startswith('.'):
            continue
        if entry.is_dir():
            if entry.suffix in ('.xcassets', '.icon'):
                fid = file_ref(rel)
                build_file(fid, rel, target, 'Resources')
                children.append((fid, entry.name))
            else:
                gid = walk(entry, target)
                children.append((gid, entry.name))
        else:
            if entry.suffix == '.swift':
                fid = file_ref(rel)
                build_file(fid, rel, target, 'Sources')
                children.append((fid, entry.name))
            elif entry.suffix in FILE_TYPES:
                fid = file_ref(rel)
                children.append((fid, entry.name))
    gid = uid('group:' + str(directory))
    kids = '\n'.join(f'\t\t\t\t{cid} /* {name} */,' for cid, name in children)
    add(f'\t\t{gid} /* {directory.name} */ = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n{kids}\n\t\t\t);\n'
        f'\t\t\tpath = "{directory.name}";\n'
        f'\t\t\tsourceTree = "<group>";\n'
        f'\t\t}};')
    return gid

app_group = walk(ROOT / 'Fix', 'app')
tests_group = walk(ROOT / 'FixTests', 'tests')
config_group = walk(ROOT / 'Config', 'app')   # no build phase membership for these

readme = file_ref(pathlib.Path('README.md'))
changelog = file_ref(pathlib.Path('CHANGELOG.md'))

# Products
APP_PRODUCT = uid('product:app')
TEST_PRODUCT = uid('product:tests')
add(f'\t\t{APP_PRODUCT} /* Fix.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; '
    f'includeInIndex = 0; path = Fix.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
add(f'\t\t{TEST_PRODUCT} /* FixTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; '
    f'includeInIndex = 0; path = FixTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')

PRODUCTS_GROUP = uid('group:products')
add(f'\t\t{PRODUCTS_GROUP} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n'
    f'\t\t\t\t{APP_PRODUCT} /* Fix.app */,\n\t\t\t\t{TEST_PRODUCT} /* FixTests.xctest */,\n'
    f'\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = "<group>";\n\t\t}};')

MAIN_GROUP = uid('group:main')
add(f'\t\t{MAIN_GROUP} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n'
    f'\t\t\t\t{app_group} /* Fix */,\n'
    f'\t\t\t\t{tests_group} /* FixTests */,\n'
    f'\t\t\t\t{config_group} /* Config */,\n'
    f'\t\t\t\t{readme} /* README.md */,\n'
    f'\t\t\t\t{changelog} /* CHANGELOG.md */,\n'
    f'\t\t\t\t{PRODUCTS_GROUP} /* Products */,\n'
    f'\t\t\t);\n\t\t\tsourceTree = "<group>";\n\t\t}};')

def phase(kind, target, items):
    pid = uid(f'phase:{kind}:{target}')
    lines = '\n'.join(f'\t\t\t\t{bid} /* {name} in {kind} */,' for bid, name in items)
    add(f'\t\t{pid} /* {kind} */ = {{\n\t\t\tisa = PBX{kind}BuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{lines}\n\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};')
    return pid

APP_SOURCES = phase('Sources', 'app', sources['app'])
APP_RESOURCES = phase('Resources', 'app', resources['app'])
TEST_SOURCES = phase('Sources', 'tests', sources['tests'])
TEST_RESOURCES = phase('Resources', 'tests', resources['tests'])
APP_FRAMEWORKS = phase('Frameworks', 'app', [])
TEST_FRAMEWORKS = phase('Frameworks', 'tests', [])

APP_TARGET, TEST_TARGET = uid('target:app'), uid('target:tests')
PROJECT = uid('project')
DEP, PROXY = uid('dependency'), uid('proxy')
BASE_XCCONFIG = uid('file:Config/Base.xcconfig')

PROJ_LIST, APP_LIST, TEST_LIST = uid('cfglist:project'), uid('cfglist:app'), uid('cfglist:tests')
PROJ_DEBUG, PROJ_RELEASE = uid('cfg:project:debug'), uid('cfg:project:release')
APP_DEBUG, APP_RELEASE = uid('cfg:app:debug'), uid('cfg:app:release')
TEST_DEBUG, TEST_RELEASE = uid('cfg:tests:debug'), uid('cfg:tests:release')

add(f'''\t\t{APP_TARGET} /* Fix */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {APP_LIST} /* Build configuration list for PBXNativeTarget "Fix" */;
\t\t\tbuildPhases = (
\t\t\t\t{APP_SOURCES} /* Sources */,
\t\t\t\t{APP_FRAMEWORKS} /* Frameworks */,
\t\t\t\t{APP_RESOURCES} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = Fix;
\t\t\tproductName = Fix;
\t\t\tproductReference = {APP_PRODUCT} /* Fix.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};''')

add(f'''\t\t{TEST_TARGET} /* FixTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {TEST_LIST} /* Build configuration list for PBXNativeTarget "FixTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{TEST_SOURCES} /* Sources */,
\t\t\t\t{TEST_FRAMEWORKS} /* Frameworks */,
\t\t\t\t{TEST_RESOURCES} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{DEP} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = FixTests;
\t\t\tproductName = FixTests;
\t\t\tproductReference = {TEST_PRODUCT} /* FixTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};''')

add(f'''\t\t{PROJECT} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2600;
\t\t\t\tLastUpgradeCheck = 2600;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{APP_TARGET} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t}};
\t\t\t\t\t{TEST_TARGET} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;
\t\t\t\t\t\tTestTargetID = {APP_TARGET};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {PROJ_LIST} /* Build configuration list for PBXProject "Fix" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {MAIN_GROUP};
\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{APP_TARGET} /* Fix */,
\t\t\t\t{TEST_TARGET} /* FixTests */,
\t\t\t);
\t\t}};''')

add(f'''\t\t{DEP} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {APP_TARGET} /* Fix */;
\t\t\ttargetProxy = {PROXY} /* PBXContainerItemProxy */;
\t\t}};''')

add(f'''\t\t{PROXY} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {PROJECT} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {APP_TARGET};
\t\t\tremoteInfo = Fix;
\t\t}};''')

SHARED = '''\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_ENABLE_OBJC_WEAK = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;'''

add(f'''\t\t{PROJ_DEBUG} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = {BASE_XCCONFIG} /* Base.xcconfig */;
\t\t\tbuildSettings = {{
{SHARED}
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};''')

add(f'''\t\t{PROJ_RELEASE} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = {BASE_XCCONFIG} /* Base.xcconfig */;
\t\t\tbuildSettings = {{
{SHARED}
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};''')

APP_SETTINGS = '''\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_ASSET_PATHS = "\\"Fix/Resources/Preview Content\\"";
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Fix/Resources/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.ndinisio.Fix;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";'''

TEST_SETTINGS = '''\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.ndinisio.FixTests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Fix.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Fix";'''

for cid, name, settings in [
    (APP_DEBUG, 'Debug', APP_SETTINGS), (APP_RELEASE, 'Release', APP_SETTINGS),
    (TEST_DEBUG, 'Debug', TEST_SETTINGS), (TEST_RELEASE, 'Release', TEST_SETTINGS),
]:
    add(f'\t\t{cid} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n'
        f'\t\t\tbuildSettings = {{\n{settings}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};')

for lid, label, debug, release in [
    (PROJ_LIST, 'PBXProject "Fix"', PROJ_DEBUG, PROJ_RELEASE),
    (APP_LIST, 'PBXNativeTarget "Fix"', APP_DEBUG, APP_RELEASE),
    (TEST_LIST, 'PBXNativeTarget "FixTests"', TEST_DEBUG, TEST_RELEASE),
]:
    add(f'\t\t{lid} /* Build configuration list for {label} */ = {{\n'
        f'\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n'
        f'\t\t\t\t{debug} /* Debug */,\n\t\t\t\t{release} /* Release */,\n'
        f'\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n'
        f'\t\t\tdefaultConfigurationName = Release;\n\t\t}};')

body = '\n'.join(objects)
out = f'''// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

{body}

\t}};
\trootObject = {PROJECT} /* Project object */;
}}
'''
pathlib.Path('Fix.xcodeproj/project.pbxproj').write_text(out)
print(f'app sources:  {len(sources["app"])}')
print(f'app resources:{len(resources["app"])}')
print(f'test sources: {len(sources["tests"])}')
print(f'bytes:        {len(out)}')
