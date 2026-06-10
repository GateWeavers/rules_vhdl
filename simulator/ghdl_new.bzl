TOOLCHAIN_REGISTRY = {
    # Default fallback
    "default": struct(simulator = "ghdl", version = "default", backend = "default"),
}

def _ghdl_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            ghdl_info = struct(
                ghdl_binary = ctx.file.ghdl_binary,
                ghdl_files = depset(ctx.files.ghdl_lib),
                version = ctx.attr.version,
                backend = ctx.attr.backend,
            ),
        ),
    ]

ghdl_toolchain = rule(
    implementation = _ghdl_toolchain_impl,
    attrs = {
        "ghdl_binary": attr.label(allow_single_file = True, mandatory = True),
        "ghdl_lib": attr.label_list(allow_files = True),
        "version": attr.string(mandatory = True),
        "backend": attr.string(mandatory = True),
    },
)

def _ghdl_transition_impl(settings, attr):
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

    # If 'simulator' attribute is provided, it might override based on repo name
    if hasattr(attr, "simulator") and attr.simulator:
        repo_name = attr.simulator.lstrip("@")
        # Try to find in registry
        # We need a way to access the registry here. 
        # For now, let's assume we can match based on known patterns if needed
        # but the best way is to have the registry available.
        
        # NOTE: In a real implementation, we would load the registry here.
        # Since this is a transition, we can't easily load another file dynamically 
        # unless it's passed as an attribute or we use a hack.
        
        # For now, let's just use the provided values or simple heuristic
        match = None
        for key in TOOLCHAIN_REGISTRY.keys():
            if key in repo_name or repo_name in key: # Simple heuristic for bzlmod
                match = key
                break

        if match:
            config = TOOLCHAIN_REGISTRY[match]
            simulator_type = config.simulator
            version = config.version
            backend = config.backend

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
