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
Rules and macros for VHDL Formal Verification using SymbiYosys (SBY), Yosys, and GHDL.
"""

load("//vhdl:vhdl.bzl", "VhdlLibraryInfo")
load("//simulator:ghdl.bzl", "map_vhdl_version_to_ghdl_flag")

def _vhdl_formal_test_impl(ctx):
    dut_lib_info = ctx.attr.dut[VhdlLibraryInfo]

    # Collect all sources (VHDL + PSL files)
    vhdl_files = []
    transitive_runfiles = []

    for _, lib_struct in dut_lib_info.libraries.items():
        for f in lib_struct.sources.to_list():
            vhdl_files.append(f)
            transitive_runfiles.append(f)

    for psl_f in ctx.files.psl_srcs:
        vhdl_files.append(psl_f)
        transitive_runfiles.append(psl_f)

    # Check for toolchain or fallback to system tools
    sby_bin_path = "sby"
    yosys_bin_path = "yosys"
    extra_tool_files = depset()

    toolchain_key = "@gateweavers_rules_vhdl//formal:toolchain_type"
    if toolchain_key in ctx.toolchains and ctx.toolchains[toolchain_key] != None:
        tc = ctx.toolchains[toolchain_key]
        if hasattr(tc, "formal_info"):
            f_info = tc.formal_info
            sby_bin_path = f_info.sby_binary.short_path
            yosys_bin_path = f_info.yosys_binary.short_path
            extra_tool_files = f_info.formal_files
            transitive_runfiles.append(f_info.sby_binary)
            transitive_runfiles.append(f_info.yosys_binary)

    # Generate .sby config file
    sby_config_file = ctx.actions.declare_file(ctx.label.name + ".sby")

    if ctx.file.sby_template:
        # Use template if supplied
        ctx.actions.expand_template(
            template = ctx.file.sby_template,
            output = sby_config_file,
            substitutions = {
                "{TOP_ENTITY}": ctx.attr.top_entity,
                "{MODE}": ctx.attr.mode,
                "{DEPTH}": str(ctx.attr.depth),
                "{ENGINE}": ctx.attr.engine,
            },
        )
    else:
        # Auto-generate .sby configuration
        lines = []

        # [options]
        lines.append("[options]")
        lines.append("mode {}".format(ctx.attr.mode))
        lines.append("depth {}".format(ctx.attr.depth))
        for k, v in ctx.attr.sby_options.items():
            lines.append("{} {}".format(k, v))
        lines.append("")

        # [engines]
        lines.append("[engines]")
        lines.append(ctx.attr.engine)
        lines.append("")

        # [script]
        lines.append("[script]")
        lines.append("plugin -i ghdl")
        ghdl_cmd_files = " ".join([f.basename for f in vhdl_files])
        lines.append("ghdl --std=08 {} -e {}".format(ghdl_cmd_files, ctx.attr.top_entity))
        lines.append("prep -top {}".format(ctx.attr.top_entity))
        lines.append("")

        # [files]
        lines.append("[files]")
        for f in vhdl_files:
            lines.append(f.short_path)
        lines.append("")

        ctx.actions.write(
            output = sby_config_file,
            content = "\n".join(lines),
        )

    transitive_runfiles.append(sby_config_file)

    # Create test execution script
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    script_path_export = "export PATH=$(pwd)/$(dirname {}):$PATH".format(sby_bin_path) if "/" in sby_bin_path else "# using system PATH"

    script_content = [
        "#!/bin/bash",
        "export PYTHONDONTWRITEBYTECODE=1",
        script_path_export,
        "",
        "SBY_STATUS=0",
        "{} -f {} || SBY_STATUS=$?".format(sby_bin_path, sby_config_file.short_path),
        "",
        "# Copy SBY generated VCD trace to test undeclared outputs if present",
        'VCD_FILE=$(find . -name "*.vcd" 2>/dev/null | head -n 1)',
        'if [ -n "$VCD_FILE" ] && [ -f "$VCD_FILE" ] && [ -n "$TEST_UNDECLARED_OUTPUTS_DIR" ]; then',
        '    echo "SBY generated VCD trace: $VCD_FILE"',
        '    cp "$VCD_FILE" "$TEST_UNDECLARED_OUTPUTS_DIR/trace.vcd"',
        '    cp "$VCD_FILE" "$TEST_UNDECLARED_OUTPUTS_DIR/{}.vcd"'.format(ctx.label.name),
        'fi',
        "",
        'exit $SBY_STATUS',
    ]

    ctx.actions.write(
        output = script,
        content = "\n".join(script_content),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = transitive_runfiles, transitive_files = extra_tool_files)

    return [
        DefaultInfo(
            executable = script,
            runfiles = runfiles,
        )
    ]

vhdl_formal_test = rule(
    implementation = _vhdl_formal_test_impl,
    test = True,
    toolchains = [config_common.toolchain_type("@gateweavers_rules_vhdl//formal:toolchain_type", mandatory = False)],
    attrs = {
        "dut": attr.label(
            providers = [VhdlLibraryInfo],
            mandatory = True,
            doc = "The target VHDL library or module under test.",
        ),
        "top_entity": attr.string(
            mandatory = True,
            doc = "The top-level VHDL entity name to verify.",
        ),
        "psl_srcs": attr.label_list(
            allow_files = True,
            doc = "Optional external PSL or VHDL formal property files.",
        ),
        "mode": attr.string(
            default = "bmc",
            values = ["bmc", "cover", "prove", "live"],
            doc = "Formal verification mode.",
        ),
        "engine": attr.string(
            default = "smtbmc yices",
            doc = "SBY formal solver engine string.",
        ),
        "depth": attr.int(
            default = 20,
            doc = "Cycle depth bound for formal check.",
        ),
        "sby_template": attr.label(
            allow_single_file = True,
            doc = "Optional custom .sby template file.",
        ),
        "sby_options": attr.string_dict(
            doc = "Extra key-value pairs added to the [options] section of generated .sby.",
        ),
    },
    doc = "Runs formal verification on a VHDL design using SymbiYosys, Yosys (GHDL plugin), and PSL assertions.",
)

def vhdl_bmc_test(name, dut, top_entity, **kwargs):
    """Macro helper to run Bounded Model Checking (BMC)."""
    vhdl_formal_test(
        name = name,
        dut = dut,
        top_entity = top_entity,
        mode = "bmc",
        **kwargs
    )

def vhdl_cover_test(name, dut, top_entity, **kwargs):
    """Macro helper to run formal Cover checks."""
    vhdl_formal_test(
        name = name,
        dut = dut,
        top_entity = top_entity,
        mode = "cover",
        **kwargs
    )

def vhdl_prove_test(name, dut, top_entity, **kwargs):
    """Macro helper to run unbounded Proving."""
    vhdl_formal_test(
        name = name,
        dut = dut,
        top_entity = top_entity,
        mode = "prove",
        **kwargs
    )
