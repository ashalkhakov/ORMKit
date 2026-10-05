#!/usr/bin/env python3
"""Write ORMKit.xcodeproj from the source lists the GNUmakefiles keep.

    python3 .tools/genxcodeproj.py

Regenerate after adding a source file rather than editing project.pbxproj by
hand: CI regenerates it and fails when the committed one differs. Object ids
are derived from names, so the output is stable and diffs stay small.
GNUstep does not read any of this -- it builds with make.
"""
import hashlib
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = "ORMKit"


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def make_list(path, var):
    """A GNUmakefile variable's words, continuation lines joined."""
    text = open(os.path.join(ROOT, path)).read().replace("\\\n", " ")
    words = []
    for m in re.finditer(r"^%s\s*\+?=\s*(.*)$" % re.escape(var), text, re.M):
        words.extend(m.group(1).split())
    return words


def headers_in(directory):
    return sorted(f for f in os.listdir(os.path.join(ROOT, directory)) if f.endswith(".h"))


# The targets, each from its directory's GNUmakefile.
KIT_SOURCES = make_list("ORMKit/GNUmakefile", "ORMKit_OBJC_FILES")
KIT_PUBLIC = make_list("ORMKit/GNUmakefile", "ORMKit_HEADER_FILES")
KIT_PRIVATE = [h for h in headers_in("ORMKit") if h not in KIT_PUBLIC]
KIT_TESTS = make_list("ORMKitTests/GNUmakefile", "ORMKitTests_OBJC_FILES")
KIT_TEST_HEADERS = headers_in("ORMKitTests")
TOOL_SOURCES = make_list("Tools/ormtool/GNUmakefile", "ormtool_OBJC_FILES")
APP_SOURCES = make_list("ORMDesigner/GNUmakefile", "ORMDesigner_OBJC_FILES")
APP_RESOURCES = make_list("ORMDesigner/GNUmakefile", "ORMDesigner_RESOURCE_FILES")
APP_HEADERS = [h for h in headers_in("ORMDesigner") if h != "ORMDesignerCompat.h"]
APP_TEST_FILES = make_list("ORMDesignerTests/GNUmakefile", "ORMDesignerTests_OBJC_FILES")
APP_TESTS = [t for t in APP_TEST_FILES if not t.startswith("../")]
# Their paths below ORMDesigner/ (ThirdParty/DMTabBar/DMTabBar.m), as the app's list has them.
APP_TESTED = [t[len("../ORMDesigner/"):] for t in APP_TEST_FILES if t.startswith("../ORMDesigner/")]
# The designer's XIBs, which its classes load from the bundle they are in.
APP_TEST_RESOURCES = [os.path.basename(t) for t in make_list("ORMDesignerTests/GNUmakefile",
                                                            "ORMDesignerTests_RESOURCE_FILES")
                      if t.startswith("../ORMDesigner/")]
DOCS = ["README.md", "CLAUDE.md", "docs/ARCHITECTURE.md", "docs/COREDATA-MAPPING.md"]

objects = {}  # id -> (comment, fields)


def add(ident, comment, fields):
    objects[ident] = (comment, fields)
    return ident


def q(s):
    if re.fullmatch(r"[A-Za-z0-9_./$]+", s):
        return s
    return '"' + s.replace('"', '\\"') + '"'


def names(ids):
    return ["%s /* %s */" % (i, objects[i][0]) for i in ids]


FILE_TYPES = {".m": "sourcecode.c.objc", ".h": "sourcecode.c.h", ".md": "net.daringfireball.markdown",
              ".png": "image.png", ".plist": "text.plist.xml", ".xib": "file.xib"}


def fileref(path):
    name = os.path.basename(path)
    return add(oid("ref", path), name, [
        ("isa", "PBXFileReference"),
        ("lastKnownFileType", FILE_TYPES.get(os.path.splitext(name)[1], "text")),
        ("path", q(name)),
        ("sourceTree", '"<group>"'),
    ])


def outsideref(path, relative):
    """A file or folder from outside the group's directory, at its path
    relative to the group's; a folder is copied into the bundle as it is (an
    Xcode folder reference)."""
    kind = "folder" if os.path.isdir(os.path.join(ROOT, path)) else FILE_TYPES.get(os.path.splitext(path)[1], "text")
    return add(oid("ref", path), os.path.basename(path), [
        ("isa", "PBXFileReference"),
        ("lastKnownFileType", kind),
        ("name", q(os.path.basename(path))),
        ("path", q(relative)),
        ("sourceTree", '"<group>"'),
    ])


