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
VUnit-Bazel integration rules.

This module provides rules for generating VUnit configuration and running
VUnit simulations hermetically within Bazel.
"""

load("@aspect_rules_py//py:defs.bzl", "py_test")
load("@gateweavers_rules_vhdl//vhdl:vhdl.bzl", "VhdlLibraryInfo")
load("@gateweavers_rules_vhdl//simulator:ghdl.bzl", "vhdl_sim_config_transition")

# --- LE TEMPLATE PYTHON ---
_RUNNER_TEMPLATE = """
from sim.vunit_bazel_helper import get_vunit_from_bazel, add_lib_from_bazel, set_nvc_options

def main():
    vu = get_vunit_from_bazel()
    
    vu.add_vhdl_builtins()
    vu.add_osvvm()
    vu.add_verification_components()
    
    add_lib_from_bazel(vu)
    
    set_nvc_options(vu)
    
    vu.main()

if __name__ == "__main__":
    main()
"""

# --- REGLE 1 : Générateur de Runner ---
def _vunit_runner_gen_impl(ctx):
    out_file = ctx.outputs.out
    ctx.actions.write(
        output = out_file,
        content = _RUNNER_TEMPLATE,
        is_executable = True
    )

_vunit_runner_gen = rule(
    implementation = _vunit_runner_gen_impl,
    attrs = {
        "out": attr.output(
            mandatory = True,
            doc = "The output path for the generated Python runner script.",
        ),
    },
    doc = "Generates a default Python runner script for VUnit.",
)

def _vunit_context_impl(ctx):
    toolchain = ctx.toolchains["@gateweavers_rules_vhdl//simulator:toolchain_type"]
    
    binary_file = None
    library_path = None
    extra_files = depset()
    sim_type = ""

    if hasattr(toolchain, "ghdl_info"):
        sim_type = "ghdl"
        info = toolchain.ghdl_info
        binary_file = info.ghdl_binary
        extra_files = info.ghdl_files
    elif hasattr(toolchain, "nvc_info"):
        sim_type = "nvc"
        info = toolchain.nvc_info
        binary_file = info.nvc_binary
        extra_files = info.nvc_lib
    else:
        fail("Unknown toolchain type")
    
    libraries_config = {}
    transitive_srcs = []
    
    dut_info = ctx.attr.dut[VhdlLibraryInfo]
    
    for lib_key, lib_struct in dut_info.libraries.items():
        lib_name = lib_struct.library_name
        if lib_name not in libraries_config:
            libraries_config[lib_name] = []
        
        for f in lib_struct.sources.to_list():
            transitive_srcs.append(f)
            libraries_config[lib_name].append({
                "file": f.short_path,
                "version": lib_struct.vhdl_version
            })

    tb_files = ctx.files.srcs
    transitive_srcs.extend(tb_files)
    
    tb_lib_name = ctx.attr.name + "_lib"
    if tb_lib_name not in libraries_config:
        libraries_config[tb_lib_name] = []
        
    for f in tb_files:
        libraries_config[tb_lib_name].append({
            "file": f.short_path,
            "version": "2008"
        })

    config_content = {
        "simulator_type": sim_type,
        "binary_path": binary_file.short_path,
        "libraries": libraries_config
    }
    
    config_file = ctx.actions.declare_file(ctx.label.name + "_config.json")
    ctx.actions.write(config_file, json.encode_indent(config_content))

    return [DefaultInfo(
        files = depset([config_file]),
        runfiles = ctx.runfiles(files = transitive_srcs + [binary_file, config_file], transitive_files = extra_files)
    )]

vunit_context = rule(
    implementation = _vunit_context_impl,
    cfg = vhdl_sim_config_transition,
    toolchains = ["@gateweavers_rules_vhdl//simulator:toolchain_type"],
    attrs = {
        "dut": attr.label(
            providers = [VhdlLibraryInfo],
            mandatory = True,
            doc = "The Design Under Test (library or module).",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = "Testbench source files.",
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
            doc = "Explicit simulator toolchain label.",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
    },
    doc = "Gathers VHDL sources and generates a VUnit JSON configuration file.",
)

def vunit_sim(name, dut, srcs = [], tool_simulator="ghdl", tool_version="default", tool_backend="default", simulator=None, deps=[], main=None, enable_coverage=True, **kwargs):
    """
    Macro to run a VUnit simulation.
    
    This macro creates a `vunit_context` to gather sources and a `py_test` to execute the simulation.
    
    Args:
        name: Unique name for the test target.
        dut: The VHDL library/module design under test.
        srcs: Testbench source files.
        tool_simulator: The simulator type ('ghdl' or 'nvc').
        tool_version: Specific version constraint.
        tool_backend: Specific backend constraint (GHDL only).
        simulator: Explicit toolchain label override.
        deps: Extra Python dependencies.
        main: Optional custom runner script.
        enable_coverage: Whether code coverage collection is enabled when running bazel coverage.
        **kwargs: Standard Bazel test attributes (tags, size, timeout).
    """
    context_name = name + "_ctx"
    runner_gen_name = name + "_gen_script"
    runner_file = name + "_runner.py"
    
    vunit_context(
        name = context_name,
        dut = dut,
        srcs = srcs,
        tool_simulator = tool_simulator,
        tool_version = tool_version,
        tool_backend = tool_backend,
        simulator = simulator,
        tags = kwargs.get("tags", []),
    )
    
    if not main:
        _vunit_runner_gen(
            name = runner_gen_name,
            out = runner_file,
            tags = kwargs.get("tags", []),
        )
        main_script = runner_file
    else:
        main_script = main
    
    test_env = {
        "VUNIT_BAZEL_CONFIG": "$(rootpath :" + context_name + ")",
        # "VUNIT_SIMULATOR": simulator if simulator else tool_simulator,
        "VUNIT_COVERAGE_DISABLED": "0" if enable_coverage else "1",
    }
    user_env = kwargs.pop("env", {})
    test_env.update(user_env)

    py_test(
        name = name,
        srcs = [main_script],
        main = main_script,
        data = [":" + context_name],
        deps = deps + ["@pypi//vunit_hdl", "@gateweavers_rules_vhdl//sim:vunit_bazel_helper"],
        args = ["--xunit-xml", "$$XML_OUTPUT_FILE"],
        env = test_env,
        **kwargs
    )
