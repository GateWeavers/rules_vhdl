load("@aspect_rules_py//py:defs.bzl", "py_test")
load("//vhdl:vhdl.bzl", "VhdlLibraryInfo")
load("//simulator:ghdl.bzl", "vhdl_sim_config_transition")

# --- LE TEMPLATE PYTHON ---
_RUNNER_TEMPLATE = """
import os
import sys
import json
from vunit import VUnit

def main():
    config_path = os.environ.get("VUNIT_BAZEL_CONFIG")
    if not config_path:
        print("Error: VUNIT_BAZEL_CONFIG not set.")
        sys.exit(1)
        
    if not os.path.exists(config_path):
        config_path = os.path.join(os.getcwd(), config_path)

    with open(config_path, 'r') as f:
        config = json.load(f)

    sim_type = config['simulator_type']
    binary_path = os.path.abspath(config['binary_path'])
    binary_dir = os.path.dirname(binary_path)

    if sim_type == "ghdl":
        os.environ["VUNIT_SIMULATOR"] = "ghdl"
        os.environ["VUNIT_GHDL_PATH"] = binary_dir
        os.environ["GHDL_PREFIX"] = os.path.join(binary_dir, "..", "lib", "ghdl")
    elif sim_type == "nvc":
        os.environ["VUNIT_SIMULATOR"] = "nvc"
        os.environ["VUNIT_NVC_PATH"] = binary_dir
    else:
        print(f"Unknown simulator: {sim_type}")
        sys.exit(1)

    # Expand environment variables in arguments (e.g. $XML_OUTPUT_FILE)
    args = [os.path.expandvars(a) for a in sys.argv]
    
    if "XML_OUTPUT_FILE" in os.environ and "--xunit-xml" not in args:
        args.extend(["--xunit-xml", os.environ["XML_OUTPUT_FILE"]])

    vu = VUnit.from_argv(args)

    for lib_name, files in config['libraries'].items():
        try:
            lib = vu.library(lib_name)
        except KeyError:
            lib = vu.add_library(lib_name)
            
        for file_entry in files:
            lib.add_source_files(file_entry['file'], vhdl_standard=file_entry['version'])

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
        "out": attr.output(mandatory = True),
    },
)

def _vunit_context_impl(ctx):
    toolchain = ctx.toolchains["//simulator:toolchain_type"]
    sim_type = ctx.attr.tool_simulator
    
    binary_file = None
    extra_files = depset()

    if sim_type == "ghdl":
        if not hasattr(toolchain, "ghdl_info"):
            fail("GHDL toolchain not found")
        info = toolchain.ghdl_info
        binary_file = info.ghdl_binary
        extra_files = info.ghdl_files
    elif sim_type == "nvc":
        if not hasattr(toolchain, "nvc_info"):
            fail("NVC toolchain not found")
        info = toolchain.nvc_info
        binary_file = info.nvc_binary
    else:
        fail("Unsupported simulator: " + sim_type)
    
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
    
    tb_lib_name = "lib_tb"
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
    toolchains = ["//simulator:toolchain_type"],
    attrs = {
        "dut": attr.label(providers = [VhdlLibraryInfo], mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "tool_simulator": attr.string(default = "ghdl"),
        "tool_version": attr.string(default = "default"),
        "tool_backend": attr.string(default = "default"),
        "simulator": attr.string(),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
    }
)

def vunit_sim(name, dut, srcs = [], tool_simulator="ghdl", tool_version="default", tool_backend="default", simulator=None, deps=[], **kwargs):
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
    
    _vunit_runner_gen(
        name = runner_gen_name,
        out = runner_file,
        tags = kwargs.get("tags", []),
    )
    
    py_test(
        name = name,
        srcs = [runner_file],
        main = runner_file,
        data = [":" + context_name],
        deps = deps + ["@pypi//vunit_hdl"],
        args = ["--xunit-xml", "$$XML_OUTPUT_FILE"],
        env = {
            "VUNIT_BAZEL_CONFIG": "$(rootpath :" + context_name + ")",
            "VUNIT_SIMULATOR": simulator if simulator else tool_simulator,
        },
        **kwargs
    )
