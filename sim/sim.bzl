# vhdl_rules.bzl
load("//toolchain:ghdl.bzl", "GhdlConfigInfo", "GhdlToolchainInfo", "ghdl_config_transition")

# ... (Inclure ici VhdlLibraryInfo, VhdlModuleInfo, _vhdl_library_impl, etc.) ...
# Je ne répète pas le code des providers et des règles vhdl_library/module pour la clarté.
# Supposons qu'ils sont définis ici comme avant.

def _vhdl_transition_impl(_, attr):
    return {
        "//vhdl/config:simulator": attr.tool_simulator,
        "//vhdl/config:version": attr.tool_version,
        "//vhdl/config:backend": attr.tool_backend, # "default" si NVC
    }

vhdl_config_transition = transition(
    implementation = _vhdl_transition_impl,
    inputs = [],
    outputs = [
        "//vhdl/config:simulator",
        "//vhdl/config:version",
        "//vhdl/config:backend"
    ],
)

# --- Implementation de ghdl_sim ---

def _map_vhdl_version_to_flag(version):
    if version == "2008": return "08"
    if version == "93": return "93"
    if version == "87": return "87"
    if version == "2019": return "19"
    return "08"

def _ghdl_sim_impl(ctx):
    
    info = ctx.toolchains["//:toolchain_type"].ghdl_info
    
    ghdl_bin = info.ghdl_binary

    # --- Logique standard de simulation ---
    # (Identique à la version précédente, mais utilise ghdl_path)
    
    dut_lib_info = ctx.attr.dut[VhdlLibraryInfo]
    tb_srcs = ctx.files.srcs
    
    # ... (Création des runfiles et script comme avant) ...
    # Utilisation simplifiée pour l'exemple :
    
    script_content = ["#!/bin/bash", "set -e"]
    
    # Commandes de compilation
    for key, info in dut_lib_info.libraries.items():
        cmd = "{ghdl} -a --std={std} --work={lib} {files}".format(
            ghdl = ghdl_bin.short_path,
            std = _map_vhdl_version_to_flag(info.vhdl_version),
            lib = info.library_name,
            files = " ".join([f.short_path for f in info.sources.to_list()])
        )
        script_content.append(cmd)

    # Compilation Testbench + Run
    tb_opts = "--std=" + _map_vhdl_version_to_flag(ctx.attr.vhdl_version)
    script_content.append("{ghdl} -a {opts} {files}".format(
        ghdl = ghdl_bin.short_path, opts = tb_opts, files = " ".join([f.short_path for f in tb_srcs])
    ))
    
    sim_args = " ".join(ctx.attr.sim_args)
    script_content.append("{ghdl} -r {opts} {entity} {args}".format(
        ghdl = ghdl_bin.short_path, opts = tb_opts, entity = ctx.attr.testbench_entity, args = sim_args
    ))

    ctx.actions.write(
        output = ctx.outputs.executable,
        content = "\n".join(script_content),
        is_executable = True
    )
    
    # Collect runfiles
    all_srcs = tb_srcs
    for l in dut_lib_info.libraries.values():
        all_srcs += l.sources.to_list()

    runfiles = ctx.runfiles(files = [ghdl_bin] + all_srcs)
    
    return [DefaultInfo(runfiles = runfiles)]

ghdl_sim = rule(
    implementation = _ghdl_sim_impl,
    test = True,
    cfg = ghdl_config_transition, # La transition magique
    toolchains = ["//toolchain/ghdl:ghdl_toolchain"],
    attrs = {
        "srcs": attr.label_list(allow_files = [".vhd"], mandatory = True),
        "dut": attr.label(providers = [VhdlLibraryInfo]),
        "testbench_entity": attr.string(mandatory = True),
        "vhdl_version": attr.string(default = "2008"),
        "sim_args": attr.string_list(),
        
        # Nouveaux attributs pour piloter la transition
        "tool_version": attr.string(default = "default", doc = "GHDL version (e.g., '1.0', '2.0')"),
        "tool_backend": attr.string(default = "default", doc = "Backend type (e.g., 'llvm', 'mcode')"),
        
        # Flags implicites modifiés par la transition
        # "_version_flag": attr.label(default = "//vhdl:ghdl_version_flag"),
        # "_backend_flag": attr.label(default = "//vhdl:ghdl_backend_flag"),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
    },
)