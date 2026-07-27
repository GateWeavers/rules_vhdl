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

# ==============================================================================
# Default toolchains
# ==============================================================================

_DEFAULT_TOOLS = [
    struct(
        name = "ghdl_6_0_mcode",
        type = "ghdl",
        version = "6.0",
        backend = "mcode",
        url = "https://github.com/ghdl/ghdl/releases/download/v6.0.0/ghdl-mcode-6.0.0-ubuntu24.04-x86_64.tar.gz",
        sha256 = "30d6a977b8456d140bbafecbbe64b1947a3d92eeae8f5e6d9f528a174f9566e7",
        strip_prefix = "ghdl-mcode-6.0.0-ubuntu24.04-x86_64",
        os = "linux",
        arch = "x86_64",
        is_default = True,
    ),
    struct(
        name = "ghdl_7_0_mcode",
        type = "ghdl",
        version = "7.0.0.dev",
        backend = "mcode",
        url = "https://github.com/ghdl/ghdl/releases/download/nightly/ghdl-mcode-7.0.0-dev-ubuntu24.04-x86_64.tar.gz",
        sha256 = "2f8744c1c3c646849b74d6ec1bb40c460b0ff3b79f72fef7326d088ec5dd7417",
        strip_prefix = "ghdl-mcode-7.0.0-dev-ubuntu24.04-x86_64",
        os = "linux",
        arch = "x86_64",
        is_default = False,
    ),
    struct(
        name = "ghdl_6_0_llvm",
        type = "ghdl",
        version = "6.0",
        backend = "llvm",
        url = "https://github.com/ghdl/ghdl/releases/download/v6.0.0/ghdl-llvm-6.0.0-ubuntu24.04-x86_64.tar.gz",
        sha256 = "e0064cd3d1569e7fca27b186b0d71e80c087de90db4e466ed77dc669a574d8bc",
        strip_prefix = "ghdl-llvm-6.0.0-ubuntu24.04-x86_64",
        os = "linux",
        arch = "x86_64",
        is_default = False,
    ),
]

# ==============================================================================
# 1. IMPLEMENTATION REPOSITORIES (Lazy Fetching)
# ==============================================================================

def _ghdl_repo_impl(ctx):
    ctx.download_and_extract(
        url = ctx.attr.url,
        sha256 = ctx.attr.sha256,
        strip_prefix = ctx.attr.strip_prefix,
    )
    ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
filegroup(name = "bin", srcs = ["bin/ghdl"])
filegroup(name = "lib", srcs = glob(["lib/**","bin/**"]))
""")

ghdl_repository = repository_rule(
    implementation = _ghdl_repo_impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
    },
)

def _nvc_repo_impl(ctx):
    ctx.download_and_extract(
        url = ctx.attr.url,
        sha256 = ctx.attr.sha256,
        strip_prefix = ctx.attr.strip_prefix,
    )
    ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
filegroup(name = "bin", srcs = ["bin/nvc"])
filegroup(name = "lib", srcs = glob(["lib/**"]))
""")

nvc_repository = repository_rule(
    implementation = _nvc_repo_impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
    },
)

def _local_nvc_repo_impl(ctx):
    path = ctx.attr.path
    # Handle workspace-relative paths
    if not path.startswith("/"):
        # Resolve path relative to the MODULE.bazel file (workspace root)
        workspace_root = ctx.path(Label("@//:MODULE.bazel")).dirname
        path = str(workspace_root.get_child(path))

    # Symlink the local directory to 'nvc_home' inside the repository
    ctx.symlink(path, "nvc_home")

    ctx.file("BUILD", """
package(default_visibility = ["//visibility:public"])
filegroup(name = "bin", srcs = ["nvc_home/bin/nvc"])
filegroup(name = "lib", srcs = glob(["nvc_home/lib/**"]))
""")

local_nvc_repository = repository_rule(
    implementation = _local_nvc_repo_impl,
    attrs = {
        "path": attr.string(mandatory = True),
    },
)

# ==============================================================================
# 2. METADATA HUB REPOSITORY
# ==============================================================================

_HUB_HEADER = """
package(default_visibility = ["//visibility:public"])

load("@bazel_skylib//lib:selects.bzl", "selects")

# Matchers pour les valeurs par défaut
config_setting(
    name = "match_version_default",
    flag_values = {"@gateweavers_rules_vhdl//vhdl/config:version": "default"},
)

config_setting(
    name = "match_backend_default",
    flag_values = {"@gateweavers_rules_vhdl//vhdl/config:backend": "default"},
)

config_setting(
    name = "match_selected_toolchain_none",
    flag_values = {"@gateweavers_rules_vhdl//vhdl/config:selected_toolchain": "none"},
)

selects.config_setting_group(
    name = "match_default_resolved",
    match_all = [
        ":match_version_default",
        ":match_selected_toolchain_none",
    ],
)
"""