def product(name, file_type, path):
    return add(oid("product", name), path, [
        ("isa", "PBXFileReference"),
        ("explicitFileType", q(file_type)),
        ("includeInIndex", "0"),
        ("path", q(path)),
        ("sourceTree", "BUILT_PRODUCTS_DIR"),
    ])


def buildfile(target, ref, settings=None):
    fields = [("isa", "PBXBuildFile"), ("fileRef", "%s /* %s */" % (ref, objects[ref][0]))]
    if settings:
        fields.append(("settings", settings))
    return add(oid("build", target, ref), objects[ref][0], fields)


def phase(isa, target, name, files, extra=()):
    fields = [("isa", isa), ("buildActionMask", "2147483647"), ("files", names(files))]
    fields.extend(extra)
    fields.append(("runOnlyForDeploymentPostprocessing", "0"))
    return add(oid("phase", target, name), name, fields)


# File references, by directory.
kit_refs = {f: fileref("ORMKit/" + f) for f in KIT_SOURCES + KIT_PUBLIC + KIT_PRIVATE}
kit_test_refs = {f: fileref("ORMKitTests/" + f) for f in KIT_TESTS + KIT_TEST_HEADERS}
tool_refs = {f: fileref("Tools/ormtool/" + f) for f in TOOL_SOURCES}
# A resource outside ORMDesigner/ is a sample, or a folder of them; a file in
# a folder of it (ThirdParty/) is named by its path from there.
app_refs = {f: outsideref(os.path.normpath("ORMDesigner/" + f), f) if f.startswith("../") or "/" in f
            else fileref("ORMDesigner/" + f)
            for f in APP_SOURCES + APP_HEADERS + APP_RESOURCES + ["ORMDesigner-Info.plist"]}
app_test_refs = {f: fileref("ORMDesignerTests/" + f) for f in APP_TESTS}
doc_refs = {d: fileref(d) for d in DOCS}
sdk = {}
for framework in ("Foundation", "AppKit", "XCTest"):
    sdk[framework] = add(oid("sdk", framework), framework + ".framework", [
        ("isa", "PBXFileReference"),
        ("lastKnownFileType", "wrapper.framework"),
        ("name", framework + ".framework"),
        ("path", "System/Library/Frameworks/%s.framework" % framework),
        ("sourceTree", "SDKROOT"),
    ])

# ODataKit's framework, which the workspace (ORMKit.xcworkspace) builds from
# ../ODataKit/ODataKit.xcodeproj, as UDWorkflow's does.
ODATAKIT = "../ODataKit"
odatakit = add(oid("built", "ODataKit"), "ODataKit.framework", [
    ("isa", "PBXFileReference"),
    ("explicitFileType", "wrapper.framework"),
    ("path", "ODataKit.framework"),
    ("sourceTree", "BUILT_PRODUCTS_DIR"),
])
# Its client library, whose query builder writes the requests' URLs.
odatastore = add(oid("built", "ODataIncrementalStore"), "ODataIncrementalStore.framework", [
    ("isa", "PBXFileReference"),
    ("explicitFileType", "wrapper.framework"),
    ("path", "ODataIncrementalStore.framework"),
    ("sourceTree", "BUILT_PRODUCTS_DIR"),
])
# The tracing library the client library links: embedded, not linked.
otelkit = add(oid("built", "OTelKit"), "OTelKit.framework", [
    ("isa", "PBXFileReference"),
    ("explicitFileType", "wrapper.framework"),
    ("path", "OTelKit.framework"),
    ("sourceTree", "BUILT_PRODUCTS_DIR"),
])
# Its service, which the tests send the queries' requests to.
odataservice = add(oid("built", "ODataService"), "ODataService.framework", [
    ("isa", "PBXFileReference"),
    ("explicitFileType", "wrapper.framework"),
    ("path", "ODataService.framework"),
    ("sourceTree", "BUILT_PRODUCTS_DIR"),
])
coredata = add(oid("sdk", "CoreData"), "CoreData.framework", [
    ("isa", "PBXFileReference"),
    ("lastKnownFileType", "wrapper.framework"),
    ("name", "CoreData.framework"),
    ("path", "System/Library/Frameworks/CoreData.framework"),
    ("sourceTree", "SDKROOT"),
])

