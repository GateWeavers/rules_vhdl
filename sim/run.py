import os
import json
import sys
from vunit import VUnit

def run_vunit_bazel():
    # 1. Récupération de la configuration générée par Bazel
    config_path = os.environ.get("VUNIT_BAZEL_CONFIG")
    if not config_path:
        print("Erreur: Ce script doit être exécuté via 'bazel test'")
        sys.exit(1)

    # Résolution du chemin absolu pour le fichier de config
    if not os.path.exists(config_path):
        config_path = os.path.join(os.getcwd(), config_path)

    with open(config_path, 'r') as f:
        config = json.load(f)

    # 2. Configuration de l'environnement VUnit
    
    # A. Définir le simulateur explicitement
    os.environ["VUNIT_SIMULATOR"] = "ghdl"
    
    # B. Définir le chemin vers le binaire GHDL
    # VUnit s'attend à ce que VUNIT_GHDL_PATH pointe vers le DOSSIER contenant l'exécutable,
    # pas l'exécutable lui-même.
    ghdl_binary_path = os.path.abspath(config['ghdl_binary'])
    ghdl_dir = os.path.dirname(ghdl_binary_path)
    
    os.environ["VUNIT_GHDL_PATH"] = ghdl_dir
    
    print(f"DEBUG: VUnit configured with GHDL at {ghdl_dir}")

    # 3. Gestion des arguments et de l'export XML (Intégration Bazel)
    # Bazel définit la variable d'environnement XML_OUTPUT_FILE pour les règles de test.
    # Nous devons dire à VUnit d'écrire son rapport à cet emplacement.
    
    argv = sys.argv[:]
    
    xml_output = os.environ.get("XML_OUTPUT_FILE")
    if xml_output:
        # On ajoute l'argument --xunit-xml pour que Bazel puisse parser les résultats
        argv.extend(["--xunit-xml", xml_output])

    # Initialisation de VUnit avec les nouveaux arguments
    vu = VUnit.from_argv(argv)

    # 4. Chargement des sources (identique à avant)
    for lib_name, files in config['libraries'].items():
        try:
            lib = vu.library(lib_name)
        except KeyError:
            lib = vu.add_library(lib_name)
            
        for file_entry in files:
            lib.add_source_files(file_entry['file'], vhdl_standard=file_entry['version'])

    # 5. Exécution
    vu.main()

if __name__ == "__main__":
    run_vunit_bazel()