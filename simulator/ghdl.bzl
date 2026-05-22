load("@vhdl_toolchains_registry//:registry.bzl", "TOOLCHAIN_REGISTRY")

# ghdl_toolchain.bzl

# --- A. Les Flags ---
# --- B. La Toolchain Hermétique ---
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
        "ghdl_binary": attr.label(mandatory = True),
        "ghdl_lib": attr.label_list(allow_files = True),
        "version": attr.string(),
        "backend": attr.string(),
    },
)

# --- C. La Transition ---
# C'est elle qui fait le lien entre l'attribut de la règle sim et les flags
def _ghdl_transition_impl(_, attr):
    simulator_type = attr.tool_simulator
    version = attr.tool_version
    backend = attr.tool_backend

    if hasattr(attr, "simulator") and attr.simulator:
        # Extract repo name from label string (e.g. @ghdl_6_0_mcode//:simulator -> ghdl_6_0_mcode)
        tc_label = str(attr.simulator)
        repo_name = tc_label.split("//")[0].lstrip("@").replace("+", "").split("~")[-1]

        # Bzlmod repo names can be complex (e.g. @@vhdl_toolchains+ghdl_6_0_mcode), 
        # but the registry is keyed by the name provided in the extension.
        # We need to find the match in the registry keys.
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
        "//vhdl/config:simulator": simulator_type,
        "//vhdl/config:version": version,
        "//vhdl/config:backend": backend,
    }

vhdl_sim_config_transition = transition(
    implementation = _ghdl_transition_impl,
    inputs = [],
    outputs = [
        "//vhdl/config:simulator",
        "//vhdl/config:version",
        "//vhdl/config:backend"
    ],
)