p_kit = product("ORMKit", "wrapper.framework", "ORMKit.framework")
p_kit_tests = product("ORMKitTests", "wrapper.cfbundle", "ORMKitTests.xctest")
p_tool = product("ormtool", "compiled.mach-o.executable", "ormtool")
p_app = product("ORMDesigner", "wrapper.application", "ORMDesigner.app")
p_app_tests = product("ORMDesignerTests", "wrapper.cfbundle", "ORMDesignerTests.xctest")

# Build phases.
kit_headers = phase("PBXHeadersBuildPhase", "ORMKit", "Headers",
                    [buildfile("ORMKit", kit_refs[h], "{ATTRIBUTES = (Public, ); }") for h in KIT_PUBLIC]
                    + [buildfile("ORMKit", kit_refs[h]) for h in KIT_PRIVATE])
kit_sources = phase("PBXSourcesBuildPhase", "ORMKit", "Sources", [buildfile("ORMKit", kit_refs[s]) for s in KIT_SOURCES])
kit_frameworks = phase("PBXFrameworksBuildPhase", "ORMKit", "Frameworks",
                       [buildfile("ORMKit", sdk["Foundation"]), buildfile("ORMKit", coredata),
                        buildfile("ORMKit", odatakit), buildfile("ORMKit", odatastore)])

kit_tests_sources = phase("PBXSourcesBuildPhase", "ORMKitTests", "Sources",
                          [buildfile("ORMKitTests", kit_test_refs[s]) for s in KIT_TESTS])
kit_tests_frameworks = phase("PBXFrameworksBuildPhase", "ORMKitTests", "Frameworks",
                             [buildfile("ORMKitTests", p_kit), buildfile("ORMKitTests", odatakit),
                              buildfile("ORMKitTests", odataservice), buildfile("ORMKitTests", coredata),
                              buildfile("ORMKitTests", sdk["XCTest"])])

tool_sources = phase("PBXSourcesBuildPhase", "ormtool", "Sources", [buildfile("ormtool", tool_refs[s]) for s in TOOL_SOURCES])
tool_frameworks = phase("PBXFrameworksBuildPhase", "ormtool", "Frameworks", [buildfile("ormtool", p_kit)])

app_sources = phase("PBXSourcesBuildPhase", "ORMDesigner", "Sources",
                    [buildfile("ORMDesigner", app_refs[s]) for s in APP_SOURCES])
app_resources = phase("PBXResourcesBuildPhase", "ORMDesigner", "Resources",
                      [buildfile("ORMDesigner", app_refs[r]) for r in APP_RESOURCES])
app_frameworks = phase("PBXFrameworksBuildPhase", "ORMDesigner", "Frameworks",
                       [buildfile("ORMDesigner", p_kit), buildfile("ORMDesigner", sdk["AppKit"])])
app_embed = phase("PBXCopyFilesBuildPhase", "ORMDesigner", "Embed Frameworks",
                  [buildfile("ORMDesigner.embed", p_kit, "{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }"),
                   buildfile("ORMDesigner.embed", odatakit, "{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }"),
                   buildfile("ORMDesigner.embed", odatastore, "{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }"),
                   buildfile("ORMDesigner.embed", otelkit, "{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }")],
                  [("dstPath", '""'), ("dstSubfolderSpec", "10"), ("name", q("Embed Frameworks"))])

app_tests_sources = phase("PBXSourcesBuildPhase", "ORMDesignerTests", "Sources",
                          [buildfile("ORMDesignerTests", app_test_refs[s]) for s in APP_TESTS]
                          + [buildfile("ORMDesignerTests.app", app_refs[s]) for s in APP_TESTED])
app_tests_resources = phase("PBXResourcesBuildPhase", "ORMDesignerTests", "Resources",
                            [buildfile("ORMDesignerTests.app", app_refs[r]) for r in APP_TEST_RESOURCES])
app_tests_frameworks = phase("PBXFrameworksBuildPhase", "ORMDesignerTests", "Frameworks",
                             [buildfile("ORMDesignerTests", p_kit), buildfile("ORMDesignerTests", sdk["AppKit"]),
                              buildfile("ORMDesignerTests", sdk["XCTest"])])


