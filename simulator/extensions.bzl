load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# ==============================================================================
# 1. REPOSITORY RULE : GHDL
# ==============================================================================
def _ghdl_repo_impl(ctx):
    # Téléchargement de l'archive GHDL
    ctx.download_and_extract(
        url = ctx.attr.url,
        sha256 = ctx.attr.sha256,
        strip_prefix = ctx.attr.strip_prefix,
    )
    
    # Génération du BUILD file pour exposer la toolchain
    # Note : On utilise le target_settings pour matcher la config
    build_content = """
load("@rules_vhdl//simulator:ghdl.bzl", "ghdl_toolchain")

package(default_visibility = ["//visibility:public"])

filegroup(name = "lib", srcs = glob(["lib/**"]))

ghdl_toolchain(
    name = "impl",
    ghdl_binary = "bin/ghdl",
    ghdl_lib = [":lib"],
    version = "{version}",
    backend = "{backend}",
)

# Match si flag version == version de ce repo
config_setting(
    name = "match_version",
    flag_values = {{"@rules_vhdl//vhdl/config:version": "{version}"}},
)

# Match si flag simulator == ghdl
config_setting(
    name = "match_simulator",
    flag_values = {{"@rules_vhdl//vhdl/config:simulator": "ghdl"}},
)

# Match si flag backend == backend de ce repo
config_setting(
    name = "match_backend",
    flag_values = {{"@rules_vhdl//vhdl/config:backend": "{backend}"}},
)

# Matchers pour les valeurs par défaut
config_setting(
    name = "match_version_default",
    flag_values = {{"@rules_vhdl//vhdl/config:version": "default"}},
)

config_setting(
    name = "match_backend_default",
    flag_values = {{"@rules_vhdl//vhdl/config:backend": "default"}},
)

toolchain(
    name = "toolchain",
    toolchain = ":impl",
    toolchain_type = "@rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":match_simulator",
        ":match_version",
        ":match_backend",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)

{default_toolchain_rule}

alias(
    name = "simulator",
    actual = ":toolchain",
)
    """.format(
        version = ctx.attr.version,
        backend = ctx.attr.backend,
        os = ctx.attr.os,
        arch = ctx.attr.arch,
        default_toolchain_rule = """
toolchain(
    name = "default_toolchain",
    toolchain = ":impl",
    toolchain_type = "@rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":match_simulator",
        ":match_version_default",
        ":match_backend_default",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)
        """.format(os = ctx.attr.os, arch = ctx.attr.arch) if ctx.attr.is_default else ""
    )
    
    ctx.file("BUILD", build_content)

ghdl_repository = repository_rule(
    implementation = _ghdl_repo_impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "version": attr.string(mandatory = True),
        "backend": attr.string(mandatory = True),
        "os": attr.string(mandatory = True),
        "arch": attr.string(mandatory = True),
        "is_default": attr.bool(default = False),
    },
)

# ==============================================================================
# 2. REPOSITORY RULE : NVC
# ==============================================================================
def _nvc_repo_impl(ctx):
    # Téléchargement de l'archive NVC
    ctx.download_and_extract(
        url = ctx.attr.url,
        sha256 = ctx.attr.sha256,
        strip_prefix = ctx.attr.strip_prefix,
    )
    
    # Génération du BUILD file pour exposer la toolchain NVC
    # NVC n'a pas de concept de "backend" (llvm/mcode), c'est plus simple.
    build_content = """
load("@rules_vhdl//simulator:nvc.bzl", "nvc_toolchain")

package(default_visibility = ["//visibility:public"])

filegroup(name = "bin", srcs = ["bin/nvc"])

nvc_toolchain(
    name = "impl",
    nvc_binary = ":bin",
    version = "{version}",
)

# Match si flag version == version de ce repo
config_setting(
    name = "match_version",
    flag_values = {{"@rules_vhdl//vhdl/config:version": "{version}"}},
)

# Match si flag simulator == nvc
config_setting(
    name = "match_simulator",
    flag_values = {{"@rules_vhdl//vhdl/config:simulator": "nvc"}},
)

# Matcher pour la valeur par défaut
config_setting(
    name = "match_version_default",
    flag_values = {{"@rules_vhdl//vhdl/config:version": "default"}},
)

toolchain(
    name = "toolchain",
    toolchain = ":impl",
    toolchain_type = "@rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":match_simulator",
        ":match_version",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)

{default_toolchain_rule}
    """.format(
        version = ctx.attr.version,
        os = ctx.attr.os,
        arch = ctx.attr.arch,
        default_toolchain_rule = """
toolchain(
    name = "default_toolchain",
    toolchain = ":impl",
    toolchain_type = "@rules_vhdl//simulator:toolchain_type",
    target_settings = [
        ":match_simulator",
        ":match_version_default",
    ],
    exec_compatible_with = [
        "@platforms//os:{os}",
        "@platforms//cpu:{arch}",
    ],
)
        """.format(os = ctx.attr.os, arch = ctx.attr.arch) if ctx.attr.is_default else ""
    )
    
    ctx.file("BUILD", build_content)

