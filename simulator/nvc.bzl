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
