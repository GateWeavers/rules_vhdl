load("@rules_python//python:defs.bzl", "py_test")
load(":ghdl_toolchain.bzl", "ghdl_config_transition")
load(":vhdl_rules.bzl", "VhdlLibraryInfo")

load("@rules_python//python:defs.bzl", "py_test")
# load(":ghdl_toolchain.bzl", "ghdl_config_transition")
load(":vhdl_rules.bzl", "VhdlLibraryInfo")

# --- LE TEMPLATE PYTHON ---
# C'est le code qui sera écrit dans le fichier généré automatiquement
_RUNNER_TEMPLATE = """
import os
import sys
import json
from vunit import VUnit

def main():
    # 1. Récupération de la config Bazel
    config_path = os.environ.get("VUNIT_BAZEL_CONFIG")
    if not config_path:
        print("Error: VUNIT_BAZEL_CONFIG not set.")
        sys.exit(1)
        
    # Résolution du chemin absolu pour le JSON
    if not os.path.exists(config_path):
        # Fallback runfiles
        config_path = os.path.join(os.getcwd(), config_path)

    with open(config_path, 'r') as f:
        config = json.load(f)

    # CONFIGURATION DYNAMIQUE DU SIMULATEUR
    sim_type = config['simulator_type']
    binary_path = os.path.abspath(config['binary_path'])
    binary_dir = os.path.dirname(binary_path)

    if sim_type == "ghdl":
        os.environ["VUNIT_SIMULATOR"] = "ghdl"
        os.environ["VUNIT_GHDL_PATH"] = binary_dir
    elif sim_type == "nvc":
        os.environ["VUNIT_SIMULATOR"] = "nvc"
        os.environ["VUNIT_NVC_PATH"] = binary_dir
    else:
        print(f"Unknown simulator: {sim_type}")
        sys.exit(1)

    # 3. Préparation des arguments (Filtres + XML)
    # On copie sys.argv pour inclure les arguments passés par --test_arg
    args = sys.argv[:]
    
    # Injection automatique de l'output XML pour Bazel CI
    if "XML_OUTPUT_FILE" in os.environ and "--xunit-xml" not in args:
        args.extend(["--xunit-xml", os.environ["XML_OUTPUT_FILE"]])

    # Initialisation VUnit
    vu = VUnit.from_argv(args)

    # 4. Chargement des sources depuis le JSON
    for lib_name, files in config['libraries'].items():
        try:
            lib = vu.library(lib_name)
        except KeyError:
            lib = vu.add_library(lib_name)
            
        for file_entry in files:
            lib.add_source_files(file_entry['file'], vhdl_standard=file_entry['version'])

    # 5. Lancement
    vu.main()

if __name__ == "__main__":
    main()
"""

# --- REGLE 1 : Générateur de Runner ---
def _vunit_runner_gen_impl(ctx):
    out_file = ctx.actions.declare_file(ctx.attr.out_name)
    ctx.actions.write(
        output = out_file,
        content = _RUNNER_TEMPLATE,
        is_executable = True
    )
    return [DefaultInfo(files = depset([out_file]))]

_vunit_runner_gen = rule(
    implementation = _vunit_runner_gen_impl,
    attrs = {
        "out_name": attr.string(mandatory = True),
    },
)