nvc_repository = repository_rule(
    implementation = _nvc_repo_impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
        "strip_prefix": attr.string(),
        "version": attr.string(mandatory = True),
        "os": attr.string(mandatory = True),
        "arch": attr.string(mandatory = True),
        "is_default": attr.bool(default = False),
    },
)

# ==============================================================================
# 2.5 REPOSITORY RULE : REGISTRY
# ==============================================================================
def _vhdl_registry_repo_impl(ctx):
    content = "TOOLCHAIN_REGISTRY = {\n"
    for repo_name, config in ctx.attr.config.items():
        content += '    "{}": struct(simulator="{}", version="{}", backend="{}"),\n'.format(
            repo_name, config[0], config[1], config[2]
        )
    content += "}\n\n"
    content += 'DEFAULT_TOOLCHAIN = "{}"\n'.format(ctx.attr.default_toolchain)
    ctx.file("registry.bzl", content)
    ctx.file("BUILD", "")

vhdl_registry_repo = repository_rule(
    implementation = _vhdl_registry_repo_impl,
    attrs = {
        "config": attr.string_list_dict(),
        "default_toolchain": attr.string(),
    },
)

# ==============================================================================
# 3. TAG CLASSES (Définition des schémas de données pour MODULE.bazel)
# ==============================================================================

# Schéma pour GHDL
_ghdl_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True, doc = "Nom unique du repo"),
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

# Schéma pour NVC (Nouveau)
_nvc_tag = tag_class(
    attrs = {
        "name": attr.string(mandatory = True, doc = "Nom unique du repo"),
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
    registry_config = {}
    default_toolchain = ""

    # On parcourt tous les modules qui utilisent cette extension
    for mod in ctx.modules:
        
        # --- A. Traitement des tags GHDL ---
        for tool in mod.tags.ghdl:
            if tool.is_default:
                if default_toolchain:
                    fail("Only one simulator can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                default_toolchain = tool.name

            ghdl_repository(
                name = tool.name,
                url = tool.url,
                sha256 = tool.sha256,
                strip_prefix = tool.strip_prefix,
                version = tool.version,
                backend = tool.backend,
                os = tool.os,
                arch = tool.arch,
                is_default = tool.is_default,
            )
            registry_config[tool.name] = ["ghdl", tool.version, tool.backend]

        # --- B. Traitement des tags NVC ---
        for tool in mod.tags.nvc:
            if tool.is_default:
                if default_toolchain:
                    fail("Only one simulator can be defined as default. Found both '{}' and '{}'".format(default_toolchain, tool.name))
                default_toolchain = tool.name

            nvc_repository(
                name = tool.name,
                url = tool.url,
                sha256 = tool.sha256,
                strip_prefix = tool.strip_prefix,
                version = tool.version,
                os = tool.os,
                arch = tool.arch,
                is_default = tool.is_default,
            )
            registry_config[tool.name] = ["nvc", tool.version, "none"]

    vhdl_registry_repo(
        name = "vhdl_toolchains_registry",
        config = registry_config,
        default_toolchain = default_toolchain,
    )

# Déclaration finale de l'extension
vhdl_toolchains = module_extension(
    implementation = _vhdl_extension_impl,
    tag_classes = {
        "ghdl": _ghdl_tag,
        "nvc": _nvc_tag,
    },
)