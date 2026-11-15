#    Copyright 2026 Nocilis
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

"""Rules and macros for defining and building VHDL libraries and modules.

This module provides rules for defining VHDL libraries and modules,
managing transitive dependencies, and handling VHDL versioning.
"""

load(
    "//vhdl:providers.bzl",
    "VhdlConfigInfo",
    "VhdlLibraryInfo",
    "VhdlLibraryUnitInfo",
    "VhdlModuleInfo",
    "VhdlNodeInfo",
)
load(
    "//vhdl:utils.bzl",
    "DEFAULT_VHDL_VERSION",
    "VHDL_VERSIONS",
    "WORK_LIB",
    "as_infos",
    "label_str",
    "module_record",
    "node_of",
    "normalize_library_name",
)

def _flag_impl(ctx):
    return [VhdlConfigInfo(value = ctx.build_setting_value)]

vhdl_flag = rule(
    implementation = _flag_impl,
    build_setting = config.string(flag = True),
    doc = "A string flag used to configure VHDL simulation parameters (e.g., simulator type, version).",
)

def vhdl_library_info(
        *,
        label,
        srcs = [],
        data = [],
        library_name = "work",
        vhdl_version = DEFAULT_VHDL_VERSION,
        deps = [],
        merge_work_lib = False,
        modules = []):
    """Builds the VhdlLibraryInfo of a target from its own files and its dependencies.

    This is the supported way to create a VhdlLibraryInfo: vhdl_library and
    vhdl_module use it, and so should any rule that produces VHDL (generated
    wrappers, IP exports, ...) or that must join the VHDL graph. It validates
    the inputs, so the invariants of the provider hold for every producer.

    Args:
        label: Label (or string) of the target, for error messages.
        srcs: List of File: the VHDL sources of this target, in compile order.
            They become one library unit, in `library_name`.
        data: List of File: extra files (memory init, constraints, ...).
        library_name: Library the sources are compiled into. Case-insensitive,
            normalized to lower case; must be a basic VHDL identifier.
            'work' is the toolchain's default library.
        vhdl_version: One of VHDL_VERSIONS.
        deps: List of Target (providing VhdlLibraryInfo) and/or of
            VhdlLibraryInfo.
        merge_work_lib: Set the units in `work` in the
            dependencies under `library_name`. See the module documentation.
        modules: List of VhdlModuleInfo: the entities declared by `srcs`.
            They are stored in the unit, so they follow it when the unit is
            sealed into another library. Requires `srcs`.

    Returns:
        A VhdlLibraryInfo.
    """
    if type(srcs) != "list" or type(data) != "list" or type(modules) != "list":
        fail("Target '{}': srcs, data and modules must be lists".format(label))
    if modules and not srcs:
        fail("Target '{}': modules require srcs: an entity is declared by a source file".format(label))
    for module in modules:
        if not hasattr(module, "entity_name") or not hasattr(module, "generics"):
            fail("Target '{}': modules must be VhdlModuleInfo, got '{}'".format(label, module))
    if vhdl_version not in VHDL_VERSIONS:
        fail("Target '{}': unsupported vhdl_version '{}', expected one of {}".format(label, vhdl_version, VHDL_VERSIONS))

    library_name = normalize_library_name(library_name, label)
    is_work = (library_name == WORK_LIB)

    if merge_work_lib and is_work:
        fail(
            "Cannot set merge_work_lib = True when library_name = 'work' in target '%s'. " % label +
            "The 'work' libraries in deps are already in work. " +
            "Specify an explicit library_name (e.g., 'neorv32_lib') to seal dependencies.",
        )

    dep_infos = as_infos(deps)
    transitive_all = [info.all_libs for info in dep_infos]

    node = VhdlNodeInfo(
        label = label_str(label),
        library_name = library_name,
        vhdl_version = vhdl_version,
        direct_deps = tuple([node_of(i) for i in dep_infos]),
        srcs = tuple([f.short_path for f in srcs]),
        data = tuple([f.short_path for f in data]),
    )

    srcs_depset = depset(srcs, transitive = [i.transitive_srcs for i in dep_infos], order = "postorder")
    data_depset = depset(data, transitive = [i.data for i in dep_infos])

    # Direct sources.
    direct_unit = VhdlLibraryUnitInfo(
        library_name = library_name,
        vhdl_version = vhdl_version,
        sources = depset(srcs, order = "preorder"),
        modules = tuple([module_record(m) for m in modules]),
    ) if srcs else None
    direct_units_list = [direct_unit] if direct_unit else []

    if not merge_work_lib:
        # Work units stay in work and keep bubbling up until a target merge them into a lib.
        return VhdlLibraryInfo(
            node = node,
            all_libs = depset(direct = direct_units_list, transitive = transitive_all, order = "postorder"),
            transitive_srcs = srcs_depset,
            data = data_depset,
        )

    # Merge the work lib.
    dep_units = depset(transitive = transitive_all, order = "postorder").to_list()

    units_libs = []
    for unit in dep_units:
        if unit.library_name == WORK_LIB:
            units_libs.append(VhdlLibraryUnitInfo(
                library_name = library_name,      # Re-mapped to the IP library boundary name
                vhdl_version = unit.vhdl_version, # Retains original standard per unit
                sources = unit.sources,           # Retains the underlying File depset (and its order)
                modules = getattr(unit, "modules", None) or (),  # The modules follow their unit into the library
            ))
        else:
            units_libs.append(unit)

    if direct_unit:
        units_libs.append(direct_unit)

    sealed = depset(units_libs, order = "postorder")

    return VhdlLibraryInfo(
        node = node,
        all_libs = sealed,
        transitive_srcs = srcs_depset,
        data = data_depset,
    )

