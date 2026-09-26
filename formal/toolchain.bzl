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
Toolchain definitions for formal verification (SymbiYosys, Yosys, GHDL plugin, solvers).
"""

FormalToolchainInfo = provider(
    doc = "Provider containing details for SymbiYosys and Yosys-GHDL formal tools.",
    fields = {
        "sby_binary": "File pointing to the sby executable.",
        "yosys_binary": "File pointing to the yosys executable with ghdl plugin.",
        "eqy_binary": "File pointing to the eqy executable.",
        "formal_files": "Depset of supporting files for formal execution.",
    },
)

def _formal_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            formal_info = FormalToolchainInfo(
                sby_binary = ctx.file.sby_binary,
                yosys_binary = ctx.file.yosys_binary,
                eqy_binary = ctx.file.eqy_binary,
                formal_files = depset(ctx.files.extra_files),
            )
        )
    ]

formal_toolchain = rule(
    implementation = _formal_toolchain_impl,
    attrs = {
        "sby_binary": attr.label(
            allow_single_file = True,
            doc = "The SymbiYosys executable.",
        ),
        "yosys_binary": attr.label(
            allow_single_file = True,
            doc = "The Yosys executable.",
        ),
        "eqy_binary": attr.label(
            allow_single_file = True,
            doc = "The EQY executable.",
        ),
        "extra_files": attr.label_list(
            allow_files = True,
            doc = "Additional tools or library files (e.g. solvers, ghdl plugin).",
        ),
    },
    doc = "Defines a formal verification toolchain.",
)
