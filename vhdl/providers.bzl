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

"""Providers for VHDL rules.

This module defines all providers used for VHDL compilation, library
management, versioning, and dependency tracking.
"""

VhdlConfigInfo = provider(
    doc = "Provider for VHDL configuration flags.",
    fields = {"value": "The current value of the flag."},
)

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