def merge_vhdl_library_infos(infos):
    """Accumulates several VhdlLibraryInfo into one, without adding sources.

     Args:
        infos: List of Target (providing VhdlLibraryInfo) and/or of VhdlLibraryInfo.

    Returns:
        A VhdlLibraryInfo (the only element of `infos` itself when there is one).
    """
    infos = as_infos(infos)
    if len(infos) == 1:
        return infos[0]
    return VhdlLibraryInfo(
        node = VhdlNodeInfo(
            label = None,
            library_name = None,
            vhdl_version = None,
            direct_deps = tuple([node_of(i) for i in infos]),
            srcs = (),
            data = (),
        ),
        all_libs = depset(transitive = [i.all_libs for i in infos], order = "postorder"),
        transitive_srcs = depset(transitive = [i.transitive_srcs for i in infos]),
        data = depset(transitive = [i.data for i in infos]),
    )

def ordered_segments(units):
    """Compile-order segments of a list of library units.

    Args:
        units: list of VhdlLibraryUnitInfo in dependency order (dependencies
            first), e.g. VhdlLibraryInfo.all_libs.to_list().

    Returns:
        The segments described in `extract_sources`.
    """

    # Only CONSECUTIVE units of the same (library, version) are merged.
    runs = []
    for unit in units:
        key = "%s@%s" % (unit.library_name, unit.vhdl_version)
        if runs and runs[-1]["key"] == key:
            runs[-1]["sources"].append(unit.sources)
        else:
            runs.append({
                "key": key,
                "library_name": unit.library_name,
                "vhdl_version": unit.vhdl_version,
                "sources": [unit.sources],
            })

    return [
        struct(
            id = "%s#%d" % (run["key"], index),
            index = index,
            library_name = run["library_name"],
            vhdl_version = run["vhdl_version"],
            sources = depset(transitive = run["sources"], order = "preorder"),
        )
        for index, run in enumerate(runs)
    ]

def extract_sources(vhdl_info):
    """Compile-order segments of Target(s) providing VhdlLibraryInfo.

    The result is valid for any sequential compiler (ghdl -a, nvc -a, Vivado
    read_vhdl, Yosys, ...): iterate it and compile each segment in turn.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        A list of structs, in compile order, with the fields:
          id: "<library>@<version>#<index>", unique.
          index: position of the segment in the list.
          library_name: lower-case library name ('work' is the default library).
          vhdl_version: VHDL standard version string.
          sources: depset[File] (`preorder`) of the segment's files: units in
              dependency order, the files of a unit in the order of its `srcs`.
    """
    infos = as_infos(vhdl_info)
    return ordered_segments(depset(transitive = [info.all_libs for info in infos], order = "postorder").to_list())

def group_segments(segments):
    """Groups the segments of `extract_sources` by (library, version), one entry each.

    For consumers that handle a library once and compute the compile order
    themselves.

    Args:
        segments: The list returned by `extract_sources`.

    Returns:
        A list of structs, one per (library, version) in order of first
        appearance, with the fields:
          id: "<library>@<version>".
          library_name: lower-case library name.
          vhdl_version: VHDL standard version string.
          sources: depset[File] of the files of all the segments of the group.
        A library that mixes versions yields one entry per version: call
        `add_library` once per library name and use the version per sources.
    """
    groups = {}
    for segment in segments:
        key = "%s@%s" % (segment.library_name, segment.vhdl_version)
        if key not in groups:
            groups[key] = {
                "library_name": segment.library_name,
                "vhdl_version": segment.vhdl_version,
                "sources": [],
            }
        groups[key]["sources"].append(segment.sources)

    return [
        struct(
            id = key,
            library_name = group["library_name"],
            vhdl_version = group["vhdl_version"],
            sources = depset(transitive = group["sources"], order = "preorder"),
        )
        for key, group in groups.items()
    ]

