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
VhdlLibraryInfo = provider(
    doc = "Provider containing VHDL library structures and their sources.",
    fields = {
        "vhdl_libs": "depset[struct(library: str, sources: depset[File], vhdl_version: str)]",
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

    current_lib = library_name
    transitive_deps = []
    merged_lib = []

    for dep in deps:
        if VhdlLibraryInfo in dep:
            info = dep[VhdlLibraryInfo]

            # check if we need to modify the work lib name
            if merge_work_lib:
                for lib_struct in info.vhdl_libs.to_list():
                    if lib_struct.library == "work":
                        merged_lib.append(struct(
                            library = current_lib,
                            sources = lib_struct.sources,
                            vhdl_version = lib_struct.vhdl_version,
                        ))
                    else:
                        merged_lib.append(lib_struct)
            else:
                # accumulate the transitive deps
                transitive_deps.append(info.vhdl_libs)

    # manage direct sources
    direct_sources = struct(
        library = current_lib,
        sources = srcs if type(srcs) == "depset" else depset(srcs),
        vhdl_version = vhdl_version,
    )

    return VhdlLibraryInfo(
        vhdl_libs = depset(
            [direct_sources] + merged_lib,
            transitive = transitive_deps,
        ),
    )

def extract_sources(vhdl_info):
    """
    Extracts and groups VHDL sources by library from a VhdlLibraryInfo provider, Target, or list thereof.

    Args:
        vhdl_info: A VhdlLibraryInfo provider, Target providing VhdlLibraryInfo, or a list thereof.

    Returns:
        A list of structs with:
          - id: unique key formatted as "<library_name>@<vhdl_version>"
          - library_name: name of the VHDL library
          - sources: depset of File objects belonging to this library
          - vhdl_version: VHDL standard version string
    """
    if type(vhdl_info) == "list":
        items = vhdl_info
    else:
        items = [vhdl_info]

    grouped = {}

    for item in items:
        if hasattr(item, "vhdl_libs"):
            info = item
        elif VhdlLibraryInfo in item:
            info = item[VhdlLibraryInfo]
        else:
            fail("Expected VhdlLibraryInfo or Target providing VhdlLibraryInfo, got {}".format(type(item)))

        # Accumulate depsets into their unique vhdl library
        for entry in info.vhdl_libs.to_list():
            lib_name = entry.library
            version = getattr(entry, "vhdl_version", None)
            key = "%s@%s" % (lib_name, version or "")

            if key not in grouped:
                grouped[key] = {
                    "library_name": lib_name,
                    "vhdl_version": version,
                    "depsets": [],
                }
            grouped[key]["depsets"].append(entry.sources)

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




