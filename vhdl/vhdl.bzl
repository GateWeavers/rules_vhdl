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
# Core VHDL rules for gateweaver_rules_vhdl.


This module provides rules for defining VHDL libraries and modules,
managing transitive dependencies, and handling VHDL versioning.
"""

load("//simulator:ghdl.bzl", "vhdl_sim_config_transition","map_vhdl_version_to_ghdl_flag")

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

def _vhdl_translate_impl(ctx):
    # Retrieve the toolchain
    toolchain = ctx.toolchains["@gateweaver_rules_vhdl//simulator:toolchain_type"]
    if not hasattr(toolchain, "ghdl_info"):
        fail("GHDL toolchain is required for translation.")

    ghdl_info = toolchain.ghdl_info
    ghdl_bin = ghdl_info.ghdl_binary

    out_file = ctx.actions.declare_file(ctx.attr.out or (ctx.label.name + ".vhd"))

    # Extract VhdlLibraryInfo details from the src target
    src_lib_info = ctx.attr.src[VhdlLibraryInfo]
    libs_list = src_lib_info.libraries.values()
    if not libs_list:
        fail("Target src VhdlLibraryInfo contains no libraries.")
    primary_lib = libs_list[-1]

    library_name = primary_lib.library_name
    vhdl_version = primary_lib.vhdl_version

    script_content = ["#!/bin/bash", "set -e"]

    # Export GHDL_PREFIX so standard libraries can be found
    script_content.append("export GHDL_PREFIX=$(dirname \"{ghdl_path}\")/../lib/ghdl".format(
        ghdl_path = ghdl_bin.path
    ))

    std_flag = map_vhdl_version_to_ghdl_flag(vhdl_version)

    # Compile transitive libraries and target library
    for lib_info in libs_list:
        sources_list = lib_info.sources.to_list()
        if not sources_list:
            continue
        cmd = "\"{ghdl}\" -a --std={std} --work={lib} {files}".format(
            ghdl = ghdl_bin.path,
            std = map_vhdl_version_to_ghdl_flag(lib_info.vhdl_version),
            lib = lib_info.library_name,
            files = " ".join(["\"" + f.path + "\"" for f in sources_list])
        )
        script_content.append(cmd)

    # Determine out flag for synthesis based on preserve_ports attribute
    out_flag = "--out=vhdl" if ctx.attr.preserve_ports else "--out=raw-vhdl"

    # Elaborate and synthesize using --synth
    cmd_synth = "\"{ghdl}\" --synth {out_flag} --std={std} --work={lib} {entity} > \"{out_file}\"".format(
        ghdl = ghdl_bin.path,
        out_flag = out_flag,
        std = std_flag,
        lib = library_name,
        entity = ctx.attr.entity_name,
        out_file = out_file.path,
    )
    script_content.append(cmd_synth)

    # Define the list of inputs for the action (sources from all libraries)
    transitive_inputs = [ghdl_info.ghdl_files]
    for lib_struct in libs_list:
        transitive_inputs.append(lib_struct.sources)
    inputs = depset(
        transitive = transitive_inputs
    )

    # Write the script file
    script_file = ctx.actions.declare_file(ctx.label.name + "_translate.sh")
    ctx.actions.write(
        output = script_file,
        content = "\n".join(script_content),
        is_executable = True,
    )

    ctx.actions.run(
        inputs = inputs,
        outputs = [out_file],
        executable = script_file,
        mnemonic = "VhdlTranslate",
        progress_message = "Translating VHDL: %{label}",
    )

    return [
        DefaultInfo(files = depset([out_file]))
    ]

vhdl_translate = rule(
    implementation = _vhdl_translate_impl,
    cfg = vhdl_sim_config_transition,
    toolchains = ["@gateweaver_rules_vhdl//simulator:toolchain_type"],
    attrs = {
        "src": attr.label(
            providers = [VhdlLibraryInfo],
            mandatory = True,
            doc = "The target library or module containing the entity to translate.",
        ),
        "entity_name": attr.string(
            mandatory = True,
            doc = "The name of the entity to synthesize.",
        ),
        "out": attr.string(
            doc = "Optional output file name. Defaults to <target_name>.vhd",
        ),
        "preserve_ports": attr.bool(
            default = True,
            doc = "Whether to preserve original top-level unit I/O ports. If True, uses --out=vhdl-ieee. If False, uses --out=raw-vhdl-ieee.",
        ),

        "tool_simulator": attr.string(
            default = "ghdl",
            doc = "Simulator type constraint ('ghdl' or 'nvc').",
        ),
        "tool_version": attr.string(
            default = "default",
            doc = "Simulator version constraint.",
        ),
        "tool_backend": attr.string(
            default = "default",
            doc = "GHDL backend constraint ('mcode' or 'llvm').",
        ),
        "simulator": attr.string(
            doc = "Explicit toolchain label (e.g. '@vhdl_toolchains//:ghdl_6_0_mcode').",
        ),

        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
    },
    doc = "Translates a VHDL 2008/2019 file to VHDL 93 by compiling it and performing synthesis using GHDL --synth.",
)

def _vhdl_wrapper_impl(ctx):
    # Retrieve the toolchain
    toolchain = ctx.toolchains["@gateweaver_rules_vhdl//simulator:toolchain_type"]
    if not hasattr(toolchain, "ghdl_info"):
        fail("GHDL toolchain is required for wrapper generation.")

    ghdl_info = toolchain.ghdl_info
    ghdl_bin = ghdl_info.ghdl_binary

    out_file = ctx.actions.declare_file(ctx.attr.out or (ctx.label.name + ".vhd"))
    
    # Extract VhdlLibraryInfo details from the src target
    src_lib_info = ctx.attr.src[VhdlLibraryInfo]
    libs_list = src_lib_info.libraries.values()
    if not libs_list:
        fail("Target src VhdlLibraryInfo contains no libraries.")
    primary_lib = libs_list[-1]

    library_name = primary_lib.library_name
    vhdl_version = primary_lib.vhdl_version
    std_flag = map_vhdl_version_to_ghdl_flag(vhdl_version)

    # Reconstruct arguments for generator
    args = ctx.actions.args()
    args.add("--ghdl", ghdl_bin.path)
    args.add("--entity", ctx.attr.entity_name)
    args.add("--out", out_file.path)
    args.add("--library", ctx.attr.library_name)
    args.add("--std", std_flag)
    if ctx.attr.reverse:
        args.add("--reverse")
    if ctx.attr.wrapper_entity:
        args.add("--wrapper-entity", ctx.attr.wrapper_entity)

    # Collect transitive inputs and construct --sources arguments
    transitive_inputs = [ghdl_info.ghdl_files]
    for lib_info in libs_list:
        transitive_inputs.append(lib_info.sources)
        for f in lib_info.sources.to_list():
            std_v = map_vhdl_version_to_ghdl_flag(lib_info.vhdl_version)
            args.add("--source", "{}:{}:{}".format(lib_info.library_name, std_v, f.path))

    inputs = depset(transitive = transitive_inputs)

    ctx.actions.run(
        inputs = inputs,
        outputs = [out_file],
        executable = ctx.executable._generator,
        arguments = [args],
        mnemonic = "VhdlWrapperGen",
        progress_message = "Generating VHDL Wrapper for %{label}",
    )

    return [
        DefaultInfo(files = depset([out_file]))
    ]

vhdl_wrapper = rule(
    implementation = _vhdl_wrapper_impl,
    cfg = vhdl_sim_config_transition,
    toolchains = ["@gateweaver_rules_vhdl//simulator:toolchain_type"],
    attrs = {
        "src": attr.label(
            providers = [VhdlLibraryInfo],
            mandatory = True,
            doc = "The target library or module containing the entity to wrap.",
        ),
        "entity_name": attr.string(
            mandatory = True,
            doc = "The name of the entity to wrap.",
        ),
        "out": attr.string(
            doc = "Optional output file name. Defaults to <target_name>.vhd",
        ),
        "reverse": attr.bool(
            default = False,
            doc = "If True, generate a VHDL 2008 wrapper with record ports wrapping a flat entity. If False, generate a VHDL 93 wrapper with flat ports wrapping a record entity.",
        ),
        "library_name": attr.string(
            default = "work",
            doc = "The library name to instantiate the wrapped entity from.",
        ),
        "wrapper_entity": attr.string(
            doc = "Override the generated wrapper entity name. Defaults to <entity_name>_wrapper.",
        ),
        "_generator": attr.label(
            default = "//vhdl:vhdl_wrapper_generator",
            executable = True,
            cfg = "exec",
        ),

        "tool_simulator": attr.string(
            default = "ghdl",
            doc = "Simulator type constraint ('ghdl' or 'nvc').",
        ),
        "tool_version": attr.string(
            default = "default",
            doc = "Simulator version constraint.",
        ),
        "tool_backend": attr.string(
            default = "default",
            doc = "GHDL backend constraint ('mcode' or 'llvm').",
        ),
        "simulator": attr.string(
            doc = "Explicit toolchain label (e.g. '@vhdl_toolchains//:ghdl_6_0_mcode').",
        ),

        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
    },
    doc = "Generates a VHDL adapter wrapper file to convert between record-based and flat ports.",
)