_GHDL_TC_TEMPLATE = """
# --- Toolchain: {name} (GHDL) ---
load("@gateweavers_rules_vhdl//simulator:ghdl.bzl", "ghdl_toolchain")

ghdl_toolchain(
    name = "{name}_impl",
    ghdl_binary = "@{name}//:bin",
    ghdl_lib = ["@{name}//:lib"],
    version = "{version}",
    backend = "{backend}",
)

config_setting(
    name = "{name}_match_version",
    flag_values = {{"@gateweavers_rules_vhdl//vhdl/config:version": "{version}"}},
)

config_setting(
    name = "{name}_match_simulator",
    flag_values = {{"@gateweavers_rules_vhdl//vhdl/config:simulator": "ghdl"}},
)

config_setting(
    name = "{name}_match_backend",
    flag_values = {{"@gateweavers_rules_vhdl//vhdl/config:backend": "{backend}"}},
)

# 1. Matcher when selected dynamically (AND logic)
selects.config_setting_group(
    name = "{name}_match_implicit",
    match_all = [
        ":{name}_match_simulator",
        ":{name}_match_version",
        ":{name}_match_backend",
    ],
)

# 2. Matcher when selected explicitly by label
config_setting(
    name = "{name}_match_explicit",
    flag_values = {{
        "@gateweavers_rules_vhdl//vhdl/config:selected_toolchain": "{name}",
    }},
)

# 3. Combined matcher (OR logic)
selects.config_setting_group(
    name = "{name}_match_resolved",
    match_any = [
        ":{name}_match_implicit",
        ":{name}_match_explicit",
    ],
)

toolchain(
    name = "{name}_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@gateweavers_rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":{name}_match_resolved",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)

{default_rule}

alias(
    name = "{name}",
    actual = ":{name}_toolchain",
)
"""

_NVC_TC_TEMPLATE = """
# --- Toolchain: {name} (NVC) ---
load("@gateweavers_rules_vhdl//simulator:nvc.bzl", "nvc_toolchain")

nvc_toolchain(
    name = "{name}_impl",
    nvc_binary = "@{name}//:bin",
    nvc_lib = ["@{name}//:lib"],
    version = "{version}",
)

config_setting(
    name = "{name}_match_version",
    flag_values = {{"@gateweavers_rules_vhdl//vhdl/config:version": "{version}"}},
)

config_setting(
    name = "{name}_match_simulator",
    flag_values = {{"@gateweavers_rules_vhdl//vhdl/config:simulator": "nvc"}},
)

# 1. Matcher when selected dynamically (AND logic)
selects.config_setting_group(
    name = "{name}_match_implicit",
    match_all = [
        ":{name}_match_simulator",
        ":{name}_match_version",
    ],
)

# 2. Matcher when selected explicitly by label
config_setting(
    name = "{name}_match_explicit",
    flag_values = {{
        "@gateweavers_rules_vhdl//vhdl/config:selected_toolchain": "{name}",
    }},
)

# 3. Combined matcher (OR logic)
selects.config_setting_group(
    name = "{name}_match_resolved",
    match_any = [
        ":{name}_match_implicit",
        ":{name}_match_explicit",
    ],
)

toolchain(
    name = "{name}_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@gateweavers_rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":{name}_match_resolved",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)

{default_rule}

alias(
    name = "{name}",
    actual = ":{name}_toolchain",
)
"""

def _vhdl_hub_repo_impl(ctx):
    tools = json.decode(ctx.attr.tools_json)
    default_toolchain = ctx.attr.default_toolchain

    registry_content = "TOOLCHAIN_REGISTRY = {\n"
    build_content = _HUB_HEADER

    for tool in tools:
        name = tool["name"]
        type = tool["type"]

        registry_content += '    "{}": struct(simulator="{}", version="{}", backend="{}"),\n'.format(
            name, type, tool["version"], tool.get("backend", "none")
        )

        if type == "ghdl":
            default_rule = ""
            if name == default_toolchain:
                default_rule = """
toolchain(
    name = "{name}_default_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@gateweavers_rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":{name}_match_simulator",
        ":match_default_resolved",
        ":match_backend_default",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)
                """.format(name = name, os = tool["os"], arch = tool["arch"])

            build_content += _GHDL_TC_TEMPLATE.format(
                name = name,
                version = tool["version"],
                backend = tool["backend"],
                os = tool["os"],
                arch = tool["arch"],
                default_rule = default_rule,
            )
        elif type == "nvc":
            default_rule = ""
            if name == default_toolchain:
                default_rule = """
toolchain(
    name = "{name}_default_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@gateweavers_rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":{name}_match_simulator",
        ":match_default_resolved",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)
                """.format(name = name, os = tool["os"], arch = tool["arch"])

            build_content += _NVC_TC_TEMPLATE.format(
                name = name,
                version = tool["version"],
                os = tool["os"],
                arch = tool["arch"],
                default_rule = default_rule,
            )

    registry_content += "}\n\n"
    registry_content += 'DEFAULT_TOOLCHAIN = "{}"\n'.format(default_toolchain)

    ctx.file("registry.bzl", registry_content)
    ctx.file("BUILD", build_content)

