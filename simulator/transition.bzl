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
VHDL simulation configuration transitions.
"""

def _vhdl_transition_impl(settings, attr):
    """
    Implementation of the configuration transition for simulators.

    Sets the simulator flags based on rule attributes or explicit hub labels.
    """
    # Default values
    simulator_type = "ghdl"
    version = "default"
    backend = "default"
    selected_toolchain = "none"

    # Use values from attributes if provided
    if hasattr(attr, "tool_simulator") and attr.tool_simulator:
        simulator_type = attr.tool_simulator
    if hasattr(attr, "tool_version") and attr.tool_version:
        version = attr.tool_version
    if hasattr(attr, "tool_backend") and attr.tool_backend:
        backend = attr.tool_backend

    # Extract target name from explicit simulator target label
    if hasattr(attr, "simulator") and attr.simulator:
        tc_label = str(attr.simulator)
        if "//:" in tc_label:
            parts = tc_label.split("//:")
            repo_part = parts[0].lstrip("@").replace("+", "").split("~")[-1]
            target_part = parts[1]

            if repo_part == "vhdl_toolchains" and target_part != "default":
                selected_toolchain = target_part
            elif repo_part != "vhdl_toolchains":
                # Direct repo access fallback
                simulator_type = "ghdl"

    return {
        "@gateweavers_rules_vhdl//vhdl/config:simulator": simulator_type,
        "@gateweavers_rules_vhdl//vhdl/config:version": version,
        "@gateweavers_rules_vhdl//vhdl/config:backend": backend,
        "@gateweavers_rules_vhdl//vhdl/config:selected_toolchain": selected_toolchain,
    }

vhdl_sim_config_transition = transition(
    implementation = _vhdl_transition_impl,
    inputs = [],
    outputs = [
        "@gateweavers_rules_vhdl//vhdl/config:simulator",
        "@gateweavers_rules_vhdl//vhdl/config:version",
        "@gateweavers_rules_vhdl//vhdl/config:backend",
        "@gateweavers_rules_vhdl//vhdl/config:selected_toolchain",
    ],
)
