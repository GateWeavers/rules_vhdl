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

## Dependency graph

Every VhdlLibraryInfo carries a `node` (VhdlNodeInfo: label, library, version,
direct deps). `extract_graph`, `graph_tree` and `graph_dot` turn it into a view
limited to modules, and the `vhdl_graph` rule writes it to files. Each node
also knows its source and data files (`include_files`).

The same source may legitimately appear twice (once sealed in `ip_lib`, once in
the default library when a top-level target also depends on it directly).
"""

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

# Constants for VHDL versioning and library names
VHDL_VERSIONS = ["87", "93", "2008", "2019"]
DEFAULT_VHDL_VERSION = "2008"
RESERVED_LIB_NAMES = ["std", "ieee"]

# Name of the default library as seen by the rules (before sealing).
_WORK = "work"

_LETTERS = "abcdefghijklmnopqrstuvwxyz"
_DIGITS = "0123456789"

def _normalize_library_name(name, label):
    """Validates a library name and returns it normalized.

    VHDL identifiers are case-insensitive, so the name is lower-cased: `Work`
    and `work` are the same library. A basic identifier is required: it starts
    with a letter, then letters, digits and single underscores, and it does not
    end with an underscore.

    Args:
        name: The `library_name` attribute value.
        label: Label of the target, for error messages.

    Returns:
        The lower-case library name.
    """
    lname = name.lower()
    if not lname:
        fail("Target '{}': library_name cannot be empty.".format(label))
    if lname in RESERVED_LIB_NAMES:
        fail("Library name '{}' is reserved and cannot be used (target '{}').".format(name, label))
    if lname[0] not in _LETTERS:
        fail("Target '{}': library name '{}' must start with a letter.".format(label, name))
    previous = ""
    for c in lname.elems():
        if c == "_":
            if previous == "_":
                fail("Target '{}': library name '{}' cannot contain consecutive underscores.".format(label, name))
        elif c not in _LETTERS and c not in _DIGITS:
            fail("Target '{}': library name '{}' contains the invalid character '{}'.".format(label, name, c))
        previous = c
    if lname[-1] == "_":
        fail("Target '{}': library name '{}' cannot end with an underscore.".format(label, name))
    return lname

# Provider for library management
VhdlLibraryUnitInfo = provider(
    doc = """Atomic vhdl library unit bound to a (library_name, vhdl_version) pair.""",
    fields = {
        "library_name": "Target logical library name (str, lower case)",
        "vhdl_version": "VHDL standard version string (e.g. '93', '2008')",
        "sources": "depset[File] of source files, in `preorder` so they keep the order of the `srcs` that declared them",
        "modules": "tuple of the entities declared by the vhdl_module that produced this unit (empty for a plain library): structs (entity_name, generics as a tuple of (name, value) pairs, label). Read them with `extract_modules`.",
    },
)

VhdlNodeInfo = provider(
    doc = """Node of the VHDL dependency graph: what a target declares, and who it depends on.

    It is the data behind `extract_graph`, `graph_tree` and `graph_dot`. A
    virtual node (label None) stands for an accumulation of several infos, see
    `merge_vhdl_library_infos`: it has no identity of its own, and the graph
    looks through it.
    """,
    fields = {
        "label": "str: label of the target (e.g. '//axis:fifo'), None for a virtual node",
        "library_name": "str: library declared by the target (lower case), None for a virtual node",
        "vhdl_version": "str: VHDL standard declared by the target, None for a virtual node",
        "direct_deps": "tuple[VhdlNodeInfo]: nodes of the direct dependencies",
        "srcs": "tuple[str]: short_path of the source files of the target (empty for a virtual node)",
        "data": "tuple[str]: short_path of the data files of the target (empty for a virtual node)",
    },
)

VhdlLibraryInfo = provider(
    doc = "Accumulated VHDL library units (VhdlLibraryUnitInfo) of a target and of its transitive dependencies.",
    fields = {
        "node": "VhdlNodeInfo: this target in the dependency graph. Read it with `extract_graph`.",
        "all_libs": "depset[VhdlLibraryUnitInfo] of all library units, in topological postorder (dependencies first). A unit of the default library has library_name 'work'.",
        "transitive_srcs": "depset[File] of every source file of this target and its transitive dependencies (flat, without library information): use it for action inputs",
        "data": "depset[File] of the data files of this target and its transitive dependencies",
    },
)

# Provider for specific VHDL module/entity details
VhdlModuleInfo = provider(
    doc = """Describes the VHDL entity declared by a vhdl_module target.

    It holds what is intrinsic to the entity. The sources, the library, the
    version and the dependencies are in the VhdlLibraryInfo of the same target.
    """,
    fields = {
        "entity_name": "The name of the VHDL entity.",
        "generics": "A dictionary of generic values.",
        "label": "Label of the vhdl_module target, to tell apart several modules of the same entity (e.g. different generics).",
    },
)

def _module_record(module):
    return struct(
        entity_name = module.entity_name,
        generics = tuple(sorted(module.generics.items())),
        label = module.label,
    )

def _label_str(label):
    """'@repo//package:name' (or '//package:name' in the main repository) from a Label or a string."""
    if type(label) == "string":
        return label
    repo = label.workspace_name
    return "%s//%s:%s" % (("@" + repo) if repo else "", label.package, label.name)

def _node_of(info):
    """The graph node of a VhdlLibraryInfo; infos built without one are an empty virtual node."""
    node = getattr(info, "node", None)
    if node != None:
        return node
    return VhdlNodeInfo(label = None, library_name = None, vhdl_version = None, direct_deps = (), srcs = (), data = ())

def _as_infos(vhdl_info):
    """Normalizes Target(s) and/or VhdlLibraryInfo value(s) to a list of VhdlLibraryInfo."""
    items = vhdl_info if type(vhdl_info) == "list" else [vhdl_info]
    infos = []
    for item in items:
        if type(item) == "Target":
            if VhdlLibraryInfo not in item:
                fail("Target '{}' does not provide VhdlLibraryInfo".format(item.label))
            infos.append(item[VhdlLibraryInfo])
        elif hasattr(item, "all_libs") and hasattr(item, "transitive_srcs"):
            infos.append(item)
        else:
            fail("Expected a Target providing VhdlLibraryInfo or a VhdlLibraryInfo, got '{}'".format(item))
    return infos

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

    library_name = _normalize_library_name(library_name, label)
    is_work = (library_name == _WORK)

    if merge_work_lib and is_work:
        fail(
            "Cannot set merge_work_lib = True when library_name = 'work' in target '%s'. " % label +
            "The 'work' libraries in deps are already in work. " +
            "Specify an explicit library_name (e.g., 'neorv32_lib') to seal dependencies.",
        )

    dep_infos = _as_infos(deps)
    transitive_all = [info.all_libs for info in dep_infos]

    node = VhdlNodeInfo(
        label = _label_str(label),
        library_name = library_name,
        vhdl_version = vhdl_version,
        direct_deps = tuple([_node_of(info) for info in dep_infos]),
        srcs = tuple([f.short_path for f in srcs]),
        data = tuple([f.short_path for f in data]),
    )

    srcs_depset = depset(srcs, transitive = [info.transitive_srcs for info in dep_infos])
    data_depset = depset(data, transitive = [info.data for info in dep_infos])

    # Direct sources.
    direct_unit = VhdlLibraryUnitInfo(
        library_name = library_name,
        vhdl_version = vhdl_version,
        sources = depset(srcs, order = "preorder"),
        modules = tuple([_module_record(m) for m in modules]),
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
        if unit.library_name == _WORK:
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
    infos = _as_infos(infos)
    if len(infos) == 1:
        return infos[0]
    return VhdlLibraryInfo(
        node = VhdlNodeInfo(
            label = None,
            library_name = None,
            vhdl_version = None,
            direct_deps = tuple([_node_of(i) for i in infos]),
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
    infos = _as_infos(vhdl_info)
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

def extract_modules(vhdl_info):
    """The modules (vhdl_module entities) of Target(s) providing VhdlLibraryInfo.

    Each module comes with the library it is compiled into.
    The result is in compile order, and a module reachable through a
    vhdl_library dependency is listed like any other. The entities used by a
    module are the entries before it.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        A list of structs with the fields entity_name, generics (dict),
        label (of the vhdl_module), library_name and vhdl_version.
    """
    units = depset(transitive = [info.all_libs for info in _as_infos(vhdl_info)], order = "postorder").to_list()
    return [
        struct(
            entity_name = module.entity_name,
            generics = dict(module.generics),
            label = module.label,
            library_name = unit.library_name,
            vhdl_version = unit.vhdl_version,
        )
        for unit in units
        for module in (getattr(unit, "modules", None) or ())
    ]

def find_module(vhdl_info, entity_name, library_name = None):
    """Finds one module by entity name, optionally in one library.

    VHDL names are case-insensitive. Several modules can share an entity name
    (different generics, or a default-library copy next to a sealed one): the
    lookup fails when it is ambiguous, and the message lists the candidates.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.
        entity_name: Entity name to look for.
        library_name: Restrict the search to this library.

    Returns:
        A struct as returned by `extract_modules`.
    """
    entity = entity_name.lower()
    library = library_name.lower() if library_name else None
    found = [
        module
        for module in extract_modules(vhdl_info)
        if module.entity_name.lower() == entity and (library == None or module.library_name == library)
    ]
    if not found:
        fail("No module with entity '{}'{} in the VHDL dependencies.".format(
            entity_name,
            " in library '{}'".format(library_name) if library_name else "",
        ))
    if len(found) > 1:
        fail("Entity '{}' is ambiguous: {}. Pass library_name, or depend on one module.".format(
            entity_name,
            ", ".join(["{} (library '{}')".format(m.label, m.library_name) for m in found]),
        ))
    return found[0]

def extract_srcs(vhdl_info):
    """Every VHDL source file of Target(s) providing VhdlLibraryInfo, as one flat depset.

    Use it for action inputs. It carries no library information: for that, use
    `extract_sources`.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        depset[File] of the sources of the targets and of their transitive dependencies.
    """
    return depset(transitive = [info.transitive_srcs for info in _as_infos(vhdl_info)])

def extract_data(vhdl_info):
    """Extracts the data files of Target(s) providing VhdlLibraryInfo.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        depset[File] of the `data` files of the targets and of their transitive
        dependencies (memory init files, constraints, templates, ...).
    """
    return depset(transitive = [info.data for info in _as_infos(vhdl_info)])

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
    """
    Implementation of the vhdl_library rule using common logic.
    """
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
    """
    Implementation of the vhdl_module rule using common logic.
    """
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
        default = _WORK,
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

# ---------------------------------------------------------------------------
# Dependency graph (debug view, like `bazel query --output graph`, VHDL aware)
# ---------------------------------------------------------------------------

_MAX_STEPS = 1000000  # Starlark has no recursion nor `while`: bounded iterative walks.

def _real_deps(node):
    """The labelled nodes among the direct deps of `node`; virtual nodes are looked through."""
    deps = []
    seen = {}
    stack = list(reversed(node.direct_deps))
    for _ in range(_MAX_STEPS):
        if not stack:
            break
        dep = stack.pop()
        if dep.label == None:
            stack.extend(reversed(dep.direct_deps))
        elif dep.label not in seen:
            seen[dep.label] = True
            deps.append(dep)
    if stack:
        fail("The VHDL dependency graph is too large to walk.")
    return deps

def _walk(roots, expand):
    """Post-order walk (dependencies first) over the labelled nodes below `roots`, each once.

    Args:
        roots: list of VhdlNodeInfo.
        expand: dict label -> bool saying whether the deps of a node are
            followed, or None to follow them all.

    Returns:
        (list of nodes, dict label -> list of the nodes it depends on).
    """
    order = []
    deps_of = {}
    seen = {}
    stack = [(node, False) for node in reversed(roots)]
    for _ in range(_MAX_STEPS):
        if not stack:
            break
        node, done = stack.pop()
        if node.label == None:
            stack.extend([(dep, False) for dep in reversed(node.direct_deps)])
            continue
        if done:
            order.append(node)
            continue
        if node.label in seen:
            continue
        seen[node.label] = True
        children = _real_deps(node) if (expand == None or expand[node.label]) else []
        deps_of[node.label] = children
        stack.append((node, True))
        stack.extend([(dep, False) for dep in reversed(children)])
    if stack:
        fail("The VHDL dependency graph is too large to walk.")
    return order, deps_of

def extract_graph(vhdl_info):
    """The dependency graph of Target(s) providing VhdlLibraryInfo, limited to modules.

    Shown: the modules (vhdl_module), the libraries that contain modules (a
    module somewhere below them), and the libraries without any module, only as
    a leaf with their name and version (they are not developed). Virtual nodes
    (accumulations of infos) are looked through.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.

    Returns:
        struct(nodes, roots). `nodes` is a list in dependency order (dependencies
        first) of structs with the fields:
          label: str, e.g. '//axis:fifo'.
          kind: 'module' or 'library'.
          entity_name: entity of a module, None for a library.
          generics: dict of the generics of a module.
          library_name: library declared by the target.
          library_names: tuple of the libraries a module is compiled into, after
              sealing (several when a default-library module is also sealed
              elsewhere); (library_name,) for a library.
          vhdl_version: VHDL standard.
          srcs: tuple of the short_path of the source files of the target.
          data: tuple of the short_path of the data files of the target.
          deps: tuple of the labels of the direct deps that are shown.
          expanded: False for a library without any module, which is not developed.
        `roots` is the tuple of the labels of the roots.
    """
    infos = _as_infos(vhdl_info)
    roots = [_node_of(info) for info in infos]

    # The modules, with the library they are compiled into after sealing.
    modules = {}
    for module in extract_modules(infos):
        record = modules.setdefault(_label_str(module.label), {"module": module, "libraries": []})
        if module.library_name not in record["libraries"]:
            record["libraries"].append(module.library_name)

    # Which nodes have a module in their closure (dependencies come first).
    everything, all_deps = _walk(roots, None)
    has_modules = {}
    for node in everything:
        has_modules[node.label] = (node.label in modules) or any([has_modules[dep.label] for dep in all_deps[node.label]])

    # The nodes that are shown: libraries without modules are leaves.
    nodes, deps_of = _walk(roots, has_modules)
    shown = []
    for node in nodes:
        record = modules.get(node.label)
        deps = tuple([dep.label for dep in deps_of[node.label]])
        if record:
            module = record["module"]
            shown.append(struct(
                label = node.label,
                kind = "module",
                entity_name = module.entity_name,
                generics = module.generics,
                library_name = node.library_name,
                library_names = tuple(sorted(record["libraries"])),
                vhdl_version = module.vhdl_version,
                srcs = node.srcs,
                data = node.data,
                deps = deps,
                expanded = True,
            ))
        else:
            shown.append(struct(
                label = node.label,
                kind = "library",
                entity_name = None,
                generics = {},
                library_name = node.library_name,
                library_names = (node.library_name,),
                vhdl_version = node.vhdl_version,
                srcs = node.srcs,
                data = node.data,
                deps = deps,
                expanded = has_modules[node.label],
            ))

    virtual_root = VhdlNodeInfo(label = None, library_name = None, vhdl_version = None, direct_deps = tuple(roots), srcs = (), data = ())
    return struct(
        nodes = shown,
        roots = tuple([node.label for node in _real_deps(virtual_root)]),
    )

def _node_text(node):
    if node.kind == "module":
        generics = ""
        if node.generics:
            generics = "(%s)" % ", ".join(["%s=%s" % kv for kv in sorted(node.generics.items())])
        return "module %s%s, lib %s %s" % (node.entity_name, generics, ",".join(node.library_names), node.vhdl_version)
    return "lib %s %s" % (node.library_name, node.vhdl_version)

def graph_tree(vhdl_info, include_files = False):
    """The dependency graph of `extract_graph` as an indented tree (text).

    A node already shown is not developed again: it is marked `(*)`.

    With `include_files`, the files of a node are listed under it, before its
    dependencies: `·` for a source file, `◆` for a data file.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.
        include_files: List the source and data files of each node.

    Returns:
        str, one line per node, ending with a newline.
    """
    graph = extract_graph(vhdl_info)
    by_label = {node.label: node for node in graph.nodes}
    lines = []
    shown = {}

    # (label, prefix of its line, prefix of the lines of its children)
    stack = [(label, "", "") for label in reversed(graph.roots)]
    for _ in range(_MAX_STEPS):
        if not stack:
            break
        label, line_prefix, child_prefix = stack.pop()
        node = by_label[label]
        text = "%s [%s]" % (label, _node_text(node))
        if label in shown and node.deps:
            lines.append(line_prefix + text + " (*)")
            continue
        shown[label] = True
        lines.append(line_prefix + text)
        if include_files:
            # Aligned under the text of the node; the bar keeps the branch to its dependencies.
            file_prefix = child_prefix + ("│   " if node.deps else "    ")
            lines.extend([file_prefix + "· " + path for path in node.srcs])
            lines.extend([file_prefix + "◆ " + path for path in node.data])
        for index in reversed(range(len(node.deps))):
            is_last = index == len(node.deps) - 1
            stack.append((
                node.deps[index],
                child_prefix + ("└── " if is_last else "├── "),
                child_prefix + ("    " if is_last else "│   "),
            ))
    if stack:
        fail("The VHDL dependency graph is too large to walk.")
    return "\n".join(lines) + "\n" if lines else ""

def _dot_escape(text):
    return text.replace("\\", "\\\\").replace("\"", "\\\"")

def graph_dot(vhdl_info, graph_name = "vhdl", include_files = False):
    """The dependency graph of `extract_graph` in DOT, like `bazel query --output graph`.

    An edge `"A" -> "B"` means that A depends on B. Modules are boxes, libraries
    that contain modules are folders, libraries without modules are dashed folders.

    With `include_files`, the files of a node are added to its label, one per
    line: `·` for a source file, `◆` for a data file.

    Args:
        vhdl_info: A Target providing VhdlLibraryInfo, a VhdlLibraryInfo, or a list thereof.
        graph_name: Name of the digraph.
        include_files: Add the source and data files of each node to its label.

    Returns:
        str, ending with a newline.
    """
    graph = extract_graph(vhdl_info)
    lines = ["digraph \"%s\" {" % _dot_escape(graph_name), "  node [shape=box];"]
    for node in graph.nodes:
        if node.kind == "module":
            attrs = ""
        elif node.expanded:
            attrs = ", shape=folder"
        else:
            attrs = ", shape=folder, style=dashed"
        text = _dot_escape(node.label) + "\\n" + _dot_escape(_node_text(node))
        if include_files:
            text += "".join(["\\n· " + _dot_escape(path) for path in node.srcs])
            text += "".join(["\\n◆ " + _dot_escape(path) for path in node.data])
        lines.append("  \"%s\" [label=\"%s\"%s]" % (_dot_escape(node.label), text, attrs))
    for node in graph.nodes:
        for dep in node.deps:
            lines.append("  \"%s\" -> \"%s\"" % (_dot_escape(node.label), _dot_escape(dep)))
    lines.append("}")
    return "\n".join(lines) + "\n"



def _vhdl_graph_impl(ctx):
    dot = ctx.actions.declare_file(ctx.label.name + ".dot")
    tree = ctx.actions.declare_file(ctx.label.name + ".txt")
    ctx.actions.write(dot, graph_dot(ctx.attr.deps, graph_name = ctx.label.name, include_files = ctx.attr.include_files))
    ctx.actions.write(tree, graph_tree(ctx.attr.deps, include_files = ctx.attr.include_files))
    return [DefaultInfo(files = depset([dot, tree]))]

vhdl_graph = rule(
    implementation = _vhdl_graph_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [VhdlLibraryInfo],
            doc = "Roots of the graph: vhdl_library and vhdl_module targets.",
        ),
        "include_files": attr.bool(
            default = False,
            doc = "List the source and data files of each node (`·` sources, `◆` data).",
        ),
    },
    doc = """Writes the VHDL dependency graph of its deps: <name>.dot and <name>.txt.

    The graph is limited to modules (see `extract_graph`). Render it with
    `bazel build //:graph && dot -Tsvg bazel-bin/graph.dot > graph.svg`.
    """,
)