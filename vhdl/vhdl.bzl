#    Copyright 2026 Nocilis

#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at

#        http://www.apache.org/licenses/LICENSE-2.0

#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

"""
# Core VHDL rules for gateweavers_rules_vhdl.


This module provides rules for defining VHDL libraries and modules,
managing transitive dependencies, and handling VHDL versioning.
"""

load("//simulator:transition.bzl", "vhdl_sim_config_transition")
load("//simulator:ghdl.bzl", "map_vhdl_version_to_ghdl_flag")

# Constants for VHDL versioning
VhdlConfigInfo = provider(
    doc = "Provider for VHDL configuration flags.",
    fields = {"value": "The current value of the flag."}
)

def _flag_impl(ctx):
    return VhdlConfigInfo(value = ctx.build_setting_value)

vhdl_flag = rule(
    implementation = _flag_impl,
    build_setting = config.string(flag = True),
    doc = "A string flag used to configure VHDL simulation parameters (e.g., simulator type, version).",
)

VHDL_VERSIONS = ["87", "93", "2008", "2019"]
DEFAULT_VHDL_VERSION = "2008"
RESERVED_LIB_NAMES = ["std","ieee"]

def _validate_library_name(name):
    if name.lower() in RESERVED_LIB_NAMES:
        fail("Library name '{}' is reserved and cannot be used.".format(name))

# Provider for library management
VhdlLibraryUnitInfo = provider(
    doc = "Atomic vhdl library unit bound to a (library_name, vhdl_version) pair.",
    fields = {
        "library_name": "Target logical library name (str)",
        "vhdl_version": "VHDL standard version string (e.g. '93', '2008')",
        "sources": "depset[File] of source files",
    },
)

VhdlLibraryInfo = provider(
    doc = "Provider containing accumulated VHDL library provider (VhdlLibraryUnitInfo).",
    fields = {
        "work_libs": "depset[VhdlLibraryUnitInfo] of default 'work' lib",
        "vhdl_libs": "depset[VhdlLibraryUnitInfo] of named library unit",
        "all_libs": "depset[VhdlLibraryUnitInfo] of all library units in topological postorder",
    },
)

# Provider for specific VHDL module/entity details
VhdlModuleInfo = provider(
    doc = "Provider containing VHDL entity and generic information.",
    fields = {
        "entity_name": "The name of the VHDL entity.",
        "generics": "A dictionary of generic values.",
        "vhdl_version": "The VHDL version used by this module.",
        "dep_entities": "A depset of all entity names this module and its dependencies use."
    }
)

def _process_vhdl_library(ctx, srcs = None, library_name = None, vhdl_version = None, deps = None, merge_work_lib = None):
    """
    Aggregates direct VHDL sources and transitive dependencies into a VhdlLibraryInfo provider.

    Args:
        ctx: The rule context.
        srcs: List of source files.
        library_name: Target library name.
        vhdl_version: VHDL standard version.
        deps: Dependencies.
        merge_work_lib: Whether to merge the 'work' library from dependencies.

    Returns:
        A VhdlLibraryInfo provider populated with aggregated library depsets.
    """
    if srcs == None:
        srcs = getattr(ctx.files, "srcs", [])
    if library_name == None:
        library_name = getattr(ctx.attr, "library_name", "work")
    if vhdl_version == None:
        vhdl_version = getattr(ctx.attr, "vhdl_version", DEFAULT_VHDL_VERSION)
    if deps == None:
        deps = getattr(ctx.attr, "deps", [])
    if merge_work_lib == None:
        merge_work_lib = getattr(ctx.attr, "merge_work_lib", getattr(ctx.attr, "merge_lib", False))

    is_work = (library_name == "work")

    if merge_work_lib and is_work:
        fail(
            "Cannot set merge_work_lib = True when library_name = 'work' in target '%s'. " % ctx.label +
            "The 'work' libraries in deps are already in work." +
            "Specify an explicit library_name (e.g., 'neorv32_lib') to seal dependencies."
        )

    # Aggregate incoming depsets
    transitive_work = []
    transitive_libs = []
    transitive_all = []
    for dep in deps:
        if VhdlLibraryInfo in dep:
            info = dep[VhdlLibraryInfo]
            transitive_work.append(info.work_libs)
            transitive_libs.append(info.vhdl_libs)
            transitive_all.append(info.all_libs)
        else:
            fail("Dependency '{}' does not provide VhdlLibraryInfo.".format(getattr(dep, "label", dep)))

    # manage direct sources
    direct_unit = VhdlLibraryUnitInfo(
        library_name = library_name,
        vhdl_version = vhdl_version,
        sources = depset(srcs),
    ) if srcs else None

    direct_units_list = [direct_unit] if direct_unit else []

    # Check if the work lib should not be merged into the current lib
    if not merge_work_lib:
        if is_work:
            work_depset = depset(direct = direct_units_list, transitive = transitive_work, order = "postorder")
            lib_depset = depset(transitive = transitive_libs, order = "postorder")
        else:
            work_depset = depset(transitive = transitive_work, order = "postorder")
            lib_depset = depset(direct = direct_units_list, transitive = transitive_libs, order = "postorder")
        all_depset = depset(direct = direct_units_list, transitive = transitive_all, order = "postorder")
        return VhdlLibraryInfo(
            work_libs = work_depset,
            vhdl_libs = lib_depset,
            all_libs = all_depset,
        )

    # Merge the work lib
    # list the current work libs. Can be costly if too many targets try to merge the work libs.
    work_libs = depset(transitive = transitive_work, order = "postorder").to_list()

    libs_units = []
    for unit in work_libs:
        libs_units.append(VhdlLibraryUnitInfo(
            library_name = library_name,      # Re-mapped to IP library boundary name
            vhdl_version = unit.vhdl_version, # Retains original standard per bucket
            sources = unit.sources,           # Retains underlying unflattened File depset
        ))

    if direct_unit:
        libs_units.append(direct_unit)

    return VhdlLibraryInfo(
        work_libs = depset(order = "postorder"), # Reset work lib for upstream targets
        vhdl_libs = depset(
            direct = libs_units,
            transitive = transitive_libs,
            order = "postorder",
        ),
        all_libs = depset(
            direct = libs_units,
            transitive = transitive_libs,
            order = "postorder",
        ),
    )

