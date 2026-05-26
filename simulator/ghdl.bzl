load("@vhdl_toolchains//:registry.bzl", "TOOLCHAIN_REGISTRY", "DEFAULT_TOOLCHAIN")

GhdlToolchainInfo = provider(
    doc = "Provider for hermetic GHDL",
    fields = {
        "ghdl_binary": "File: The executable",
        "ghdl_files": "Depset: All files needed for GHDL",
        "version": "String",
        "backend": "String",
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
    
    if not selected_repo and simulator_type == "ghdl" and version == "default" and backend == "default":
        # Global resolution fallback (Bazel native)
        pass

    if selected_repo:
        # Bzlmod repo names can be complex (e.g. @@vhdl_toolchains+ghdl_6_0_mcode), 
        # but the registry is keyed by the name provided in the extension.
        # We need to find the match in the registry keys.
        match = None
        for key in TOOLCHAIN_REGISTRY.keys():
            if key == selected_repo or key in selected_repo:
                match = key
                break

        if match:
            config = TOOLCHAIN_REGISTRY[match]
            simulator_type = config.simulator
            version = config.version
            backend = config.backend

    return {
        "@rules_vhdl//vhdl/config:simulator": simulator_type,
        "@rules_vhdl//vhdl/config:version": version,
        "@rules_vhdl//vhdl/config:backend": backend,
    }

vhdl_sim_config_transition = transition(
    implementation = _ghdl_transition_impl,
    inputs = [],
    outputs = [
        "@rules_vhdl//vhdl/config:simulator",
        "@rules_vhdl//vhdl/config:version",
        "@rules_vhdl//vhdl/config:backend",
    ],
)