def extract_srcs(vhdl_info):
    """Every VHDL source file of Target(s) providing VhdlLibraryInfo, as one flat depset.

    Use it for action inputs. It carries no library information: for that, use
    `extract_sources`.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        depset[File] of the sources of the targets and of their transitive dependencies.
    """
    return depset(transitive = [info.transitive_srcs for info in as_infos(vhdl_info)])

def extract_data(vhdl_info):
    """Extracts the data files of Target(s) providing VhdlLibraryInfo.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        depset[File] of the `data` files of the targets and of their transitive
        dependencies (memory init files, constraints, templates, ...).
    """
    return depset(transitive = [info.data for info in as_infos(vhdl_info)])

def _default_info(ctx):
    """DefaultInfo of this target: own files, and runfiles of the whole closure."""
    own_files = ctx.files.srcs + ctx.files.data
    runfiles = ctx.runfiles(files = own_files).merge_all(
        [dep[DefaultInfo].default_runfiles for dep in ctx.attr.deps],
    )
    return DefaultInfo(
        files = depset(direct = own_files),
        runfiles = runfiles,
    )

def _vhdl_library_impl(ctx):
    """Implementation of the vhdl_library rule using common logic."""
    vhdl_info = vhdl_library_info(
        label = ctx.label,
        srcs = ctx.files.srcs,
        data = ctx.files.data,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
        deps = ctx.attr.deps,
        merge_work_lib = ctx.attr.merge_work_lib,
    )
    return [
        vhdl_info,
        _default_info(ctx),
    ]

def _vhdl_module_impl(ctx):
    """Implementation of the vhdl_module rule using common logic."""
    module = VhdlModuleInfo(
        entity_name = ctx.attr.entity_name,
        generics = ctx.attr.generics,
        label = ctx.label,
    )
    vhdl_info = vhdl_library_info(
        label = ctx.label,
        srcs = ctx.files.srcs,
        data = ctx.files.data,
        library_name = ctx.attr.library_name,
        vhdl_version = ctx.attr.vhdl_version,
        deps = ctx.attr.deps,
        merge_work_lib = False,
        modules = [module],
    )
    return [
        vhdl_info,
        module,
        _default_info(ctx),
    ]

# Common attributes to avoid repetition
_COMMON_ATTRS = {
    "srcs": attr.label_list(
        allow_files = [".vhd", ".vhdl"],
        doc = "VHDL source files. Compiled in this order within the library.",
    ),
    "library_name": attr.string(
        default = WORK_LIB,
        doc = "Library the sources are compiled into. Case-insensitive; must be a basic VHDL identifier. 'work' is the toolchain's default library.",
    ),
    "vhdl_version": attr.string(
        default = DEFAULT_VHDL_VERSION,
        values = VHDL_VERSIONS,
        doc = "VHDL standard version of the sources.",
    ),
    "deps": attr.label_list(
        providers = [VhdlLibraryInfo],
        doc = "vhdl_library and vhdl_module targets this target depends on.",
    ),
    "data": attr.label_list(
        allow_files = True,
        doc = "Extra files to package (e.g. memory init files, constraints, templates). Propagated transitively: see `extract_data` and the runfiles.",
    ),
}

vhdl_library = rule(
    implementation = _vhdl_library_impl,
    attrs = dict(
        _COMMON_ATTRS,
        merge_work_lib = attr.bool(
            default = False,
            doc = ("Set the units in the default library (`work`) of the transitive deps under `library_name`, " +
                   "so that they are isolated from other " +
                   "implementations. Meant for the top-level IP boundary. Requires an explicit " +
                   "`library_name` other than 'work'."),
        ),
    ),
    doc = "Collects VHDL source files into a logical library.",
)

vhdl_module = rule(
    implementation = _vhdl_module_impl,
    attrs = dict(
        _COMMON_ATTRS,
        srcs = attr.label_list(
            allow_files = [".vhd", ".vhdl"],
            allow_empty = False,
            mandatory = True,
            doc = "VHDL source files declaring the entity. Compiled in this order within the library.",
        ),
        entity_name = attr.string(
            mandatory = True,
            doc = "Name of the VHDL entity.",
        ),
        generics = attr.string_dict(
            doc = "Generic values of the entity.",
        ),
    ),
    doc = "Defines a VHDL entity and its generics. Its dependencies, sources and library are in its VhdlLibraryInfo.",
)