def _unit_files(unit):
    """Files of a library unit, in the order of the `srcs` that declared them."""
    srcs = unit.sources
    return srcs.to_list() if type(srcs) == "depset" else list(srcs)

def _as_infos(vhdl_info):
    items = vhdl_info if type(vhdl_info) == "list" else [vhdl_info]
    infos = []
    for item in items:
        if VhdlLibraryInfo in item:
            infos.append(item[VhdlLibraryInfo])
        else:
            fail("Expected Target providing VhdlLibraryInfo, got {}".format(type(item)))
    return infos

def _extract_grouped(infos):
    grouped = {}
    for info in infos:
        # Accumulate depsets into their unique vhdl library
        for entry in info.all_libs.to_list():
            lib_name = entry.library_name
            version = entry.vhdl_version
            key = "%s@%s" % (lib_name, version or "")

            if key not in grouped:
                grouped[key] = {
                    "library_name": lib_name,
                    "vhdl_version": version,
                    "depsets": [],
                }
            srcs = entry.sources
            if type(srcs) == "depset":
                grouped[key]["depsets"].append(srcs)
            else:
                grouped[key]["depsets"].append(depset(srcs))

    # Merge the depsets of each lib and return a list of library structs
    result = []
    for key, item in grouped.items():
        result.append(struct(
            id = key,
            library_name = item["library_name"],
            sources = depset(transitive = item["depsets"]),
            vhdl_version = item["vhdl_version"],
        ))
    return result

def ordered_segments(units):
    """Compile-order segments of a list of library units.

    Args:
        units: list of VhdlLibraryUnitInfo in dependency order (dependencies
            first), e.g. VhdlLibraryInfo.all_libs.to_list().

    Returns:
        The segments described in `extract_sources(ordered = True)`.
    """

    # Only CONSECUTIVE units of the same (library, version) are merged. Merging
    # the others would make the order impossible: with ip_a -> ip_b -> ip_a
    # (a unit of ip_a uses ip_b, which uses another unit of ip_a), the group
    # ip_a needs ip_b first and ip_b needs ip_a first.
    segments = []
    for unit in units:
        key = "%s@%s" % (unit.library_name, unit.vhdl_version or "")
        if segments and segments[-1]["key"] == key:
            seg = segments[-1]
        else:
            seg = {
                "key": key,
                "library_name": unit.library_name,
                "vhdl_version": unit.vhdl_version,
                "files": [],
                "seen": {},
            }
            segments.append(seg)
        for f in _unit_files(unit):
            if f.path not in seg["seen"]:
                seg["seen"][f.path] = True
                seg["files"].append(f)

    result = []
    for index, seg in enumerate(segments):
        result.append(struct(
            id = "%s#%d" % (seg["key"], index),
            key = seg["key"],
            index = index,
            library_name = seg["library_name"],
            vhdl_version = seg["vhdl_version"],
            files = seg["files"],
            sources = depset(seg["files"]),
        ))
    return result

