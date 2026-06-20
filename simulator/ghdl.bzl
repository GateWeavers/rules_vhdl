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
GHDL toolchain rules and configuration transitions.

This module manages the GHDL hermetic toolchain and provides the mechanism
to transition simulator flags based on target attributes or explicit selection.
"""

load("@vhdl_toolchains//:registry.bzl", "TOOLCHAIN_REGISTRY", "DEFAULT_TOOLCHAIN")

GhdlToolchainInfo = provider(
    doc = "Provider for hermetic GHDL toolchain details.",
    fields = {
        "ghdl_binary": "File: The GHDL executable.",
        "ghdl_files": "Depset: All support files (libraries, prefixes) needed for GHDL execution.",
        "version": "String: The tool version.",
        "backend": "String: The backend type ('mcode' or 'llvm').",
    }
)

def _ghdl_toolchain_impl(ctx):
    # If it's a filegroup or produces multiple files, we pick 'bin/ghdl' or the first one.
    # However, for simulation we need the 'ghdl' executable specifically.
    ghdl_binary = None
    for f in ctx.files.ghdl_binary:
        if f.basename == "ghdl":
            ghdl_binary = f
            break
    
    if not ghdl_binary:
        ghdl_binary = ctx.files.ghdl_binary[0]

    all_files = depset(
        direct = ctx.files.ghdl_binary,
        transitive = [dep[DefaultInfo].files for dep in ctx.attr.ghdl_lib]
    )
    return [
        platform_common.ToolchainInfo(
            ghdl_info = GhdlToolchainInfo(
                ghdl_binary = ghdl_binary,
                ghdl_files = all_files,
                version = ctx.attr.version,
                backend = ctx.attr.backend,
            )
        )
    ]

ghdl_toolchain = rule(
    implementation = _ghdl_toolchain_impl,
    attrs = {
        "ghdl_binary": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "Label pointing to the GHDL executable.",
        ),
        "ghdl_lib": attr.label_list(
            allow_files = True,
            doc = "List of labels for GHDL support files/libraries.",
        ),
        "version": attr.string(
            mandatory = True,
            doc = "The version of this GHDL toolchain.",
        ),
        "backend": attr.string(
            mandatory = True,
            doc = "The GHDL backend ('mcode' or 'llvm').",
        ),
    },
    doc = "Defines a GHDL hermetic toolchain.",
)

def _ghdl_transition_impl(settings, attr):
    """
    Implementation of the configuration transition for simulators.
    
    Sets the simulator flags based on rule attributes or explicit hub labels.
    """
    # Default values
    simulator_type = "ghdl"
    version = "default"
    backend = "default"

    # Use values from attributes if provided
    if hasattr(attr, "tool_simulator") and attr.tool_simulator:
        simulator_type = attr.tool_simulator
    if hasattr(attr, "tool_version") and attr.tool_version:
        version = attr.tool_version
    if hasattr(attr, "tool_backend") and attr.tool_backend:
        backend = attr.tool_backend

    selected_repo = ""
    if hasattr(attr, "simulator") and attr.simulator:
        tc_label = str(attr.simulator)
        if "//:" in tc_label:
            parts = tc_label.split("//:")
            repo_part = parts[0].lstrip("@").replace("+", "").split("~")[-1]
            target_part = parts[1]
            
            if repo_part == "vhdl_toolchains":
                if target_part == "default":
                    selected_repo = DEFAULT_TOOLCHAIN
                else:
                    selected_repo = target_part
            else:
                # Direct repo access (backward compatibility or external)
                selected_repo = repo_part
    
    if selected_repo:

        for key in TOOLCHAIN_REGISTRY.keys():
            if key in selected_repo:
                config = TOOLCHAIN_REGISTRY[key]
                simulator_type = config.simulator
                version = config.version
                backend = config.backend
                break

    return {
        "@gateweaver_rules_vhdl//vhdl/config:simulator": simulator_type,
        "@gateweaver_rules_vhdl//vhdl/config:version": version,
        "@gateweaver_rules_vhdl//vhdl/config:backend": backend,
    }

vhdl_sim_config_transition = transition(
    implementation = _ghdl_transition_impl,
    inputs = [],
    outputs = [
        "@gateweaver_rules_vhdl//vhdl/config:simulator",
        "@gateweaver_rules_vhdl//vhdl/config:version",
        "@gateweaver_rules_vhdl//vhdl/config:backend",
    ],
)
