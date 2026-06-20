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
Mock toolchain rules for internal testing.
"""

load(":ghdl.bzl", "GhdlToolchainInfo")

def _mock_ghdl_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            ghdl_info = GhdlToolchainInfo(
                ghdl_binary = ctx.file.ghdl_binary,
                ghdl_files = depset([ctx.file.ghdl_binary]),
                version = "mock",
                backend = "mock",
            )
        )
    ]

mock_ghdl_toolchain = rule(
    implementation = _mock_ghdl_toolchain_impl,
    attrs = {
        "ghdl_binary": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The mock executable file.",
        ),
    },
    doc = "Defines a mock GHDL toolchain for testing purposes.",
)

# Internal provider for mock NVC
_MockNvcToolchainInfo = provider(fields = ["nvc_binary", "version"])

def _mock_nvc_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            nvc_info = _MockNvcToolchainInfo(
                nvc_binary = ctx.file.nvc_binary,
                version = "mock",
            )
        )
    ]

mock_nvc_toolchain = rule(
    implementation = _mock_nvc_toolchain_impl,
    attrs = {
        "nvc_binary": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "The mock executable file.",
        ),
    },
    doc = "Defines a mock NVC toolchain for testing purposes.",
)
