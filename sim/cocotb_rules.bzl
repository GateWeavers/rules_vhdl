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
Cocotb 2.0 integration rules for Bazel.
"""

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@gateweavers_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo")
load("@gateweavers_rules_vhdl//simulator:ghdl.bzl", "vhdl_sim_config_transition")

def _cocotb_context_impl(ctx):
    toolchain = ctx.toolchains["@gateweavers_rules_vhdl//simulator:toolchain_type"]
    
    if hasattr(toolchain, "ghdl_info"):
        sim_type, info = "ghdl", toolchain.ghdl_info
        binary_file, extra_files = info.ghdl_binary, info.ghdl_files
    elif hasattr(toolchain, "nvc_info"):
        sim_type, info = "nvc", toolchain.nvc_info
        binary_file, extra_files = info.nvc_binary, info.nvc_lib
    else:
        fail("Unknown toolchain type")
    
    libraries_config = {}
    transitive_srcs = []
    
    for lib_key, lib_struct in ctx.attr.dut[VhdlLibraryInfo].libraries.items():
        lib_name = lib_struct.library_name
        files = [{"file": f.short_path, "version": lib_struct.vhdl_version} for f in lib_struct.sources.to_list()]
        libraries_config.setdefault(lib_name, []).extend(files)
        transitive_srcs.extend(lib_struct.sources.to_list())

    config_content = {
        "simulator_type": sim_type,
        "binary_path": binary_file.short_path,
        "libraries": libraries_config,
        "hdl_toplevel": ctx.attr.hdl_toplevel,
        "test_module": ctx.attr.test_module,
    }
    
    config_file = ctx.actions.declare_file(ctx.label.name + "_config.json")
    ctx.actions.write(config_file, json.encode_indent(config_content))

    return [DefaultInfo(
        files = depset([config_file]),
        runfiles = ctx.runfiles(
            files = transitive_srcs + [binary_file, config_file], 
            transitive_files = extra_files
        )
    )]

cocotb_context = rule(
    implementation = _cocotb_context_impl,
    cfg = vhdl_sim_config_transition,
    toolchains = ["@gateweavers_rules_vhdl//simulator:toolchain_type"],
    attrs = {
        "dut": attr.label(providers = [VhdlLibraryInfo], mandatory = True),
        "hdl_toplevel": attr.string(mandatory = True),
        "test_module": attr.string(mandatory = True),
        "tool_simulator": attr.string(default = "ghdl"),
        "tool_version": attr.string(default = "default"),
        "tool_backend": attr.string(default = "default"),
        "simulator": attr.string(),
        "_allowlist_function_transition": attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist"),
    },
)

def cocotb_sim(name, dut, hdl_toplevel, test_module, srcs = [], main = None, **kwargs):
    """
    Macro to run a Cocotb simulation.
    """
    context_name = name + "_ctx"
    
    # Simplify test_module: if it's just a name, prepend the package module path
    full_test_module = test_module
    if "." not in test_module:
        pkg = native.package_name().replace("/", ".")
        if pkg:
            full_test_module = pkg + "." + test_module

    cocotb_context(
        name = context_name,
        dut = dut,
        hdl_toplevel = hdl_toplevel,
        test_module = full_test_module,
        **{k: v for k, v in kwargs.items() if k in ["tool_simulator", "tool_version", "tool_backend", "simulator", "tags"]}
    )
    
    env = dict(kwargs.get("env", {}), **{
        "COCOTB_BAZEL_CONFIG": "$(rootpath :" + context_name + ")",
        "PYTHONPATH": ".:" + native.package_name(),
    })
    
    deps = kwargs.get("deps", []) + [
        "@pypi//cocotb",
        "@gateweavers_rules_vhdl//sim:cocotb_bazel_helper"
    ]

    if main:
        # Resolve the module name relative to the workspace root
        pkg = native.package_name().replace("/", ".")
        module_name = main.replace(".py", "")
        if ":" in module_name:
            module_name = module_name.split(":")[-1]
        
        full_user_module = pkg + "." + module_name if pkg else module_name
        env["COCOTB_USER_RUNNER"] = full_user_module
        actual_srcs = srcs + [main]
    else:
        actual_srcs = srcs

    py_test(
        name = name,
        srcs = actual_srcs,
        main = "@gateweavers_rules_vhdl//sim:cocotb_bazel_helper.py",
        data = [":" + context_name],
        deps = deps,
        env = env,
        **{k: v for k, v in kwargs.items() if k not in ["deps", "env", "tool_simulator", "tool_version", "tool_backend", "simulator", "srcs", "main"]}
    )
