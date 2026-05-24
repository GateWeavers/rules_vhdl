load("@rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo", "VhdlModuleInfo")
load("@rules_vhdl//simulator:ghdl.bzl", "vhdl_sim_config_transition")

def _map_vhdl_version_to_ghdl_flag(version):
    if version == "2008": return "08"
    if version == "93": return "93"
    if version == "87": return "87"
    if version == "2019": return "19"
    return "08"

def _vhdl_test_impl(ctx):
    toolchain = ctx.toolchains["@rules_vhdl//simulator:toolchain_type"]
    
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
        executable, bin_file = _nvc_sim_impl(ctx, toolchain.nvc_info, dut_lib_info, tb_srcs)
        extra_files = depset()
    else:
        fail("Unknown toolchain type")

    runfiles = ctx.runfiles(files = [bin_file] + all_srcs, transitive_files = extra_files)
    
    return [DefaultInfo(executable = executable, runfiles = runfiles)]

def _ghdl_sim_impl(ctx, info, dut_lib_info, tb_srcs):
    ghdl_bin = info.ghdl_binary
    script_content = ["#!/bin/bash", "set -e"]
    
    script_content.append("export GHDL_PREFIX=$(dirname " + ghdl_bin.short_path + ")/../lib/ghdl")

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
    script_content.append("{ghdl} -r {opts} {entity} {args}".format(
        ghdl = ghdl_bin.short_path, opts = tb_opts, entity = ctx.attr.testbench_entity, args = sim_args
    ))

    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(output = executable, content = "\n".join(script_content), is_executable = True)
    
    return executable, ghdl_bin, info.ghdl_files

def _nvc_sim_impl(ctx, info, dut_lib_info, tb_srcs):
    nvc_bin = info.nvc_binary
    script_content = ["#!/bin/bash", "set -e"]
    
    for key, lib_info in dut_lib_info.libraries.items():
        cmd = "{nvc} --std={std} --work={lib} -a {files}".format(
            nvc = nvc_bin.short_path,
            std = lib_info.vhdl_version,
            lib = lib_info.library_name,
            files = " ".join([f.short_path for f in lib_info.sources.to_list()])
        )
        script_content.append(cmd)

    script_content.append("{nvc} --std={std} -a {files}".format(
        nvc = nvc_bin.short_path,
        std = ctx.attr.vhdl_version,
        files = " ".join([f.short_path for f in tb_srcs])
    ))
    
    sim_args = " ".join(ctx.attr.sim_args)
    script_content.append("{nvc} -e {entity} -r {args}".format(
        nvc = nvc_bin.short_path,
        entity = ctx.attr.testbench_entity,
        args = sim_args
    ))

    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(output = executable, content = "\n".join(script_content), is_executable = True)
    
    return executable, nvc_bin


vhdl_test = rule(
    implementation = _vhdl_test_impl,
    test = True,
    cfg = vhdl_sim_config_transition,
    toolchains = ["@rules_vhdl//simulator:toolchain_type"],
    attrs = {
        "srcs": attr.label_list(allow_files = [".vhd"], mandatory = True),
        "dut": attr.label(providers = [VhdlLibraryInfo]),
        "testbench_entity": attr.string(mandatory = True),
        "vhdl_version": attr.string(default = "2008"),
        "sim_args": attr.string_list(),
        
        "tool_simulator": attr.string(default = "ghdl"),
        "tool_version": attr.string(default = "default"),
        "tool_backend": attr.string(default = "default"),
        "simulator": attr.string(),
        
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
    },
)
