"""
NVC toolchain rules.

This module manages the NVC hermetic toolchain and provides its provider.
"""

NvcToolchainInfo = provider(
    doc = "Provider for hermetic NVC toolchain details.",
    fields = {
        "nvc_binary": "File: The NVC executable.",
        "version": "String: The tool version.",
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
        "nvc_binary": attr.label(
            allow_single_file = True,
            mandatory = True,
            doc = "Label pointing to the NVC executable.",
        ),
        "version": attr.string(
            doc = "The version of this NVC toolchain.",
        ),
    },
    doc = "Defines an NVC hermetic toolchain.",
)