vhdl_hub_repo = repository_rule(
    implementation = _vhdl_hub_repo_impl,
    attrs = {
        "tools_json": attr.string(mandatory = True),
        "default_toolchain": attr.string(),
    },
)

# ==============================================================================
# 3. TAG CLASSES
# ==============================================================================

_defaults_tag = tag_class(
    attrs = {},
)

_ghdl_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "backend": attr.string(mandatory = True, values = ["mcode", "llvm"]),
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "os": attr.string(default = "linux"),
        "arch": attr.string(default = "x86_64"),
        "is_default": attr.bool(default = False),
    }
)

_nvc_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "os": attr.string(default = "linux"),
        "arch": attr.string(default = "x86_64"),
        "is_default": attr.bool(default = False),
    }
)

_nvc_local_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True),
        "version": attr.string(mandatory = True),
        "path": attr.string(mandatory = True),
        "os": attr.string(default = "linux"),
        "arch": attr.string(default = "x86_64"),
        "is_default": attr.bool(default = False),
    }
)

# ==============================================================================
# 4. IMPLEMENTATION
# ==============================================================================

def _vhdl_extension_impl(ctx):
    tools = []
    default_toolchain = ""
    defined_names = {}

    for mod in ctx.modules:
        # check if default toolchains are requested
        if mod.tags.defaults:
            for tool in _DEFAULT_TOOLS:
                if tool.name in defined_names:
                    continue
                defined_names[tool.name] = True

                if tool.is_default:
                    if default_toolchain:
                        fail("Only one simulator can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                    default_toolchain = tool.name

                if tool.type == "ghdl":
                    ghdl_repository(
                        name = tool.name,
                        url = tool.url,
                        sha256 = tool.sha256,
                        strip_prefix = tool.strip_prefix,
                    )
                    tools.append({
                        "name": tool.name,
                        "type": "ghdl",
                        "version": tool.version,
                        "backend": tool.backend,
                        "url": tool.url,
                        "sha256": tool.sha256,
                        "strip_prefix": tool.strip_prefix,
                        "os": tool.os,
                        "arch": tool.arch,
                    })

        # Handle GHDL toolchain specified by the user
        for tool in mod.tags.ghdl:
            if tool.name in defined_names:
                fail("Toolchain '{}' defined multiple times.".format(tool.name))
            defined_names[tool.name] = True

            if tool.is_default:
                if default_toolchain:
                    fail("Only one simulator can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                default_toolchain = tool.name

            ghdl_repository(
                name = tool.name,
                url = tool.url,
                sha256 = tool.sha256,
                strip_prefix = tool.strip_prefix,
            )

            tools.append({
                "name": tool.name,
                "type": "ghdl",
                "version": tool.version,
                "backend": tool.backend,
                "url": tool.url,
                "sha256": tool.sha256,
                "strip_prefix": tool.strip_prefix,
                "os": tool.os,
                "arch": tool.arch,
            })

        # Handle NVC toolchain specified by the user
        for tool in mod.tags.nvc:
            if tool.name in defined_names:
                fail("Toolchain '{}' defined multiple times.".format(tool.name))
            defined_names[tool.name] = True

            if tool.is_default:
                if default_toolchain:
                    fail("Only one simulator can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                default_toolchain = tool.name

            nvc_repository(
                name = tool.name,
                url = tool.url,
                sha256 = tool.sha256,
                strip_prefix = tool.strip_prefix,
            )

            tools.append({
                "name": tool.name,
                "type": "nvc",
                "version": tool.version,
                "url": tool.url,
                "sha256": tool.sha256,
                "strip_prefix": tool.strip_prefix,
                "os": tool.os,
                "arch": tool.arch,
            })

        # Handle NVC local toolchain specified by the user
        for tool in mod.tags.nvc_local:
            if tool.name in defined_names:
                fail("Toolchain '{}' defined multiple times.".format(tool.name))
            defined_names[tool.name] = True

            if tool.is_default:
                if default_toolchain:
                    fail("Only one simulator can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                default_toolchain = tool.name

            local_nvc_repository(
                name = tool.name,
                path = tool.path,
            )

            tools.append({
                "name": tool.name,
                "type": "nvc",
                "version": tool.version,
                "os": tool.os,
                "arch": tool.arch,
            })

    vhdl_hub_repo(
        name = "vhdl_toolchains",
        tools_json = json.encode(tools),
        default_toolchain = default_toolchain,
    )

    return ctx.extension_metadata(
        reproducible = True,
    )

vhdl_toolchains = module_extension(
    implementation = _vhdl_extension_impl,
    tag_classes = {
        "defaults": _defaults_tag,
        "ghdl": _ghdl_tag,
        "nvc": _nvc_tag,
        "nvc_local": _nvc_local_tag,
    },
)