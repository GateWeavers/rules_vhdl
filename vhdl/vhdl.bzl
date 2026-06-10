"""
# Core VHDL rules for gateweaver_rules_vhdl.


This module provides rules for defining VHDL libraries and modules,
managing transitive dependencies, and handling VHDL versioning.
"""

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
        "libraries": "A dictionary mapping 'lib_name@version' to a struct(sources, library_name, vhdl_version)."
    }
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

def _process_vhdl_libraries(ctx, srcs, library_name, vhdl_version, deps, merge_work_lib):
    """
    Common logic to merge libraries and organize sources.
    
    Args:
        ctx: The rule context.
        srcs: List of source files.
        library_name: Target library name.
        vhdl_version: VHDL standard version.
        deps: Dependencies.
        merge_work_lib: Whether to merge the 'work' library from dependencies.
        
    Returns:
        A dictionary of library structures.
    """
    merged_sources_map = {}

    # 1. Collect transitive library info from dependencies
    for dep in deps:
        if VhdlLibraryInfo in dep:
            for key, info in dep[VhdlLibraryInfo].libraries.items():
                if key not in merged_sources_map:
                    merged_sources_map[key] = []
                merged_sources_map[key].append(info.sources)

    # 2. Add current target sources to the specified library
    current_key = "{}@{}".format(library_name, vhdl_version)
    if current_key not in merged_sources_map:
        merged_sources_map[current_key] = []
    merged_sources_map[current_key].append(depset(srcs))

    # 3. Handle work merging logic
    if merge_work_lib and library_name != "work":
        work_key = "work@{}".format(vhdl_version)
        if work_key in merged_sources_map:
            merged_sources_map[current_key].extend(merged_sources_map[work_key])

    # 4. Finalize the structures
    final_libraries = {}
    for key, depset_list in merged_sources_map.items():
        lib_name, ver = key.split("@")
        final_libraries[key] = struct(
            sources = depset(transitive = depset_list),
            library_name = lib_name,
            vhdl_version = ver
        )
    
    return final_libraries

def _vhdl_library_impl(ctx):
    """
    Implementation of the vhdl_library rule using common logic.
    """
    _validate_library_name(ctx.attr.library_name)
    libs = _process_vhdl_libraries(
        ctx = ctx,
        srcs = ctx.files.srcs,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
        deps = ctx.attr.deps,
        merge_work_lib = ctx.attr.merge_work_lib
    )

    all_files = depset(transitive = [l.sources for l in libs.values()])
    return [
        VhdlLibraryInfo(libraries = libs),
        DefaultInfo(files = all_files)
    ]

def _vhdl_module_impl(ctx):
    """
    Implementation of the vhdl_module rule using common logic and transitive depset tracking.
    """

    _validate_library_name(ctx.attr.library_name)
    libs = _process_vhdl_libraries(
        ctx = ctx,
        srcs = ctx.files.srcs,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
        deps = ctx.attr.deps,
        merge_work_lib = False
    )

    transitive_entities = []
    for dep in ctx.attr.deps:
        if VhdlModuleInfo in dep:
            transitive_entities.append(dep[VhdlModuleInfo].dep_entities)

    dep_entities_depset = depset(
        direct = [ctx.attr.entity_name],
        transitive = transitive_entities
    )

    all_files = depset(transitive = [l.sources for l in libs.values()])

    return [
        VhdlLibraryInfo(libraries = libs),
        VhdlModuleInfo(
            entity_name = ctx.attr.entity_name,
            generics = ctx.attr.generics,
            vhdl_version = ctx.attr.vhdl_version,
            dep_entities = dep_entities_depset
        ),
        DefaultInfo(files = all_files)
    ]

# Common attributes to avoid repetition
_COMMON_ATTRS = {
    "srcs": attr.label_list(allow_files = [".vhd"]),
    "library_name": attr.string(default = "work"),
    "vhdl_version": attr.string(default = DEFAULT_VHDL_VERSION, values = VHDL_VERSIONS),
    "deps": attr.label_list(providers = [VhdlLibraryInfo]),
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