# Groups.
def group(key, name, children, path=None):
    fields = [("isa", "PBXGroup"), ("children", names(children))]
    fields.append(("path", q(path)) if path else ("name", q(name)))
    fields.append(("sourceTree", '"<group>"'))
    return add(oid("group", key), name, fields)


def by_stem(files):
    return sorted(files, key=lambda n: (os.path.splitext(n)[0], os.path.splitext(n)[1] != ".h"))


g_kit = group("ORMKit", "ORMKit", [kit_refs[f] for f in by_stem(KIT_SOURCES + KIT_PUBLIC + KIT_PRIVATE)], "ORMKit")
g_kit_tests = group("ORMKitTests", "ORMKitTests", [kit_test_refs[f] for f in by_stem(KIT_TESTS + KIT_TEST_HEADERS)],
                    "ORMKitTests")
g_tool = group("ormtool", "ormtool", [tool_refs[f] for f in TOOL_SOURCES], "Tools/ormtool")
g_app = group("ORMDesigner", "ORMDesigner",
              [app_refs[f] for f in by_stem(APP_SOURCES + APP_HEADERS)]
              + [app_refs[f] for f in APP_RESOURCES + ["ORMDesigner-Info.plist"]], "ORMDesigner")
g_app_tests = group("ORMDesignerTests", "ORMDesignerTests", [app_test_refs[f] for f in APP_TESTS], "ORMDesignerTests")
g_docs = group("Docs", "Docs", [doc_refs[d] for d in DOCS])
g_frameworks = group("Frameworks", "Frameworks", [sdk[f] for f in ("Foundation", "AppKit", "XCTest")]
                     + [coredata, odatakit, odatastore, otelkit, odataservice])
g_products = group("Products", "Products", [p_kit, p_kit_tests, p_tool, p_app, p_app_tests])
g_main = group("main", PROJECT, [g_docs, g_kit, g_kit_tests, g_tool, g_app, g_app_tests, g_frameworks, g_products])
objects[g_main] = ("", [(k, v) for k, v in objects[g_main][1] if k != "name"])


# Build settings.
def settings(d):
    return "{\n" + "".join("\t\t\t\t%s = %s;\n" % (k, v) for k, v in sorted(d.items())) + "\t\t\t}"


COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CODE_SIGN_IDENTITY": q("-"),
    "CODE_SIGN_STYLE": "Manual",
    "COPY_PHASE_STRIP": "NO",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    "MACOSX_DEPLOYMENT_TARGET": "12.0",
    "MARKETING_VERSION": "0.0.0",
    "OTHER_CFLAGS": q("-Werror=int-conversion -Werror=incompatible-pointer-types -Werror=logical-not-parentheses"),
    "SDKROOT": "macosx",
    "VERSIONING_SYSTEM": q("apple-generic"),
}
DEBUG = dict(COMMON, **{"DEBUG_INFORMATION_FORMAT": "dwarf", "GCC_OPTIMIZATION_LEVEL": "0", "ONLY_ACTIVE_ARCH": "YES",
                        "GCC_PREPROCESSOR_DEFINITIONS": q("DEBUG=1")})
RELEASE = dict(COMMON, **{"DEBUG_INFORMATION_FORMAT": q("dwarf-with-dsym")})

TARGET_SETTINGS = {
    "ORMKit": {
        "DEFINES_MODULE": "YES",
        "DYLIB_COMPATIBILITY_VERSION": "1",
        "DYLIB_CURRENT_VERSION": "1",
        "DYLIB_INSTALL_NAME_BASE": q("@rpath"),
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_KEY_NSHumanReadableCopyright": q("Copyright (C) 2026 the ORMKit contributors. LGPL 2.1."),
        "INSTALL_PATH": q("$(LOCAL_LIBRARY_DIR)/Frameworks"),
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/Frameworks")',
        "PRODUCT_BUNDLE_IDENTIFIER": "org.ormkit.ORMKit",
        "PRODUCT_NAME": q("$(TARGET_NAME)"),
        "SKIP_INSTALL": "YES",
    },
    "ORMKitTests": {
        "GENERATE_INFOPLIST_FILE": "YES",
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks")',
        "PRODUCT_BUNDLE_IDENTIFIER": "org.ormkit.ORMKitTests",
        "PRODUCT_NAME": q("$(TARGET_NAME)"),
    },
    "ormtool": {
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path", "@loader_path")',
        "PRODUCT_NAME": q("$(TARGET_NAME)"),
    },
    "ORMDesigner": {
        "ASSETCATALOG_COMPILER_APPICON_NAME": '""',
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": q("ORMDesigner/ORMDesigner-Info.plist"),
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks")',
        "PRODUCT_BUNDLE_IDENTIFIER": "org.ormkit.designer",
        "PRODUCT_NAME": q("$(TARGET_NAME)"),
    },
    "ORMDesignerTests": {
        "GENERATE_INFOPLIST_FILE": "YES",
        "HEADER_SEARCH_PATHS": q("$(SRCROOT)/ORMDesigner"),
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks")',
        "PRODUCT_BUNDLE_IDENTIFIER": "org.ormkit.ORMDesignerTests",
        "PRODUCT_NAME": q("$(TARGET_NAME)"),
    },
}


