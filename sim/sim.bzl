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
Rules for running VHDL simulations.

This module provides rules and macros for executing VHDL testbenches using
GHDL or NVC, as well as high-level VUnit integration.
"""

load("@gateweaver_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo", "VhdlModuleInfo")
load("@gateweaver_rules_vhdl//simulator:ghdl.bzl", "vhdl_sim_config_transition")

def _map_vhdl_version_to_ghdl_flag(version):
    if version == "2008": return "08"
    if version == "93": return "93"
    if version == "87": return "87"
    if version == "2019": return "19"
    return "08"

def _vhdl_test_impl(ctx):
    toolchain = ctx.toolchains["@gateweaver_rules_vhdl//simulator:toolchain_type"]
    
    # Collect all sources for runfiles
    dut_lib_info = ctx.attr.dut[VhdlLibraryInfo]
    tb_srcs = ctx.files.srcs
    all_srcs = []
    all_srcs.extend(tb_srcs)
    for l in dut_lib_info.libraries.values():
        all_srcs.extend(l.sources.to_list())

    # Check if it's GHDL or NVC
    is_ghdl = hasattr(toolchain, "ghdl_info")
    is_nvc = hasattr(toolchain, "nvc_info")
    
    if is_ghdl:
        executable, bin_file, extra_files = _ghdl_sim_impl(ctx, toolchain.ghdl_info, dut_lib_info, tb_srcs)
    elif is_nvc:
        executable, bin_file, extra_files = _nvc_sim_impl(ctx, toolchain.nvc_info, dut_lib_info, tb_srcs)
    else:
        fail("Unknown toolchain type")

    runfiles = ctx.runfiles(files = [bin_file] + all_srcs, transitive_files = extra_files)
    
    return [DefaultInfo(executable = executable, runfiles = runfiles)]

def _ghdl_sim_impl(ctx, info, dut_lib_info, tb_srcs):
    ghdl_bin = info.ghdl_binary
    script_content = ["#!/bin/bash", "set -e"]
    
    # script_content.append("export GHDL_PREFIX=$(dirname " + ghdl_bin.short_path + ")/../lib/ghdl")

    for key, lib_info in dut_lib_info.libraries.items():
        cmd = "{ghdl} -a --std={std} --work={lib} {files}".format(
            ghdl = ghdl_bin.short_path,
            std = _map_vhdl_version_to_ghdl_flag(lib_info.vhdl_version),
            lib = lib_info.library_name,
            files = " ".join([f.short_path for f in lib_info.sources.to_list()])
        )
        script_content.append(cmd)

    tb_opts = "--std=" + _map_vhdl_version_to_ghdl_flag(ctx.attr.vhdl_version)
    script_content.append("{ghdl} -a {opts} {files}".format(
        ghdl = ghdl_bin.short_path, opts = tb_opts, files = " ".join([f.short_path for f in tb_srcs])
    ))
    
    sim_args = " ".join(ctx.attr.sim_args)
    script_content.append("{ghdl} -e {opts} {entity}".format(
        ghdl = ghdl_bin.short_path, opts = tb_opts, entity = ctx.attr.testbench_entity,
    ))
    script_content.append("{ghdl} -r {opts} {entity} {args}".format(
        ghdl = ghdl_bin.short_path, opts = tb_opts, entity = ctx.attr.testbench_entity, args = sim_args
    ))

    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(output = executable, content = "\n".join(script_content), is_executable = True)
    
    return executable, ghdl_bin, info.ghdl_files

def _nvc_sim_impl(ctx, info, dut_lib_info, tb_srcs):
    nvc_bin = info.nvc_binary
    script_content = ["#!/bin/bash", "set -e"]

    nvc_opts = []
    if info.nvc_lib:
        script_content.append("NVC_LIB_DIR=$(dirname " + nvc_bin.short_path + ")/../lib")
        nvc_opts.append("-L $NVC_LIB_DIR")
    
    # # Add the current directory to search path for locally compiled libraries
    nvc_opts.append("-L .")

    nvc_opts_str = " ".join(nvc_opts)

    for key, lib_info in dut_lib_info.libraries.items():
        cmd = "{nvc} {opts} --std={std} --work={lib} -a {files}".format(
            nvc = nvc_bin.short_path,
            opts = nvc_opts_str,
            std = lib_info.vhdl_version,
            lib = lib_info.library_name,
            files = " ".join([f.short_path for f in lib_info.sources.to_list()])
        )
        script_content.append(cmd)

    script_content.append("{nvc} {opts} --std={std} -a {files}".format(
        nvc = nvc_bin.short_path,
        opts = nvc_opts_str,
        std = ctx.attr.vhdl_version,
        files = " ".join([f.short_path for f in tb_srcs])
    ))
    
    sim_args = " ".join(ctx.attr.sim_args)
    script_content.append("{nvc} {opts} -e {entity} -r {args}".format(
        nvc = nvc_bin.short_path,
        opts = nvc_opts_str,
        entity = ctx.attr.testbench_entity,
        args = sim_args
    ))

    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(output = executable, content = "\n".join(script_content), is_executable = True)
    
    return executable, nvc_bin, info.nvc_lib


vhdl_test = rule(
    implementation = _vhdl_test_impl,
    test = True,
    cfg = vhdl_sim_config_transition,
    toolchains = ["@gateweaver_rules_vhdl//simulator:toolchain_type"],
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".vhd"],
            mandatory = True,
            doc = "VHDL source files containing the testbench.",
        ),
        "dut": attr.label(
            providers = [VhdlLibraryInfo],
            doc = "The Design Under Test (library or module).",
        ),
        "testbench_entity": attr.string(
            mandatory = True,
            doc = "The name of the testbench entity to run.",
        ),
        "vhdl_version": attr.string(
            default = "2008",
            doc = "VHDL standard version for the testbench.",
        ),
        "sim_args": attr.string_list(
            doc = "Extra command-line arguments for the simulator run command.",
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
            doc = "Explicit simulator toolchain label (e.g. '@vhdl_toolchains//:ghdl_6_0_mcode').",
        ),
        
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
    },
    doc = "Runs a VHDL testbench using the resolved hermetic simulator.",
)
