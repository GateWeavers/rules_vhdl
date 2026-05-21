# ghdl_toolchain.bzl

# --- A. Les Flags ---
# --- B. La Toolchain Hermétique ---
GhdlToolchainInfo = provider(
    doc = "Provider for hermetic GHDL",
    fields = {
        "ghdl_binary": "File: The executable",
        "version": "String",
        "backend": "String",
    }
)

def _ghdl_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            ghdl_info = GhdlToolchainInfo(
                ghdl_binary = ctx.file.ghdl_binary,
                version = ctx.attr.version,
                backend = ctx.attr.backend,
            )
        )
    ]

ghdl_toolchain = rule(
    implementation = _ghdl_toolchain_impl,
    attrs = {
        "ghdl_binary": attr.label(allow_single_file = True, mandatory = True),
        "version": attr.string(),
        "backend": attr.string(),
    },
)

# --- C. La Transition ---
# C'est elle qui fait le lien entre l'attribut de la règle sim et les flags
def _ghdl_transition_impl(_, attr):
    return {
        "//vhdl/config:version": attr.tool_version,
        "//vhdl/config:backend": attr.tool_backend,
    }

ghdl_config_transition = transition(
    implementation = _ghdl_transition_impl,
    inputs = [],
    outputs = [
        "//vhdl/config:version",
        "//vhdl/config:backend"
    ],
)