def _extract_ordered(infos):
    # One postorder over all the targets: dependencies first, shared units once.
    return ordered_segments(depset(transitive = [info.all_libs for info in infos], order = "postorder").to_list())

def extract_sources(vhdl_info, ordered = False):
    """Extracts VHDL sources by library from Target(s) providing VhdlLibraryInfo.

    Two modes, depending on what the consumer does with the result.

    ordered = False (default, unchanged): one struct per (library, version).
      Fields: id ("<library>@<version>"), library_name, vhdl_version and
      sources (depset of File).
      The order BETWEEN libraries is lost: when libraries interleave (a unit of
      ip_a uses ip_b, which uses another unit of ip_a) no order of the groups is
      valid. Only for consumers that compute the compile order themselves
      (VUnit, `ghdl -i` + `ghdl -m`, ...).

    ordered = True: the list of segments to compile in sequence, valid for any
      sequential compiler (ghdl -a, nvc -a, Yosys, ...). A segment is a run of
      consecutive units (dependencies first) with the same (library, version),
      so a library can appear several times.
      Fields: id ("<library>@<version>#<index>", unique), key, index,
      library_name, vhdl_version, files (ordered list of File: units in
      dependency order, files of a unit in the order of its `srcs`) and
      sources (depset of the same files).

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, or a list thereof.
        ordered: Return the compile-order segments instead of the groups.

    Returns:
        A list of structs, see above.
    """
    infos = _as_infos(vhdl_info)
    if ordered:
        return _extract_ordered(infos)
    return _extract_grouped(infos)

def _vhdl_library_impl(ctx):
    """
    Implementation of the vhdl_library rule using common logic.
    """
    _validate_library_name(ctx.attr.library_name)
    vhdl_info = _process_vhdl_library(
        ctx = ctx,
        srcs = ctx.files.srcs,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
        deps = ctx.attr.deps,
        merge_work_lib = ctx.attr.merge_work_lib,
    )

    all_files = depset(direct = ctx.files.srcs + ctx.files.data)
    return [
        vhdl_info,
        DefaultInfo(files = all_files),
    ]

def _vhdl_module_impl(ctx):
    """
    Implementation of the vhdl_module rule using common logic and transitive depset tracking.
    """

    _validate_library_name(ctx.attr.library_name)
    vhdl_info = _process_vhdl_library(
        ctx = ctx,
        srcs = ctx.files.srcs,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
        deps = ctx.attr.deps,
        merge_work_lib = False,
    )

    transitive_entities = []
    for dep in ctx.attr.deps:
        if VhdlModuleInfo in dep:
            transitive_entities.append(dep[VhdlModuleInfo].dep_entities)

    dep_entities_depset = depset(
        direct = [ctx.attr.entity_name],
        transitive = transitive_entities,
    )

    all_files = depset(direct = ctx.files.srcs + ctx.files.data)

    return [
        vhdl_info,
        VhdlModuleInfo(
            entity_name = ctx.attr.entity_name,
            generics = ctx.attr.generics,
            vhdl_version = ctx.attr.vhdl_version,
            dep_entities = dep_entities_depset,
        ),
        DefaultInfo(files = all_files),
    ]

# Common attributes to avoid repetition
_COMMON_ATTRS = {
    "srcs": attr.label_list(allow_files = [".vhd"]),
    "library_name": attr.string(default = "work"),
    "vhdl_version": attr.string(default = DEFAULT_VHDL_VERSION, values = VHDL_VERSIONS),
    "deps": attr.label_list(providers = [VhdlLibraryInfo]),
    "data": attr.label_list(
        allow_files = True,
        doc = "Extra files to package (e.g. constraints, templates) included in the DefaultInfo provider.",
    ),
}

vhdl_library = rule(
    implementation = _vhdl_library_impl,
    attrs = dict(_COMMON_ATTRS,
        merge_work_lib = attr.bool(default = False),
    ),
    doc = "Collects VHDL source files into a logical library.",
)

vhdl_module = rule(
    implementation = _vhdl_module_impl,
    attrs = dict(_COMMON_ATTRS,
        entity_name = attr.string(mandatory = True,),
        generics = attr.string_dict(),
    ),
    doc = "Defines a VHDL entity with its generics and transitive dependencies.",
)




