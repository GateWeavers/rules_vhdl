load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# ==============================================================================
# 1. TEMPLATES POUR LE BUILD FILE UNIQUE
# ==============================================================================

_COMMON_HEADER = """
package(default_visibility = ["//visibility:public"])

# Matchers pour les valeurs par défaut
config_setting(
    name = "match_version_default",
    flag_values = {"@rules_vhdl//vhdl/config:version": "default"},
)

config_setting(
    name = "match_backend_default",
    flag_values = {"@rules_vhdl//vhdl/config:backend": "default"},
)
"""

_GHDL_TEMPLATE = """
# --- Toolchain: {name} (GHDL) ---
filegroup(name = "{name}_bin", srcs = ["{name}/bin/ghdl"])
filegroup(name = "{name}_lib_files", srcs = glob(["{name}/lib/**"]))

load("@rules_vhdl//simulator:ghdl.bzl", "ghdl_toolchain")

ghdl_toolchain(
    name = "{name}_impl",
    ghdl_binary = ":{name}_bin",
    ghdl_lib = [":{name}_lib_files"],
    version = "{version}",
    backend = "{backend}",
)

config_setting(
    name = "{name}_match_version",
    flag_values = {{"@rules_vhdl//vhdl/config:version": "{version}"}},
)

config_setting(
    name = "{name}_match_simulator",
    flag_values = {{"@rules_vhdl//vhdl/config:simulator": "ghdl"}},
)

config_setting(
    name = "{name}_match_backend",
    flag_values = {{"@rules_vhdl//vhdl/config:backend": "{backend}"}},
)

toolchain(
    name = "{name}_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":{name}_match_simulator",
        ":{name}_match_version",
        ":{name}_match_backend",
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

_GHDL_DEFAULT_TEMPLATE = """
toolchain(
    name = "{name}_default_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":{name}_match_simulator",
        ":match_version_default",
        ":match_backend_default",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)
"""

_NVC_TEMPLATE = """
# --- Toolchain: {name} (NVC) ---
filegroup(name = "{name}_bin", srcs = ["{name}/bin/nvc"])

load("@rules_vhdl//simulator:nvc.bzl", "nvc_toolchain")

nvc_toolchain(
    name = "{name}_impl",
    nvc_binary = ":{name}_bin",
    version = "{version}",
)

config_setting(
    name = "{name}_match_version",
    flag_values = {{"@rules_vhdl//vhdl/config:version": "{version}"}},
)

config_setting(
    name = "{name}_match_simulator",
    flag_values = {{"@rules_vhdl//vhdl/config:simulator": "nvc"}},
)

toolchain(
    name = "{name}_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":{name}_match_simulator",
        ":{name}_match_version",
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

_NVC_DEFAULT_TEMPLATE = """
toolchain(
    name = "{name}_default_toolchain",
    toolchain = ":{name}_impl",
    toolchain_type = "@rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":{name}_match_simulator",
        ":match_version_default",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)
"""

# ==============================================================================
# 2. REPOSITORY RULE : UNIFIED TOOLCHAIN HUB
# ==============================================================================

def _vhdl_combined_toolchains_repo_impl(ctx):
    tools = json.decode(ctx.attr.tools_json)
    default_toolchain = ctx.attr.default_toolchain
    
    registry_content = "TOOLCHAIN_REGISTRY = {\n"
    build_content = _COMMON_HEADER
    
    for tool in tools:
        name = tool["name"]
        type = tool["type"]
        
        # Download and extract into subdirectory
        ctx.download_and_extract(
            url = tool["url"],
            sha256 = tool["sha256"],
            strip_prefix = tool["strip_prefix"],
            output = name,
        )
        
        # Collect registry info
        registry_content += '    "{}": struct(simulator="{}", version="{}", backend="{}"),\n'.format(
            name, type, tool["version"], tool.get("backend", "none")
        )
        
        # Generate BUILD rules
        if type == "ghdl":
            default_rule = ""
            if name == default_toolchain:
                default_rule = _GHDL_DEFAULT_TEMPLATE.format(
                    name = name, os = tool["os"], arch = tool["arch"]
                )
            
            build_content += _GHDL_TEMPLATE.format(
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
                default_rule = _NVC_DEFAULT_TEMPLATE.format(
                    name = name, os = tool["os"], arch = tool["arch"]
                )
                
            build_content += _NVC_TEMPLATE.format(
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

vhdl_combined_toolchains_repo = repository_rule(
    implementation = _vhdl_combined_toolchains_repo_impl,
    attrs = {
        "tools_json": attr.string(mandatory = True),
        "default_toolchain": attr.string(),
    },
)

# ==============================================================================
# 3. TAG CLASSES
# ==============================================================================

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

# ==============================================================================
# 4. IMPLEMENTATION DE L'EXTENSION
# ==============================================================================

def _vhdl_extension_impl(ctx):
    tools = []
    default_toolchain = ""

    for mod in ctx.modules:
        for tool in mod.tags.ghdl:
            if tool.is_default:
                if default_toolchain:
                    fail("Only one simulator can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                default_toolchain = tool.name
            
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

        for tool in mod.tags.nvc:
            if tool.is_default:
                if default_toolchain:
                    fail("Only one simulator can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                default_toolchain = tool.name

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

    vhdl_combined_toolchains_repo(
        name = "vhdl_toolchains",
        tools_json = json.encode(tools),
        default_toolchain = default_toolchain,
    )

vhdl_toolchains = module_extension(
    implementation = _vhdl_extension_impl,
    tag_classes = {
        "ghdl": _ghdl_tag,
        "nvc": _nvc_tag,
    },
)