def _vunit_context_impl(ctx):
    
    sim_type = ctx.attr.tool_simulator
    
    binary_file = None

    # 2. Résolution conditionnelle de la Toolchain
    if sim_type == "ghdl":
        info = ctx.toolchains["//:ghdl_toolchain_type"].ghdl_info
        binary_file = info.ghdl_binary
    elif sim_type == "nvc":
        info = ctx.toolchains["//:nvc_toolchain_type"].nvc_info
        binary_file = info.nvc_binary
    else:
        fail("Unsupported simulator: " + sim_type)
    
    # B. Collecte des Sources VHDL
    # On parcourt les dépendances pour construire une structure de données pour Python
    libraries_config = {}
    transitive_srcs = []
    
    # On ajoute le DUT
    dut_info = ctx.attr.dut[VhdlLibraryInfo]
    
    # On fusionne les libraries du DUT et celles définies localement (srcs)
    # Note: Pour simplifier, on traite 'srcs' comme appartenant à la lib 'test_lib' ou 'work'
    
    # 1. Traitement des libs du DUT
    for lib_key, lib_struct in dut_info.libraries.items():
        lib_name = lib_struct.library_name
        if lib_name not in libraries_config:
            libraries_config[lib_name] = []
        
        # On ajoute les fichiers
        for f in lib_struct.sources.to_list():
            transitive_srcs.append(f)
            libraries_config[lib_name].append({
                "file": f.short_path,
                "version": lib_struct.vhdl_version
            })

    # 2. Traitement des sources du Testbench (attribut srcs)
    # On les met par défaut dans la lib 'tb_lib' ou celle spécifiée
    tb_files = ctx.files.srcs
    transitive_srcs.extend(tb_files)
    
    tb_lib_name = "lib_tb" # Nom arbitraire pour le testbench
    if tb_lib_name not in libraries_config:
        libraries_config[tb_lib_name] = []
        
    for f in tb_files:
        libraries_config[tb_lib_name].append({
            "file": f.short_path,
            "version": "2008" # Version par défaut pour le TB
        })

    # C. Génération du JSON de configuration
    # 3. Construction du JSON
    config_content = {
        "simulator_type": sim_type,
        "binary_path": binary_file.short_path,
        "libraries": libraries_config # (Fonction extraite pour clarté)
    }
    
    config_file = ctx.actions.declare_file(ctx.label.name + "_config.json")
    ctx.actions.write(config_file, json.encode_indent(config_content))

    # D. Retourner les Runfiles
    # C'est CRUCIAL : Python a besoin d'accéder physiquement à ces fichiers
    return [DefaultInfo(
        files = depset([config_file]),
        runfiles = ctx.runfiles(files = transitive_srcs + [ghdl_binary, config_file])
    )]

_vunit_context = rule(
    implementation = _vunit_context_impl,
    # On applique ici la transition pour choisir la version de GHDL
    cfg = vhdl_config_transition,
    toolchains = [
        "//:ghdl_toolchain_type",
        "//:nvc_toolchain_type", # On demande les deux !
    ],
    attrs = {
        "dut": attr.label(providers = [VhdlLibraryInfo], mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "tool_simulator": attr.string(default = "ghdl"),
        "tool_version": attr.string(default = "default"),
        "tool_backend": attr.string(default = "default"),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist"
        ),
    }
)

# --- MACRO UTILISATEUR ---

def vunit_sim(name, dut, srcs = [],tool_simulator="ghdl", tool_version="default", tool_backend="default", deps=[], **kwargs):
    """
    Lance une simulation VUnit avec génération automatique du runner Python.
    """
    
    context_name = name + "_ctx"
    runner_name = name + "_runner.py"
    
    # 1. Générer le fichier de configuration JSON (et collecter les sources)
    _vunit_context(
        name = context_name,
        dut = dut,
        srcs = srcs,
        tool_simulator = tool_simulator, # Passe l'info
        tool_version = tool_version,
        tool_backend = tool_backend,
    )
    
    # 2. Générer le script Python automatiquement
    _vunit_runner_gen(
        name = name + "_gen_script",
        out_name = runner_name,
    )
    
    # 3. Lancer le test
    py_test(
        name = name,
        srcs = [runner_name],     # Utilise le script généré
        main = runner_name,       # Point d'entrée
        data = [":" + context_name], # Dépendance aux données (JSON + VHDL + GHDL)
        deps = deps,              # Deps Python (ex: vunit_hdl)
        env = {
            "VUNIT_BAZEL_CONFIG": "$(location :" + context_name + ")",
        },
        **kwargs
    )