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
NVC toolchain rules.

This module manages the NVC hermetic toolchain and provides its provider.
"""

NvcToolchainInfo = provider(
    doc = "Provider for hermetic NVC toolchain details.",
    fields = {
        "nvc_binary": "File: The NVC executable.",
        "nvc_lib": "Depset: NVC library files.",
        "version": "String: The tool version.",
    }
)

def _nvc_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            nvc_info = NvcToolchainInfo(
                nvc_binary = ctx.file.nvc_binary,
                nvc_lib = depset(ctx.files.nvc_lib),
                version = ctx.attr.version,
            )
        )
    ]

nvc_toolchain = rule(
    implementation = _nvc_toolchain_impl,
    attrs = {
        "nvc_binary": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "Label pointing to the NVC executable.",
        ),
        "nvc_lib": attr.label_list(
            allow_files = True,
            doc = "List of labels for NVC support files/libraries.",
        ),
        "version": attr.string(
            doc = "The version of this NVC toolchain.",
        ),
    },
    doc = "Defines an NVC hermetic toolchain.",
)
