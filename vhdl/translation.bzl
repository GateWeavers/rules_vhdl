#  Copyright 2026 Nocilis
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#      http://www.apache.org/licenses/LICENSE-2.0
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

"""
VHDL Translation and wrapper generation rules.
"""

load("//vhdl:vhdl.bzl", "VhdlLibraryInfo", "vhdl_library")
load("//simulator:transition.bzl", "vhdl_sim_config_transition")
load("//simulator:ghdl.bzl", "map_vhdl_version_to_ghdl_flag")
load("//sim:sim.bzl", "vhdl_test")
load("//sim:vunit_rules.bzl", "vunit_sim")
load("//sim:cocotb_rules.bzl", "cocotb_sim")

def _vhdl_translate_impl(ctx):
    # Retrieve the toolchain
    toolchain = ctx.toolchains["@gateweavers_rules_vhdl//simulator:toolchain_type"]
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
    toolchains = ["@gateweavers_rules_vhdl//simulator:toolchain_type"],
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
    toolchain = ctx.toolchains["@gateweavers_rules_vhdl//simulator:toolchain_type"]
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
    toolchains = ["@gateweavers_rules_vhdl//simulator:toolchain_type"],
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

def vhdl_translate_and_verify(
    name,
    src,
    entity_name,
    testbench_srcs = [],
    testbench_entity = None,
    test_module = None,
    test_type = "vhdl", # "vhdl", "vunit", or "cocotb"
    preserve_ports = True,
    simulator = None,
    sim_args = [],
    deps = [],
    **kwargs
):
    """Translates a VHDL entity to VHDL 93 and runs equivalence checks against a testbench."""
    
    # 1. Translation
    translated_vhd = name + "_translated_vhd"
    vhdl_translate(
        name = translated_vhd,
        src = src,
        entity_name = entity_name,
        preserve_ports = preserve_ports,
        simulator = simulator,
    )
    
    # 2. Translated Library (compiled to a unique flat library to avoid name collision with wrapper)
    translated_lib = name + "_translated_lib"
    flat_library_name = name + "_flat_lib"
    vhdl_library(
        name = translated_lib,
        srcs = [":" + translated_vhd],
        library_name = flat_library_name,
    )
    
    # 3. Wrapper (if ports are flattened)
    if not preserve_ports:
        wrapper_target = name + "_wrapper"
        vhdl_wrapper(
            name = wrapper_target,
            src = src, # Pass original src containing record type package
            entity_name = entity_name,
            reverse = True,
            library_name = flat_library_name,
            wrapper_entity = entity_name,
            simulator = simulator,
        )
        
        # Wrapped translated library (exposing record ports)
        wrapped_lib = name + "_wrapped_lib"
        vhdl_library(
            name = wrapped_lib,
            srcs = [":" + wrapper_target],
            library_name = "work",
            deps = [":" + translated_lib, src],
        )
        dut_target = ":" + wrapped_lib
    else:
        dut_target = ":" + translated_lib

    # 4. Generate tests if testbench parameters are specified
    if testbench_srcs or test_module:
        orig_test_name = name + "_orig_test"
        trans_test_name = name + "_translated_test"
        
        if test_type == "vhdl":
            vhdl_test(
                name = orig_test_name,
                srcs = testbench_srcs,
                dut = src,
                testbench_entity = testbench_entity,
                simulator = simulator,
                sim_args = sim_args,
                **kwargs
            )
            vhdl_test(
                name = trans_test_name,
                srcs = testbench_srcs,
                dut = dut_target,
                testbench_entity = testbench_entity,
                simulator = simulator,
                sim_args = sim_args,
                **kwargs
            )
        elif test_type == "vunit":
            vunit_sim(
                name = orig_test_name,
                srcs = testbench_srcs,
                dut = src,
                simulator = simulator,
                deps = deps,
                **kwargs
            )
            vunit_sim(
                name = trans_test_name,
                srcs = testbench_srcs,
                dut = dut_target,
                simulator = simulator,
                deps = deps,
                **kwargs
            )
        elif test_type == "cocotb":
            cocotb_sim(
                name = orig_test_name,
                srcs = testbench_srcs,
                dut = src,
                hdl_toplevel = entity_name,
                test_module = test_module,
                simulator = simulator,
                **kwargs
            )
            cocotb_sim(
                name = trans_test_name,
                srcs = testbench_srcs,
                dut = dut_target,
                hdl_toplevel = entity_name,
                test_module = test_module,
                simulator = simulator,
                **kwargs
            )
        else:
            fail("Unsupported test_type: " + test_type)
