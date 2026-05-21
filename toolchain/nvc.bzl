NvcToolchainInfo = provider(
    doc = "Provider for hermetic NVC",
    fields = {
        "nvc_binary": "File: The executable",
        "version": "String",
    }
)

def _nvc_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            nvc_info = NvcToolchainInfo(
                nvc_binary = ctx.file.nvc_binary,
                version = ctx.attr.version,
            )
        )
    ]

nvc_toolchain = rule(
    implementation = _nvc_toolchain_impl,
    attrs = {
        "nvc_binary": attr.label(allow_single_file = True, mandatory = True),
        "version": attr.string(),
    },
)