def configs(key, debug, release):
    ids = []
    for name, values in (("Debug", debug), ("Release", release)):
        ids.append(add(oid("cfg", key, name), name, [
            ("isa", "XCBuildConfiguration"), ("buildSettings", settings(values)), ("name", name)]))
    return add(oid("cfglist", key), "Build configuration list for " + key, [
        ("isa", "XCConfigurationList"),
        ("buildConfigurations", names(ids)),
        ("defaultConfigurationIsVisible", "0"),
        ("defaultConfigurationName", "Release"),
    ])


project_id = oid("project")


def dependency(target, on_id, on_name):
    proxy = add(oid("proxy", target, on_name), "PBXContainerItemProxy", [
        ("isa", "PBXContainerItemProxy"),
        ("containerPortal", "%s /* Project object */" % project_id),
        ("proxyType", "1"),
        ("remoteGlobalIDString", on_id),
        ("remoteInfo", on_name),
    ])
    return add(oid("dep", target, on_name), "PBXTargetDependency", [
        ("isa", "PBXTargetDependency"),
        ("target", "%s /* %s */" % (on_id, on_name)),
        ("targetProxy", "%s /* PBXContainerItemProxy */" % proxy),
    ])


def target(name, phases, deps, prod, ptype):
    cfglist = configs(name, TARGET_SETTINGS[name], TARGET_SETTINGS[name])
    return add(oid("target", name), name, [
        ("isa", "PBXNativeTarget"),
        ("buildConfigurationList", '%s /* Build configuration list for PBXNativeTarget "%s" */' % (cfglist, name)),
        ("buildPhases", names(phases)),
        ("buildRules", []),
        ("dependencies", names(deps)),
        ("name", q(name)),
        ("productName", q(name)),
        ("productReference", "%s /* %s */" % (prod, objects[prod][0])),
        ("productType", '"%s"' % ptype),
    ])


t_kit = target("ORMKit", [kit_headers, kit_sources, kit_frameworks], [], p_kit, "com.apple.product-type.framework")
t_kit_tests = target("ORMKitTests", [kit_tests_sources, kit_tests_frameworks],
                     [dependency("ORMKitTests", t_kit, "ORMKit")], p_kit_tests,
                     "com.apple.product-type.bundle.unit-test")
t_tool = target("ormtool", [tool_sources, tool_frameworks], [dependency("ormtool", t_kit, "ORMKit")], p_tool,
                "com.apple.product-type.tool")
t_app = target("ORMDesigner", [app_sources, app_resources, app_frameworks, app_embed],
               [dependency("ORMDesigner", t_kit, "ORMKit")], p_app, "com.apple.product-type.application")
t_app_tests = target("ORMDesignerTests", [app_tests_sources, app_tests_resources, app_tests_frameworks],
                     [dependency("ORMDesignerTests", t_kit, "ORMKit")], p_app_tests,
                     "com.apple.product-type.bundle.unit-test")

cl_project = configs("project", DEBUG, RELEASE)
add(project_id, "Project object", [
    ("isa", "PBXProject"),
    ("attributes", "{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t}"),
    ("buildConfigurationList", '%s /* Build configuration list for PBXProject "%s" */' % (cl_project, PROJECT)),
    ("compatibilityVersion", '"Xcode 14.0"'),
    ("developmentRegion", "en"),
    ("hasScannedForEncodings", "0"),
    ("knownRegions", ["en", "Base"]),
    ("mainGroup", g_main),
    ("productRefGroup", "%s /* Products */" % g_products),
    ("projectDirPath", '""'),
    ("projectRoot", '""'),
    ("targets", names([t_kit, t_kit_tests, t_tool, t_app, t_app_tests])),
])


