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
Module extension for registering formal verification toolchains (SymbiYosys, Yosys, solvers).
"""

def _oss_cad_suite_repo_impl(ctx):
    ctx.download_and_extract(
        url = ctx.attr.url,
        sha256 = ctx.attr.sha256,
        strip_prefix = ctx.attr.strip_prefix,
    )
    ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
filegroup(name = "sby_bin", srcs = ["bin/sby"])
filegroup(name = "yosys_bin", srcs = ["bin/yosys"])
filegroup(name = "extra_files", srcs = glob(["**"], allow_empty = True))
""")

oss_cad_suite_repository = repository_rule(
    implementation = _oss_cad_suite_repo_impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(default = "oss-cad-suite"),
    },
)

def _local_formal_repo_impl(ctx):
    path = ctx.attr.path
    if not path.startswith("/"):
        workspace_root = ctx.path(Label("@//:MODULE.bazel")).dirname
        path = str(workspace_root.get_child(path))

    ctx.symlink(path, "formal_home")

    ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
filegroup(name = "sby_bin", srcs = ["formal_home/bin/sby"])
filegroup(name = "yosys_bin", srcs = ["formal_home/bin/yosys"])
filegroup(name = "extra_files", srcs = glob(["formal_home/bin/**", "formal_home/lib/**", "formal_home/share/**"]))
""")

local_formal_repository = repository_rule(
    implementation = _local_formal_repo_impl,
    attrs = {
        "path": attr.string(mandatory = True),
    },
)

def _mock_formal_repo_impl(ctx):
    ctx.file("bin/sby", "#!/bin/bash\necho 'Mock SBY'\nexit 0\n", executable = True)
    ctx.file("bin/yosys", "#!/bin/bash\necho 'Mock Yosys'\nexit 0\n", executable = True)
    ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
filegroup(name = "sby_bin", srcs = ["bin/sby"])
filegroup(name = "yosys_bin", srcs = ["bin/yosys"])
filegroup(name = "extra_files", srcs = ["bin/sby", "bin/yosys"])
""")

mock_formal_repository = repository_rule(
    implementation = _mock_formal_repo_impl,
)

_HUB_HEADER = """
package(default_visibility = ["//visibility:public"])
"""

_FORMAL_TC_TEMPLATE = """
# --- Toolchain: {name} (Formal) ---
load("@gateweavers_rules_vhdl//formal:toolchain.bzl", "formal_toolchain")

formal_toolchain(
    name = "{name}_impl",
    sby_binary = "@{name}//:sby_bin",
    yosys_binary = "@{name}//:yosys_bin",
    extra_files = ["@{name}//:extra_files"],
)

toolchain(
    name = "{name}_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@gateweavers_rules_vhdl//formal:toolchain_type",
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)

alias(
    name = "{name}",
    actual = ":{name}_toolchain",
)
"""

def _formal_hub_repo_impl(ctx):
    tools = json.decode(ctx.attr.tools_json)
    build_content = _HUB_HEADER

    for tool in tools:
        name = tool["name"]
        build_content += _FORMAL_TC_TEMPLATE.format(
            name = name,
            os = tool["os"],
            arch = tool["arch"],
        )

    ctx.file("BUILD", build_content)

formal_hub_repo = repository_rule(
    implementation = _formal_hub_repo_impl,
    attrs = {
        "tools_json": attr.string(mandatory = True),
    },
)

_oss_cad_suite_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(default = "oss-cad-suite"),
        "os": attr.string(default = "linux"),
        "arch": attr.string(default = "x86_64"),
    }
)

_local_formal_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "path": attr.string(mandatory = True),
        "os": attr.string(default = "linux"),
        "arch": attr.string(default = "x86_64"),
    }
)

_mock_formal_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "os": attr.string(default = "linux"),
        "arch": attr.string(default = "x86_64"),
    }
)

def _formal_extension_impl(ctx):
    tools = []

    for mod in ctx.modules:
        for tool in mod.tags.oss_cad_suite:
            oss_cad_suite_repository(
                name = tool.name,
                url = tool.url,
                sha256 = tool.sha256,
                strip_prefix = tool.strip_prefix,
            )
            tools.append({
                "name": tool.name,
                "os": tool.os,
                "arch": tool.arch,
            })

        for tool in mod.tags.local:
            local_formal_repository(
                name = tool.name,
                path = tool.path,
            )
            tools.append({
                "name": tool.name,
                "os": tool.os,
                "arch": tool.arch,
            })

        for tool in mod.tags.mock:
            mock_formal_repository(
                name = tool.name,
            )
            tools.append({
                "name": tool.name,
                "os": tool.os,
                "arch": tool.arch,
            })

    formal_hub_repo(
        name = "formal_toolchains",
        tools_json = json.encode(tools),
    )

    return ctx.extension_metadata(
        reproducible = True,
    )

formal_toolchains = module_extension(
    implementation = _formal_extension_impl,
    tag_classes = {
        "oss_cad_suite": _oss_cad_suite_tag,
        "local": _local_formal_tag,
        "mock": _mock_formal_tag,
    },
)
