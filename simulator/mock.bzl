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
        "ghdl_binary": attr.label(allow_single_file = True, mandatory = True),
    },
)

NvcToolchainInfo = provider(fields = ["nvc_binary", "version"])

def _mock_nvc_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            nvc_info = NvcToolchainInfo(
                nvc_binary = ctx.file.nvc_binary,
                version = "mock",
            )
        )
    ]

mock_nvc_toolchain = rule(
    implementation = _mock_nvc_toolchain_impl,
    attrs = {
        "nvc_binary": attr.label(allow_single_file = True, mandatory = True),
    },
)