def value(v, indent):
    if isinstance(v, list):
        if not v:
            return "(\n%s)" % ("\t" * indent)
        inner = "".join("%s%s,\n" % ("\t" * (indent + 1), x) for x in v)
        return "(\n%s%s)" % (inner, "\t" * indent)
    return v


def render():
    by_isa = {}
    for ident, (comment, fields) in objects.items():
        by_isa.setdefault(dict(fields)["isa"], []).append((ident, comment, fields))
    out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;",
           "\tobjects = {"]
    for isa in sorted(by_isa):
        out.append("")
        out.append("/* Begin %s section */" % isa)
        for ident, comment, fields in sorted(by_isa[isa]):
            head = "\t\t%s /* %s */ = {" % (ident, comment) if comment else "\t\t%s = {" % ident
            out.append(head)
            for k, v in fields:
                out.append("\t\t\t%s = %s;" % (k, value(v, 3)))
            out.append("\t\t};")
        out.append("/* End %s section */" % isa)
    out += ["\t};", "\trootObject = %s /* Project object */;" % project_id, "}", ""]
    return "\n".join(out)


proj = os.path.join(ROOT, PROJECT + ".xcodeproj")
os.makedirs(os.path.join(proj, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(proj, "project.pbxproj"), "w") as f:
    f.write(render())

# The workspace: this project and ODataKit's, whose framework ORMKit links.
workspace = os.path.join(ROOT, PROJECT + ".xcworkspace")
os.makedirs(workspace, exist_ok=True)
with open(os.path.join(workspace, "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n'
            '   <FileRef\n      location = "group:%s.xcodeproj">\n   </FileRef>\n'
            '   <FileRef\n      location = "group:%s/ODataKit.xcodeproj">\n   </FileRef>\n'
            '</Workspace>\n' % (PROJECT, ODATAKIT))


def reference(target_id, name, path):
    return ('<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "%s" '
            'BlueprintName = "%s" ReferencedContainer = "container:%s.xcodeproj"></BuildableReference>'
            % (target_id, path, name, PROJECT))


def scheme(name, builds, test=None, run=None):
    entries = "".join('<BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" '
                      'buildForArchiving = "YES" buildForAnalyzing = "YES">%s</BuildActionEntry>' % b for b in builds)
    testables = '<TestableReference skipped = "NO">%s</TestableReference>' % test if test else ""
    runnable = '<BuildableProductRunnable runnableDebuggingMode = "0">%s</BuildableProductRunnable>' % run if run else ""
    xml = ('<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion = "1600" version = "1.7">'
           '<BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">'
           '<BuildActionEntries>%s</BuildActionEntries></BuildAction>'
           '<TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
           'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">'
           '<Testables>%s</Testables></TestAction>'
           '<LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" '
           'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" '
           'useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" '
           'debugServiceExtension = "internal" allowLocationSimulation = "YES">%s</LaunchAction>'
           '<ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" '
           'useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES"></ProfileAction>'
           '<AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>'
           '<ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>'
           '</Scheme>\n') % (entries, testables, runnable)
    with open(os.path.join(proj, "xcshareddata", "xcschemes", name + ".xcscheme"), "w") as f:
        f.write(xml)


kit_ref = reference(t_kit, "ORMKit", "ORMKit.framework")
kit_tests_ref = reference(t_kit_tests, "ORMKitTests", "ORMKitTests.xctest")
tool_ref = reference(t_tool, "ormtool", "ormtool")
app_ref = reference(t_app, "ORMDesigner", "ORMDesigner.app")
app_tests_ref = reference(t_app_tests, "ORMDesignerTests", "ORMDesignerTests.xctest")
scheme("ORMKit", [kit_ref], test=kit_tests_ref)
scheme("ORMKitTests", [kit_tests_ref], test=kit_tests_ref)
scheme("ormtool", [tool_ref], run=tool_ref)
scheme("ORMDesigner", [kit_ref, app_ref], test=app_tests_ref, run=app_ref)
scheme("ORMDesignerTests", [app_tests_ref], test=app_tests_ref)
print("wrote", proj)
